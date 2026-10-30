import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/capture_photo.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/ocr/model_manager.dart';
import '../../services/ocr/ocr_text_composer.dart';
import '../../state/capture_session.dart';
import '../../state/providers.dart';
import 'capture_buttons.dart';
import 'capture_corpus.dart';
import 'capture_dialogs.dart';

class PhotoMultiSelectPage extends ConsumerStatefulWidget {
  const PhotoMultiSelectPage({super.key, this.initialFingerprint});

  final String? initialFingerprint;

  @override
  ConsumerState<PhotoMultiSelectPage> createState() =>
      _PhotoMultiSelectPageState();
}

class _PhotoMultiSelectPageState extends ConsumerState<PhotoMultiSelectPage> {
  final Set<String> _selected = {};
  String? _fingerprint;
  String? _recognizingPhotoId;
  String? _error;
  bool _busy = false;
  bool _saving = false;
  int _runToken = 0;
  bool _disposed = false;
  StreamSubscription<OcrProgress>? _progressSubscription;
  final Set<String> _autoSaved = {};
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _fingerprint = widget.initialFingerprint;
    _progressSubscription = ref.read(ocrServiceProvider).progress.listen((
      event,
    ) {
      if (!mounted || !_busy) return;
      setState(() => _progress = event.progress);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _recognizeMissing());
  }

  @override
  void dispose() {
    _disposed = true;
    _runToken++;
    _progressSubscription?.cancel();
    unawaited(ref.read(ocrServiceProvider).cancel().catchError((_) {}));
    super.dispose();
  }

  Future<void> _recognizeMissing() async {
    if (_disposed) return;
    final token = ++_runToken;
    final photos = ref.read(captureSessionProvider).photos;
    final knownFingerprint =
        _fingerprint ?? ref.read(ocrServiceProvider).fingerprint;

    bool hasMissing(String fingerprint) {
      return photos.any(
        (photo) =>
            photo.findOcrResult(mode: photo.mode, fingerprint: fingerprint) ==
            null,
      );
    }

    if (knownFingerprint != null) {
      if (_fingerprint != knownFingerprint && mounted) {
        setState(() => _fingerprint = knownFingerprint);
      }
      if (!hasMissing(knownFingerprint)) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = null;
            _progress = 1;
            _recognizingPhotoId = null;
          });
        }
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _recognizingPhotoId = null;
    });
    try {
      final fingerprint = knownFingerprint ?? await _ensureFingerprint();
      if (token != _runToken || _disposed) return;
      setState(() => _fingerprint = fingerprint);
      for (final photo in photos) {
        if (token != _runToken || _disposed) return;
        final key = photoOcrCacheKey(
          mode: photo.mode,
          fingerprint: fingerprint,
        );
        if (photo.findOcrResult(mode: photo.mode, fingerprint: fingerprint) !=
            null) {
          continue;
        }
        setState(() => _recognizingPhotoId = photo.id);
        try {
          final result = await ref
              .read(ocrServiceProvider)
              .recognize(imagePath: photo.filePath, mode: photo.mode);
          if (token != _runToken || _disposed) return;
          final text = composeOcrText(result.blocks);
          final photoResult = PhotoOcrResult.fromOcrResult(result, text);
          ref
              .read(captureSessionProvider.notifier)
              .setOcrResult(photo.id, key, photoResult);
          unawaited(_autoSave(photo, photoResult));
        } on OcrException catch (error) {
          if (error.code == 'CANCELLED') return;
          _error = error.message;
        } catch (error) {
          _error = _errorText(error);
        }
        if (token != _runToken || _disposed) return;
      }
    } catch (error) {
      if (token != _runToken || _disposed) return;
      _error = _errorText(error);
    } finally {
      if (mounted && token == _runToken) {
        setState(() {
          _busy = false;
          _recognizingPhotoId = null;
        });
      }
    }
  }

  Future<String> _ensureFingerprint() async {
    final manifest = await ref.read(ocrModelManifestProvider.future);
    return ref.read(ocrServiceProvider).ensureReady(manifest);
  }

  Future<void> _autoSave(CapturePhoto photo, PhotoOcrResult result) async {
    if (!ref.read(appSettingsProvider).autoSaveOcr) return;
    if (result.text.trim().isEmpty) return;
    final key = '${photo.id}|${photo.mode.name}|${result.text}';
    if (!_autoSaved.add(key)) return;
    try {
      await saveCapturePhotoToCorpus(
        history: ref.read(historyStoreProvider),
        photo: photo,
        result: result,
      );
      if (!mounted || _disposed) return;
      ref.invalidate(corpusEntriesProvider);
    } catch (_) {
      _autoSaved.remove(key);
    }
  }

  Future<void> _cancelRecognition() async {
    _runToken++;
    try {
      await ref.read(ocrServiceProvider).cancel();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _busy = false;
        _recognizingPhotoId = null;
      });
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _selectAll(List<CapturePhoto> photos) {
    setState(() {
      if (_selected.length == photos.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(photos.map((photo) => photo.id));
      }
    });
  }

  Future<void> _saveSelected() async {
    if (_saving || _selected.isEmpty || _busy) return;
    final selected = ref
        .read(captureSessionProvider)
        .photos
        .where((photo) => _selected.contains(photo.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('保存所选 ${selected.length} 张照片？'),
        content: const Text('将保存照片、OCR 原文、识别模式和时间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    var saved = 0;
    try {
      for (final photo in selected) {
        final cached = _fingerprint == null
            ? null
            : photo.findOcrResult(mode: photo.mode, fingerprint: _fingerprint!);
        await saveCapturePhotoToCorpus(
          history: ref.read(historyStoreProvider),
          photo: photo,
          result: cached,
        );
        saved++;
      }
      if (!mounted) return;
      ref.invalidate(corpusEntriesProvider);
      RikaiToast.show(context, '已保存 $saved 张照片到语料库');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final choice = await showDeletePhotoDialog(
      context,
      count: _selected.length,
      allowOriginal: true,
    );
    if (choice == null || !choice.confirmed || !mounted) return;
    await _cancelRecognition();
    final storage = ref.read(captureStorageProvider);
    final photos = ref
        .read(captureSessionProvider)
        .photos
        .where((photo) => _selected.contains(photo.id))
        .toList(growable: false);
    var originalDeleteFailed = false;
    for (final photo in photos) {
      await storage.deleteSessionFile(photo.filePath);
      if (choice.deleteOriginal) {
        final deleted = await storage.tryDeleteOriginal(photo.originalPath);
        if (!deleted && photo.originalPath != null) {
          originalDeleteFailed = true;
        }
      }
    }
    if (!mounted) return;
    if (originalDeleteFailed) {
      RikaiToast.show(context, '部分设备原图无法删除，已仅从照片集移除');
    }
    ref.read(captureSessionProvider.notifier).removePhotos(_selected.toSet());
    _selected.clear();
    if (ref.read(captureSessionProvider).isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {});
    await _recognizeMissing();
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(captureSessionProvider).photos;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('选择照片'),
        actions: [
          TextButton(
            onPressed: _busy
                ? _cancelRecognition
                : () {
                    final photos = ref.read(captureSessionProvider).photos;
                    _selectAll(photos);
                  },
            child: Text(
              _busy
                  ? '取消识别'
                  : _selected.length == photos.length
                  ? '取消全选'
                  : '全选',
              style: const TextStyle(color: AppColors.onHeader),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Text('已选 ${_selected.length}/${photos.length}'),
                ),
                if (_busy) ...[
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _recognizingPhotoId == null ? '正在准备识别…' : '正在补识别未缓存照片…',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.xs,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSizes.captureGridBottomReserve,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.md,
                          mainAxisSpacing: AppSpacing.md,
                          childAspectRatio: 0.78,
                        ),
                    itemCount: photos.length,
                    itemBuilder: (context, index) {
                      final photo = photos[index];
                      final result = _fingerprint == null
                          ? null
                          : photo.findOcrResult(
                              mode: photo.mode,
                              fingerprint: _fingerprint!,
                            );
                      return _PhotoGridTile(
                        photo: photo,
                        text: result?.text,
                        selected: _selected.contains(photo.id),
                        recognizing: _recognizingPhotoId == photo.id,
                        onTap: () => _toggle(photo.id),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              left: AppSpacing.lg,
              bottom: AppSpacing.md,
              child: CaptureRoundButton(
                tooltip: '删除所选照片',
                icon: Icons.delete_outline,
                background: AppColors.error,
                onPressed: _selected.isEmpty || _saving
                    ? null
                    : _deleteSelected,
              ),
            ),
            Positioned(
              right: AppSpacing.lg,
              bottom: AppSpacing.md,
              child: CaptureRoundButton(
                tooltip: '保存所选照片到语料库',
                icon: Icons.bookmark_add_outlined,
                background: AppColors.header,
                onPressed: _selected.isEmpty || _busy || _saving
                    ? null
                    : _saveSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _errorText(Object error) {
    if (error is OcrModelException) return error.message;
    if (error is OcrException) return error.message;
    return error.toString();
  }
}

class _PhotoGridTile extends StatelessWidget {
  const _PhotoGridTile({
    required this.photo,
    required this.text,
    required this.selected,
    required this.recognizing,
    required this.onTap,
  });

  final CapturePhoto photo;
  final String? text;
  final bool selected;
  final bool recognizing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 2 : AppSizes.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ColoredBox(
                    color: AppColors.surfaceMuted,
                    child: Image.file(
                      File(photo.filePath),
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    text == null || text!.isEmpty ? '尚未识别' : text!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: AppTypography.ocrPreview,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (recognizing)
              const Center(
                child: SizedBox(
                  width: AppSizes.iconLarge,
                  height: AppSizes.iconLarge,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Positioned(
              left: AppSpacing.xs,
              top: AppSpacing.xs,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                side: const BorderSide(color: AppColors.onHeader),
                checkColor: AppColors.onHeader,
                activeColor: AppColors.primary,
                fillColor: WidgetStateProperty.resolveWith((states) {
                  return states.contains(WidgetState.selected)
                      ? AppColors.primary
                      : AppColors.transparent;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
