import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/format_bytes.dart';
import '../../services/mecab/unidic_validator.dart';
import '../../services/storage/permission_service.dart';
import '../../services/storage/settings_store.dart';
import '../../state/providers.dart';
import 'storage_permission_prompt.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  late final TextEditingController _pathController;

  UnidicValidation? _validation;
  bool _validating = false;
  StorageAccessStatus? _storageStatus;
  bool _permissionBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pathController = TextEditingController(
      text: ref.read(appSettingsProvider).unidicPath,
    );
    _refreshPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final path = ref.read(appSettingsProvider).unidicPath;
      if (path.trim().isNotEmpty) {
        ensurePathAccess(context, ref, path);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pathController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final status = await ref.read(permissionServiceProvider).getStatus();
    if (!mounted) return;
    setState(() => _storageStatus = status);
  }

  Future<void> _requestPermission() async {
    final status = _storageStatus;
    final service = ref.read(permissionServiceProvider);
    setState(() => _permissionBusy = true);
    try {
      if (status != null && status.sdkInt >= 30) {
        await service.requestAllFilesAccess();
      } else {
        await service.requestLegacyReadPermission();
      }
      await _refreshPermissions();
      // A previous MeCab init may have failed before the permission was
      // granted; drop the cached error so the next analysis retries.
      ref.invalidate(mecabServiceProvider);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开权限设置：${error.message ?? error.code}')),
      );
    } finally {
      if (mounted) setState(() => _permissionBusy = false);
    }
  }

  Future<void> _validateAndSave() async {
    final path = UnidicValidator.normalizePath(_pathController.text);
    if (!await ensurePathAccess(context, ref, path)) return;
    if (!mounted) return;
    _pathController.text = path;
    ref.read(appSettingsProvider.notifier).setUnidicPath(path);
    setState(() {
      _validating = true;
      _validation = null;
    });

    UnidicValidation result;
    try {
      result = await UnidicValidator.validate(path);
    } catch (error) {
      result = UnidicValidation(
        code: UnidicValidationCode.unreadable,
        path: path,
        message: '校验失败：$error',
      );
    }
    if (!mounted) return;
    setState(() {
      _validating = false;
      _validation = result;
    });
    if (result.isValid) {
      ref.invalidate(mecabServiceProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('UniDic 校验通过，路径已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final dictionaries = ref.watch(dictionaryRepositoryProvider);
    final enabledDictionaries = dictionaries
        .where((dictionary) => dictionary.enabled)
        .length;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _sectionTitle(theme, 'MDict 词典'),
          ListTile(
            leading: const Icon(Icons.library_books_outlined),
            title: const Text('管理词典'),
            subtitle: Text(
              dictionaries.isEmpty
                  ? '尚未添加 .mdx 词典'
                  : '已添加 ${dictionaries.length} 本 · '
                        '$enabledDictionaries 本启用',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/dictionaries'),
          ),
          const Divider(height: AppSpacing.xxl),
          _sectionTitle(theme, 'OCR 模型'),
          ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('管理 OCR 模型'),
            subtitle: const Text('PaddleOCR 横向 / MangaOCR 竖向'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/models'),
          ),
          const Divider(height: AppSpacing.xxl),
          _sectionTitle(theme, '阅读显示'),
          _buildDisplaySection(settings, theme),
          const Divider(height: AppSpacing.xxl),
          _sectionTitle(theme, 'UniDic 分词'),
          _buildUnidicSection(theme),
          const Divider(height: AppSpacing.xxl),
          _sectionTitle(theme, '存储权限'),
          _buildPermissionSection(theme),
          const Divider(height: AppSpacing.xl),
          _buildPrivateDirectoryInfo(theme),
          const Divider(height: AppSpacing.xl),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清除模型缓存'),
            subtitle: const Text('删除未完成的下载临时文件；已安装模型不受影响'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearModelCache,
          ),
        ],
      ),
    );
  }

  Future<void> _clearModelCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除模型缓存？'),
        content: const Text('将删除下载中断留下的临时文件。已安装完成的模型不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final bytes = await ref
          .read(ocrModelManagerProvider)
          .clearPartialDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已清除 ${formatBytes(bytes)} 临时文件')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清除失败：$error')));
    }
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
  }

  Widget _buildDisplaySection(AppSettings settings, ThemeData theme) {
    final maxEntries = settings.maxEntriesPerDictionary;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('显示注音'),
          subtitle: const Text('在词条上方显示振假名'),
          value: settings.showFurigana,
          onChanged: (value) {
            ref.read(appSettingsProvider.notifier).setShowFurigana(value);
          },
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('阅读字号'),
          subtitle: Slider(
            value: settings.readerFontSize,
            min: 14,
            max: 30,
            divisions: 8,
            label: settings.readerFontSize.round().toString(),
            onChanged: (value) {
              ref.read(appSettingsProvider.notifier).setReaderFontSize(value);
            },
          ),
          trailing: Text(
            settings.readerFontSize.round().toString(),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('每词典词条上限'),
          subtitle: Text(maxEntries == 0 ? '无限制' : '最多 $maxEntries 条'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showMaxEntriesDialog,
        ),
      ],
    );
  }

  Future<void> _showMaxEntriesDialog() async {
    final current = ref.read(appSettingsProvider).maxEntriesPerDictionary;
    const choices = [0, 1, 3, 5, 10];
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('每词典词条上限'),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final choice in choices)
              ListTile(
                leading: Icon(
                  current == choice
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: current == choice
                      ? AppColors.primary
                      : AppColors.textTertiary,
                ),
                title: Text(choice == 0 ? '无限制' : '$choice 条'),
                onTap: () => Navigator.of(dialogContext).pop(choice),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    ref.read(appSettingsProvider.notifier).setMaxEntriesPerDictionary(selected);
  }

  Widget _buildUnidicSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _pathController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'UniDic 目录',
            hintText: '请选择 UniDic 词典文件夹',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.folder_open_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '可直接选择目录或手动填写；应用原地读取，不复制文件。',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AppTypography.helper,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _validating ? null : _pickUnidicDirectory,
              icon: const Icon(Icons.folder_open_outlined, size: AppSizes.icon),
              label: const Text('浏览…'),
            ),
            FilledButton.icon(
              onPressed: _validating ? null : _validateAndSave,
              icon: _validating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined, size: AppSizes.icon),
              label: Text(_validating ? '正在校验…' : '校验并保存'),
            ),
          ],
        ),
        if (_validation case final validation?) ...[
          const SizedBox(height: AppSpacing.lg),
          _ValidationCard(result: validation),
        ],
      ],
    );
  }

  Future<void> _pickUnidicDirectory() async {
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: '选择 UniDic 目录',
      );
      if (!mounted || path == null) return;
      _pathController.text = UnidicValidator.normalizePath(path);
      await _validateAndSave();
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件管理器：${error.message ?? error.code}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('选择目录失败：$error')));
    }
  }

  Widget _buildPrivateDirectoryInfo(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('应用外部私有目录', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        const SelectableText(
          '/sdcard/Android/data/com.rikai.mobile/files/',
          style: TextStyle(
            fontSize: AppTypography.headline,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '把 UniDic 目录放到这里无需「所有文件访问」权限；'
          '在上方填写完整路径即可。',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildPermissionSection(ThemeData theme) {
    final status = _storageStatus;
    if (status == null) {
      return Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text('正在检查权限…', style: theme.textTheme.bodyLarge)),
        ],
      );
    }

    final granted = status.granted;
    final needsAllFiles = status.sdkInt >= 30;
    final subtitle = granted
        ? '已授权，可原地读取 /sdcard/... 下的分词词典与 MDict 词典。'
        : needsAllFiles
        ? '未授权。Android 11+ 需要「所有文件访问」才能读取 /sdcard/... 目录。'
        : '未授予读取存储权限。';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          granted ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('所有文件访问', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AppTypography.helper,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (granted)
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm),
            child: Icon(Icons.check_circle, color: AppColors.success),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: FilledButton(
              onPressed: _permissionBusy ? null : _requestPermission,
              child: Text(needsAllFiles ? '去授权' : '申请权限'),
            ),
          ),
      ],
    );
  }
}

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({required this.result});

  final UnidicValidation result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = result.isValid;
    final color = valid ? AppColors.success : theme.colorScheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: valid
            ? AppColors.surfaceMuted
            : AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                valid ? Icons.check_circle_outline : Icons.error_outline,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  valid ? '校验通过' : '校验失败',
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(result.summary),
          if (valid) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '词条数 ${_formatCount(result.entryCount ?? 0)} · '
              '编码 ${result.charset} · 词典版本 ${result.version}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.helper,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final entry in result.fileSizes.entries)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${entry.key} ${formatBytes(entry.value)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: AppTypography.helper,
                      ),
                    ),
                  ),
              ],
            ),
          ] else if (result.missingFiles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '缺少：${result.missingFiles.join('、')}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.helper,
                height: 1.5,
              ),
            ),
          ],
          if (!valid) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '若路径正确，请确认已授予所有文件访问权限，或改用应用外部私有目录。',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.helper,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatCount(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
}
