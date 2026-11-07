import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_ocr.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/agent/ocr_consensus.dart';
import '../../state/agent_ocr_variants.dart';
import 'agent_message_widgets.dart' show openAgentImageViewer;
import 'agent_thumbnail.dart';

/// P6.6: explicit multi-OCR comparison, diff preview, bounded dictionary
/// previews and dictionary-backed repair suggestions. It also renders for a
/// failed run with no result (using the locally generated baseline). It never
/// applies a variant or repair automatically and never calls a provider.
class AgentOcrVariantsPanel extends StatefulWidget {
  const AgentOcrVariantsPanel({
    super.key,
    this.result,
    this.imageSources = const <AgentSourceInput>[],
    this.ocrQuality = const <String, OcrQuality>{},
    required this.variantsState,
    required this.strings,
    this.imagePaths = const <String>[],
    this.onGenerate,
    this.onCancelGenerate,
    this.onReanalyze,
  });

  final AgentRunResult? result;

  /// Image sources when no result exists (for example the analysis failed).
  /// When [result] is present its image sources take precedence.
  final List<AgentSourceInput> imageSources;
  final Map<String, OcrQuality> ocrQuality;
  final AgentOcrVariantsState variantsState;
  final AgentUiStrings strings;

  /// Local image paths used only for the thumbnail and full-screen viewer.
  /// Never sent to the provider or persisted by this widget.
  final List<String> imagePaths;
  final void Function(String imageId)? onGenerate;
  final void Function(String imageId)? onCancelGenerate;

  /// Called with the selected/prepared variant and the opaque image id.
  final void Function(String imageId, AgentOcrVariant variant)? onReanalyze;

  @override
  State<AgentOcrVariantsPanel> createState() => _AgentOcrVariantsPanelState();
}

class _AgentOcrVariantsPanelState extends State<AgentOcrVariantsPanel> {
  final Map<String, String> _selectedByImage = <String, String>{};

  /// Selected repair candidate per image and suggestion index. The index is
  /// the word/span identity; at most one candidate is kept for each word.
  final Map<String, Map<int, OcrRepairCandidate>> _repairSelections =
      <String, Map<int, OcrRepairCandidate>>{};

  @override
  void didUpdateWidget(covariant AgentOcrVariantsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.result, widget.result)) {
      _selectedByImage.clear();
      _repairSelections.clear();
    }
    if (!identical(
          oldWidget.variantsState.repairs,
          widget.variantsState.repairs,
        ) ||
        !identical(
          oldWidget.variantsState.repairBaselineIds,
          widget.variantsState.repairBaselineIds,
        )) {
      _repairSelections.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final imageSources = result != null
        ? result.input.sources
              .where((source) => source.isImage)
              .toList(growable: false)
        : widget.imageSources
              .where((source) => source.isImage)
              .toList(growable: false);
    if (imageSources.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AgentTokens.cardPadding),
      decoration: BoxDecoration(
        color: AgentTokens.evidenceSurface,
        border: Border.all(color: AgentTokens.evidenceBorder),
        borderRadius: BorderRadius.circular(AgentTokens.evidenceRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.strings.ocrVersionsTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: AgentTokens.evidenceTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final (index, source) in imageSources.indexed) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildImageSection(context, source, index + 1),
          ],
        ],
      ),
    );
  }

  Widget _buildImageSection(
    BuildContext context,
    AgentSourceInput source,
    int imageNumber,
  ) {
    final theme = Theme.of(context);
    final imageId = source.imageId ?? source.id;
    final pathAvailable = _hasImagePath(imageNumber);
    final baseline =
        source.selectedVariant ??
        widget.variantsState.baselineVariants[imageId];
    if (baseline == null) {
      final loading = widget.variantsState.loadingImageIds.contains(imageId);
      final errorCode = widget.variantsState.errorFor(imageId);
      final canGenerate = pathAvailable && widget.onGenerate != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageHeader(context, imageNumber),
          const SizedBox(height: AppSpacing.xxs),
          if (!pathAvailable)
            Text(
              widget.strings.ocrOriginalUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.warning,
              ),
            )
          else if (loading)
            Row(
              children: [
                const SizedBox(
                  width: AppSizes.iconSmall,
                  height: AppSizes.iconSmall,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.strings.ocrVariantsLoading,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onCancelGenerate == null
                      ? null
                      : () => widget.onCancelGenerate!(imageId),
                  child: Text(widget.strings.ocrCancelComparison),
                ),
              ],
            )
          else ...[
            if (errorCode != null)
              Text(
                widget.strings.errorMessageFor(
                  errorCode,
                  widget.strings.ocrVariantsFailed,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.warning,
                ),
              ),
            _GenerateButton(
              label: widget.strings.ocrVariantsGenerate,
              onPressed: canGenerate ? () => widget.onGenerate!(imageId) : null,
            ),
          ],
        ],
      );
    }
    final variants = <String, AgentOcrVariant>{baseline.id: baseline};
    for (final variant in source.variants) {
      variants.putIfAbsent(variant.id, () => variant);
    }
    for (final variant
        in widget.variantsState.extraVariants[imageId] ??
            const <AgentOcrVariant>[]) {
      variants.putIfAbsent(variant.id, () => variant);
    }
    final stateBaseline = widget.variantsState.baselineVariants[imageId];
    if (stateBaseline != null) {
      variants.putIfAbsent(stateBaseline.id, () => stateBaseline);
    }
    final all = variants.values.toList(growable: false);
    final resultQuality =
        widget.ocrQuality[imageId] ?? widget.result?.ocrQuality[imageId];
    final qualityById = <String, OcrQuality>{
      for (final variant in all)
        variant.id: variant.id == baseline.id && resultQuality != null
            ? resultQuality
            : widget.variantsState.qualities[imageId]?[variant.id] ??
                  OcrConsensus.assess(variant: variant),
    };
    final view = OcrConsensus.compare(
      baseline: baseline,
      variants: all,
      qualityById: qualityById,
    );
    final selectedId =
        _selectedByImage[imageId] ?? source.selectedVariantId ?? baseline.id;
    final selected = all.firstWhere(
      (variant) => variant.id == selectedId,
      orElse: () => baseline,
    );
    final comparison = view.comparisons.firstWhere(
      (item) => item.variant.id == selected.id,
      orElse: () => view.comparisons.first,
    );
    final isBaseline = selected.id == baseline.id;
    final repairs =
        widget.variantsState.repairBaselineIds[imageId] == baseline.id
        ? widget.variantsState.repairs[imageId] ?? const <OcrRepairSuggestion>[]
        : const <OcrRepairSuggestion>[];
    final repairSelections =
        _repairSelections[imageId] ?? const <int, OcrRepairCandidate>{};
    final generated = widget.variantsState.generatedImages.contains(imageId);
    final loading = widget.variantsState.loadingImageIds.contains(imageId);
    final errorCode = widget.variantsState.errorFor(imageId);
    final canGenerate = pathAvailable && widget.onGenerate != null;
    final preview = widget.variantsState.previews[imageId]?[selected.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImageHeader(context, imageNumber),
        if (!pathAvailable) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.strings.ocrOriginalUnavailable,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          alignment: WrapAlignment.start,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            for (final item in view.comparisons)
              _VariantChip(
                label: _variantLabel(item.variant),
                selected: item.variant.id == selected.id,
                recommended: item.recommended,
                recommendedLabel: widget.strings.ocrRecommended,
                onTap: () =>
                    setState(() => _selectedByImage[imageId] = item.variant.id),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        _QualityMetrics(quality: comparison.quality, strings: widget.strings),
        if (comparison.quality.isLowQuality) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.strings.ocrQualityLow,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        ],
        if (!loading && preview != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _VariantLookupPreview(preview: preview, strings: widget.strings),
        ],
        if (loading) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const SizedBox(
                width: AppSizes.iconSmall,
                height: AppSizes.iconSmall,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.strings.ocrVariantsLoading,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onCancelGenerate == null
                    ? null
                    : () => widget.onCancelGenerate!(imageId),
                child: Text(widget.strings.ocrCancelComparison),
              ),
            ],
          ),
        ] else if (errorCode != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.strings.errorMessageFor(
              errorCode,
              widget.strings.ocrVariantsFailed,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
          _GenerateButton(
            label: widget.strings.ocrVariantsGenerate,
            onPressed: canGenerate ? () => widget.onGenerate!(imageId) : null,
          ),
        ] else if (!generated) ...[
          _GenerateButton(
            label: widget.strings.ocrVariantsGenerate,
            onPressed: canGenerate ? () => widget.onGenerate!(imageId) : null,
          ),
        ] else if (view.comparisons.length <= 1) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.strings.ocrVariantsUnavailable,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          _GenerateButton(
            label: widget.strings.ocrVariantsRegenerate,
            onPressed: canGenerate ? () => widget.onGenerate!(imageId) : null,
          ),
        ] else if (isBaseline && repairs.isEmpty) ...[
          _GenerateButton(
            label: widget.strings.ocrRepairSearch,
            onPressed: canGenerate ? () => widget.onGenerate!(imageId) : null,
          ),
        ],
        if (!loading && !isBaseline) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.strings.ocrDiffHint,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _HighlightedText(spans: comparison.diffFromBaseline.candidateSpans),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: widget.onReanalyze == null
                  ? null
                  : () => widget.onReanalyze!(imageId, selected),
              child: Text(widget.strings.ocrUseVariant),
            ),
          ),
        ],
        if (!loading && isBaseline && repairs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.strings.ocrRepairsTitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.strings.ocrRepairHint,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          for (final (index, suggestion) in repairs.indexed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    suggestion.original,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    '→',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        for (final candidate in suggestion.candidates)
                          _RepairCandidateButton(
                            label: candidate.text,
                            selected:
                                repairSelections[index]?.text == candidate.text,
                            onTap: () => _toggleRepairCandidate(
                              imageId: imageId,
                              suggestionIndex: index,
                              candidate: candidate,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed:
                  widget.onReanalyze == null ||
                      !repairs.indexed.any(
                        (entry) => repairSelections.containsKey(entry.$1),
                      )
                  ? null
                  : () => _applySelectedRepairs(
                      imageId: imageId,
                      baseline: baseline,
                      repairs: repairs,
                    ),
              child: Text(widget.strings.ocrUseVariant),
            ),
          ),
        ],
      ],
    );
  }

  String _variantLabel(AgentOcrVariant variant) {
    final engine = widget.strings.ocrEngineLabel(variant.engine);
    final mode = switch (variant.mode) {
      OcrMode.auto => widget.strings.ocrModeAuto,
      OcrMode.horizontal => widget.strings.ocrModeHorizontal,
      OcrMode.vertical => widget.strings.ocrModeVertical,
    };
    final confidence = variant.confidence > 0
        ? ' · ${(variant.confidence * 100).round()}%'
        : '';
    return '$engine · $mode$confidence';
  }

  bool _hasImagePath(int imageNumber) {
    final path = imageNumber - 1 < widget.imagePaths.length
        ? widget.imagePaths[imageNumber - 1]
        : '';
    if (path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Widget _buildImageHeader(BuildContext context, int imageNumber) {
    final theme = Theme.of(context);
    final path = imageNumber - 1 < widget.imagePaths.length
        ? widget.imagePaths[imageNumber - 1]
        : '';
    if (path.isEmpty) {
      return Row(
        children: [
          Container(
            width: AgentTokens.sentImageWidth,
            height: AgentTokens.sentImageHeight,
            color: AppColors.surfaceMuted,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, size: AppSizes.icon),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            widget.strings.ocrImageUnavailable,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      image: true,
      label: '${widget.strings.ocrVersionsTitle} $imageNumber',
      child: GestureDetector(
        key: ValueKey('agent-ocr-image-$imageNumber'),
        onTap: () => openAgentImageViewer(context, path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.file(
            File(path),
            width: AgentTokens.sentImageWidth,
            height: AgentTokens.sentImageHeight,
            cacheWidth: agentThumbnailCacheSize(
              context,
              AgentTokens.sentImageWidth,
            ),
            cacheHeight: agentThumbnailCacheSize(
              context,
              AgentTokens.sentImageHeight,
            ),
            filterQuality: FilterQuality.low,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: AgentTokens.sentImageWidth,
              height: AgentTokens.sentImageHeight,
              color: AppColors.surfaceMuted,
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                size: AppSizes.icon,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleRepairCandidate({
    required String imageId,
    required int suggestionIndex,
    required OcrRepairCandidate candidate,
  }) {
    setState(() {
      final selected = _repairSelections.putIfAbsent(
        imageId,
        () => <int, OcrRepairCandidate>{},
      );
      if (selected[suggestionIndex]?.text == candidate.text) {
        selected.remove(suggestionIndex);
      } else {
        // One candidate per suspicious word/span.
        selected[suggestionIndex] = candidate;
      }
      if (selected.isEmpty) _repairSelections.remove(imageId);
    });
  }

  void _applySelectedRepairs({
    required String imageId,
    required AgentOcrVariant baseline,
    required List<OcrRepairSuggestion> repairs,
  }) {
    final selected = _repairSelections[imageId];
    if (selected == null || selected.isEmpty) return;
    final selections = <OcrRepairSelection>[
      for (final entry in selected.entries)
        if (entry.key >= 0 &&
            entry.key < repairs.length &&
            repairs[entry.key].candidates.any(
              (candidate) => candidate.text == entry.value.text,
            ))
          OcrRepairSelection(
            suggestion: repairs[entry.key],
            candidate: entry.value,
          ),
    ];
    final repaired = OcrConsensus.applyRepairs(
      baseline: baseline,
      selections: selections,
      id: 'repair-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (repaired == null) return;
    setState(() => _repairSelections.remove(imageId));
    widget.onReanalyze?.call(imageId, repaired);
  }
}

class _VariantLookupPreview extends StatelessWidget {
  const _VariantLookupPreview({required this.preview, required this.strings});

  final OcrVariantLookupPreview preview;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.ocrPreviewTitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            strings.ocrPreviewHits(preview.hitCount),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          if (preview.entries.isEmpty && preview.hitCount == 0) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              strings.ocrPreviewEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.textSecondary,
              ),
            ),
          ] else
            for (final entry in preview.entries)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  '${entry.dictionaryTitle} · '
                  '${entry.headword.isEmpty ? strings.citationTitleFallback : entry.headword}'
                  '：${entry.snippet}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _QualityMetrics extends StatelessWidget {
  const _QualityMetrics({required this.quality, required this.strings});

  final OcrQuality quality;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final confidence = quality.meanConfidence > 0
        ? strings.ocrPercent((quality.meanConfidence * 100).round())
        : strings.ocrUnknownValue;
    final hitRate = quality.dictionaryHitRate != null
        ? strings.ocrPercent((quality.dictionaryHitRate! * 100).round())
        : strings.ocrUnknownValue;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _MetricPill(label: strings.ocrConfidenceLabel, value: confidence),
        _MetricPill(label: strings.ocrDictionaryHitLabel, value: hitRate),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: AgentTokens.citationChipHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(
              AgentTokens.citationChipHeight / 2,
            ),
            border: Border.all(color: AgentTokens.evidenceBorder),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.citationChip,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.helper,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _VariantChip extends StatelessWidget {
  const _VariantChip({
    required this.label,
    required this.selected,
    required this.recommended,
    required this.recommendedLabel,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool recommended;
  final String recommendedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: recommended ? '$label · $recommendedLabel' : label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            AgentTokens.ocrVariantChipHeight / 2,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AgentTokens.actionTapTarget,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                height: AgentTokens.ocrVariantChipHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: selected
                      ? AgentTokens.citationSurface
                      : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(
                    AgentTokens.ocrVariantChipHeight / 2,
                  ),
                  border: Border.all(
                    color: selected
                        ? AgentTokens.citationText
                        : AgentTokens.evidenceBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AgentTokens.ocrVariantChipMaxWidth,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: AgentTokens.citationChip,
                          color: selected
                              ? AgentTokens.citationText
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // Reserve the icon slot even when this variant is not the
                    // recommended one, so selecting a chip never changes its
                    // width and all chips share the same visual size.
                    const SizedBox(width: AppSpacing.xs),
                    SizedBox(
                      width: AgentTokens.citationChip,
                      height: AgentTokens.citationChip,
                      child: recommended
                          ? Icon(
                              Icons.auto_awesome,
                              size: AgentTokens.citationChip,
                              color: selected
                                  ? AgentTokens.citationText
                                  : AppColors.textSecondary,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  const _GenerateButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.compare_arrows, size: AppSizes.iconSmall),
        label: Text(label),
      ),
    );
  }
}

class _RepairCandidateButton extends StatelessWidget {
  const _RepairCandidateButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _RepairChip(label: label, selected: selected, onTap: onTap);
  }
}

class _RepairChip extends StatelessWidget {
  const _RepairChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            AgentTokens.ocrVariantChipHeight / 2,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AgentTokens.actionTapTarget,
              minWidth: AgentTokens.citationChipMinWidth,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: Container(
                height: AgentTokens.ocrVariantChipHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: selected
                      ? AgentTokens.citationSurface
                      : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(
                    AgentTokens.ocrVariantChipHeight / 2,
                  ),
                  border: Border.all(
                    color: selected
                        ? AgentTokens.citationText
                        : AgentTokens.evidenceBorder,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.citationChip,
                      color: selected
                          ? AgentTokens.citationText
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.spans});

  final List<OcrDiffSpan> spans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(
      fontSize: AgentTokens.helper,
      height: 1.5,
      color: AppColors.textPrimary,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            for (final span in spans)
              TextSpan(
                text: span.text,
                style: span.changed
                    ? base?.copyWith(
                        backgroundColor: AgentTokens.diffHighlightSurface,
                        color: AgentTokens.diffHighlightText,
                        fontWeight: FontWeight.w600,
                      )
                    : base?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
        key: const ValueKey('agent-ocr-diff'),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
