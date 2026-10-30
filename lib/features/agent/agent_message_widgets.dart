import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_messages.dart';
import '../../services/agent/agent_run.dart';
import 'agent_progress_view.dart';

class AgentUserBubble extends StatelessWidget {
  const AgentUserBubble({
    super.key,
    required this.text,
    required this.hasImage,
    this.imagePaths = const <String>[],
  });

  final String text;
  final bool hasImage;
  final List<String> imagePaths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
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
                padding: EdgeInsets.only(top: text.isEmpty ? 0 : AppSpacing.xs),
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
                            '图片（仅本机 OCR）',
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
                            label: '已发送图片 ${imagePaths.length} 张',
                            image: true,
                            child: Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                for (final path in imagePaths)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                    child: Image.file(
                                      File(path),
                                      width: AgentTokens.sentImageWidth,
                                      height: AgentTokens.sentImageHeight,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                width:
                                                    AgentTokens.sentImageWidth,
                                                height:
                                                    AgentTokens.sentImageHeight,
                                                color: AppColors.surfaceMuted,
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.broken_image_outlined,
                                                  size: AppSizes.icon,
                                                ),
                                              ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            '图片仅在本机 OCR，不会上传',
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
    );
  }
}

class AgentAssistantBubble extends StatelessWidget {
  const AgentAssistantBubble({
    super.key,
    required this.theme,
    required this.providerLabel,
    required this.mode,
    required this.running,
    required this.cancelled,
    required this.error,
    required this.errorDetail,
    required this.stageMessage,
    required this.startedAt,
    required this.finishedAt,
    required this.progressStep,
    required this.evidenceCount,
    required this.citationCount,
    required this.uiLanguage,
    required this.result,
    required this.onRetry,
    required this.onLooseRetry,
    required this.onSettings,
  });

  final ThemeData theme;
  final String providerLabel;
  final AgentMode mode;
  final bool running;
  final bool cancelled;
  final String? error;
  final String errorDetail;
  final String stageMessage;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int progressStep;
  final int evidenceCount;
  final int citationCount;
  final AgentUiLanguage uiLanguage;
  final AgentRunResult? result;
  final VoidCallback? onRetry;
  final VoidCallback? onLooseRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final modelLabel =
        '${providerLabel.isEmpty ? '模型' : providerLabel} · ${mode == AgentMode.strict ? '严格' : '宽松'}';
    final summary = result == null
        ? ''
        : result!.analysis.translation.isNotEmpty
        ? result!.analysis.translation.map((item) => item.text).join('\n')
        : result!.analysis.segments.isNotEmpty
        ? result!.analysis.segments.first.interpretation
        : '已生成结果，请展开详细解析。';
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
              AgentErrorCard(
                message: error!,
                detail: errorDetail,
                onAction: onRetry ?? onSettings,
                actionLabel: onRetry == null ? '去设置' : '重试',
                onSecondary: onLooseRetry,
                secondaryLabel: '宽松重试',
              )
            else if (running)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    language: uiLanguage,
                  ),
                  if (startedAt != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AgentElapsedLabel(
                      startedAt: startedAt!,
                      language: uiLanguage,
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
                          ? agentStageMessage(
                              AgentStage.cancelled,
                              uiLanguage,
                            )
                          : stageMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: AgentTokens.helper,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: const Text('重试')),
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
          ],
        ),
      ),
    );
  }
}

/// Ticking "thinking time" label. Character counts are intentionally not shown:
/// the provider stream is raw JSON and users should see how long the run has
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
    this.onSecondary,
    this.secondaryLabel = '',
  });

  final String message;
  final String detail;
  final VoidCallback onAction;
  final String actionLabel;
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
                  '查看诊断',
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
  });

  final bool hasProvider;
  final VoidCallback onSettings;

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
            '词典助手',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: AgentTokens.section,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '输入日文或选择图片；图片只在本机 OCR，不会上传。'
            '结果会附带可点击的词典依据。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          if (!hasProvider) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onSettings, child: const Text('去配置模型')),
          ],
        ],
      ),
    );
  }
}

