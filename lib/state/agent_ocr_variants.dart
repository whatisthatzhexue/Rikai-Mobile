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
    this.qualities = const <String, Map<String, OcrQuality>>{},
    this.repairs = const <String, List<OcrRepairSuggestion>>{},
    this.repairBaselineIds = const <String, String>{},
    this.generatedImages = const <String>{},
    this.loading = false,
    this.errorCode,
    this.errorMessage = '',
  });

  /// Additional variants keyed by the opaque image id. The variant currently
  /// used by the run lives in the result input, not here.
  final Map<String, List<AgentOcrVariant>> extraVariants;

  /// Quality per image id and variant id. It includes the baseline variant.
  final Map<String, Map<String, OcrQuality>> qualities;

  /// Dictionary repair suggestions for the baseline text of each image.
  final Map<String, List<OcrRepairSuggestion>> repairs;

  /// Variant id whose text the [repairs] offsets refer to. After the user
  /// selects another variant, old suggestions must not be applied to the new
  /// baseline text.
  final Map<String, String> repairBaselineIds;

  /// Images for which a multi-OCR comparison was attempted, even if no extra
  /// variant was produced (for example vertical OCR is unavailable).
  final Set<String> generatedImages;
  final bool loading;
  final AgentToolErrorCode? errorCode;

  /// Diagnostic fallback only; the UI maps [errorCode] to localized copy.
  final String errorMessage;

  AgentOcrVariantsState copyWith({
    Map<String, List<AgentOcrVariant>>? extraVariants,
    Map<String, Map<String, OcrQuality>>? qualities,
    Map<String, List<OcrRepairSuggestion>>? repairs,
    Map<String, String>? repairBaselineIds,
    Set<String>? generatedImages,
    bool? loading,
    Object? errorCode = _unset,
    String? errorMessage,
  }) {
    return AgentOcrVariantsState(
      extraVariants: extraVariants ?? this.extraVariants,
      qualities: qualities ?? this.qualities,
      repairs: repairs ?? this.repairs,
      repairBaselineIds: repairBaselineIds ?? this.repairBaselineIds,
      generatedImages: generatedImages ?? this.generatedImages,
      loading: loading ?? this.loading,
      errorCode: identical(errorCode, _unset)
          ? this.errorCode
          : errorCode as AgentToolErrorCode?,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// App-scoped controller for explicit multi-OCR comparison. Leaving the Agent
/// page does not cancel the local recognition; the user must press stop.
class AgentOcrVariantsController extends Notifier<AgentOcrVariantsState> {
  static final RegExp _whitespace = RegExp(r'\s+');

  int _generation = 0;
  bool _cancelled = false;
  Future<void> Function()? _cancelOcr;

  @override
  AgentOcrVariantsState build() {
    ref.onDispose(() => _generation++);
    return const AgentOcrVariantsState();
  }

  Future<void> generate({
    required List<AgentImageInput> images,
    required Map<String, List<AgentOcrVariant>> baselineVariants,
    required List<DictionaryInfo> dictionaries,
  }) async {
    if (state.loading || images.isEmpty) return;
    final generation = ++_generation;
    _cancelled = false;
    bool cancelled() => _cancelled || generation != _generation;
    state = state.copyWith(loading: true, errorCode: null, errorMessage: '');
    try {
      final services = await ref.read(agentRunServicesProvider)(
        needsOcr: true,
        isCancelled: cancelled,
      );
      if (services == null) {
        if (!cancelled()) {
          state = state.copyWith(
            loading: false,
            errorCode: AgentToolErrorCode.internalError,
            errorMessage: '',
          );
        }
        return;
      }
      if (cancelled()) return;
      _cancelOcr = services.cancelOcr;

      final extra = <String, List<AgentOcrVariant>>{...state.extraVariants};
      final qualities = <String, Map<String, OcrQuality>>{
        for (final entry in state.qualities.entries)
          entry.key: <String, OcrQuality>{...entry.value},
      };
      final repairs = <String, List<OcrRepairSuggestion>>{...state.repairs};
      final repairBaselines = <String, String>{...state.repairBaselineIds};
      final generated = <String>{...state.generatedImages};

      for (final image in images) {
        if (cancelled()) return;
        final known = <AgentOcrVariant>[...?baselineVariants[image.id]];
        final AgentOcrVariant baseline;
        if (known.isEmpty) {
          final run = await services.ocrPort.recognize(
            image: LocalOcrHandle(id: image.id, localPath: image.localPath),
            mode: image.mode,
          );
          baseline = _variantFromRun(image.id, run);
          known.add(baseline);
        } else {
          baseline = known.firstWhere(
            (variant) => variant.id == image.selectedVariantId,
            orElse: () => known.first,
          );
        }

        final imageQuality = <String, OcrQuality>{...?qualities[image.id]};
        imageQuality[baseline.id] = await _assess(
          baseline,
          services,
          dictionaries,
          cancelled,
        );
        // The baseline is never its own "alternative". Source variants from a
        // previous re-analysis and variants generated but not yet used are both
        // kept, so switching back and forth does not lose choices.
        final imageExtras = <AgentOcrVariant>[
          for (final variant in known)
            if (variant.id != baseline.id) variant,
          for (final variant in extra[image.id] ?? const <AgentOcrVariant>[])
            if (variant.id != baseline.id &&
                !known.any((existing) => existing.id == variant.id))
              variant,
        ];
        for (final variant in imageExtras) {
          if (imageQuality.containsKey(variant.id)) continue;
          imageQuality[variant.id] = await _assess(
            variant,
            services,
            dictionaries,
            cancelled,
          );
        }
        final modes = <OcrMode>{
          if (image.mode != OcrMode.horizontal) OcrMode.horizontal,
          if (services.ocrPort.verticalAvailable &&
              image.mode != OcrMode.vertical)
            OcrMode.vertical,
        };
        AgentToolErrorCode? modeError;
        var modeSucceeded = false;
        for (final mode in modes) {
          if (cancelled()) return;
          try {
            final run = await services.ocrPort.recognize(
              image: LocalOcrHandle(id: image.id, localPath: image.localPath),
              mode: mode,
            );
            modeSucceeded = true;
            var variant = _variantFromRun(image.id, run);
            final duplicate = <AgentOcrVariant>[
              ...known,
              ...imageExtras,
            ].any((item) => _sameRecognizedText(item, variant));
            if (duplicate) continue;
            if (known.any((item) => item.id == variant.id) ||
                imageExtras.any((item) => item.id == variant.id)) {
              variant = variant.copyWith(
                id: '${variant.id}-${imageExtras.length + 1}',
              );
            }
            imageExtras.add(variant);
            known.add(variant);
            imageQuality[variant.id] = await _assess(
              variant,
              services,
              dictionaries,
              cancelled,
            );
          } on AgentCapabilityException catch (error) {
            if (error.code == AgentToolErrorCode.toolCancelled) return;
            // One unavailable mode (for example MangaOCR) must not hide the
            // other mode's result; remember the error for the no-alternative
            // case so the UI can show a stable code instead of "unavailable".
            modeError ??= error.code;
          } catch (_) {
            modeError ??= AgentToolErrorCode.internalError;
          }
        }
        if (imageExtras.isEmpty && modeError != null && !modeSucceeded) {
          throw AgentCapabilityException(modeError, '');
        }

        extra[image.id] = imageExtras;
        qualities[image.id] = imageQuality;
        repairBaselines[image.id] = baseline.id;
        if (imageExtras.isEmpty) {
          repairs[image.id] = const <OcrRepairSuggestion>[];
        } else {
          repairs[image.id] = await _repairsFor(
            baseline: baseline,
            variants: imageExtras,
            dictionaries: dictionaries,
            services: services,
            cancelled: cancelled,
          );
        }
        generated.add(image.id);
        if (!cancelled()) {
          state = state.copyWith(
            extraVariants: extra,
            qualities: qualities,
            repairs: repairs,
            repairBaselineIds: repairBaselines,
            generatedImages: generated,
          );
        }
      }
      if (!cancelled()) {
        state = state.copyWith(
          loading: false,
          extraVariants: extra,
          qualities: qualities,
          repairs: repairs,
          repairBaselineIds: repairBaselines,
          generatedImages: generated,
        );
      }
    } on AgentCapabilityException catch (error) {
      if (!cancelled()) {
        state = state.copyWith(
          loading: false,
          errorCode: error.code,
          errorMessage: error.message,
        );
      }
    } catch (_) {
      if (!cancelled()) {
        state = state.copyWith(
          loading: false,
          errorCode: AgentToolErrorCode.internalError,
          errorMessage: '',
        );
      }
    } finally {
      if (generation == _generation) _cancelOcr = null;
    }
  }

  /// Stops the local comparison and any in-flight OCR. It never cancels an
  /// Agent analysis run; those have their own controller.
  void cancel() {
    if (!state.loading) return;
    _cancelled = true;
    _generation++;
    final cancelOcr = _cancelOcr;
    if (cancelOcr != null) unawaited(cancelOcr());
    state = state.copyWith(loading: false);
  }

  void clear() {
    _cancelled = true;
    _generation++;
    final cancelOcr = _cancelOcr;
    _cancelOcr = null;
    if (cancelOcr != null) unawaited(cancelOcr());
    state = const AgentOcrVariantsState();
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

  Future<OcrQuality> _assess(
    AgentOcrVariant variant,
    AgentRunServices services,
    List<DictionaryInfo> dictionaries,
    bool Function() cancelled,
  ) async {
    ({double rate, int words})? hits;
    if (dictionaries.isNotEmpty && !cancelled()) {
      try {
        hits = await OcrConsensus.measureDictionaryHits(
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
    return OcrConsensus.assess(
      variant: variant,
      dictionaryHitRate: hits?.rate,
      contentWords: hits?.words ?? 0,
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

  bool _sameRecognizedText(AgentOcrVariant left, AgentOcrVariant right) =>
      left.text.replaceAll(_whitespace, '') ==
      right.text.replaceAll(_whitespace, '');
}

const Object _unset = Object();

final agentOcrVariantsProvider =
    NotifierProvider<AgentOcrVariantsController, AgentOcrVariantsState>(
      AgentOcrVariantsController.new,
    );
