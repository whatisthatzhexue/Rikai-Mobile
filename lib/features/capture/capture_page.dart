import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/ocr_model.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/ocr/model_manager.dart';
import '../../services/ocr/ocr_text_composer.dart';
import '../../state/providers.dart';
import '../reader/reader_page.dart';

class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key});

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage> {
  final ImagePicker _picker = ImagePicker();
  final RikaiOcr _ocr = RikaiOcr();
  StreamSubscription<OcrProgress>? _progressSubscription;

  File? _image;
  OcrMode _mode = OcrMode.auto;
  OcrModelManifest? _manifest;
  OcrModelSet? _paddleSet;
  OcrModelStatus? _paddleStatus;
  OcrModelDownloadProgress? _downloadProgress;
  CancelToken? _downloadCancel;

  bool _loadingModels = true;
  bool _downloading = false;
  bool _recognizing = false;
  String? _error;
  String _stage = '';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _progressSubscription = _ocr.progress.listen((event) {
      if (!mounted) return;
      setState(() {
        _stage = _stageLabel(event);
        _progress = event.progress;
      });
    });
    _loadModels();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _downloadCancel?.cancel();
    unawaited(_ocr.dispose());
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final manifest = await ref.read(ocrModelManifestProvider.future);
      final set = manifest.sets['paddle_v5'];
      if (set == null) {
        throw const OcrModelException('MANIFEST_INVALID', '模型清单缺少 PaddleOCR');
      }
      final status = await ref.read(ocrModelManagerProvider).status(set);
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _paddleSet = set;
        _paddleStatus = status;
        _loadingModels = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _error = _errorText(error);
      });
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _image = File(picked.path);
        _error = null;
        _progress = 0;
        _stage = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '无法打开图片选择器：$error');
    }
  }

  Future<void> _downloadModels() async {
    final set = _paddleSet;
    if (set == null || _downloading) return;
    final cancel = CancelToken();
    setState(() {
      _downloading = true;
      _downloadCancel = cancel;
      _downloadProgress = null;
      _error = null;
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
      await _loadModels();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PaddleOCR 模型已下载并校验完成')));
    } on OcrModelException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'CANCELLED' ? '已取消下载' : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '模型下载失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadCancel = null;
          _downloadProgress = null;
        });
      }
    }
  }

  void _cancelDownload() {
    _downloadCancel?.cancel('用户取消下载');
  }

  Future<void> _recognize() async {
    final image = _image;
    final manifest = _manifest;
    final status = _paddleStatus;
    if (image == null || _recognizing) return;
    if (manifest == null || status == null || !status.isInstalled) {
      setState(() => _error = '请先下载 PaddleOCR 模型');
      return;
    }

    setState(() {
      _recognizing = true;
      _error = null;
      _stage = '准备 OCR 模型…';
      _progress = 0;
    });
    try {
      final paths = await ref
          .read(ocrModelManagerProvider)
          .paddlePaths(manifest);
      await _ocr.initialize(
        detModelPath: paths.det,
        recModelPath: paths.rec,
        keysPath: paths.keys,
      );
      final result = await _ocr.recognize(imagePath: image.path, mode: _mode);
      final text = composeOcrText(result.blocks);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        setState(() => _error = '没有识别到文字，请换一张更清晰、方向正确的图片');
        return;
      }
      await context.push('/reader', extra: ReaderRouteArgs(text));
    } on OcrException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code == 'CANCELLED' ? '已取消识别' : error.message;
      });
    } on OcrModelException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '识别失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _recognizing = false;
          _stage = '';
          _progress = 0;
        });
      }
    }
  }

  Future<void> _cancelRecognize() async {
    setState(() => _stage = '正在取消…');
    await _ocr.cancel();
  }

  Future<void> _openModelManager() async {
    await context.push('/models');
    if (!mounted) return;
    await _loadModels();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _image;
    final status = _paddleStatus;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('拍照识别')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            if (image == null)
              _CapturePrompt(
                onCamera: () => _pick(ImageSource.camera),
                onGallery: () => _pick(ImageSource.gallery),
              )
            else ...[
              _ImagePreview(file: image),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _recognizing
                        ? null
                        : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('重新拍照'),
                  ),
                  TextButton.icon(
                    onPressed: _recognizing
                        ? null
                        : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('从相册选择'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text('识别方向', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<OcrMode>(
              segments: const [
                ButtonSegment(
                  value: OcrMode.auto,
                  icon: Icon(Icons.auto_awesome),
                  label: Text('自动'),
                ),
                ButtonSegment(
                  value: OcrMode.horizontal,
                  icon: Icon(Icons.format_align_left),
                  label: Text('横向'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _recognizing
                  ? null
                  : (selection) => setState(() => _mode = selection.first),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('当前版本支持横排文字；竖排识别将在后续版本加入。', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xl),
            _buildModelSection(theme, status),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            if (_recognizing) ...[
              const SizedBox(height: AppSpacing.xl),
              Text(_stage.isEmpty ? '正在识别…' : _stage),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _cancelRecognize,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('取消识别'),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: image == null || _recognizing || _downloading
                  ? null
                  : _recognize,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('开始识别'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSection(ThemeData theme, OcrModelStatus? status) {
    if (_loadingModels) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: AppSpacing.sm),
          Text('正在检查 OCR 模型…'),
        ],
      );
    }
    final set = _paddleSet;
    if (set == null || status == null) {
      return Text(
        '无法读取 OCR 模型清单',
        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
      );
    }
    if (status.isInstalled) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: AppSizes.icon,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'PaddleOCR 已就绪（${_formatBytes(status.totalBytes)}）',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: _openModelManager, child: const Text('管理模型')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '需要下载 PaddleOCR 模型（${_formatBytes(set.totalSize)}，${set.license}）',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('模型由应用在本地校验，下载后可完全离线使用。', style: theme.textTheme.bodySmall),
        if (_downloading) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(value: _downloadProgress?.overallProgress),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _downloadProgress == null
                ? '正在连接模型服务器…'
                : '正在下载 ${_downloadProgress!.fileName} '
                      '（${_downloadProgress!.fileIndex + 1}/${_downloadProgress!.fileCount}）'
                      ' ${(_downloadProgress!.overallProgress * 100).round()}%',
            style: theme.textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: _cancelDownload,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('取消下载'),
          ),
        ] else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: _downloading ? null : _downloadModels,
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载模型'),
              ),
              OutlinedButton(
                onPressed: _downloading ? null : _openModelManager,
                child: const Text('管理模型'),
              ),
            ],
          ),
      ],
    );
  }

  String _stageLabel(OcrProgress event) {
    switch (event.stage) {
      case 'detect':
        return '正在检测文本行…';
      case 'recognize':
        final current = event.total > 0 ? event.current + 1 : event.current;
        return event.total > 0 ? '正在识别第 $current/${event.total} 行…' : '正在识别文字…';
      case 'done':
        return '识别完成';
      case 'cancelled':
        return '已取消识别';
      default:
        return '正在识别…';
    }
  }

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

class _CapturePrompt extends StatelessWidget {
  const _CapturePrompt({required this.onCamera, required this.onGallery});

  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.document_scanner_outlined,
            size: AppSizes.heroIcon,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('拍摄或选择一张日文图片', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '支持相机拍照和相册图片；图片会在设备本地处理，不会上传。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('拍照'),
              ),
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('从相册选择'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            const Center(child: Text('无法显示图片预览')),
      ),
    );
  }
}
