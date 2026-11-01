import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/security/secret_store.dart';
import '../../state/agent_providers.dart';
import '../../state/providers.dart';
import '../agent/agent_profile_inbox_host.dart';

class AgentSettingsPage extends ConsumerWidget {
  const AgentSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final providersAsync = ref.watch(agentProvidersProvider);
    final strings = AgentUiStrings.of(
      resolveAgentUiLanguage(
        AgentResponseLanguage.fromWire(settings.agentResponseLanguage),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: AgentProfileInboxHost(
        strings: strings,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Text(
              strings.profileLanguageTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: AppTypography.sectionHeading,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              strings.profileLanguageBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: AppTypography.helper,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: settings.agentProfileLanguage,
              decoration: InputDecoration(
                labelText: strings.profileLanguageLabel,
                isDense: true,
              ),
              items: <DropdownMenuItem<String>>[
                for (final language in AgentProfileLanguage.values)
                  DropdownMenuItem(
                    value: language.wireName,
                    child: Text(language.label),
                  ),
              ],
              onChanged: (value) {
                if (value == null || value == settings.agentProfileLanguage) {
                  return;
                }
                ref
                    .read(appSettingsProvider.notifier)
                    .setAgentProfileLanguage(value);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: settings.agentResponseLanguage,
              decoration: InputDecoration(
                labelText: strings.answerLanguageLabel,
                isDense: true,
              ),
              items: <DropdownMenuItem<String>>[
                for (final language in AgentResponseLanguage.values)
                  DropdownMenuItem(
                    value: language.wireName,
                    child: Text(language.label),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref
                    .read(appSettingsProvider.notifier)
                    .setAgentResponseLanguage(value);
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            CheckboxListTile(
              value: settings.agentProfilesAutoAccept,
              onChanged: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setAgentProfilesAutoAccept(value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(
                strings.autoAcceptProfiles,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AppTypography.helper,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                strings.autoAcceptProfilesBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.helper,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Divider(height: AppSpacing.xxl),
            Text(
              strings.modelServicesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: AppTypography.sectionHeading,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              strings.secretBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: AppTypography.helper,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            providersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (error, stack) => Text(
                strings.providerLoadFailed,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AppTypography.helper,
                  color: AppColors.error,
                ),
              ),
              data: (providers) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (providers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(
                        strings.noProviders,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: AppTypography.helper,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  for (final provider in providers) ...[
                    _ProviderRow(
                      provider: provider,
                      strings: strings,
                      onEdit: () =>
                          _editProvider(context, ref, provider, strings),
                      onDelete: () =>
                          _deleteProvider(context, ref, provider, strings),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: AppSizes.control,
                    child: FilledButton(
                      onPressed: () =>
                          _editProvider(context, ref, null, strings),
                      child: Text(strings.addProvider),
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

  Future<void> _editProvider(
    BuildContext context,
    WidgetRef ref,
    AgentProviderConfig? existing,
    AgentUiStrings strings,
  ) async {
    final result = await showDialog<AgentProviderDraft>(
      context: context,
      builder: (context) =>
          _ProviderDialog(initial: existing, strings: strings),
    );
    if (result == null) return;
    final id =
        existing?.id ??
        'provider-${DateTime.now().microsecondsSinceEpoch.toString()}';
    final config = AgentProviderConfig(
      id: id,
      kind: result.kind,
      displayName: result.displayName.trim().isEmpty
          ? strings.unnamedProvider
          : result.displayName.trim(),
      baseUrl: result.baseUrl.trim(),
      smallModel: result.smallModel.trim(),
      complexModel: result.complexModel.trim(),
      supportsStreaming: true,
    );
    final store = ref.read(agentStoreProvider);
    await store.saveProvider(config);
    if (result.apiKey.trim().isNotEmpty) {
      await ref
          .read(secretStoreProvider)
          .write(agentProviderSecretKey(id), result.apiKey.trim());
    }
    ref.read(selectedAgentProviderProvider.notifier).select(id);
    ref.invalidate(agentProvidersProvider);
    if (context.mounted) RikaiToast.show(context, strings.providerSaved);
  }

  Future<void> _deleteProvider(
    BuildContext context,
    WidgetRef ref,
    AgentProviderConfig provider,
    AgentUiStrings strings,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteProviderTitle),
        content: Text(strings.deleteProviderBody(provider.displayName)),
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
    await ref.read(agentStoreProvider).deleteProvider(provider.id);
    await ref
        .read(secretStoreProvider)
        .delete(agentProviderSecretKey(provider.id));
    ref.invalidate(agentProvidersProvider);
    if (context.mounted) RikaiToast.show(context, strings.providerDeleted);
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.strings,
    required this.onEdit,
    required this.onDelete,
  });

  final AgentProviderConfig provider;
  final AgentUiStrings strings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: AppTypography.headline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${strings.providerBaseUrl}：${provider.baseUrl}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppTypography.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${strings.providerComplexModelSummary}：${provider.complexModel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppTypography.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${strings.providerSmallModelSummary}：${provider.smallModel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppTypography.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: strings.profileEdit,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: AppSizes.icon),
          ),
          IconButton(
            tooltip: strings.delete,
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline,
              size: AppSizes.icon,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class AgentProviderDraft {
  const AgentProviderDraft({
    required this.kind,
    required this.displayName,
    required this.baseUrl,
    required this.smallModel,
    required this.complexModel,
    required this.apiKey,
  });

  final AgentProviderKind kind;
  final String displayName;
  final String baseUrl;
  final String smallModel;
  final String complexModel;
  final String apiKey;
}

class _ProviderDialog extends StatefulWidget {
  const _ProviderDialog({this.initial, required this.strings});

  final AgentProviderConfig? initial;
  final AgentUiStrings strings;

  @override
  State<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<_ProviderDialog> {
  late AgentProviderPreset _preset;
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _smallModel;
  late final TextEditingController _complexModel;
  late final TextEditingController _apiKey;
  String? _baseUrlError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _preset = AgentProviderPreset.forConfig(initial);
    _name = TextEditingController(text: initial?.displayName ?? '');
    _baseUrl = TextEditingController(
      text: initial?.baseUrl ?? _preset.defaultBaseUrl,
    );
    _smallModel = TextEditingController(text: initial?.smallModel ?? '');
    _complexModel = TextEditingController(text: initial?.complexModel ?? '');
    _apiKey = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _smallModel.dispose();
    _complexModel.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _changePreset(AgentProviderPreset next) {
    final previousDefault = _preset.defaultBaseUrl;
    final current = _baseUrl.text.trim();
    setState(() {
      _preset = next;
      // Fill the address for a new/untouched form, but never overwrite an
      // address the user typed or an existing custom service.
      if (current.isEmpty || current == previousDefault) {
        _baseUrl.text = next.defaultBaseUrl;
      }
      _baseUrlError = null;
    });
  }

  void _save() {
    final error = agentBaseUrlError(_baseUrl.text);
    if (error != null) {
      setState(() => _baseUrlError = error);
      return;
    }
    Navigator.of(context).pop(
      AgentProviderDraft(
        kind: _preset.kind,
        displayName: _name.text,
        baseUrl: _baseUrl.text,
        smallModel: _smallModel.text,
        complexModel: _complexModel.text,
        apiKey: _apiKey.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(
        editing ? widget.strings.editProvider : widget.strings.addProvider,
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<AgentProviderPreset>(
                initialValue: _preset,
                decoration: InputDecoration(
                  labelText: widget.strings.providerPreset,
                  isDense: true,
                ),
                items: <DropdownMenuItem<AgentProviderPreset>>[
                  for (final preset in AgentProviderPreset.values)
                    DropdownMenuItem(
                      value: preset,
                      child: Text(
                        preset == AgentProviderPreset.custom
                            ? widget.strings.otherCompatibleProvider
                            : preset.label,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _changePreset(value);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: widget.strings.providerName,
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-base-url'),
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: widget.strings.providerBaseUrl,
                  hintText: 'https://api.deepseek.com/',
                  errorText: _baseUrlError,
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-small-model'),
                controller: _smallModel,
                decoration: InputDecoration(
                  labelText: widget.strings.providerSmallModel,
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-complex-model'),
                controller: _complexModel,
                decoration: InputDecoration(
                  labelText: widget.strings.providerComplexModel,
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: widget.strings.providerApiKey,
                  hintText: editing ? widget.strings.providerApiKeyKeep : '',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.strings.providerSmallModelHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.helper,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                widget.strings.providerComplexModelHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.helper,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.strings.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(widget.strings.save)),
      ],
    );
  }
}
