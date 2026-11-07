import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/agent/agent_input.dart';
import '../core/models/agent/agent_profile.dart';
import '../core/models/agent/agent_provider.dart';
import '../core/models/agent/agent_tool.dart';
import '../core/models/dict_info.dart';
import '../services/agent/agent_background_service.dart';
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
  AgentRichTextOutputs? _pendingRichText;
  AgentUiLanguage _uiLanguage = AgentUiLanguage.chinese;
  Future<void> Function()? _cancelOcr;
  AgentBackgroundPort? _backgroundPort;
  AgentMode? _sessionMode;
  Timer? _deadlineTimer;

  /// Strict/loose selected for the current app session. It survives page
  /// rebuilds, is snapshotted into each run, and resets with a new session.
  AgentMode get sessionMode => _sessionMode ?? state.mode;

  void setSessionMode(AgentMode mode) {
    _sessionMode = mode;
  }

  AgentBackgroundPort get _background {
    final existing = _backgroundPort;
    if (existing != null) return existing;
    final created = ref.read(agentBackgroundServiceProvider);
    _backgroundPort = created;
    return created;
  }

  @override
  AgentRunSnapshot build() {
    ref.onDispose(() {
      _deadlineTimer?.cancel();
      final port = _backgroundPort;
      if (port != null) unawaited(port.stop());
    });
    ref.listen(agentProfileInboxProvider, (previous, next) {
      // Pending profiles may be resolved after this run is done. Keep the
      // visible count in sync instead of only updating while running.
      if (state.pendingProfileCount != next.pendingCount) {
        state = state.copyWith(pendingProfileCount: next.pendingCount);
      }
    });
    return AgentRunSnapshot.idle;
  }

  /// Local input images from the most recent request. Used by the failed-run
  /// multi-OCR entry; paths are never sent to the provider or persisted here.
  List<AgentImageInput> get lastImages =>
      _lastInputs?.images ?? const <AgentImageInput>[];

  /// Dictionaries selected for the most recent request.
  List<DictionaryInfo> get lastDictionaries =>
      _lastInputs?.dictionaries ?? const <DictionaryInfo>[];

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
    _sessionMode = mode;
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

    // A previous run may still have a display-only formatting task in flight.
    // Its result can no longer be shown, so stop it before starting a new run.
    _cancellation?.cancel();
    final token = AgentCancellation();
    final limits = ref.read(agentLimitsProvider);
    final runId = _nextRunId();
    final sessionId =
        _sessionId ?? 'session-${DateTime.now().microsecondsSinceEpoch}';
    _sessionId = sessionId;
    _cancellation = token;
    _textChars = 0;
    _reasoningChars = 0;
    _pendingRichText = null;
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
    _deadlineTimer?.cancel();
    if (limits.runDeadlineSeconds > 0) {
      _deadlineTimer = Timer(
        Duration(seconds: limits.runDeadlineSeconds),
        () => _onDeadline(token, limits.runDeadlineSeconds),
      );
    }

    // Keep the process (and therefore the HTTP stream) alive if the user
    // switches apps or turns the screen off. This is best-effort: a platform
    // failure must not block the analysis.
    try {
      await _background.start();
    } catch (_) {
      // Ignored; the run continues without the process-lifetime guarantee.
    }

    try {
      final loadServices = ref.read(agentRunServicesProvider);
      final services = await loadServices(
        needsOcr: inputs.images.isNotEmpty,
        isCancelled: () => !_isActive(token),
      );
      if (services == null) {
        _deadlineTimer?.cancel();
        _deadlineTimer = null;
        unawaited(_background.stop());
        return;
      }
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

      final pendingProfileIds = ref
          .read(agentProfileInboxProvider)
          .pending
          .map((proposal) => proposal.dictionaryId)
          .toSet();
      final result = await orchestrator.run(
        AgentRunRequest(
          sessionId: sessionId,
          runId: runId,
          mode: mode,
          dictionaries: inputs.dictionaries,
          provider: provider,
          userText: text,
          images: inputs.images,
          pendingProfileDictionaryIds: pendingProfileIds,
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
        onRichTextReady: (rich) {
          if (!_isActive(token)) return;
          final result = state.result;
          if (result == null) {
            // The run may still be finishing its `done` state transition.
            // Apply the tags together with the core result below.
            _pendingRichText = rich;
            return;
          }
          _update(token, (snapshot) {
            final current = snapshot.result;
            if (current == null) return snapshot;
            return snapshot.copyWith(result: current.copyWithRichText(rich));
          });
        },
        onRichTextFormattingChanged: (active) {
          _update(
            token,
            (snapshot) => snapshot.copyWith(richTextFormatting: active),
          );
        },
        // Only the accumulated character count is needed; the raw tagged
        // stream is never rendered. This avoids per-delta String copies and
        // 4 Hz whole-page rebuilds for an unused counter.
        onTextDelta: (chars) => _textChars = chars,
        onReasoningDelta: (chars) => _reasoningChars = chars,
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
      _deadlineTimer?.cancel();
      _deadlineTimer = null;
      final pendingRichText = _pendingRichText;
      _pendingRichText = null;
      final finalResult = pendingRichText == null
          ? result
          : result.copyWithRichText(pendingRichText);
      state = state.copyWith(
        status: AgentRunStatus.done,
        stageMessage: agentStageMessage(AgentStage.done, _uiLanguage),
        result: finalResult,
        provisionalResult: null,
        // The user already saw the provisional answer; replaying the result
        // block entrance animation on the final replacement looks like a
        // page flash.
        resultReplaced: state.provisionalResult != null,
        progressStep: 4,
        evidenceCount: result.evidence.citations.length,
        citationCount: result.validation.citationsUsed.length,
        pendingProfileCount: ref.read(agentProfileInboxProvider).pendingCount,
        receivedChars: 0,
        errorMessage: null,
        errorDetail: '',
        retainedResult: null,
        resultRetainedAfterFailure: false,
        finishedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      unawaited(_background.stop());
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
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    token.cancel();
    final runId = state.runId;
    if (runId != null) {
      ref.read(agentProfileInboxProvider.notifier).cancelRun(runId);
    }
    final cancelOcr = _cancelOcr;
    if (cancelOcr != null) unawaited(cancelOcr());
    unawaited(_background.stop());
    _pendingRichText = null;
    state = state.copyWith(
      status: AgentRunStatus.cancelled,
      stageMessage: agentStageMessage(AgentStage.cancelled, _uiLanguage),
      result: state.provisionalResult ?? state.retainedResult,
      provisionalResult: null,
      retainedResult: null,
      resultReplaced: state.provisionalResult != null,
      pendingProfileCount: ref.read(agentProfileInboxProvider).pendingCount,
      richTextFormatting: false,
      finishedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void newSession() {
    if (state.isRunning) return;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _cancellation?.cancel();
    unawaited(_background.stop());
    _cancellation = null;
    _lastInputs = null;
    _sessionId = null;
    _sessionMode = null;
    _cancelOcr = null;
    _textChars = 0;
    _reasoningChars = 0;
    _pendingRichText = null;
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

  /// Global run deadline. Cancels the in-flight provider request immediately
  /// and keeps any provisional/retained result visible with a retryable
  /// TOOL_TIMEOUT error instead of letting the user wait indefinitely.
  void _onDeadline(AgentCancellation token, int seconds) {
    if (!_isActive(token)) return;
    _deadlineTimer = null;
    token.cancel();
    final cancelOcr = _cancelOcr;
    if (cancelOcr != null) unawaited(cancelOcr());
    unawaited(_background.stop());
    _pendingRichText = null;
    final hadProvisional = state.provisionalResult != null;
    final fallback = state.provisionalResult ?? state.retainedResult;
    final message = agentRunTimeoutMessage(_uiLanguage, seconds);
    state = state.copyWith(
      status: AgentRunStatus.error,
      stageMessage: message,
      errorMessage: message,
      errorCode: AgentToolErrorCode.toolTimeout,
      retryable: true,
      errorDetail: '',
      result: fallback,
      provisionalResult: null,
      retainedResult: null,
      resultRetainedAfterFailure: fallback != null,
      resultReplaced: hadProvisional,
      pendingProfileCount: ref.read(agentProfileInboxProvider).pendingCount,
      richTextFormatting: false,
      finishedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void _fail(
    AgentCancellation token,
    String message,
    String detail, [
    AgentToolErrorCode? code,
  ]) {
    if (!_isActive(token)) return;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    _pendingRichText = null;
    unawaited(_background.stop());
    // Prefer the current run's provisional answer over an older retained one;
    // the user has already seen it and a failed post-check must not erase it.
    final hadProvisional = state.provisionalResult != null;
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
      resultReplaced: hadProvisional,
      pendingProfileCount: ref.read(agentProfileInboxProvider).pendingCount,
      richTextFormatting: false,
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
