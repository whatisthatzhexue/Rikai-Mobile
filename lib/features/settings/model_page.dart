import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ocr_model.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../core/utils/format_bytes.dart';
import '../../services/ocr/model_manager.dart';
import '../../state/providers.dart';
import 'storage_permission_prompt.dart';

class ModelPage extends ConsumerStatefulWidget {
  const ModelPage({super.key});

  @override
  ConsumerState<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends ConsumerState<ModelPage> {
  OcrModelManifest? _manifest;
  final Map<String, OcrModelStatus> _statuses = {};
  late final TextEditingController _mirrorController;
  String _directoryPath = '';
  bool _directoryAvailable = true;
  String _directoryError = '';
  bool _loading = true;
  String? _busySetId;
  String? _error;
  String? _mirrorError;
  CancelToken? _downloadCancel;
  OcrModelDownloadProgress? _downloadProgress;
  OcrModelMigrationProgress? _migrationProgress;
  bool _permissionPrompted = false;
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    _mirrorController = TextEditingController(
      text: ref.read(appSettingsProvider).ocrMirror,
    );
    _load();
  }

  @override
  void dispose() {
    // Downloads intentionally survive page disposal. The user can stop one
    // explicitly from the leave-confirmation dialog; leaving the page without
    // stopping keeps the .part file and lets a later download resume.
    _mirrorController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => _loading = true);
    try {
      final manifest = await ref.read(ocrModelManifestProvider.future);
      final manager = ref.read(ocrModelManagerProvider);
      final directory = await manager.modelsDirectoryPath();
      final statuses = <String, OcrModelStatus>{};
      for (final set in manifest.sets.values) {
        statuses[set.id] = await manager.status(set);
      }
      if (!mounted) return;
      final unavailable = statuses.values.where(
        (status) => !status.directoryAvailable,
      );
      setState(() {
        _manifest = manifest;
        _statuses
          ..clear()
          ..addAll(statuses);
        _directoryPath = directory;
        _directoryAvailable = unavailable.isEmpty;
        _directoryError = unavailable.isEmpty
            ? ''
            : unavailable.first.directoryError;
        _loading = false;
        _error = null;
      });
      if (!_permissionPrompted) {
        _permissionPrompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ensurePathAccess(context, ref, directory);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(error);
      });
    }
  }

  bool _persistMirror() {
    final value = _mirrorController.text.trim();
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !uri.hasScheme ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.isEmpty) {
        setState(() {
          _mirrorError = '请输入包含 http:// 或 https:// 的完整镜像地址';
        });
        return false;
      }
    }
    ref.read(appSettingsProvider.notifier).setOcrMirror(value);
    setState(() {
      _mirrorError = null;
      _error = null;
    });
    return true;
  }

  void _saveMirror() {
    if (!_persistMirror()) return;
    FocusScope.of(context).unfocus();
    RikaiToast.show(context, '模型镜像设置已保存');
  }

  Future<void> _download(OcrModelSet set) async {
    if (_busySetId != null || !_persistMirror()) return;
    FocusScope.of(context).unfocus();
    if (set.requiresAcceptance) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('下载前确认'),
          content: Text(
            '${set.displayName} 的许可未在上游明确声明。'
            '下载前请确认上游模型卡的使用条款；模型只保存在本机。'
            '是否继续下载？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续下载'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    final cancel = CancelToken();
    setState(() {
      _busySetId = set.id;
      _error = null;
      _downloadCancel = cancel;
      _downloadProgress = null;
    });
    try {
      await ref
          .read(ocrModelManagerProvider)
          .downloadSet(
            set,
            cancelToken: cancel,
            customMirror: ref.read(appSettingsProvider).ocrMirror,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _downloadProgress = progress);
            },
          );
      if (!mounted) return;
      await _load(showLoading: false);
      if (!mounted) return;
      RikaiToast.show(context, '${set.displayName} 下载完成');
    } on OcrModelException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'CANCELLED' ? '已取消下载' : error.message;
      });
      await _load(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '下载失败：$error');
      await _load(showLoading: false);
    } finally {
      if (mounted) {
        setState(() {
          _busySetId = null;
          _downloadCancel = null;
          _downloadProgress = null;
        });
      }
    }
  }

  void _cancelDownload() {
    _downloadCancel?.cancel('用户取消下载');
  }

  Future<void> _import(OcrModelSet set) async {
    if (_busySetId != null) return;
    try {
      final files = await FilePicker.pickFiles();
      if (!mounted || files.isEmpty) return;
      setState(() {
        _busySetId = set.id;
        _error = null;
      });
      try {
        await ref.read(ocrModelManagerProvider).importSet(set, files);
      } finally {
        // FilePicker copies picks into its cache; do not leave 140MB of
        // temporary MangaOCR weights behind.
        try {
          await FilePicker.clearTemporaryFiles();
        } catch (_) {}
      }
      await _load(showLoading: false);
      if (!mounted) return;
      RikaiToast.show(context, '${set.displayName} 导入完成');
    } on OcrModelException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      await _load(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '导入失败：$error');
      await _load(showLoading: false);
    } finally {
      if (mounted) setState(() => _busySetId = null);
    }
  }

  Future<void> _delete(OcrModelSet set) async {
    // Close the mirror field's keyboard before the confirmation dialog. On
    // Android, dismissing a dialog otherwise restores the previous focus and
    // bounces the keyboard back up.
    FocusScope.of(context).unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除${set.displayName}？'),
        content: const Text('只会删除模型目录中的该模型文件，不会影响其他文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onHeader,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busySetId = set.id);
    try {
      await ref.read(ocrModelManagerProvider).deleteSet(set);
      await _load(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '删除失败：$error');
    } finally {
      if (mounted) setState(() => _busySetId = null);
    }
  }

  Future<void> _changeDirectory() async {
    if (_busySetId != null) return;
    FocusScope.of(context).unfocus();
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: '选择 OCR 模型目录',
    );
    if (!mounted || selected == null) return;
    var trimmed = selected.trim();
    if (trimmed.isEmpty) return;
    if (!await ensurePathAccess(context, ref, trimmed)) return;
    if (!mounted) return;

    final installedBytes = _statuses.values.fold<int>(
      0,
      (sum, status) => sum + status.installedBytes,
    );
    final manager = ref.read(ocrModelManagerProvider);
    // Accept either the root containing model folders or a single model folder
    // such as `paddle_v5`; both resolve to the shared models root.
    trimmed = await manager.resolveModelsRoot(trimmed);
    if (!mounted) return;
    if (trimmed == _directoryPath) return;
    if (!await ensurePathAccess(context, ref, trimmed)) return;
    if (!mounted) return;

    final check = await manager.validateModelsDirectory(
      trimmed,
      requiredBytes: installedBytes,
    );
    if (!mounted) return;
    if (!check.ok) {
      setState(() => _error = check.message);
      return;
    }
    final hasModels = installedBytes > 0;
    final migrate = hasModels ? await _askMigration(trimmed) : true;
    if (migrate == null) return;

    try {
      if (hasModels && migrate) {
        setState(() {
          _busySetId = 'migration';
          _error = null;
          _migrationProgress = null;
        });
        final sets = _manifest?.sets.values.toList(growable: false) ?? const [];
        await manager.migrateModels(
          sets: sets,
          destinationPath: trimmed,
          move: true,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _migrationProgress = progress);
          },
        );
      }
      ref.read(appSettingsProvider.notifier).setOcrModelsDirectory(trimmed);
      await _load(showLoading: false);
      if (!mounted) return;
      RikaiToast.show(context, hasModels && migrate ? '模型已迁移到新目录' : '模型目录已切换');
    } on OcrModelException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'CANCELLED' ? '已取消迁移' : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '迁移失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busySetId = null;
          _migrationProgress = null;
        });
      }
    }
  }

  Future<bool?> _askMigration(String destination) {
    var migrate = true;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('更改模型目录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新目录：$destination',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  migrate ? Icons.check_circle : Icons.circle_outlined,
                  color: migrate ? AppColors.primary : AppColors.textTertiary,
                ),
                onTap: () => setState(() => migrate = true),
                title: const Text('迁移现有模型（推荐）'),
                subtitle: const Text('复制到新目录并校验成功后，删除旧目录中的模型。'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  !migrate ? Icons.check_circle : Icons.circle_outlined,
                  color: !migrate ? AppColors.primary : AppColors.textTertiary,
                ),
                onTap: () => setState(() => migrate = false),
                title: const Text('仅切换目录'),
                subtitle: const Text('保留旧目录中的模型，之后在新目录重新下载或导入。'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(migrate),
              child: const Text('继续'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeaveDownload() async {
    if (_downloadCancel == null || !mounted) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    FocusScope.of(context).unfocus();
    var stop = false;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('模型正在下载'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('退出后下载会继续在后台进行。再次下载时会从已完成的断点继续。'),
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: stop,
                onChanged: (value) =>
                    setDialogState(() => stop = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('同时停止下载'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('留在本页'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('退出'),
            ),
          ],
        ),
      ),
    );
    if (leave != true || !mounted) return;
    if (stop) _downloadCancel?.cancel('用户退出下载页面');
    setState(() => _allowPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _allowPop || _downloadCancel == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeaveDownload();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('OCR 模型')),
        body: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    Text('正在检查模型…', style: theme.textTheme.bodyMedium),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  Text(
                    'OCR 模型需单独下载，下载完成后可离线使用。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('模型目录', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    _directoryPath,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: AppTypography.headline,
                      height: 1.5,
                    ),
                  ),
                  if (!_directoryAvailable) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '模型目录不可用${_directoryError.isEmpty ? '' : '：$_directoryError'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '已安装 ${formatBytes(_installedBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AppTypography.helper,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _busySetId == null ? _changeDirectory : null,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('更改目录'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '可选择模型总目录，也可直接选择 paddle_v5 / manga_ocr '
                    '等单个模型文件夹，应用会自动定位总目录。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AppTypography.helper,
                      height: 1.5,
                    ),
                  ),
                  if (_migrationProgress != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '正在迁移 ${_migrationProgress!.fileName} '
                      '${(_migrationProgress!.progress * 100).round()}%',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(
                      value: _migrationProgress!.progress,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                  const Divider(height: AppSpacing.xxl),
                  Text('模型下载镜像', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _mirrorController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _saveMirror(),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: const InputDecoration(
                      labelText: '自定义镜像前缀（可选）',
                      hintText: 'https://hf-mirror.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '留空时依次尝试 hf-mirror.com、hf-mirror.net，再尝试 Hugging Face。'
                    '自定义前缀会保留模型路径并替换服务器地址，必须使用 http/https。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AppTypography.helper,
                      height: 1.5,
                    ),
                  ),
                  if (_mirrorError != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _mirrorError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saveMirror,
                      icon: const Icon(
                        Icons.save_outlined,
                        size: AppSizes.icon,
                      ),
                      label: const Text('保存镜像'),
                    ),
                  ),
                  if (_downloadCancel != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _downloadProgress == null
                          ? '正在连接模型服务器…'
                          : '正在下载 ${_downloadProgress!.fileName} '
                                '${(_downloadProgress!.overallProgress * 100).round()}%',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(
                      value: _downloadProgress?.overallProgress,
                    ),
                    TextButton.icon(
                      onPressed: _cancelDownload,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('取消下载'),
                    ),
                    Text(
                      '可以离开本页，下载会继续；再次下载时会从断点继续。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: AppTypography.helper,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  for (final set
                      in _manifest?.sets.values ?? const <OcrModelSet>[]) ...[
                    _buildSetSection(theme, set),
                    const Divider(height: AppSpacing.xxl),
                  ],
                ],
              ),
      ),
    );
  }

  int get _installedBytes =>
      _statuses.values.fold(0, (sum, status) => sum + status.installedBytes);

  Widget _buildSetSection(ThemeData theme, OcrModelSet set) {
    final status = _statuses[set.id];
    final busy = _busySetId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(set.displayName, style: theme.textTheme.titleMedium),
            ),
            Text(formatBytes(set.totalSize), style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${_licenseLabel(set.license)}'
          '${set.licenseUrl.isEmpty ? '' : ' · ${set.licenseUrl}'}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AppTypography.helper,
            height: 1.5,
          ),
        ),
        if (set.licenseNote.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            set.licenseNote,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AppTypography.helper,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (status != null)
          Text(
            status.isInstalled
                ? '已安装（${formatBytes(status.installedBytes)}）'
                : status.missingFiles.length <= 3
                ? '未安装：缺少 ${status.missingFiles.join('、')}'
                : '未安装：缺少 ${status.missingFiles.length} 个文件',
            style: theme.textTheme.bodyMedium,
          ),
        if (set.id == 'manga_ocr') ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '安装后可在照片集中选择「竖向」；自动模式也会按检测到的文字方向路由。',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AppTypography.helper,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (status?.isInstalled != true)
              OutlinedButton.icon(
                onPressed: busy ? null : () => _download(set),
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载'),
              ),
            if (status?.isInstalled ?? false)
              OutlinedButton.icon(
                onPressed: busy ? null : () => _delete(set),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                label: const Text(
                  '删除',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _import(set),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('本地导入'),
            ),
          ],
        ),
      ],
    );
  }

  String _licenseLabel(String license) =>
      license == 'UNKNOWN' ? '许可未声明' : license;

  String _errorText(Object error) {
    if (error is OcrModelException) return error.message;
    return error.toString();
  }
}
