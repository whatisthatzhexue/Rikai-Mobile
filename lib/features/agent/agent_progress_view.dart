import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_messages.dart';

/// Coarse, safe progress for a run: OCR → lookup → generate → validate.
/// It never renders streamed model JSON or hidden reasoning.
class AgentProgressView extends StatelessWidget {
  const AgentProgressView({
    super.key,
    required this.running,
    required this.step,
    required this.evidenceCount,
    required this.citationCount,
    required this.language,
  });

  final bool running;
  final int step;
  final int evidenceCount;
  final int citationCount;
  final AgentUiLanguage language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = agentProgressStepLabels(language);
    final current = step.clamp(0, labels.length);
    return Semantics(
      label: '${labels[(current < labels.length ? current : labels.length - 1)]} '
          '$current/${labels.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: current / labels.length,
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.divider,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (var index = 0; index < labels.length; index++)
                Expanded(
                  child: _ProgressStep(
                    label: labels[index],
                    index: index,
                    current: current,
                    running: running,
                  ),
                ),
            ],
          ),
          if (evidenceCount > 0 || citationCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              agentEvidenceProgressLabel(
                evidenceCount,
                citationCount,
                language,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.label,
    required this.index,
    required this.current,
    required this.running,
  });

  final String label;
  final int index;
  final int current;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    final background = done || active
        ? AppColors.primary
        : AppColors.surfaceMuted;
    final foreground = done || active
        ? AppColors.onHeader
        : AppColors.textSecondary;
    return Column(
      children: [
        Container(
          width: AppSizes.iconSmall,
          height: AppSizes.iconSmall,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: done
              ? Icon(Icons.check, size: 10, color: foreground)
              : Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 9,
                    color: foreground,
                    height: 1,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.citationChip,
            color: active && running
                ? AppColors.primary
                : AppColors.textSecondary,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
