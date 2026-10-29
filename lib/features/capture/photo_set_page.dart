import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/capture_photo.dart';
import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/mecab/mecab_service.dart';
import '../../services/ocr/model_manager.dart';
import '../../services/ocr/ocr_text_composer.dart';
import '../../services/storage/settings_store.dart';
import '../../state/capture_session.dart';
import '../../state/providers.dart';
import '../lookup/lookup_sheet.dart';
import '../reader/reader_block.dart';
import '../reader/reader_lines.dart';
import '../reader/reader_options.dart';
import 'capture_buttons.dart';
import 'capture_dialogs.dart';
import 'photo_multi_select_page.dart';
import 'photo_viewer_page.dart';

class PhotoSetPage extends ConsumerStatefulWidget {
  const PhotoSetPage({super.key});

  @override
  ConsumerState<PhotoSetPage> createState() => _PhotoSetPageState();
}

class _PhotoSetPageState extends ConsumerState<PhotoSetPage> {
  OcrMode _mode = OcrMode.auto;
  String? _fingerprint;
  String? _error;
  String _stage = '';
  double _progress = 0;
  bool _busy = false;
  bool _saving = false;
  bool _disposed = false;
  int _runToken = 0;
  int _analysisToken = 0;
  List<Token> _tokens = const [];
  String? _analysedText;
  MecabException? _mecabError;
  Object? _analysisError;
  bool _analysisBusy = false;
  bool _unidicConfigured = false;
  double _photoHeight = AppSizes.capturePhotoHeight;
  StreamSubscription<OcrProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _progressSubscription = ref.read(ocrServiceProvider).progress.listen((
      event,
    ) {
      if (!mounted || !_busy) return;
      setState(() {
        _stage = _stageLabel(event);
        _progress = _progressFor(event);
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCurrent());
  }

  @override
  void dispose() {
    _disposed = true;
    _runToken++;
    _analysisToken++;
    _progressSubscription?.cancel();
    unawaited(ref.read(ocrServiceProvider).cancel().catchError((_) {}));
    super.dispose();
  }

  Future<void> _cancelRecognition() async {
    _runToken++;
    try {
      await ref.read(ocrServiceProvider).cancel();
    } catch (_) {
      // A cancel racing with completion is harmless.
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _stage = '';
      });
    }
  }

  Future<void> _refreshCurrent({bool force = false}) async {
    if (_disposed) return;
    final photo = ref.read(captureSessionProvider).current;
    if (photo == null) return;
    final token = ++_runToken;
    _analysisToken++;
    if (mounted) {
      setState(() {
        _error = null;
        _progress = 0;
        _stage = '正在检查 OCR 模型…';
        _busy = true;
        _tokens = const [];
        _analysedText = null;
        _mecabError = null;
        _analysisError = null;
        _analysisBusy = false;
      });
    }
    try {
      await ref.read(ocrServiceProvider).cancel();
      if (token != _runToken || _disposed) return;
      final manifest = await ref.read(ocrModelManifestProvider.future);
      final fingerprint = await ref
          .read(ocrServiceProvider)
          .ensureReady(manifest);
      if (token != _runToken || _disposed) return;
      final key = photoOcrCacheKey(mode: _mode, fingerprint: fingerprint);
      final cached = photo.ocrCache[key];
      setState(() {
        _fingerprint = fingerprint;
        if (cached != null && !force) {
          _busy = false;
          _stage = '';
          _progress = 1;
        } else {
          _busy = true;
          _stage = '准备 OCR…';
          _progress = 0.05;
        }
      });
      if (cached != null && !force) {
        await _startAnalysis(photo.id, cached.text);
        return;
      }
      final result = await ref
          .read(ocrServiceProvider)
          .recognize(imagePath: photo.filePath, mode: _mode);
      if (token != _runToken || _disposed) return;
      final text = composeOcrText(result.blocks);
      ref
          .read(captureSessionProvider.notifier)
          .setOcrResult(
            photo.id,
            key,
            PhotoOcrResult.fromOcrResult(result, text),
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
        _progress = 1;
        _error = null;
      });
      await _startAnalysis(photo.id, text);
    } on OcrException catch (error) {
      if (token != _runToken || _disposed) return;
      if (error.code == 'CANCELLED') {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } catch (error) {
      if (token != _runToken || _disposed) return;
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errorText(error);
        });
      }
    }
  }

  Future<void> _startAnalysis(String photoId, String text) async {
    final token = ++_analysisToken;
    final configured = ref
        .read(appSettingsProvider)
        .unidicPath
        .trim()
        .isNotEmpty;
    if (!mounted || _disposed) return;
    if (text.trim().isEmpty || !configured) {
      setState(() {
        _unidicConfigured = configured;
        _tokens = const [];
        _analysedText = null;
        _mecabError = null;
        _analysisError = null;
        _analysisBusy = false;
      });
      return;
    }
    setState(() {
      _unidicConfigured = true;
      _tokens = const [];
      _analysedText = null;
      _mecabError = null;
      _analysisError = null;
      _analysisBusy = true;
    });
    try {
      final service = await ref.read(mecabServiceProvider.future);
      if (!_isCurrentAnalysis(token, photoId)) return;
      final tokens = await service.analyze(text);
      if (!_isCurrentAnalysis(token, photoId)) return;
      setState(() {
        _tokens = tokens;
        _analysedText = text;
      });
    } on MecabException catch (error) {
      if (!_isCurrentAnalysis(token, photoId)) return;
      setState(() => _mecabError = error);
    } catch (error) {
      if (!_isCurrentAnalysis(token, photoId)) return;
      setState(() => _analysisError = error);
    } finally {
      if (_isCurrentAnalysis(token, photoId)) {
        setState(() => _analysisBusy = false);
      }
    }
  }

  bool _isCurrentAnalysis(int token, String photoId) {
    return mounted &&
        !_disposed &&
        token == _analysisToken &&
        ref.read(captureSessionProvider).current?.id == photoId;
  }

  void _retryAnalysis() {
    if (_analysisBusy) return;
    final photo = ref.read(captureSessionProvider).current;
    if (photo == null) return;
    final text = _cachedText(photo);
    if (text.isEmpty) return;
    ref.invalidate(mecabServiceProvider);
    unawaited(_startAnalysis(photo.id, text));
  }

  String _cachedText(CapturePhoto photo) {
    final key = _fingerprint == null
        ? null
        : photoOcrCacheKey(mode: _mode, fingerprint: _fingerprint!);
    return key == null ? '' : photo.ocrCache[key]?.text ?? '';
  }

  Future<void> _copyText(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制全文')));
  }

  Future<void> _changeMode(OcrMode mode) async {
    if (mode == _mode) return;
    await _cancelRecognition();
    setState(() {
      _mode = mode;
      _error = null;
    });
    await _refreshCurrent();
  }

  Future<void> _changePhoto(int delta) async {
    final session = ref.read(captureSessionProvider);
    final next = session.currentIndex + delta;
    if (next < 0 || next >= session.photos.length) return;
    await _cancelRecognition();
    ref.read(captureSessionProvider.notifier).setCurrentIndex(next);
    await _refreshCurrent();
  }

  Future<void> _saveCurrent() async {
    if (_saving) return;
    final photo = ref.read(captureSessionProvider).current;
    if (photo == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存到语料库？'),
        content: const Text('将保存当前照片、OCR 原文、识别模式和时间。'),
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
    final key = _fingerprint == null
        ? null
        : photoOcrCacheKey(mode: _mode, fingerprint: _fingerprint!);
    final cached = key == null ? null : photo.ocrCache[key];
    final blocksJson = jsonEncode(
      (cached?.blocks ?? const []).map((block) {
        return {
          'text': block.text,
          'left': block.left,
          'top': block.top,
          'right': block.right,
          'bottom': block.bottom,
          'confidence': block.confidence,
          'orientation': block.orientation,
          'points': block.points,
        };
      }).toList(),
    );
    setState(() => _saving = true);
    try {
      await ref
          .read(historyStoreProvider)
          .savePhoto(
            sourceImagePath: photo.filePath,
            text: cached?.text ?? '',
            engine: cached?.engine ?? 'paddle_v5',
            mode: _mode.name,
            orientation: cached?.blocks.isNotEmpty == true
                ? cached!.blocks.first.orientation
                : 'unknown',
            blocksJson: blocksJson,
          );
      ref.invalidate(corpusEntriesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存到语料库')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openModelSettings() async {
    await _cancelRecognition();
    final previous = _fingerprint;
    if (!mounted) return;
    await context.push('/models');
    if (!mounted) return;
    try {
      final manifest = await ref.read(ocrModelManifestProvider.future);
      final fingerprint = await ref
          .read(ocrServiceProvider)
          .ensureReady(manifest);
      if (previous != null && fingerprint != previous) {
        ref.read(captureSessionProvider.notifier).clearOcrCache();
      }
    } catch (_) {
      // The refresh below surfaces the model error in the page.
    }
    await _refreshCurrent(force: true);
  }

  Future<void> _deleteCurrent() async {
    final photo = ref.read(captureSessionProvider).current;
    if (photo == null) return;
    final choice = await showDeletePhotoDialog(
      context,
      count: 1,
      allowOriginal: photo.originalPath != null,
    );
    if (choice == null || !choice.confirmed || !mounted) return;
    await _cancelRecognition();
    final storage = ref.read(captureStorageProvider);
    await storage.deleteSessionFile(photo.filePath);
    var originalDeleted = true;
    if (choice.deleteOriginal) {
      originalDeleted = await storage.tryDeleteOriginal(photo.originalPath);
    }
    if (!mounted) return;
    ref.read(captureSessionProvider.notifier).removePhotos({photo.id});
    if (ref.read(captureSessionProvider).isEmpty) {
      if (mounted) context.pop();
      return;
    }
    if (!originalDeleted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法删除设备原图，已仅从照片集移除')));
    }
    await _refreshCurrent();
  }

  void _openPhotoViewer() {
    final photo = ref.read(captureSessionProvider).current;
    if (photo == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PhotoViewerPage(imagePath: photo.filePath),
      ),
    );
  }

  Future<void> _openMultiSelect() async {
    await _cancelRecognition();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PhotoMultiSelectPage(mode: _mode),
      ),
    );
    if (!mounted) return;
    if (ref.read(captureSessionProvider).isEmpty) {
      context.pop();
      return;
    }
    await _refreshCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(captureSessionProvider);
    final settings = ref.watch(appSettingsProvider);
    final photo = session.current;
    final theme = Theme.of(context);
    if (session.isEmpty || photo == null) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('照片集')),
        body: const Center(child: Text('照片集为空')),
      );
    }
    final text = _cachedText(photo);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('照片集'),
        actions: [
          TextButton.icon(
            onPressed: text.isEmpty ? null : () => _copyText(text),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onHeader,
              disabledForegroundColor: AppColors.onHeader.withValues(
                alpha: 0.4,
              ),
            ),
            icon: const Icon(Icons.copy_all_outlined, size: AppSizes.iconSmall),
            label: const Text('复制'),
          ),
          const ReaderOptionsMenu(),
          TextButton(
            onPressed: _openMultiSelect,
            child: const Text(
              '多选',
              style: TextStyle(color: AppColors.onHeader),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep room for the mode selector, page navigation and the
            // screen-corner actions; the photo itself can grow into the rest.
            final maxPhotoHeight = (constraints.maxHeight - 340)
                .clamp(AppSizes.capturePhotoMin, constraints.maxHeight)
                .toDouble();
            final photoHeight = _photoHeight
                .clamp(AppSizes.capturePhotoMin, maxPhotoHeight)
                .toDouble();
            return Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: photoHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Semantics(
                            button: true,
                            label: '查看照片',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _openPhotoViewer,
                              child: ColoredBox(
                                color: AppColors.surfaceMuted,
                                child: Image.file(
                                  File(photo.filePath),
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Center(child: Text('无法显示照片')),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: AppSizes.captureResizeHandle,
                            child: Semantics(
                              label: '调整照片显示范围',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (details) {
                                  setState(() {
                                    _photoHeight =
                                        (_photoHeight + details.delta.dy)
                                            .clamp(
                                              AppSizes.capturePhotoMin,
                                              maxPhotoHeight,
                                            )
                                            .toDouble();
                                  });
                                },
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                      bottom: AppSpacing.xs,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: AppSpacing.xxs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.cameraScrim,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.pill,
                                      ),
                                    ),
                                    child: Container(
                                      width: AppSizes.captureResizeBarWidth,
                                      height: AppSizes.captureResizeBarHeight,
                                      decoration: BoxDecoration(
                                        color: AppColors.cameraControl,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.pill,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: _buildRecognitionArea(theme, settings, text),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xs,
                      ),
                      child: SegmentedButton<OcrMode>(
                        segments: const [
                          ButtonSegment(value: OcrMode.auto, label: Text('自动')),
                          ButtonSegment(
                            value: OcrMode.horizontal,
                            label: Text('横向'),
                          ),
                          ButtonSegment(
                            value: OcrMode.vertical,
                            label: Text('竖向'),
                            enabled: false,
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _busy
                            ? null
                            : (selection) => _changeMode(selection.first),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '竖向识别将在后续版本支持。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: AppTypography.helper,
                            ),
                          ),
                          Center(
                            child: TextButton.icon(
                              onPressed: _openModelSettings,
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('模型设置'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _PageNavigation(
                      index: session.currentIndex,
                      count: session.length,
                      onPrevious: () => _changePhoto(-1),
                      onNext: () => _changePhoto(1),
                    ),
                    const SizedBox(height: AppSizes.captureBottomReserve),
                  ],
                ),
                Positioned(
                  left: AppSpacing.lg,
                  bottom: AppSpacing.md,
                  child: CaptureRoundButton(
                    tooltip: '删除照片',
                    icon: Icons.delete_outline,
                    background: AppColors.error,
                    onPressed: _deleteCurrent,
                  ),
                ),
                Positioned(
                  right: AppSpacing.lg,
                  bottom: AppSpacing.md,
                  child: CaptureRoundButton(
                    tooltip: '保存到语料库',
                    icon: Icons.bookmark_add_outlined,
                    background: AppColors.header,
                    onPressed: _saving || _busy ? null : _saveCurrent,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecognitionArea(
    ThemeData theme,
    AppSettings settings,
    String text,
  ) {
    if (_busy) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_stage.isEmpty ? '正在识别…' : _stage),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _cancelRecognition,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('取消识别'),
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '识别失败',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(_error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _refreshCurrent(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (text.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '尚未识别',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('切换照片或模式会自动识别；也可以点击重试。', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _refreshCurrent(force: true),
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('识别当前照片'),
            ),
          ],
        ),
      );
    }
    if (_analysisBusy) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '正在分词…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AppTypography.helper,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildRawResult(theme, settings, text)),
        ],
      );
    }
    if (_tokens.isNotEmpty && _analysedText == text) {
      return _buildTokenResult(settings, text);
    }
    return _buildRawResult(theme, settings, text);
  }

  Widget _buildRawResult(ThemeData theme, AppSettings settings, String text) {
    final analysisError = _analysisErrorText();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (analysisError.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '分词不可用：$analysisError',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AppTypography.helper,
                      height: 1.5,
                      color: AppColors.error,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _retryAnalysis,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试分词'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ] else if (!_unidicConfigured) ...[
            Text(
              '尚未配置 UniDic，当前显示 OCR 原文。',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AppTypography.helper,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SelectableText(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: settings.readerFontSize,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenResult(AppSettings settings, String text) {
    final lines = buildReaderLines(text, _tokens);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        if (line.tokens.isEmpty) {
          return SizedBox(height: settings.readerFontSize + AppSpacing.md);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: ReaderBlock(
            tokens: line.tokens,
            fontSize: settings.readerFontSize,
            showFurigana: settings.showFurigana,
            onTokenTap: (token) => showTokenLookupSheet(context, token),
          ),
        );
      },
    );
  }

  String _analysisErrorText() {
    final mecabError = _mecabError;
    if (mecabError != null) return mecabError.message;
    return _analysisError?.toString() ?? '';
  }

  String _stageLabel(OcrProgress event) {
    switch (event.stage) {
      case 'detect':
        return '正在检测文字区域…';
      case 'recognize':
        final total = event.total;
        final current = total > 0 ? event.current : 0;
        return total > 0 ? '正在识别第 $current/$total 行…' : '正在识别文字…';
      case 'done':
        return '识别完成';
      case 'cancelled':
        return '已取消识别';
      default:
        return '正在识别…';
    }
  }

  double _progressFor(OcrProgress event) {
    switch (event.stage) {
      case 'detect':
        return 0.1;
      case 'recognize':
        return 0.1 + 0.85 * event.progress;
      case 'done':
        return 1;
      default:
        return _progress;
    }
  }

  String _errorText(Object error) {
    if (error is OcrModelException) return error.message;
    if (error is OcrException) return error.message;
    return error.toString();
  }
}

class _PageNavigation extends StatelessWidget {
  const _PageNavigation({
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final int index;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '上一张',
            onPressed: index > 0 ? onPrevious : null,
            icon: const Icon(Icons.arrow_back),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text('${index + 1}/$count'),
          ),
          IconButton(
            tooltip: '下一张',
            onPressed: index < count - 1 ? onNext : null,
            icon: const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    );
  }
}
