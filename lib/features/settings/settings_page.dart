import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/mecab/unidic_validator.dart';
import '../../services/storage/permission_service.dart';
import '../../state/providers.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('UniDic', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _pathController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'UniDic 目录',
                      hintText: '/sdcard/Download/unidic-cwj-202512',
                      helperText: '应用原地读取，不复制文件，也不会写入该目录。',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder_open_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _validating ? null : _validateAndSave,
                        icon: _validating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.fact_check_outlined),
                        label: Text(_validating ? '正在校验…' : '校验并保存'),
                      ),
                    ],
                  ),
                  if (_validation case final validation?) ...[
                    const SizedBox(height: 16),
                    _ValidationCard(result: validation),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('存储权限', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildPermissionCard(),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('应用外部私有目录', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const SelectableText(
                    '/sdcard/Android/data/com.rikai.mobile/files/',
                    style: TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '把 UniDic 目录放到这里无需「所有文件访问」权限；'
                    '在上方填写完整路径即可。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('阅读显示', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('显示注音'),
                  subtitle: const Text('在词条上方显示振假名'),
                  value: settings.showFurigana,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setShowFurigana(value);
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
                      ref
                          .read(appSettingsProvider.notifier)
                          .setReaderFontSize(value);
                    },
                  ),
                  trailing: Text(
                    settings.readerFontSize.round().toString(),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard() {
    final status = _storageStatus;
    if (status == null) {
      return const Card(
        child: ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('所有文件访问'),
          subtitle: Text('正在检查权限…'),
        ),
      );
    }

    final granted = status.granted;
    final needsAllFiles = status.sdkInt >= 30;
    final subtitle = granted
        ? '已授权，可原地读取 /sdcard/... 下的 UniDic 与词典。'
        : needsAllFiles
        ? '未授权。Android 11+ 需要「所有文件访问」才能读取 /sdcard/... 目录。'
        : '未授予读取存储权限。';

    return Card(
      child: ListTile(
        leading: Icon(
          granted ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
        ),
        title: const Text('所有文件访问'),
        subtitle: Text(subtitle),
        trailing: granted
            ? Icon(Icons.check_circle, color: Colors.green.shade600)
            : FilledButton(
                onPressed: _permissionBusy ? null : _requestPermission,
                child: Text(needsAllFiles ? '去授权' : '申请权限'),
              ),
      ),
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
    final color = valid ? Colors.green.shade700 : theme.colorScheme.error;

    return Card(
      color: valid
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.errorContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  valid ? Icons.check_circle_outline : Icons.error_outline,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    valid ? '校验通过' : '校验失败',
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.summary),
            if (valid) ...[
              const SizedBox(height: 6),
              Text(
                '词条数 ${_formatCount(result.entryCount ?? 0)} · '
                '编码 ${result.charset} · 词典版本 ${result.version}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in result.fileSizes.entries)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${entry.key} ${_formatBytes(entry.value)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ] else if (result.missingFiles.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '缺少：${result.missingFiles.join('、')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (!valid) ...[
              const SizedBox(height: 6),
              Text(
                '若路径正确，请确认已授予所有文件访问权限，或改用应用外部私有目录。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatCount(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}
