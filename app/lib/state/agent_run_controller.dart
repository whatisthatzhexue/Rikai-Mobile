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
  AgentRichTextOutputs? _pendingRichText;
  AgentUiLanguage _uiLanguage = AgentUiLanguage.chinese;
  Future<void> Function()? _cancelOcr;
  AgentBackgroundLease? _backgroundLease;
  _BackgroundHold? _backgroundHold;
  AgentMode? _sessionMode;
  Timer? _slowWarningTimer;

  /// Strict/loose selected for the current app session. It survives page
  /// rebuilds, is snapshotted into each run, and resets with a new session.
  AgentMode get sessionMode => _sessionMode ?? state.mode;

  void setSessionMode(AgentMode mode) {
    _sessionMode = mode;
  }

  AgentBackgroundLease get _backgroundLeaseRef {
    final existing = _backgroundLease;
    if (existing != null) return existing;
    final created = ref.read(agentBackgroundLeaseProvider);
    _backgroundLease = created;
    return created;
  }

  @override
  AgentRunSnapshot build() {
    ref.onDispose(() {
      _slowWarningTimer?.cancel();
      final hold = _backgroundHold;
      _backgroundHold = null;
      if (hold != null) unawaited(hold.release());
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
    // The slow-request advisory starts only when the main analysis model
    // enters its generation stage, not while OCR/tokenization/lookup run.
    _slowWarningTimer?.cancel();
    _slowWarningTimer = null;

    // Keep the process (and therefore the HTTP stream and deferred profile
    // generation) alive if the user switches apps or turns the screen off.
    // This is best-effort: a platform failure must not block the analysis.
    final previousHold = _backgroundHold;
    if (previousHold != null) unawaited(previousHold.release());
    final backgroundHold = _BackgroundHold(_backgroundLeaseRef);
    _backgroundHold = backgroundHold;
    try {
      await backgroundHold.acquire();
    } catch (_) {
      // Ignored; the run continues without the process-lifetime guarantee.
    }
    Future<void>? backgroundProfileWork;

    try {
      final loadServices = ref.read(agentRunServicesProvider);
      final services = await loadServices(
        needsOcr: inputs.images.isNotEmpty,
        isCancelled: () => !_isActive(token),
      );
      if (services == null) {
        _slowWarningTimer?.cancel();
        _slowWarningTimer = null;
        await _releaseBackgroundHold(backgroundHold);
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
        evidenceCache: ref.read(agentEvidenceCacheProvider),
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
          if (stage == AgentStage.reasoning &&
              state.thinkingStartedAt == null) {
            _startSlowWarningTimer(token, limits.slowRequestWarningSeconds);
          }
          _update(token, (snapshot) {
            final thinkingStartedAt = stage == AgentStage.reasoning
                ? snapshot.thinkingStartedAt ?? DateTime.now()
                : snapshot.thinkingStartedAt;
            return snapshot.copyWith(
              status: _statusFor(stage),
              stageMessage: message,
              progressStep: _progressStepFor(stage, snapshot.progressStep),
              thinkingStartedAt: thinkingStartedAt,
              // Force the last throttled progress value; stage changes are rare
              // and the stream may already be done when `validating` arrives.
              receivedChars: _receivedChars,
            );
          });
        },
        onTranslationPreview: (text) {
          if (!_isActive(token) || text.trim().isEmpty) return;
          _update(
            token,
            (snapshot) => snapshot.copyWith(translationPreview: text),
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
            (snapshot) => snapshot.copyWith(
              provisionalResult: provisional,
              translationPreview: null,
            ),
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
            return snapshot.copyWith(result: _applyRichText(current, rich));
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
        // The app-level inbox owns the pending queue. Generation does not
        // wait for the user's decision: profiles take effect next run, and
        // waiting here would keep the foreground service alive indefinitely.
        onProfilesGenerated: (runId, proposals) async {
          final inbox = ref.read(agentProfileInboxProvider.notifier);
          if (ref.read(appSettingsProvider).agentProfilesAutoAccept) {
            return inbox.autoAcceptAll(proposals);
          }
          await inbox.enqueue(proposals);
          return const <ProfileConfirmation>[];
        },
        onBackgroundProfiles: (work) => backgroundProfileWork = work,
      );
      if (!_isActive(token)) return;
      if (kDebugMode) {
        debugPrint(
          '[AgentTiming] controller result_received '
          'elapsed=${runWatch.elapsedMilliseconds}ms',
        );
      }
      _slowWarningTimer?.cancel();
      _slowWarningTimer = null;
      final pendingRichText = _pendingRichText;
      _pendingRichText = null;
      final finalResult = pendingRichText == null
          ? result
          : _applyRichText(result, pendingRichText);
      state = state.copyWith(
        status: AgentRunStatus.done,
        stageMessage: agentStageMessage(AgentStage.done, _uiLanguage),
        result: finalResult,
        provisionalResult: null,
        translationPreview: null,
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
        slowRequestWarning: false,
        finishedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      if (identical(_backgroundHold, backgroundHold)) {
        _backgroundHold = null;
      }
      // Keep the foreground service until deferred profile generation has
      // actually enqueued its proposals. Stopping it at `done` let Android
      // suspend the process mid-generation when the user switched apps,
      // which silently skipped the remaining dictionaries.
      unawaited(_releaseBackgroundAfter(backgroundHold, backgroundProfileWork));
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
    _slowWarningTimer?.cancel();
    _slowWarningTimer = null;
    token.cancel();
    final runId = state.runId;
    if (runId != null) {
      ref.read(agentProfileInboxProvider.notifier).cancelRun(runId);
    }
    final cancelOcr = _cancelOcr;
    if (cancelOcr != null) unawaited(cancelOcr());
    _releaseBackgroundNow();
    _pendingRichText = null;
    state = state.copyWith(
      status: AgentRunStatus.cancelled,
      stageMessage: agentStageMessage(AgentStage.cancelled, _uiLanguage),
      result: state.provisionalResult ?? state.retainedResult,
      provisionalResult: null,
      translationPreview: null,
      retainedResult: null,
      resultReplaced: state.provisionalResult != null,
      pendingProfileCount: ref.read(agentProfileInboxProvider).pendingCount,
      richTextFormatting: false,
      slowRequestWarning: false,
      finishedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void newSession() {
    if (state.isRunning) return;
    _slowWarningTimer?.cancel();
    _slowWarningTimer = null;
    _cancellation?.cancel();
    _releaseBackgroundNow();
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

  AgentRunResult _applyRichText(
    AgentRunResult result,
    AgentRichTextOutputs rich,
  ) {
    final updated = result.copyWithRichText(rich);
    return updated.copyWithTelemetry(
      updated.telemetry.copyWith(
        llmCalls: updated.telemetry.llmCalls + rich.formattingCalls,
        formattingCalls:
            updated.telemetry.formattingCalls + rich.formattingCalls,
        formattingAcceptedSections:
            updated.telemetry.formattingAcceptedSections +
            rich.acceptedSections,
        formattingRejectedSections:
            updated.telemetry.formattingRejectedSections +
            rich.rejectedSections,
        formattingRepairedSections:
            updated.telemetry.formattingRepairedSections +
            rich.repairedSections,
      ),
    );
  }

  bool _isActive(AgentCancellation token) =>
      identical(_cancellation, token) && !token.isCancelled;

  /// Releases the current run's foreground-service hold immediately. Safe to
  /// call when no hold is active or when a deferred profile task has already
  /// taken over the hold.
  void _releaseBackgroundNow() {
    final hold = _backgroundHold;
    _backgroundHold = null;
    if (hold != null) unawaited(hold.release());
  }

  Future<void> _releaseBackgroundHold(_BackgroundHold hold) async {
    if (identical(_backgroundHold, hold)) _backgroundHold = null;
    await hold.release();
  }

  Future<void> _releaseBackgroundAfter(
    _BackgroundHold hold,
    Future<void>? work,
  ) async {
    if (work != null) {
      try {
        await work;
      } catch (_) {
        // Profile generation already logs its own failures; the service must
        // still be released.
      }
    }
    await _releaseBackgroundHold(hold);
  }

  int get _receivedChars =>
      _textChars > _reasoningChars ? _textChars : _reasoningChars;

  void _update(
    AgentCancellation token,
    AgentRunSnapshot Function(AgentRunSnapshot snapshot) update,
  ) {
    if (!_isActive(token)) return;
    state = update(state).copyWith(updatedAt: DateTime.now());
  }

  /// Starts the orange advisory shown after the main analysis model has been
  /// generating for [seconds]. It never cancels the run: the user can keep
  /// waiting or stop explicitly. Zero/negative disables the advisory.
  void _startSlowWarningTimer(AgentCancellation token, int seconds) {
    _slowWarningTimer?.cancel();
    _slowWarningTimer = null;
    if (seconds <= 0) return;
    _slowWarningTimer = Timer(Duration(seconds: seconds), () {
      if (!_isActive(token)) return;
      _slowWarningTimer = null;
      _update(token, (snapshot) {
        if (snapshot.slowRequestWarning) return snapshot;
        return snapshot.copyWith(slowRequestWarning: true);
      });
    });
  }

  void _fail(
    AgentCancellation token,
    String message,
    String detail, [
    AgentToolErrorCode? code,
  ]) {
    if (!_isActive(token)) return;
    _slowWarningTimer?.cancel();
    _slowWarningTimer = null;
    _pendingRichText = null;
    _releaseBackgroundNow();
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
      translationPreview: null,
      retainedResult: null,
      resultRetainedAfterFailure: fallback != null,
      resultReplaced: hadProvisional,
      pendingProfileCount: ref.read(agentProfileInboxProvider).pendingCount,
      richTextFormatting: false,
      slowRequestWarning: false,
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

/// One run's foreground-service hold. A hold is released at most once even if
/// done/failure/dispose race with deferred profile generation.
class _BackgroundHold {
  _BackgroundHold(this.lease);

  final AgentBackgroundLease lease;
  bool _released = false;

  Future<void> acquire() => lease.acquire();

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await lease.release();
  }
}

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
