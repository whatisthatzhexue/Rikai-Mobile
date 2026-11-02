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

/// P6.6: explicit multi-OCR comparison, diff preview and dictionary-backed
/// repair suggestions. It never applies a variant or repair automatically.
class AgentOcrVariantsPanel extends StatefulWidget {
  const AgentOcrVariantsPanel({
    super.key,
    required this.result,
    required this.variantsState,
    required this.strings,
    this.imagePaths = const <String>[],
    this.onGenerate,
    this.onCancelGenerate,
    this.onReanalyze,
  });

  final AgentRunResult result;
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

  @override
  void didUpdateWidget(covariant AgentOcrVariantsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.result, widget.result)) {
      _selectedByImage.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageSources = widget.result.input.sources
        .where((source) => source.isImage && source.selectedVariant != null)
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
    final baseline = source.selectedVariant!;
    final variants = <String, AgentOcrVariant>{baseline.id: baseline};
    for (final variant in source.variants) {
      variants.putIfAbsent(variant.id, () => variant);
    }
    for (final variant
        in widget.variantsState.extraVariants[imageId] ??
            const <AgentOcrVariant>[]) {
      variants.putIfAbsent(variant.id, () => variant);
    }
    final all = variants.values.toList(growable: false);
    final qualityById = <String, OcrQuality>{
      for (final variant in all)
        variant.id:
            variant.id == baseline.id &&
                widget.result.ocrQuality[imageId] != null
            ? widget.result.ocrQuality[imageId]!
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
    final generated = widget.variantsState.generatedImages.contains(imageId);
    final loading = widget.variantsState.loadingImageIds.contains(imageId);
    final errorCode = widget.variantsState.errorFor(imageId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImageHeader(context, imageNumber),
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
            onPressed: widget.onGenerate == null
                ? null
                : () => widget.onGenerate!(imageId),
          ),
        ] else if (!generated) ...[
          _GenerateButton(
            label: widget.strings.ocrVariantsGenerate,
            onPressed: widget.onGenerate == null
                ? null
                : () => widget.onGenerate!(imageId),
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
            onPressed: widget.onGenerate == null
                ? null
                : () => widget.onGenerate!(imageId),
          ),
        ] else if (isBaseline && repairs.isEmpty) ...[
          _GenerateButton(
            label: widget.strings.ocrRepairSearch,
            onPressed: widget.onGenerate == null
                ? null
                : () => widget.onGenerate!(imageId),
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
          for (final suggestion in repairs)
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
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        for (final candidate in suggestion.candidates)
                          _RepairCandidateButton(
                            label: candidate.text,
                            onTap: () => _applyRepair(
                              imageId: imageId,
                              baseline: baseline,
                              suggestion: suggestion,
                              candidate: candidate,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
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

  void _applyRepair({
    required String imageId,
    required AgentOcrVariant baseline,
    required OcrRepairSuggestion suggestion,
    required OcrRepairCandidate candidate,
  }) {
    final repaired = OcrConsensus.applyRepair(
      baseline: baseline,
      suggestion: suggestion,
      candidate: candidate,
      id: 'repair-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (repaired == null) return;
    widget.onReanalyze?.call(imageId, repaired);
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
  const _RepairCandidateButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            AgentTokens.citationChipHeight / 2,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AgentTokens.actionTapTarget,
              minWidth: AgentTokens.citationChipMinWidth,
            ),
            child: Center(
              child: Container(
                height: AgentTokens.citationChipHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AgentTokens.citationSurface,
                  borderRadius: BorderRadius.circular(
                    AgentTokens.citationChipHeight / 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.citationChip,
                      color: AgentTokens.citationText,
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
