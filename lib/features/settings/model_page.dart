import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ocr_model.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/ocr/model_manager.dart';
import '../../state/providers.dart';

class ModelPage extends ConsumerStatefulWidget {
  const ModelPage({super.key});

  @override
  ConsumerState<ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends ConsumerState<ModelPage> {
  OcrModelManifest? _manifest;
  final Map<String, OcrModelStatus> _statuses = {};
  bool _loading = true;
  String? _busySetId;
  String? _error;
  CancelToken? _downloadCancel;
  OcrModelDownloadProgress? _downloadProgress;
  late final TextEditingController _mirrorController;

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
    _downloadCancel?.cancel();
    _mirrorController.dispose();
    super.dispose();
  }

  void _saveMirror() {
    ref.read(appSettingsProvider.notifier).setOcrMirror(_mirrorController.text);
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('模型镜像设置已保存')));
  }

  Future<void> _load() async {
    try {
      final manifest = await ref.read(ocrModelManifestProvider.future);
      final manager = ref.read(ocrModelManagerProvider);
      final statuses = <String, OcrModelStatus>{};
      for (final set in manifest.sets.values) {
        statuses[set.id] = await manager.status(set);
      }
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _statuses
          ..clear()
          ..addAll(statuses);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _download(OcrModelSet set) async {
    if (_busySetId != null) return;
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
            customMirror: _mirrorController.text,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _downloadProgress = progress);
            },
          );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${set.displayName} 下载完成')));
    } on OcrModelException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'CANCELLED' ? '已取消下载' : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '下载失败：$error');
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
      await ref.read(ocrModelManagerProvider).importSet(set, files);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${set.displayName} 导入完成')));
    } on OcrModelException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _busySetId = null);
    }
  }

  Future<void> _delete(OcrModelSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除${set.displayName}？'),
        content: const Text('只会删除应用下载目录中的模型文件，不会影响其他文件。'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _busySetId = set.id);
    try {
      await ref.read(ocrModelManagerProvider).deleteSet(set);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '删除失败：$error');
    } finally {
      if (mounted) setState(() => _busySetId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('OCR 模型')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                Text(
                  '模型不随应用分发。下载后保存在应用外部私有目录，完全离线运行。',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('模型下载镜像', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _mirrorController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _saveMirror(),
                  decoration: const InputDecoration(
                    labelText: '自定义镜像前缀（可选）',
                    hintText: 'https://hf-mirror.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '留空时按清单顺序尝试 hf-mirror，再尝试 Hugging Face。'
                  '自定义前缀会保留模型路径并替换服务器地址。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppTypography.helper,
                    height: 1.5,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _saveMirror,
                    icon: const Icon(Icons.save_outlined, size: AppSizes.icon),
                    label: const Text('保存镜像'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
                if (_downloadCancel != null) ...[
                  const SizedBox(height: AppSpacing.lg),
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
                ],
                const SizedBox(height: AppSpacing.xl),
                for (final set
                    in _manifest?.sets.values ?? const <OcrModelSet>[]) ...[
                  _buildSetSection(theme, set),
                  const Divider(height: AppSpacing.xxl),
                ],
              ],
            ),
    );
  }

  Widget _buildSetSection(ThemeData theme, OcrModelSet set) {
    final status = _statuses[set.id];
    final busy = _busySetId != null;
    final phaseFour = set.id == 'manga_ocr';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(set.displayName, style: theme.textTheme.titleMedium),
            ),
            Text(_formatBytes(set.totalSize), style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${_licenseLabel(set.license)}'
          '${set.licenseUrl.isEmpty ? '' : ' · ${set.licenseUrl}'}',
          style: theme.textTheme.bodySmall,
        ),
        if (set.licenseNote.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(set.licenseNote, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (status != null)
          Text(
            status.isInstalled
                ? '已安装（${_formatBytes(status.installedBytes)}）'
                : status.missingFiles.length <= 3
                ? '未安装：缺少 ${status.missingFiles.join('、')}'
                : '未安装：缺少 ${status.missingFiles.length} 个文件',
            style: theme.textTheme.bodyMedium,
          ),
        if (phaseFour) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '竖排识别将在后续 Phase 4 接入；当前 Phase 3 只需 PaddleOCR 模型。',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (!phaseFour && (status?.isInstalled != true))
              FilledButton.icon(
                onPressed: busy ? null : () => _download(set),
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载'),
              ),
            if (!phaseFour && (status?.isInstalled ?? false))
              OutlinedButton.icon(
                onPressed: busy ? null : () => _delete(set),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除'),
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

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
