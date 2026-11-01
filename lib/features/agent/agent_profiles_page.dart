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
import 'familiarization_sheet.dart';

class AgentProfilesPage extends ConsumerStatefulWidget {
  const AgentProfilesPage({super.key});

  @override
  ConsumerState<AgentProfilesPage> createState() => _AgentProfilesPageState();
}

class _AgentProfilesPageState extends ConsumerState<AgentProfilesPage> {
  bool _selecting = false;
  bool _busy = false;
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
    final running = ref.watch(agentRunControllerProvider).isRunning;
    final settings = ref.watch(appSettingsProvider);
    ref.listen(appSettingsProvider, (previous, next) {
      if (previous?.agentProfileLanguage != next.agentProfileLanguage) {
        _staleFutures.clear();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.profileManagerTitle),
        actions: [
          if (_selecting) ...[
            IconButton(
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
              tooltip: strings.profileRegenerateSelected,
              onPressed: _busy || _selected.isEmpty || running
                  ? null
                  : () => _regenerateSelected(enabled, running),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: strings.profileDeleteSelected,
              onPressed: _busy || _selected.isEmpty || running
                  ? null
                  : () => _deleteSelected(strings),
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: strings.profileExitSelection,
              onPressed: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
              icon: const Icon(Icons.close),
            ),
          ] else
            IconButton(
              tooltip: strings.profileSelectMode,
              onPressed: () => setState(() => _selecting = true),
              icon: const Icon(Icons.checklist),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
                child: LinearProgressIndicator(minHeight: 2),
              ),
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
                  trailing: TextButton(
                    onPressed: () => _resolveProposal(proposal, strings),
                    child: Text(strings.profileOpen),
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
                        running,
                        strings,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context,
    StoredDictionaryProfile profile,
    List<DictionaryInfo> enabled,
    String profileLanguage,
    bool running,
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
    final card = _ProfileCard(
      title: profile.displayTitle,
      statusLabel: profile.status == DictionaryProfileStatus.confirmed
          ? strings.profileStatusConfirmed
          : strings.profileStatusDeclined,
      statusColor: profile.status == DictionaryProfileStatus.confirmed
          ? AppColors.success
          : AppColors.textSecondary,
      subtitle: profile.confirmedAt == null
          ? ''
          : formatCorpusDate(profile.confirmedAt!),
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
                  onPressed: running
                      ? null
                      : () => _editProfile(profile, strings),
                  icon: const Icon(Icons.edit_outlined, size: AppSizes.icon),
                ),
                IconButton(
                  tooltip: strings.profileRegenerate,
                  onPressed: running || dictionary == null
                      ? null
                      : () => _regenerate(dictionary!, strings),
                  icon: const Icon(Icons.refresh, size: AppSizes.icon),
                ),
                IconButton(
                  tooltip: strings.profileDelete,
                  onPressed: running
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

    final dictionaryForFingerprint = dictionary;
    if (dictionaryForFingerprint == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
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
    if (ref.read(agentRunControllerProvider).isRunning) {
      RikaiToast.show(context, strings.profileActionsDisabledWhileRunning);
      return;
    }
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
    final decision = await showFamiliarizationSheet(
      context,
      profile: proposal.profile,
      markdown: proposal.markdown,
      strings: strings,
    );
    if (!mounted || decision == null) return;
    await ref
        .read(agentProfileInboxProvider.notifier)
        .resolve(proposal.id, decision);
    _staleFutures.clear();
    ref.invalidate(agentProfilesProvider);
  }

  Future<void> _regenerate(
    DictionaryInfo dictionary,
    AgentUiStrings strings,
  ) async {
    await _regenerateDictionaries(<DictionaryInfo>[dictionary], strings);
  }

  Future<void> _regenerateSelected(
    List<DictionaryInfo> enabled,
    bool running,
  ) async {
    final strings = _strings();
    if (running) {
      RikaiToast.show(context, strings.profileActionsDisabledWhileRunning);
      return;
    }
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
    final run = ref.read(agentRunControllerProvider);
    if (run.isRunning) {
      RikaiToast.show(context, strings.profileActionsDisabledWhileRunning);
      return;
    }
    final providers =
        ref.read(agentProvidersProvider).asData?.value ??
        const <AgentProviderConfig>[];
    if (providers.isEmpty) {
      RikaiToast.show(context, strings.profileRegenerateNeedsProvider);
      return;
    }
    final provider = providers.first;
    setState(() => _busy = true);
    try {
      final generation = await ref
          .read(agentProfileManagerProvider)
          .generate(dictionaries: dictionaries, provider: provider);
      ref
          .read(agentProfileInboxProvider.notifier)
          .enqueue(generation.proposals);
      if (generation.issues.isNotEmpty && mounted) {
        RikaiToast.show(context, generation.issues.first.reason);
      }
      if (generation.proposals.isNotEmpty && mounted) {
        _staleFutures.clear();
        ref.invalidate(agentProfilesProvider);
        await _resolveProposal(generation.proposals.first, strings);
      }
    } catch (_) {
      if (mounted) RikaiToast.show(context, strings.profileRegenerateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (ref.read(agentRunControllerProvider).isRunning) {
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
