import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/agent/agent_input.dart';
import '../core/models/agent/agent_profile.dart';
import '../core/models/agent/agent_provider.dart';
import '../core/models/agent/agent_tool.dart';
import '../core/models/dict_info.dart';
import '../services/agent/agent_messages.dart';
import '../services/agent/agent_orchestrator.dart';
import '../services/agent/agent_run.dart';
import '../services/agent/citation_registry.dart';
import '../services/agent/familiarization/dictionary_familiarization_service.dart';
import '../services/agent/familiarization/unidic_familiarization_service.dart';
import '../services/mdict/mdict_worker.dart';
import 'agent_profile_inbox.dart';
import 'agent_providers.dart';
import 'agent_run_services.dart';
import 'providers.dart';

/// Owns the current Agent run at application scope. `AgentPage` is only a
/// subscriber: navigating away, rotating, or reopening the page never cancels
/// the OCR/tokenize/lookup/provider work or loses its progress.
class AgentRunController extends Notifier<AgentRunSnapshot> {
  AgentCancellation? _cancellation;
  _RunInputs? _lastInputs;
  String? _sessionId;
  int _runSerial = 0;
  int _textChars = 0;
  int _reasoningChars = 0;
  DateTime? _lastProgressAt;
  AgentUiLanguage _uiLanguage = AgentUiLanguage.chinese;
  Future<void> Function()? _cancelOcr;

  @override
  AgentRunSnapshot build() {
    ref.listen(agentProfileInboxProvider, (previous, next) {
      if (state.isRunning && state.pendingProfileCount != next.pendingCount) {
        state = state.copyWith(pendingProfileCount: next.pendingCount);
      }
    });
    return AgentRunSnapshot.idle;
  }

  Future<void> start({
    required String userText,
    required List<AgentImageInput> images,
    required List<DictionaryInfo> dictionaries,
    required AgentProviderConfig provider,
    required AgentMode mode,
    required String unidicPath,
    required AgentResponseLanguage responseLanguage,
    required AgentProfileLanguage profileLanguage,
    AgentRunResult? retainResult,
  }) async {
    if (state.isRunning) return;
    final text = userText.trim();
    final normalizedImages = <AgentImageInput>[
      for (var index = 0; index < images.length; index++)
        AgentImageInput(
          id: 'img-${index + 1}',
          localPath: images[index].localPath,
          mode: images[index].mode,
          variants: images[index].variants,
          selectedVariantId: images[index].selectedVariantId,
        ),
    ];
    final inputs = _RunInputs(
      userText: text,
      images: List<AgentImageInput>.unmodifiable(normalizedImages),
      dictionaries: List<DictionaryInfo>.unmodifiable(dictionaries),
      provider: provider,
      mode: mode,
      unidicPath: unidicPath,
      responseLanguage: responseLanguage,
      profileLanguage: profileLanguage,
    );
    // Keep the request even when validation fails immediately: the page should
    // not lose the user's text/image and retry must be able to replay it.
    _lastInputs = inputs;
    _uiLanguage = resolveAgentUiLanguage(responseLanguage);
    if (text.isEmpty && images.isEmpty) {
      _setImmediateError(
        agentInputRequiredMessage(_uiLanguage),
        _uiLanguage,
        inputs,
        retainResult: retainResult,
      );
      return;
    }
    if (dictionaries.isEmpty) {
      _setImmediateError(
        agentDictionaryRequiredMessage(_uiLanguage),
        _uiLanguage,
        inputs,
        retainResult: retainResult,
      );
      return;
    }
    final model = provider.complexModel.trim().isEmpty
        ? provider.smallModel.trim()
        : provider.complexModel.trim();
    if (model.isEmpty) {
      _setImmediateError(
        agentModelRequiredMessage(_uiLanguage),
        _uiLanguage,
        inputs,
        retainResult: retainResult,
      );
      return;
    }

    final token = AgentCancellation();
    final limits = ref.read(agentLimitsProvider);
    final runId = _nextRunId();
    final sessionId =
        _sessionId ?? 'session-${DateTime.now().microsecondsSinceEpoch}';
    _sessionId = sessionId;
    _cancellation = token;
    _textChars = 0;
    _reasoningChars = 0;
    _lastProgressAt = null;
    _cancelOcr = null;
    final startedAt = DateTime.now();
    final runWatch = Stopwatch()..start();
    state = AgentRunSnapshot(
      runId: runId,
      sessionId: sessionId,
      status: AgentRunStatus.preparing,
      stageMessage: agentStageMessage(AgentStage.prepare, _uiLanguage),
      sentText: text,
      sentImage: images.isNotEmpty,
      sentImagePaths: <String>[
        for (final image in inputs.images) image.localPath,
      ],
      mode: mode,
      responseLanguage: responseLanguage,
      providerLabel: provider.displayName,
      retainedResult: retainResult,
      maxEvidenceEntries: limits.maxEvidenceEntries,
      startedAt: startedAt,
      updatedAt: startedAt,
    );

    try {
      final loadServices = ref.read(agentRunServicesProvider);
      final services = await loadServices(
        needsOcr: inputs.images.isNotEmpty,
        isCancelled: () => !_isActive(token),
      );
      if (services == null) return;
      _cancelOcr = services.cancelOcr;

      final smallModel = provider.smallModel.trim().isEmpty
          ? provider.complexModel
          : provider.smallModel;
      final dictionaryFamiliarizer = DictionaryFamiliarizationService(
        samplePort: services.samplePort,
        repository: services.profileRepository,
        llm: services.llmFactory(provider),
        smallModel: smallModel,
        profileLanguage: profileLanguage,
      );
      final unidicFamiliarizer = UnidicFamiliarizationService(
        tokenizePort: services.tokenizePort,
        repository: services.unidicRepository,
      );
      final orchestrator = AgentOrchestrator(
        ocrPort: services.ocrPort,
        tokenizePort: services.tokenizePort,
        lookupPort: services.lookupPort,
        grammar: services.grammar,
        citations: CitationRegistry(),
        llmFactory: services.llmFactory,
        dictionaryFamiliarizer: dictionaryFamiliarizer,
        unidicFamiliarizer: unidicFamiliarizer,
        limits: limits,
      );

      final result = await orchestrator.run(
        AgentRunRequest(
          sessionId: sessionId,
          runId: runId,
          mode: mode,
          dictionaries: inputs.dictionaries,
          provider: provider,
          userText: text,
          images: inputs.images,
          unidicPath: unidicPath,
          responseLanguage: responseLanguage,
        ),
        cancellation: token,
        onStage: (stage, message) {
          if (kDebugMode) {
            debugPrint(
              '[AgentTiming] controller stage=${stage.name} '
              'elapsed=${runWatch.elapsedMilliseconds}ms',
            );
          }
          _update(
            token,
            (snapshot) => snapshot.copyWith(
              status: _statusFor(stage),
              stageMessage: message,
              progressStep: _progressStepFor(stage, snapshot.progressStep),
              // Force the last throttled progress value; stage changes are rare
              // and the stream may already be done when `validating` arrives.
              receivedChars: _receivedChars,
            ),
          );
          _lastProgressAt = DateTime.now();
        },
        onProvisionalResult: (provisional) {
          if (kDebugMode) {
            debugPrint(
              '[AgentTiming] controller provisional '
              'elapsed=${runWatch.elapsedMilliseconds}ms',
            );
          }
          _update(
            token,
            (snapshot) => snapshot.copyWith(provisionalResult: provisional),
          );
        },
        onEvidenceProgress: (count) {
          _update(
            token,
            (snapshot) => snapshot.copyWith(
              evidenceCount: count,
              progressStep: snapshot.progressStep < 1 ? 1 : null,
            ),
          );
        },
        onTextDelta: (value) {
          _textChars = value.length;
          _publishProgress(token);
        },
        onReasoningDelta: (value) {
          _reasoningChars = value.length;
          _publishProgress(token);
        },
        // The app-level inbox owns the decision futures. If the page is not
        // mounted, the run stays in `awaitingProfile`; it never auto-skips.
        onProfilesGenerated: (runId, proposals) async {
          final inbox = ref.read(agentProfileInboxProvider.notifier);
          if (ref.read(appSettingsProvider).agentProfilesAutoAccept) {
            return inbox.autoAcceptAll(proposals);
          }
          return inbox.waitForAll(runId, proposals);
        },
      );
      if (!_isActive(token)) return;
      if (kDebugMode) {
        debugPrint(
          '[AgentTiming] controller result_received '
          'elapsed=${runWatch.elapsedMilliseconds}ms',
        );
      }
      state = state.copyWith(
        status: AgentRunStatus.done,
        stageMessage: agentStageMessage(AgentStage.done, _uiLanguage),
        result: result,
        provisionalResult: null,
        progressStep: 4,
        evidenceCount: result.evidence.citations.length,
        citationCount: result.validation.citationsUsed.length,
        pendingProfileCount: 0,
        receivedChars: 0,
        errorMessage: null,
        errorDetail: '',
        retainedResult: null,
        resultRetainedAfterFailure: false,
        finishedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      if (kDebugMode) {
        debugPrint(
          '[AgentTiming] controller done_state '
          'elapsed=${runWatch.elapsedMilliseconds}ms',
        );
      }
    } on AgentRunFailure catch (error) {
      _fail(token, error.message, error.detail, error.code);
    } on MdictException catch (error) {
      _fail(token, error.message, '');
    } on Object {
      _fail(token, agentStageMessage(AgentStage.error, _uiLanguage), '');
    }
  }

  Future<void> retry({AgentMode? mode}) async {
    final inputs = _lastInputs;
    if (inputs == null || state.isRunning) return;
    await start(
      userText: inputs.userText,
      images: inputs.images,
      dictionaries: inputs.dictionaries,
      provider: inputs.provider,
      mode: mode ?? inputs.mode,
      unidicPath: inputs.unidicPath,
      responseLanguage: inputs.responseLanguage,
      profileLanguage: inputs.profileLanguage,
      retainResult: state.result ?? state.retainedResult,
    );
  }

  /// Re-analyzes with prepared OCR variants (P6.6). The run keeps the same
  /// text/dictionaries/provider/mode, reuses the supplied OCR text instead of
  /// running recognition again, and keeps the previous result visible until
  /// the new one succeeds.
  Future<void> reanalyzeWithImages(List<AgentImageInput> images) async {
    final inputs = _lastInputs;
    if (inputs == null || state.isRunning) return;
    await start(
      userText: inputs.userText,
      images: images,
      dictionaries: inputs.dictionaries,
      provider: inputs.provider,
      mode: inputs.mode,
      unidicPath: inputs.unidicPath,
      responseLanguage: inputs.responseLanguage,
      profileLanguage: inputs.profileLanguage,
      retainResult: state.result ?? state.retainedResult,
    );
  }

  /// Re-runs from the familiarization stage with the same request snapshot.
  /// The previous result stays visible until the new run succeeds; a failure
  /// restores it and flags [AgentRunSnapshot.resultRetainedAfterFailure].
  Future<void> regenerate() async {
    final inputs = _lastInputs;
    if (inputs == null || state.isRunning) return;
    await start(
      userText: inputs.userText,
      images: inputs.images,
      dictionaries: inputs.dictionaries,
      provider: inputs.provider,
      mode: inputs.mode,
      unidicPath: inputs.unidicPath,
      responseLanguage: inputs.responseLanguage,
      profileLanguage: inputs.profileLanguage,
      retainResult: state.result ?? state.retainedResult,
    );
  }

  /// Only the user's explicit "stop" may call this. Page disposal/route pop
  /// must never cancel the run.
  void cancel() {
    final token = _cancellation;
    if (token == null || token.isCancelled || !state.isRunning) return;
    token.cancel();
    final runId = state.runId;
    if (runId != null) {
      ref.read(agentProfileInboxProvider.notifier).cancelRun(runId);
    }
    final cancelOcr = _cancelOcr;
    if (cancelOcr != null) unawaited(cancelOcr());
    state = state.copyWith(
      status: AgentRunStatus.cancelled,
      stageMessage: agentStageMessage(AgentStage.cancelled, _uiLanguage),
      result: state.provisionalResult ?? state.retainedResult,
      provisionalResult: null,
      retainedResult: null,
      pendingProfileCount: 0,
      finishedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void newSession() {
    if (state.isRunning) return;
    _cancellation?.cancel();
    _cancellation = null;
    _lastInputs = null;
    _sessionId = null;
    _cancelOcr = null;
    _textChars = 0;
    _reasoningChars = 0;
    _lastProgressAt = null;
    ref.read(agentProfileInboxProvider.notifier).clearAll();
    state = AgentRunSnapshot.idle;
  }

  bool _isActive(AgentCancellation token) =>
      identical(_cancellation, token) && !token.isCancelled;

  int get _receivedChars =>
      _textChars > _reasoningChars ? _textChars : _reasoningChars;

  void _update(
    AgentCancellation token,
    AgentRunSnapshot Function(AgentRunSnapshot snapshot) update,
  ) {
    if (!_isActive(token)) return;
    state = update(state).copyWith(updatedAt: DateTime.now());
  }

  void _publishProgress(AgentCancellation token) {
    // Reasoning models can emit >10k tiny deltas. The UI shows elapsed time,
    // not the character counter, so publishing every delta only causes
    // thousands of Riverpod state updates/rebuilds.
    final now = DateTime.now();
    final last = _lastProgressAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 250)) {
      return;
    }
    _lastProgressAt = now;
    _update(
      token,
      (snapshot) => snapshot.copyWith(
        receivedChars: _receivedChars,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _fail(
    AgentCancellation token,
    String message,
    String detail, [
    AgentToolErrorCode? code,
  ]) {
    if (!_isActive(token)) return;
    // Prefer the current run's provisional answer over an older retained one;
    // the user has already seen it and a failed post-check must not erase it.
    final fallback = state.provisionalResult ?? state.retainedResult;
    state = state.copyWith(
      status: AgentRunStatus.error,
      stageMessage: message,
      errorMessage: message,
      errorCode: code,
      retryable: code == null || _isRetryable(code),
      errorDetail: detail,
      result: fallback,
      provisionalResult: null,
      retainedResult: null,
      resultRetainedAfterFailure: fallback != null,
      pendingProfileCount: 0,
      finishedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void _setImmediateError(
    String message,
    AgentUiLanguage language,
    _RunInputs inputs, {
    AgentRunResult? retainResult,
  }) {
    _uiLanguage = language;
    state = AgentRunSnapshot(
      status: AgentRunStatus.error,
      stageMessage: message,
      errorMessage: message,
      retryable: true,
      sentText: inputs.userText,
      sentImage: inputs.images.isNotEmpty,
      sentImagePaths: <String>[
        for (final image in inputs.images) image.localPath,
      ],
      mode: inputs.mode,
      responseLanguage: inputs.responseLanguage,
      providerLabel: inputs.provider.displayName,
      result: retainResult,
      resultRetainedAfterFailure: retainResult != null,
      finishedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  String _nextRunId() {
    _runSerial++;
    return 'run-${DateTime.now().microsecondsSinceEpoch}-$_runSerial';
  }
}

bool _isRetryable(AgentToolErrorCode code) => switch (code) {
  AgentToolErrorCode.providerRateLimited ||
  AgentToolErrorCode.providerUnavailable ||
  AgentToolErrorCode.toolTimeout ||
  AgentToolErrorCode.dictionaryNotReady ||
  AgentToolErrorCode.dictionaryLookupFailed ||
  AgentToolErrorCode.internalError => true,
  _ => false,
};

int _progressStepFor(AgentStage stage, int current) => switch (stage) {
  AgentStage.prepare || AgentStage.ocr => 0,
  AgentStage.familiarizing ||
  AgentStage.awaitingProfile ||
  AgentStage.tokenizing ||
  AgentStage.evidence ||
  AgentStage.coverage => 1,
  AgentStage.reasoning => 2,
  AgentStage.validating || AgentStage.formatting => 3,
  AgentStage.done => 4,
  AgentStage.error || AgentStage.cancelled => current,
};

AgentRunStatus _statusFor(AgentStage stage) => switch (stage) {
  AgentStage.prepare => AgentRunStatus.preparing,
  AgentStage.ocr => AgentRunStatus.ocr,
  AgentStage.familiarizing => AgentRunStatus.familiarizing,
  AgentStage.awaitingProfile => AgentRunStatus.awaitingProfile,
  AgentStage.tokenizing => AgentRunStatus.tokenizing,
  AgentStage.evidence => AgentRunStatus.tokenizing,
  AgentStage.coverage => AgentRunStatus.tokenizing,
  AgentStage.reasoning => AgentRunStatus.reasoning,
  AgentStage.validating || AgentStage.formatting => AgentRunStatus.validating,
  AgentStage.done => AgentRunStatus.done,
  AgentStage.error => AgentRunStatus.error,
  AgentStage.cancelled => AgentRunStatus.cancelled,
};

class _RunInputs {
  const _RunInputs({
    required this.userText,
    required this.images,
    required this.dictionaries,
    required this.provider,
    required this.mode,
    required this.unidicPath,
    required this.responseLanguage,
    required this.profileLanguage,
  });

  final String userText;
  final List<AgentImageInput> images;
  final List<DictionaryInfo> dictionaries;
  final AgentProviderConfig provider;
  final AgentMode mode;
  final String unidicPath;
  final AgentResponseLanguage responseLanguage;
  final AgentProfileLanguage profileLanguage;
}

final agentRunControllerProvider =
    NotifierProvider<AgentRunController, AgentRunSnapshot>(
      AgentRunController.new,
    );
