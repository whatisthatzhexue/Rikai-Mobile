import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/security/secret_store.dart';
import '../../state/agent_providers.dart';
import '../../state/providers.dart';

class AgentSettingsPage extends ConsumerWidget {
  const AgentSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final providersAsync = ref.watch(agentProvidersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('词典助手设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            '词典档案语言',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: AppTypography.sectionHeading,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '模型生成的词典用途/结构说明使用哪种语言；日文词条与读音保持原文。'
            '默认中文。切换语言后会重新生成未匹配的档案。',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AppTypography.helper,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: settings.agentProfileLanguage,
            decoration: const InputDecoration(
              labelText: '档案主体语言',
              isDense: true,
            ),
            items: <DropdownMenuItem<String>>[
              for (final language in AgentProfileLanguage.values)
                DropdownMenuItem(
                  value: language.wireName,
                  child: Text(language.label),
                ),
            ],
            onChanged: (value) async {
              if (value == null || value == settings.agentProfileLanguage) {
                return;
              }
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('重新生成词典档案？'),
                  content: const Text(
                    '切换档案语言后，已有词典档案会失效，并在下次分析时重新生成。'
                    '是否继续？',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('继续'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              ref
                  .read(appSettingsProvider.notifier)
                  .setAgentProfileLanguage(value);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: settings.agentResponseLanguage,
            decoration: const InputDecoration(labelText: '回答语言', isDense: true),
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
          const Divider(height: AppSpacing.xxl),
          Text(
            '模型服务',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: AppTypography.sectionHeading,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'API Key 只保存在 Android 安全存储中，不会写入 SharedPreferences、'
            '日志或导出文件。图片仍只在本机 OCR，不会上传。',
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
              '读取模型配置失败',
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
                      '还没有配置模型。添加一个 DeepSeek、Claude 或其他 '
                      'OpenAI 兼容服务后即可使用词典助手。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: AppTypography.helper,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                for (final provider in providers) ...[
                  _ProviderRow(
                    provider: provider,
                    onEdit: () => _editProvider(context, ref, provider),
                    onDelete: () => _deleteProvider(context, ref, provider),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: AppSizes.control,
                  child: FilledButton(
                    onPressed: () => _editProvider(context, ref, null),
                    child: const Text('添加模型服务'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProvider(
    BuildContext context,
    WidgetRef ref,
    AgentProviderConfig? existing,
  ) async {
    final result = await showDialog<AgentProviderDraft>(
      context: context,
      builder: (context) => _ProviderDialog(initial: existing),
    );
    if (result == null) return;
    final id =
        existing?.id ??
        'provider-${DateTime.now().microsecondsSinceEpoch.toString()}';
    final config = AgentProviderConfig(
      id: id,
      kind: result.kind,
      displayName: result.displayName.trim().isEmpty
          ? '未命名模型服务'
          : result.displayName.trim(),
      baseUrl: result.baseUrl.trim(),
      smallModel: result.smallModel.trim(),
      complexModel: result.complexModel.trim(),
      supportsStreaming: true,
      supportsJsonSchema: result.kind == AgentProviderKind.anthropic,
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
    if (context.mounted) RikaiToast.show(context, '模型配置已保存');
  }

  Future<void> _deleteProvider(
    BuildContext context,
    WidgetRef ref,
    AgentProviderConfig provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型服务'),
        content: Text('确定删除「${provider.displayName}」及其 API Key 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
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
    if (context.mounted) RikaiToast.show(context, '已删除模型服务');
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.onEdit,
    required this.onDelete,
  });

  final AgentProviderConfig provider;
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
                  '接口地址：${provider.baseUrl}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppTypography.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '复杂模型：${provider.complexModel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppTypography.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '简单模型：${provider.smallModel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppTypography.helper,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '编辑',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: AppSizes.icon),
          ),
          IconButton(
            tooltip: '删除',
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
  const _ProviderDialog({this.initial});

  final AgentProviderConfig? initial;

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
      title: Text(editing ? '编辑模型服务' : '添加模型服务'),
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
                decoration: const InputDecoration(
                  labelText: '服务商',
                  isDense: true,
                ),
                items: <DropdownMenuItem<AgentProviderPreset>>[
                  for (final preset in AgentProviderPreset.values)
                    DropdownMenuItem(value: preset, child: Text(preset.label)),
                ],
                onChanged: (value) {
                  if (value != null) _changePreset(value);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '名称',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-base-url'),
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: '接口地址',
                  hintText: 'https://api.deepseek.com/',
                  errorText: _baseUrlError,
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-small-model'),
                controller: _smallModel,
                decoration: const InputDecoration(
                  labelText: '快速模型',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('agent-provider-complex-model'),
                controller: _complexModel,
                decoration: const InputDecoration(
                  labelText: '高精度模型',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '接口密钥（API Key）',
                  hintText: editing ? '留空则不修改' : '',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '快速模型用于词典档案和资料检查。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.helper,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '高精度模型用于最终解析。',
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
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
