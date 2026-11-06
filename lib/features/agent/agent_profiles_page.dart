import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/dict_info.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../core/utils/date_format.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart';
import '../../services/agent/familiarization/profile_fingerprint.dart';
import '../../state/agent_profile_inbox.dart';
import '../../state/agent_profile_manager.dart';
import '../../state/agent_providers.dart';
import '../../state/agent_run_controller.dart';
import '../../state/providers.dart';
import 'agent_profile_inbox_host.dart';
import 'familiarization_sheet.dart';

// Stable keys keep each AppBar action's element (and its ink/focus state) tied
// to the action itself. Without them, inserting the selection actions at the
// front makes Flutter reuse the tapped selection-mode button's element for the
// new "select all" button, which then shows a lingering highlight.
const _selectAllActionKey = ValueKey<String>('agent-profile-action-select-all');
const _regenerateSelectedActionKey = ValueKey<String>(
  'agent-profile-action-regenerate-selected',
);
const _deleteSelectedActionKey = ValueKey<String>(
  'agent-profile-action-delete-selected',
);
const _selectionModeActionKey = ValueKey<String>(
  'agent-profile-action-selection-mode',
);

class AgentProfilesPage extends ConsumerStatefulWidget {
  const AgentProfilesPage({super.key});

  @override
  ConsumerState<AgentProfilesPage> createState() => _AgentProfilesPageState();
}

class _AgentProfilesPageState extends ConsumerState<AgentProfilesPage> {
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  final Map<String, Future<bool>> _staleFutures = <String, Future<bool>>{};

  AgentUiStrings _strings() {
    final run = ref.read(agentRunControllerProvider);
    final settings = ref.read(appSettingsProvider);
    final language = run.hasConversation
        ? run.responseLanguage
        : AgentResponseLanguage.fromWire(settings.agentResponseLanguage);
    return AgentUiStrings.of(resolveAgentUiLanguage(language));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = _strings();
    final profilesAsync = ref.watch(agentProfilesProvider);
    final enabled = ref.watch(enabledDictionariesProvider);
    final pending = ref.watch(agentProfileInboxProvider).pending;
    final profilesInUse = ref.watch(agentRunControllerProvider).profilesInUse;
    final regeneration = ref.watch(agentProfileRegenerationProvider);
    final settings = ref.watch(appSettingsProvider);
    final canRegenerateSelection =
        _selected.isNotEmpty &&
        enabled.any(
          (dictionary) =>
              _selected.contains(dictionary.id) &&
              !regeneration.isGenerating(dictionary.id),
        );
    ref.listen(appSettingsProvider, (previous, next) {
      if (previous?.agentProfileLanguage != next.agentProfileLanguage) {
        _staleFutures.clear();
      }
    });
    ref.listen(agentProfileRegenerationProvider, (previous, next) {
      final error = next.error;
      if (error == null || error == previous?.error) return;
      final message = error == 'profile_regenerate_failed'
          ? strings.profileRegenerateFailed
          : error;
      RikaiToast.show(context, message);
      ref.read(agentProfileRegenerationProvider.notifier).clearError();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.profileManagerTitle),
        actions: [
          if (_selecting) ...[
            IconButton(
              key: _selectAllActionKey,
              tooltip: strings.profileSelectAll,
              onPressed: () {
                final profiles = profilesAsync.asData?.value ?? const [];
                setState(() {
                  _selected
                    ..clear()
                    ..addAll(profiles.map((profile) => profile.dictionaryId));
                });
              },
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              key: _regenerateSelectedActionKey,
              tooltip: strings.profileRegenerateSelected,
              onPressed: canRegenerateSelection
                  ? () => _regenerateSelected(enabled)
                  : null,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              key: _deleteSelectedActionKey,
              tooltip: strings.profileDeleteSelected,
              onPressed: profilesInUse || _selected.isEmpty
                  ? null
                  : () => _deleteSelected(strings),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          // Keep the mode toggle as the rightmost action in both states. It
          // must not be replaced by "select all" in place, which caused a
          // lingering highlight and a visual jump.
          IconButton(
            key: _selectionModeActionKey,
            tooltip: _selecting
                ? strings.profileExitSelection
                : strings.profileSelectMode,
            onPressed: () => setState(() {
              _selecting = !_selecting;
              if (!_selecting) _selected.clear();
            }),
            icon: Icon(_selecting ? Icons.close : Icons.checklist),
          ),
        ],
      ),
      body: AgentProfileInboxHost(
        strings: strings,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (regeneration.active)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        strings.regeneratingProfile(
                          regeneration.titles.join('、'),
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: AgentTokens.helper,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const LinearProgressIndicator(),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  children: [
                    if (pending.isNotEmpty) ...[
                      Text(
                        strings.pendingProfiles(pending.length),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: AgentTokens.helper,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (final proposal in pending)
                        _ProfileCard(
                          title: proposal.title,
                          statusLabel: strings.profileStatusPending,
                          statusColor: AppColors.warning,
                          subtitle: '',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: strings.profileRegenerate,
                                onPressed:
                                    regeneration.isGenerating(
                                      proposal.dictionary.id,
                                    )
                                    ? null
                                    : () => _regenerate(
                                        proposal.dictionary,
                                        strings,
                                      ),
                                icon: const Icon(
                                  Icons.refresh,
                                  size: AppSizes.icon,
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _resolveProposal(proposal, strings),
                                child: Text(strings.profileOpen),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: AppSpacing.xl),
                    ],
                    profilesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                      error: (error, stack) => Text(
                        strings.providerLoadFailed,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: AgentTokens.helper,
                          color: AppColors.error,
                        ),
                      ),
                      data: (profiles) {
                        if (profiles.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xl,
                            ),
                            child: Text(
                              strings.profileManagerEmpty,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: AgentTokens.helper,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final profile in profiles)
                              _buildProfileCard(
                                context,
                                profile,
                                enabled,
                                settings.agentProfileLanguage,
                                profilesInUse,
                                regeneration,
                                strings,
                              ),
                          ],
                        );
                      },
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

  Widget _buildProfileCard(
    BuildContext context,
    StoredDictionaryProfile profile,
    List<DictionaryInfo> enabled,
    String profileLanguage,
    bool profilesInUse,
    AgentProfileRegenerationState regeneration,
    AgentUiStrings strings,
  ) {
    DictionaryInfo? dictionary;
    for (final item in enabled) {
      if (item.id == profile.dictionaryId) {
        dictionary = item;
        break;
      }
    }
    final selected = _selected.contains(profile.dictionaryId);
    final pairLabel =
        profile.profile?.languagePairs.map((pair) => pair.label).join(' · ') ??
        '';
    final dateLabel = profile.confirmedAt == null
        ? ''
        : formatCorpusDate(profile.confirmedAt!);
    final card = _ProfileCard(
      title: profile.displayTitle,
      statusLabel: profile.status == DictionaryProfileStatus.confirmed
          ? strings.profileStatusConfirmed
          : strings.profileStatusDeclined,
      statusColor: profile.status == DictionaryProfileStatus.confirmed
          ? AppColors.success
          : AppColors.textSecondary,
      subtitle: <String>[
        if (pairLabel.isNotEmpty) pairLabel,
        if (dateLabel.isNotEmpty) dateLabel,
      ].join(' · '),
      leading: _selecting
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelected(profile.dictionaryId),
            )
          : null,
      onTap: _selecting ? () => _toggleSelected(profile.dictionaryId) : null,
      trailing: _selecting
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: strings.profileEdit,
                  onPressed: () => _editProfile(profile, strings),
                  icon: const Icon(Icons.edit_outlined, size: AppSizes.icon),
                ),
                IconButton(
                  tooltip: strings.profileRegenerate,
                  onPressed:
                      dictionary == null ||
                          regeneration.isGenerating(profile.dictionaryId)
                      ? null
                      : () => _regenerate(dictionary!, strings),
                  icon: const Icon(Icons.refresh, size: AppSizes.icon),
                ),
                IconButton(
                  tooltip: strings.profileDelete,
                  onPressed: profilesInUse
                      ? null
                      : () => _deleteProfiles(<StoredDictionaryProfile>[
                          profile,
                        ], strings),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: AppSizes.icon,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
    );

    final coverage = profile.profile?.coverage;
    final coverageWarning = coverage != null && coverage.sampleTruncated
        ? Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              strings.profileSampleTruncated(coverage.unsampledProbeCount),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.warning,
              ),
            ),
          )
        : null;

    final dictionaryForFingerprint = dictionary;
    if (dictionaryForFingerprint == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          ?coverageWarning,
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              strings.profileUnavailableDictionary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      );
    }

    final future = _staleFutures.putIfAbsent(
      profile.dictionaryId,
      () => _isStale(
        dictionaryForFingerprint,
        profile,
        AgentProfileLanguage.fromWire(profileLanguage),
      ),
    );
    return FutureBuilder<bool>(
      future: future,
      builder: (context, snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          ?coverageWarning,
          if (snapshot.data == true)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                strings.profileStatusStale,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _isStale(
    DictionaryInfo dictionary,
    StoredDictionaryProfile profile,
    AgentProfileLanguage language,
  ) async {
    final fingerprint = await dictionaryProfileFingerprint(
      dictionary,
      promptVersion: dictionaryProfilePromptVersion,
      schemaVersion: dictionaryProfileSchemaVersion,
      language: language,
    );
    return fingerprint != profile.fingerprint;
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      _selecting = true;
    });
  }

  Future<void> _editProfile(
    StoredDictionaryProfile profile,
    AgentUiStrings strings,
  ) async {
    final draft = profile.profile;
    if (draft == null) {
      RikaiToast.show(context, strings.profileMarkdownMissing);
      return;
    }
    final decision = await showFamiliarizationSheet(
      context,
      profile: draft,
      markdown: profile.markdown,
      strings: strings,
      editOnly: true,
    );
    if (!mounted || decision == null) return;
    await ref
        .read(agentStoreProvider)
        .updateProfileMarkdown(profile.dictionaryId, decision.markdown);
    _staleFutures.clear();
    ref.invalidate(agentProfilesProvider);
    if (mounted) RikaiToast.show(context, strings.profileUpdated);
  }

  Future<void> _resolveProposal(
    AgentProfileProposal proposal,
    AgentUiStrings strings,
  ) async {
    await presentAgentProfileConfirmation(
      context,
      ref,
      strings,
      proposal: proposal,
    );
    _staleFutures.clear();
    ref.invalidate(agentProfilesProvider);
  }

  Future<void> _regenerate(
    DictionaryInfo dictionary,
    AgentUiStrings strings,
  ) async {
    await _regenerateDictionaries(<DictionaryInfo>[dictionary], strings);
  }

  Future<void> _regenerateSelected(List<DictionaryInfo> enabled) async {
    final strings = _strings();
    final selected = <DictionaryInfo>[
      for (final dictionary in enabled)
        if (_selected.contains(dictionary.id)) dictionary,
    ];
    await _regenerateDictionaries(selected, strings);
  }

  Future<void> _regenerateDictionaries(
    List<DictionaryInfo> dictionaries,
    AgentUiStrings strings,
  ) async {
    if (dictionaries.isEmpty) return;
    final regeneration = ref.read(agentProfileRegenerationProvider);
    final seen = <String>{};
    final targets = <DictionaryInfo>[
      for (final dictionary in dictionaries)
        if (!regeneration.isGenerating(dictionary.id) &&
            seen.add(dictionary.id))
          dictionary,
    ];
    if (targets.isEmpty) return;

    // A pending proposal for the same dictionary would otherwise block
    // regeneration while the main agent is waiting in `awaitingProfile`.
    // Resolve it as "skip once": the current run continues without that
    // profile, and the new generation is queued for the user.
    final inbox = ref.read(agentProfileInboxProvider.notifier);
    final pending = ref.read(agentProfileInboxProvider).pending;
    for (final proposal in pending) {
      if (!targets.any(
        (dictionary) => dictionary.id == proposal.dictionaryId,
      )) {
        continue;
      }
      await inbox.resolve(
        proposal.id,
        ProfileConfirmation(
          action: ProfileConfirmationAction.skipOnce,
          markdown: proposal.markdown,
        ),
      );
    }
    if (!mounted) return;

    final providers =
        ref.read(agentProvidersProvider).asData?.value ??
        const <AgentProviderConfig>[];
    if (providers.isEmpty) {
      RikaiToast.show(context, strings.profileRegenerateNeedsProvider);
      return;
    }
    _staleFutures.clear();
    await ref
        .read(agentProfileRegenerationProvider.notifier)
        .start(dictionaries: targets, provider: providers.first);
  }

  Future<void> _deleteSelected(AgentUiStrings strings) async {
    final profiles = ref.read(agentProfilesProvider).asData?.value ?? const [];
    final selected = <StoredDictionaryProfile>[
      for (final profile in profiles)
        if (_selected.contains(profile.dictionaryId)) profile,
    ];
    await _deleteProfiles(selected, strings);
  }

  Future<void> _deleteProfiles(
    List<StoredDictionaryProfile> profiles,
    AgentUiStrings strings,
  ) async {
    if (profiles.isEmpty) return;
    if (ref.read(agentRunControllerProvider).profilesInUse) {
      RikaiToast.show(context, strings.profileActionsDisabledWhileRunning);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.profileDeleteTitle),
        content: Text(strings.profileDeleteBody(profiles.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(agentStoreProvider).deleteDictionaryProfiles(<String>[
      for (final profile in profiles) profile.dictionaryId,
    ]);
    ref.invalidate(agentProfilesProvider);
    _staleFutures.clear();
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    RikaiToast.show(context, strings.profileDeleted);
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    required this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String statusLabel;
  final Color statusColor;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ?leading,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: AppTypography.headline,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Text(
                        statusLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: AppTypography.helper,
                          color: statusColor,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: AppTypography.helper,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
