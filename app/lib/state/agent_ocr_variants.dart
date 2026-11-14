import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

import '../core/models/agent/agent_input.dart';
import '../core/models/agent/agent_ocr.dart';
import '../core/models/agent/agent_tool.dart';
import '../core/models/dict_info.dart';
import '../services/agent/agent_run.dart';
import '../services/agent/ocr_consensus.dart';
import '../services/agent/ports/agent_capability_exception.dart';
import '../services/agent/ports/ocr_port.dart';
import 'agent_run_services.dart';

/// Local results of the explicit P6.6 multi-OCR comparison.
///
/// Only OCR text, local quality signals and dictionary suggestions are kept.
/// Images/paths never enter this state; the provider is not called here.
class AgentOcrVariantsState {
  const AgentOcrVariantsState({
    this.extraVariants = const <String, List<AgentOcrVariant>>{},
    this.baselineVariants = const <String, AgentOcrVariant>{},
    this.qualities = const <String, Map<String, OcrQuality>>{},
    this.previews = const <String, Map<String, OcrVariantLookupPreview>>{},
    this.repairs = const <String, List<OcrRepairSuggestion>>{},
    this.repairBaselineIds = const <String, String>{},
    this.generatedImages = const <String>{},
    this.loadingImageIds = const <String>{},
    this.errorCodes = const <String, AgentToolErrorCode>{},
    this.errorMessages = const <String, String>{},
  });

  /// Additional variants keyed by the opaque image id. The variant currently
  /// used by the run lives in the result input, not here.
  final Map<String, List<AgentOcrVariant>> extraVariants;

  /// Baseline variant generated locally when a failed run has no displayable
  /// result (for example OCR succeeded but the provider failed before a result
  /// was assembled). The result input remains the source of truth when present.
  final Map<String, AgentOcrVariant> baselineVariants;

  /// Quality per image id and variant id. It includes the baseline variant.
  final Map<String, Map<String, OcrQuality>> qualities;

  /// Bounded local dictionary lookups per image and variant. These are display
  /// previews only, never formal citations or provider input.
  final Map<String, Map<String, OcrVariantLookupPreview>> previews;

  /// Dictionary repair suggestions for the baseline text of each image.
  final Map<String, List<OcrRepairSuggestion>> repairs;

  /// Variant id whose text the [repairs] offsets refer to. After the user
  /// selects another variant, old suggestions must not be applied to the new
  /// baseline text.
  final Map<String, String> repairBaselineIds;

  /// Images for which a multi-OCR comparison was attempted, even if no extra
  /// variant was produced (for example vertical OCR is unavailable).
  final Set<String> generatedImages;

  /// Per-image loading state. A comparison of image 1 must not make image 2
  /// show a spinner or block its own comparison.
  final Set<String> loadingImageIds;
  final Map<String, AgentToolErrorCode> errorCodes;

  /// Diagnostic fallback only; the UI maps [errorCode] to localized copy.
  final Map<String, String> errorMessages;

  bool get loading => loadingImageIds.isNotEmpty;

  /// Convenience for tests/external callers; the UI uses [errorFor].
  AgentToolErrorCode? get errorCode =>
      errorCodes.isEmpty ? null : errorCodes.values.first;

  AgentToolErrorCode? errorFor(String imageId) => errorCodes[imageId];

  AgentOcrVariantsState copyWith({
    Map<String, List<AgentOcrVariant>>? extraVariants,
    Map<String, AgentOcrVariant>? baselineVariants,
    Map<String, Map<String, OcrQuality>>? qualities,
    Map<String, Map<String, OcrVariantLookupPreview>>? previews,
    Map<String, List<OcrRepairSuggestion>>? repairs,
    Map<String, String>? repairBaselineIds,
    Set<String>? generatedImages,
    Set<String>? loadingImageIds,
    Map<String, AgentToolErrorCode>? errorCodes,
    Map<String, String>? errorMessages,
  }) {
    return AgentOcrVariantsState(
      extraVariants: extraVariants ?? this.extraVariants,
      baselineVariants: baselineVariants ?? this.baselineVariants,
      qualities: qualities ?? this.qualities,
      previews: previews ?? this.previews,
      repairs: repairs ?? this.repairs,
      repairBaselineIds: repairBaselineIds ?? this.repairBaselineIds,
      generatedImages: generatedImages ?? this.generatedImages,
      loadingImageIds: loadingImageIds ?? this.loadingImageIds,
      errorCodes: errorCodes ?? this.errorCodes,
      errorMessages: errorMessages ?? this.errorMessages,
    );
  }
}

/// App-scoped controller for explicit multi-OCR comparison. Leaving the Agent
/// page does not cancel the local recognition; the user must press stop.
///
/// Different images may run their comparisons concurrently. Native OCR calls
/// are serialized through [_ocrQueue] because the underlying engine is shared;
/// the UI still tracks loading/error per image.
class AgentOcrVariantsController extends Notifier<AgentOcrVariantsState> {
  int _epoch = 0;
  final Set<String> _activeImages = <String>{};
  final Set<String> _cancelledImages = <String>{};
  Future<void> _ocrQueue = Future<void>.value();
  String? _activeOcrImageId;
  Future<void> Function()? _cancelOcr;

  @override
  AgentOcrVariantsState build() {
    ref.onDispose(() => _epoch++);
    return const AgentOcrVariantsState();
  }

  Future<void> generate({
    required List<AgentImageInput> images,
    required Map<String, List<AgentOcrVariant>> baselineVariants,
    required List<DictionaryInfo> dictionaries,
  }) async {
    for (final image in images) {
      if (_activeImages.contains(image.id)) continue;
      _activeImages.add(image.id);
      _cancelledImages.remove(image.id);
      final epoch = _epoch;
      _setLoading(image.id, true, epoch);
      _clearError(image.id, epoch);
      try {
        await _generateOne(image, baselineVariants, dictionaries, epoch);
      } on AgentCapabilityException catch (error) {
        if (error.code != AgentToolErrorCode.toolCancelled) {
          _setError(image.id, error.code, error.message, epoch);
        }
      } catch (_) {
        _setError(image.id, AgentToolErrorCode.internalError, '', epoch);
      } finally {
        _activeImages.remove(image.id);
        _setLoading(image.id, false, epoch);
        _cancelledImages.remove(image.id);
      }
    }
  }

  Future<void> _generateOne(
    AgentImageInput image,
    Map<String, List<AgentOcrVariant>> baselineVariants,
    List<DictionaryInfo> dictionaries,
    int epoch,
  ) async {
    bool current() => _isCurrent(image.id, epoch);
    final services = await ref.read(agentRunServicesProvider)(
      needsOcr: true,
      isCancelled: () => !current(),
    );
    if (services == null) {
      throw const AgentCapabilityException(
        AgentToolErrorCode.internalError,
        '',
      );
    }
    if (!current()) return;
    _cancelOcr = services.cancelOcr;

    // Resolve readiness before checking vertical availability; otherwise the
    // first comparison in a session can incorrectly think MangaOCR is missing.
    await _enqueueOcr(image.id, epoch, services.ocrPort.ensureReady);
    if (!current()) return;

    final known = <AgentOcrVariant>[...?baselineVariants[image.id]];
    final AgentOcrVariant baseline;
    if (known.isEmpty) {
      final run = await _enqueueOcr(
        image.id,
        epoch,
        () => services.ocrPort.recognize(
          image: LocalOcrHandle(id: image.id, localPath: image.localPath),
          mode: image.mode,
        ),
      );
      baseline = _variantFromRun(image.id, run);
      known.add(baseline);
    } else {
      baseline = known.firstWhere(
        (variant) => variant.id == image.selectedVariantId,
        orElse: () => known.first,
      );
    }
    if (!current()) return;

    final imageQuality = <String, OcrQuality>{...?state.qualities[image.id]};
    final imagePreviews = <String, OcrVariantLookupPreview>{
      ...?state.previews[image.id],
    };
    final baselineAssessment = await _assess(
      baseline,
      services,
      dictionaries,
      () => !current(),
    );
    if (!current()) return;
    imageQuality[baseline.id] = baselineAssessment.quality;
    final baselinePreview = baselineAssessment.preview;
    if (baselinePreview != null) {
      imagePreviews[baseline.id] = baselinePreview;
    } else {
      imagePreviews.remove(baseline.id);
    }

    // The baseline is never its own "alternative". Source variants from a
    // previous re-analysis and variants generated but not yet used are both
    // kept, so switching back and forth does not lose choices. The provider
    // contract allows four variants per source, so alternatives are capped at
    // three and always include the selected variant separately.
    final imageExtras = <AgentOcrVariant>[];
    void addExtra(AgentOcrVariant variant) {
      if (variant.id == baseline.id) return;
      if (imageExtras.length >= _maxAlternatives) return;
      if (imageExtras.any((existing) => existing.id == variant.id)) return;
      imageExtras.add(variant);
    }

    for (final variant in known) {
      addExtra(variant);
    }
    for (final variant
        in state.extraVariants[image.id] ?? const <AgentOcrVariant>[]) {
      addExtra(variant);
    }
    for (final variant in imageExtras) {
      if (imageQuality.containsKey(variant.id)) continue;
      final assessment = await _assess(
        variant,
        services,
        dictionaries,
        () => !current(),
      );
      if (!current()) return;
      imageQuality[variant.id] = assessment.quality;
      final preview = assessment.preview;
      if (preview != null) {
        imagePreviews[variant.id] = preview;
      } else {
        imagePreviews.remove(variant.id);
      }
    }

    // Generate a model x orientation matrix instead of asking the same model
    // for three orientations. A forced engine either returns that engine or
    // fails, so the UI never presents two PaddleOCR results as different
    // models. Order is: Paddle horizontal, Manga vertical, Paddle vertical,
    // then auto (the first three win the four-variant budget).
    final specs = _alternativeSpecs(
      baseline: baseline,
      paddleAvailable: services.ocrPort.horizontalAvailable,
      mangaAvailable: services.ocrPort.verticalAvailable,
    );
    AgentToolErrorCode? modeError;
    var modeSucceeded = false;
    for (final spec in specs) {
      if (!current()) return;
      if (imageExtras.length >= _maxAlternatives) break;
      if (_hasSpecCombination(known, spec) ||
          _hasSpecCombination(imageExtras, spec)) {
        continue;
      }
      try {
        final run = await _enqueueOcr(
          image.id,
          epoch,
          () => services.ocrPort.recognize(
            image: LocalOcrHandle(id: image.id, localPath: image.localPath),
            mode: spec.mode,
            engine: spec.engine,
          ),
        );
        modeSucceeded = true;
        final variant = _variantFromRun(image.id, run);
        // Deduplicate the actual result combo, not text. auto/horizontal can
        // share text but remain distinct options; forced engines guarantee
        // that the model shown on the chip is the model that produced it.
        if (_hasVariantCombination(known, variant) ||
            imageExtras.any((item) => item.id == variant.id)) {
          continue;
        }
        if (imageExtras.length >= _maxAlternatives) continue;
        imageExtras.add(variant);
        known.add(variant);
        final assessment = await _assess(
          variant,
          services,
          dictionaries,
          () => !current(),
        );
        if (!current()) return;
        imageQuality[variant.id] = assessment.quality;
        final preview = assessment.preview;
        if (preview != null) {
          imagePreviews[variant.id] = preview;
        } else {
          imagePreviews.remove(variant.id);
        }
      } on AgentCapabilityException catch (error) {
        if (error.code == AgentToolErrorCode.toolCancelled) return;
        // One unavailable engine/orientation (for example MangaOCR missing)
        // must not hide the other combinations; remember the error for the
        // no-alternative case so the UI can show a stable code.
        modeError ??= error.code;
      } catch (_) {
        modeError ??= AgentToolErrorCode.internalError;
      }
    }
    if (imageExtras.isEmpty && modeError != null && !modeSucceeded) {
      throw AgentCapabilityException(modeError, '');
    }
    if (!current()) return;

    final repairs = imageExtras.isEmpty
        ? const <OcrRepairSuggestion>[]
        : await _repairsFor(
            baseline: baseline,
            variants: imageExtras,
            dictionaries: dictionaries,
            services: services,
            cancelled: () => !current(),
          );
    if (!current()) return;
    _publishImage(
      imageId: image.id,
      epoch: epoch,
      baseline: baseline,
      alternatives: imageExtras,
      quality: imageQuality,
      previews: imagePreviews,
      repairs: repairs,
      baselineId: baseline.id,
    );
  }

  /// Stops one image's comparison. Other images continue independently. It
  /// never cancels an Agent analysis run; those have their own controller.
  void cancelImage(String imageId) {
    if (!state.loadingImageIds.contains(imageId) &&
        !_activeImages.contains(imageId)) {
      return;
    }
    _cancelledImages.add(imageId);
    _setLoading(imageId, false, _epoch);
    if (_activeOcrImageId == imageId) {
      final cancelOcr = _cancelOcr;
      if (cancelOcr != null) unawaited(cancelOcr());
    }
  }

  /// Stops every in-flight comparison.
  void cancel() {
    final ids = <String>{...state.loadingImageIds, ..._activeImages};
    for (final imageId in ids) {
      cancelImage(imageId);
    }
  }

  void clear() {
    _epoch++;
    _cancelledImages.addAll(_activeImages);
    _cancelledImages.addAll(state.loadingImageIds);
    final cancelOcr = _cancelOcr;
    _cancelOcr = null;
    if (cancelOcr != null) unawaited(cancelOcr());
    state = const AgentOcrVariantsState();
  }

  bool _isCurrent(String imageId, int epoch) =>
      epoch == _epoch && !_cancelledImages.contains(imageId);

  void _setLoading(String imageId, bool loading, int epoch) {
    if (epoch != _epoch) return;
    final next = <String>{...state.loadingImageIds};
    if (loading) {
      next.add(imageId);
    } else {
      next.remove(imageId);
    }
    state = state.copyWith(loadingImageIds: next);
  }

  void _clearError(String imageId, int epoch) {
    if (epoch != _epoch) return;
    state = state.copyWith(
      errorCodes: _withoutKey(state.errorCodes, imageId),
      errorMessages: _withoutKey(state.errorMessages, imageId),
    );
  }

  void _setError(
    String imageId,
    AgentToolErrorCode code,
    String message,
    int epoch,
  ) {
    if (epoch != _epoch || _cancelledImages.contains(imageId)) return;
    state = state.copyWith(
      errorCodes: <String, AgentToolErrorCode>{
        ...state.errorCodes,
        imageId: code,
      },
      errorMessages: <String, String>{...state.errorMessages, imageId: message},
      loadingImageIds: _withoutSet(state.loadingImageIds, imageId),
    );
  }

  void _publishImage({
    required String imageId,
    required int epoch,
    required AgentOcrVariant baseline,
    required List<AgentOcrVariant> alternatives,
    required Map<String, OcrQuality> quality,
    required Map<String, OcrVariantLookupPreview> previews,
    required List<OcrRepairSuggestion> repairs,
    required String baselineId,
  }) {
    if (epoch != _epoch || _cancelledImages.contains(imageId)) return;
    state = state.copyWith(
      extraVariants: <String, List<AgentOcrVariant>>{
        ...state.extraVariants,
        imageId: alternatives,
      },
      baselineVariants: <String, AgentOcrVariant>{
        ...state.baselineVariants,
        imageId: baseline,
      },
      qualities: <String, Map<String, OcrQuality>>{
        ...state.qualities,
        imageId: quality,
      },
      previews: <String, Map<String, OcrVariantLookupPreview>>{
        ...state.previews,
        imageId: previews,
      },
      repairs: <String, List<OcrRepairSuggestion>>{
        ...state.repairs,
        imageId: repairs,
      },
      repairBaselineIds: <String, String>{
        ...state.repairBaselineIds,
        imageId: baselineId,
      },
      generatedImages: <String>{...state.generatedImages, imageId},
      errorCodes: _withoutKey(state.errorCodes, imageId),
      errorMessages: _withoutKey(state.errorMessages, imageId),
    );
  }

  /// Serializes native OCR calls while leaving per-image tasks independent.
  Future<T> _enqueueOcr<T>(
    String imageId,
    int epoch,
    Future<T> Function() task,
  ) {
    final completer = Completer<T>();
    _ocrQueue = _ocrQueue.then((_) async {
      if (!_isCurrent(imageId, epoch)) {
        completer.completeError(
          const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          ),
        );
        return;
      }
      _activeOcrImageId = imageId;
      try {
        completer.complete(await task());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (_activeOcrImageId == imageId) _activeOcrImageId = null;
      }
    });
    return completer.future;
  }

  Future<List<OcrRepairSuggestion>> _repairsFor({
    required AgentOcrVariant baseline,
    required List<AgentOcrVariant> variants,
    required List<DictionaryInfo> dictionaries,
    required AgentRunServices services,
    required bool Function() cancelled,
  }) async {
    if (dictionaries.isEmpty) return const <OcrRepairSuggestion>[];
    final spans = <OcrDiffSpan>[];
    final seenSpans = <String>{};
    var changedChars = 0;
    for (final variant in variants) {
      if (cancelled()) return const <OcrRepairSuggestion>[];
      final diff = OcrConsensus.diff(baseline.text, variant.text);
      for (final span in diff.changedBaseSpans) {
        if (!seenSpans.add('${span.start}:${span.end}:${span.text}')) continue;
        spans.add(span);
        changedChars += span.end - span.start;
      }
    }
    if (spans.isEmpty) return const <OcrRepairSuggestion>[];
    // Query each suspicious span once even when several variants disagree with
    // the baseline. The lookup budget stays bounded by OcrConsensus.
    final merged = OcrTextDiff(
      baseSpans: spans,
      candidateSpans: const <OcrDiffSpan>[],
      baseChangedChars: changedChars,
      candidateChangedChars: 0,
    );
    return OcrConsensus.suggestRepairs(
      text: baseline.text,
      diff: merged,
      dictionaries: dictionaries,
      lookupPort: services.lookupPort,
      isCancelled: cancelled,
    );
  }

  Future<({OcrQuality quality, OcrVariantLookupPreview? preview})> _assess(
    AgentOcrVariant variant,
    AgentRunServices services,
    List<DictionaryInfo> dictionaries,
    bool Function() cancelled,
  ) async {
    OcrDictionaryProbe? probe;
    if (dictionaries.isNotEmpty && !cancelled()) {
      try {
        probe = await OcrConsensus.probeDictionary(
          text: variant.text,
          tokenizePort: services.tokenizePort,
          lookupPort: services.lookupPort,
          dictionaries: dictionaries,
          isCancelled: cancelled,
        );
      } catch (_) {
        // Quality is advisory; keep the text-only assessment.
      }
    }
    return (
      quality: OcrConsensus.assess(
        variant: variant,
        dictionaryHitRate: probe?.rate,
        contentWords: probe?.words ?? 0,
      ),
      preview: probe?.preview,
    );
  }

  static const int _maxAlternatives = AgentOcrVariant.maxPerSource - 1;

  List<_VariantSpec> _alternativeSpecs({
    required AgentOcrVariant baseline,
    required bool paddleAvailable,
    required bool mangaAvailable,
  }) {
    final specs = <_VariantSpec>[
      if (paddleAvailable)
        const _VariantSpec(
          mode: OcrMode.horizontal,
          engine: OcrEngineId.paddleV5,
        ),
      if (mangaAvailable)
        const _VariantSpec(
          mode: OcrMode.vertical,
          engine: OcrEngineId.mangaOcr,
        ),
      if (paddleAvailable)
        const _VariantSpec(
          mode: OcrMode.vertical,
          engine: OcrEngineId.paddleV5,
        ),
      const _VariantSpec(mode: OcrMode.auto),
    ];
    final filtered = <_VariantSpec>[
      for (final spec in specs)
        if (!(spec.mode == baseline.mode &&
            (spec.engine == null || spec.engine == baseline.engine)))
          spec,
    ];
    return filtered.take(_maxAlternatives).toList(growable: false);
  }

  bool _hasSpecCombination(List<AgentOcrVariant> variants, _VariantSpec spec) {
    for (final variant in variants) {
      if (variant.mode != spec.mode) continue;
      // An unforced auto request is already represented by any auto variant;
      // a forced request must match the exact engine that would be shown.
      if (spec.engine == null || variant.engine == spec.engine) return true;
    }
    return false;
  }

  bool _hasVariantCombination(
    List<AgentOcrVariant> variants,
    AgentOcrVariant candidate,
  ) {
    return variants.any(
      (variant) =>
          variant.mode == candidate.mode && variant.engine == candidate.engine,
    );
  }

  AgentOcrVariant _variantFromRun(String imageId, OcrRun run) {
    return AgentOcrVariant(
      id: 'var-$imageId-${run.mode.name}-${run.engine}',
      engine: run.engine,
      mode: run.mode,
      text: run.text,
      confidence: run.confidence,
      elapsedMs: run.elapsedMs,
    );
  }
}

class _VariantSpec {
  const _VariantSpec({required this.mode, this.engine});

  final OcrMode mode;
  final String? engine;
}

Map<String, T> _withoutKey<T>(Map<String, T> map, String key) {
  final next = <String, T>{...map};
  next.remove(key);
  return next;
}

Set<String> _withoutSet(Set<String> set, String value) {
  final next = <String>{...set};
  next.remove(value);
  return next;
}

final agentOcrVariantsProvider =
    NotifierProvider<AgentOcrVariantsController, AgentOcrVariantsState>(
      AgentOcrVariantsController.new,
    );
