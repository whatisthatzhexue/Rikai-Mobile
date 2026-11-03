import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/page_route.dart';
import '../../services/agent/agent_messages.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../capture/photo_viewer_page.dart';
import 'agent_progress_view.dart';
import 'agent_rich_text.dart';
import 'agent_thumbnail.dart';

class AgentUserBubble extends StatelessWidget {
  const AgentUserBubble({
    super.key,
    required this.text,
    required this.hasImage,
    this.imagePaths = const <String>[],
    required this.strings,
    this.onLongPress,
  });

  final String text;
  final bool hasImage;
  final List<String> imagePaths;
  final AgentUiStrings strings;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.sizeOf(context).width * AgentTokens.messageMaxWidth,
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AgentTokens.userSurface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AgentTokens.bubbleRadius),
              topRight: Radius.circular(AgentTokens.bubbleRadius),
              bottomLeft: Radius.circular(AgentTokens.bubbleRadius),
              bottomRight: Radius.circular(AgentTokens.bubbleTailRadius),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: AgentTokens.body,
                    color: AppColors.textPrimary,
                  ),
                ),
              if (hasImage)
                Padding(
                  padding: EdgeInsets.only(
                    top: text.isEmpty ? 0 : AppSpacing.xs,
                  ),
                  child: imagePaths.isEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.image_outlined,
                              size: AppSizes.icon,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              strings.imageOnly,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: AgentTokens.helper,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              label: strings.sentImages(imagePaths.length),
                              image: true,
                              child: Wrap(
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  for (
                                    var index = 0;
                                    index < imagePaths.length;
                                    index++
                                  )
                                    Semantics(
                                      button: true,
                                      label:
                                          '${strings.imageOnly} ${index + 1}',
                                      child: GestureDetector(
                                        key: ValueKey(
                                          'agent-sent-image-$index',
                                        ),
                                        onTap: () => openAgentImageViewer(
                                          context,
                                          imagePaths[index],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.sm,
                                          ),
                                          child: Image.file(
                                            File(imagePaths[index]),
                                            width: AgentTokens.sentImageWidth,
                                            height: AgentTokens.sentImageHeight,
                                            cacheWidth: agentThumbnailCacheSize(
                                              context,
                                              AgentTokens.sentImageWidth,
                                            ),
                                            cacheHeight:
                                                agentThumbnailCacheSize(
                                                  context,
                                                  AgentTokens.sentImageHeight,
                                                ),
                                            filterQuality: FilterQuality.low,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) => Container(
                                                  width: AgentTokens
                                                      .sentImageWidth,
                                                  height: AgentTokens
                                                      .sentImageHeight,
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
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              strings.imageLocalOnly,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: AgentTokens.helper,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void openAgentImageViewer(BuildContext context, String path) {
  Navigator.of(context).push(
    RikaiPageRoute<void>(
      builder: (context) => PhotoViewerPage(imagePath: path),
    ),
  );
}

class AgentAssistantBubble extends StatelessWidget {
  const AgentAssistantBubble({
    super.key,
    required this.theme,
    required this.providerLabel,
    required this.mode,
    required this.running,
    this.provisional = false,
    required this.cancelled,
    required this.error,
    required this.errorDetail,
    required this.stageMessage,
    required this.startedAt,
    required this.finishedAt,
    required this.progressStep,
    required this.evidenceCount,
    required this.citationCount,
    this.maxEvidenceEntries = 0,
    required this.uiLanguage,
    required this.strings,
    required this.result,
    required this.onRetry,
    required this.onLooseRetry,
    required this.onSettings,
    this.resultRetainedAfterFailure = false,
    this.onRegenerate,
    this.onCopy,
  });

  final ThemeData theme;
  final String providerLabel;
  final AgentMode mode;
  final bool running;

  /// True while [result] is a provisional answer shown before optional
  /// format/language post-checks finish.
  final bool provisional;
  final bool cancelled;
  final String? error;
  final String errorDetail;
  final String stageMessage;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int progressStep;
  final int evidenceCount;
  final int citationCount;
  final int maxEvidenceEntries;
  final AgentUiLanguage uiLanguage;
  final AgentUiStrings strings;
  final AgentRunResult? result;
  final VoidCallback? onRetry;
  final VoidCallback? onLooseRetry;
  final VoidCallback onSettings;
  final bool resultRetainedAfterFailure;
  final VoidCallback? onRegenerate;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final modelLabel =
        '${providerLabel.isEmpty ? strings.model : providerLabel} · '
        '${mode == AgentMode.strict ? strings.strictShort : strings.looseShort}';
    final summarySource = result == null
        ? ''
        : result!.richSummary ?? agentSummaryDisplayText(result!.analysis);
    final summary = summarySource.isEmpty
        ? strings.assistantFallback
        : summarySource;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width * AgentTokens.messageMaxWidth,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AgentTokens.assistantSurface,
          border: Border.all(color: AgentTokens.evidenceBorder),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AgentTokens.bubbleTailRadius),
            topRight: Radius.circular(AgentTokens.bubbleRadius),
            bottomLeft: Radius.circular(AgentTokens.bubbleRadius),
            bottomRight: Radius.circular(AgentTokens.bubbleRadius),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              modelLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AgentTokens.modelLabel,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AgentErrorCard(
                    message: error!,
                    detail: errorDetail,
                    onAction: onRetry ?? onSettings,
                    actionLabel: onRetry == null
                        ? strings.goSettings
                        : strings.retry,
                    onSecondary: onLooseRetry,
                    secondaryLabel: strings.looseRetry,
                    strings: strings,
                  ),
                  if (resultRetainedAfterFailure) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      strings.resultRetainedAfterFailure,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: AgentTokens.helper,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AgentRichText(
                      text: summary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: AgentTokens.body,
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              )
            else if (running)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (provisional) ...[
                    AgentRichText(
                      text: summary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: AgentTokens.body,
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      strings.resultReviewing,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: AgentTokens.helper,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
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
                          stageMessage.isEmpty
                              ? agentThinkingFallback(uiLanguage)
                              : stageMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: AgentTokens.helper,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AgentProgressView(
                    running: true,
                    step: progressStep,
                    evidenceCount: evidenceCount,
                    citationCount: citationCount,
                    maxEvidenceEntries: maxEvidenceEntries,
                    language: uiLanguage,
                  ),
                  if (startedAt != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AgentElapsedLabel(
                      startedAt: startedAt!,
                      language: uiLanguage,
                    ),
                  ],
                  if (!provisional && result != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      strings.retainedResult,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: AgentTokens.helper,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              )
            else if (cancelled)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stageMessage.isEmpty
                          ? agentStageMessage(AgentStage.cancelled, uiLanguage)
                          : stageMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: AgentTokens.helper,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: Text(strings.retry)),
                ],
              )
            else
              Text(
                summary,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: AgentTokens.body,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            if (!running && startedAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              if (evidenceCount > 0 || citationCount > 0)
                Text(
                  agentEvidenceProgressLabel(
                    evidenceCount,
                    citationCount,
                    maxEvidenceEntries,
                    uiLanguage,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: AppSpacing.xxs),
              AgentElapsedLabel(
                startedAt: startedAt!,
                finishedAt: finishedAt,
                language: uiLanguage,
              ),
            ],
            if (!running &&
                result != null &&
                (onRegenerate != null || onCopy != null)) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onRegenerate != null)
                      IconButton(
                        tooltip: strings.regenerateResult,
                        onPressed: onRegenerate,
                        iconSize: AgentTokens.actionIcon,
                        constraints: const BoxConstraints(
                          minWidth: AgentTokens.actionTapTarget,
                          minHeight: AgentTokens.actionTapTarget,
                        ),
                        icon: const Icon(Icons.refresh),
                      ),
                    if (onCopy != null)
                      IconButton(
                        tooltip: strings.copyResultMarkdown,
                        onPressed: onCopy,
                        iconSize: AgentTokens.actionIcon,
                        constraints: const BoxConstraints(
                          minWidth: AgentTokens.actionTapTarget,
                          minHeight: AgentTokens.actionTapTarget,
                        ),
                        icon: const Icon(Icons.copy_outlined),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ticking "thinking time" label. Character counts are intentionally not shown:
/// the provider stream is raw tagged text and users should see how long the run has
/// been thinking, not internal generation volume.
class AgentElapsedLabel extends StatefulWidget {
  const AgentElapsedLabel({
    super.key,
    required this.startedAt,
    required this.language,
    this.finishedAt,
  });

  final DateTime startedAt;
  final AgentUiLanguage language;
  final DateTime? finishedAt;

  @override
  State<AgentElapsedLabel> createState() => _AgentElapsedLabelState();
}

class _AgentElapsedLabelState extends State<AgentElapsedLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AgentElapsedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.finishedAt != null) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null) {
      _startTimerIfNeeded();
    }
  }

  void _startTimerIfNeeded() {
    if (widget.finishedAt != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.finishedAt ?? DateTime.now();
    final elapsed = end.difference(widget.startedAt);
    final text = agentElapsedLabel(elapsed.inSeconds, widget.language);
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: AgentTokens.helper,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class AgentErrorCard extends StatelessWidget {
  const AgentErrorCard({
    super.key,
    required this.message,
    required this.detail,
    required this.onAction,
    required this.actionLabel,
    required this.strings,
    this.onSecondary,
    this.secondaryLabel = '',
  });

  final String message;
  final String detail;
  final VoidCallback onAction;
  final String actionLabel;
  final AgentUiStrings strings;
  final VoidCallback? onSecondary;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                size: AppSizes.icon,
                color: AppColors.error,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
                title: Text(
                  strings.viewDiagnostics,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.citationChip,
                    color: AppColors.textSecondary,
                  ),
                ),
                children: [
                  Text(
                    detail,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSecondary != null)
                  TextButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel),
                  ),
                TextButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AgentEmptyState extends StatelessWidget {
  const AgentEmptyState({
    super.key,
    required this.hasProvider,
    required this.onSettings,
    required this.strings,
  });

  final bool hasProvider;
  final VoidCallback onSettings;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.assistant_outlined,
            size: AppSizes.heroIcon,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            strings.emptyTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: AgentTokens.section,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            strings.emptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          if (!hasProvider) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: onSettings,
              child: Text(strings.goConfigureModel),
            ),
          ],
        ],
      ),
    );
  }
}
