import 'package:flutter/material.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/dict_info.dart';
import '../../core/theme/app_tokens.dart';
import '../lookup/dictionary_filter_bar.dart';

Widget buildAgentSessionBar(
  BuildContext context, {
  required AgentMode mode,
  required String providerName,
  required bool expanded,
  required VoidCallback onToggle,
}) {
  final theme = Theme.of(context);
  final modeLabel = mode == AgentMode.strict ? '严格' : '宽松';
  return Material(
    color: AgentTokens.supplementSurface,
    child: InkWell(
      onTap: onToggle,
      child: SizedBox(
        height: AgentTokens.composerButton,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '本会话设置 · $modeLabel · $providerName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: AppSizes.icon,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget buildAgentSessionPanel(
  BuildContext context, {
  required List<AgentProviderConfig> providers,
  required AgentProviderConfig? provider,
  required AgentMode mode,
  required List<DictionaryInfo> enabled,
  required Set<String> selectedIds,
  required DictionarySelectionMode selectionMode,
  required bool running,
  required ValueChanged<String?> onProviderChanged,
  required ValueChanged<AgentMode> onModeChanged,
  required ValueChanged<DictionarySelectionMode> onSelectionModeChanged,
  required ValueChanged<String> onToggleDictionary,
  required VoidCallback onSelectAll,
  required VoidCallback onOpenSettings,
}) {
  final theme = Theme.of(context);
  return ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 320),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (providers.isEmpty)
            ProviderEmptyBanner(onTap: onOpenSettings)
          else
            DropdownButtonFormField<String>(
              initialValue: provider?.id,
              decoration: const InputDecoration(
                labelText: '模型',
                isDense: true,
              ),
              items: <DropdownMenuItem<String>>[
                for (final item in providers)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.displayName),
                  ),
              ],
              onChanged: running ? null : onProviderChanged,
            ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<AgentMode>(
            segments: const <ButtonSegment<AgentMode>>[
              ButtonSegment(value: AgentMode.strict, label: Text('严格模式')),
              ButtonSegment(value: AgentMode.loose, label: Text('宽松模式')),
            ],
            selected: <AgentMode>{mode},
            showSelectedIcon: false,
            onSelectionChanged: running
                ? null
                : (selection) => onModeChanged(selection.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                '本次词典',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: AgentTokens.evidenceTitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              DictionarySelectionModeToggle(
                mode: selectionMode,
                onChanged: running ? (_) {} : onSelectionModeChanged,
              ),
            ],
          ),
          if (enabled.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '尚未添加可用的 MDict 词典',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            DictionaryFilterBar(
              dictionaries: enabled,
              selectedIds: selectedIds,
              mode: selectionMode,
              onToggle: running ? (_) {} : onToggleDictionary,
              onSelectAll: running ? () {} : onSelectAll,
            ),
        ],
      ),
    ),
  );
}

class ProviderEmptyBanner extends StatelessWidget {
  const ProviderEmptyBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '尚未配置模型',
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: AgentTokens.evidenceTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '配置 API Key 后才能使用词典助手；图片仍只在本机 OCR，不会上传。',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onTap, child: const Text('去配置模型')),
        ],
      ),
    );
  }
}
