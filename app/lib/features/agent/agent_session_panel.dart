import 'package:flutter/material.dart';

import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/dict_info.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../lookup/dictionary_filter_bar.dart';

Widget buildAgentSessionBar(
  BuildContext context, {
  required AgentMode mode,
  required String providerName,
  required bool expanded,
  required AgentUiStrings strings,
  required VoidCallback onToggle,
}) {
  final theme = Theme.of(context);
  final modeLabel = mode == AgentMode.strict
      ? strings.strictShort
      : strings.looseShort;
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
                  '${strings.sessionSettings} · $modeLabel · $providerName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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
  required AgentUiStrings strings,
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
            ProviderEmptyBanner(onTap: onOpenSettings, strings: strings)
          else
            DropdownButtonFormField<String>(
              initialValue: provider?.id,
              decoration: InputDecoration(
                labelText: strings.model,
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
            segments: <ButtonSegment<AgentMode>>[
              ButtonSegment(
                value: AgentMode.strict,
                label: Text(strings.strictMode),
              ),
              ButtonSegment(
                value: AgentMode.loose,
                label: Text(strings.looseMode),
              ),
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
                strings.sessionDictionaries,
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
                strings.noDictionaries,
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
  const ProviderEmptyBanner({
    super.key,
    required this.onTap,
    required this.strings,
  });

  final VoidCallback onTap;
  final AgentUiStrings strings;

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
            strings.noProviderTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: AgentTokens.evidenceTitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            strings.noProviderBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: onTap,
            child: Text(strings.goConfigureModel),
          ),
        ],
      ),
    );
  }
}
