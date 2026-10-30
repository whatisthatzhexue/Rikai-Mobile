import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/corpus_entry.dart';
import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/page_route.dart';
import '../../core/ui/no_scrollbar_behavior.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/mecab/mecab_service.dart';
import '../../services/storage/settings_store.dart';
import '../../state/providers.dart';
import '../capture/capture_buttons.dart';
import '../capture/photo_pane.dart';
import '../capture/photo_viewer_page.dart';
import '../lookup/lookup_sheet.dart';
import '../reader/reader_block.dart';
import '../reader/reader_lines.dart';
import '../reader/reader_options.dart';

class CorpusDetailRouteArgs {
  const CorpusDetailRouteArgs(this.entry);

  final CorpusEntry entry;
}

class CorpusDetailPage extends ConsumerStatefulWidget {
  const CorpusDetailPage({super.key, required this.initialEntry});

  final CorpusEntry initialEntry;

  @override
  ConsumerState<CorpusDetailPage> createState() => _CorpusDetailPageState();
}

class _CorpusDetailPageState extends ConsumerState<CorpusDetailPage> {
  late String _selectedId;
  String? _analysisKey;
  List<Token> _tokens = const [];
  String? _analysedText;
  MecabException? _mecabError;
  Object? _analysisError;
  bool _analysisBusy = false;
  bool _unidicConfigured = false;
  bool _disposed = false;
  int _analysisToken = 0;
  double _photoHeight = AppSizes.capturePhotoHeight;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialEntry.id;
    _unidicConfigured = ref
        .read(appSettingsProvider)
        .unidicPath
        .trim()
        .isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _analyze(widget.initialEntry);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _analysisToken++;
    super.dispose();
  }

  Future<void> _analyze(CorpusEntry entry, {bool force = false}) async {
    final key = '${entry.id}\u0000${entry.text}';
    if (!force && _analysisKey == key) return;
    _analysisKey = key;
    final token = ++_analysisToken;
    final configured = ref
        .read(appSettingsProvider)
        .unidicPath
        .trim()
        .isNotEmpty;
    if (!mounted || _disposed) return;
    if (entry.text.trim().isEmpty || !configured) {
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
      if (!_isCurrent(token, entry.id)) return;
      final tokens = await service.analyze(entry.text);
      if (!_isCurrent(token, entry.id)) return;
      setState(() {
        _tokens = tokens;
        _analysedText = entry.text;
      });
    } on MecabException catch (error) {
      if (!_isCurrent(token, entry.id)) return;
      setState(() => _mecabError = error);
    } catch (error) {
      if (!_isCurrent(token, entry.id)) return;
      setState(() => _analysisError = error);
    } finally {
      if (_isCurrent(token, entry.id)) {
        setState(() => _analysisBusy = false);
      }
    }
  }

  bool _isCurrent(int token, String entryId) {
    return mounted &&
        !_disposed &&
        token == _analysisToken &&
        _selectedId == entryId;
  }

  void _retryAnalysis(CorpusEntry entry) {
    if (_analysisBusy) return;
    ref.invalidate(mecabServiceProvider);
    unawaited(_analyze(entry, force: true));
  }

  void _navigate(List<CorpusEntry> entries, int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= entries.length) return;
    final entry = entries[target];
    setState(() => _selectedId = entry.id);
    unawaited(_analyze(entry));
  }

  Future<void> _delete(List<CorpusEntry> entries, int index) async {
    final entry = entries[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条语料？'),
        content: const Text('照片副本和 OCR 文本会从本机删除，无法恢复。'),
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
    final next = entries.length <= 1
        ? null
        : entries[index + 1 < entries.length ? index + 1 : index - 1];
    await ref.read(historyStoreProvider).delete(entry);
    ref.invalidate(corpusEntriesProvider);
    if (!mounted) return;
    if (next == null) {
      context.pop();
      return;
    }
    setState(() => _selectedId = next.id);
    await _analyze(next);
  }

  void _openPhoto(CorpusEntry entry) {
    if (entry.imagePath.isEmpty) return;
    Navigator.of(context).push(
      RikaiPageRoute<void>(
        builder: (context) => PhotoViewerPage(imagePath: entry.imagePath),
      ),
    );
  }

  Future<void> _copyText(String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    RikaiToast.show(context, '已复制全文');
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(corpusEntriesProvider);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('语料'),
        actions: const [ReaderOptionsMenu()],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('语料读取失败', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(corpusEntriesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('没有可显示的语料'));
          }
          var index = entries.indexWhere((entry) => entry.id == _selectedId);
          if (index < 0) index = 0;
          final entry = entries[index];
          final settings = ref.watch(appSettingsProvider);
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxPhotoHeight =
                    (constraints.maxHeight - AppSizes.captureControlsReserve)
                        .clamp(AppSizes.capturePhotoMin, constraints.maxHeight)
                        .toDouble();
                final photoHeight = _photoHeight
                    .clamp(0.0, maxPhotoHeight)
                    .toDouble();
                return Stack(
                  children: [
                    Column(
                      children: [
                        PhotoPane(
                          imagePath: entry.imagePath,
                          height: photoHeight,
                          maxHeight: maxPhotoHeight,
                          onTap: () => _openPhoto(entry),
                          onHeightChanged: (value) =>
                              setState(() => _photoHeight = value),
                          overlays: [
                            Positioned(
                              right: AppSpacing.md,
                              bottom: AppSpacing.md,
                              child: PhotoCopyButton(
                                onPressed: entry.text.isEmpty
                                    ? null
                                    : () => _copyText(entry.text),
                              ),
                            ),
                          ],
                        ),
                        Expanded(child: _buildContent(entry, settings, theme)),
                        CapturePageNavigation(
                          index: index,
                          count: entries.length,
                          onPrevious: () => _navigate(entries, index, -1),
                          onNext: () => _navigate(entries, index, 1),
                          previousTooltip: '上一条语料',
                          nextTooltip: '下一条语料',
                        ),
                      ],
                    ),
                    Positioned(
                      left: AppSpacing.lg,
                      bottom: AppSpacing.md,
                      child: CaptureRoundButton(
                        tooltip: '删除语料',
                        icon: Icons.delete_outline,
                        background: AppColors.error,
                        onPressed: () => _delete(entries, index),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    CorpusEntry entry,
    AppSettings settings,
    ThemeData theme,
  ) {
    final lines = _readyLines(entry);
    if (lines == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text('分词结果', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          ..._buildTokenStatus(entry, theme),
        ],
      );
    }

    // Build token lines lazily. A long corpus can contain thousands of tokens;
    // spreading them into one ListView made the first frame and scrolling janky.
    return ScrollConfiguration(
      behavior: const NoScrollbarBehavior(),
      child: CustomScrollView(
        cacheExtent: 800,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Text('分词结果', style: theme.textTheme.titleMedium),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            sliver: SliverList.builder(
              itemCount: lines.length,
              addAutomaticKeepAlives: false,
              itemBuilder: (context, index) {
                final line = lines[index];
                if (line.tokens.isEmpty) {
                  return SizedBox(
                    height: settings.readerFontSize + AppSpacing.md,
                  );
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
            ),
          ),
        ],
      ),
    );
  }

  List<ReaderLine>? _readyLines(CorpusEntry entry) {
    if (_analysisBusy ||
        _mecabError != null ||
        _analysisError != null ||
        !_unidicConfigured ||
        _tokens.isEmpty ||
        _analysedText != entry.text) {
      return null;
    }
    return buildReaderLines(entry.text, _tokens);
  }

  List<Widget> _buildTokenStatus(CorpusEntry entry, ThemeData theme) {
    if (_analysisBusy) {
      return const [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('正在分词…'),
          ],
        ),
      ];
    }
    final mecabError = _mecabError;
    final errorText = mecabError?.message ?? _analysisError?.toString() ?? '';
    if (errorText.isNotEmpty) {
      return [
        Text(
          '分词不可用：$errorText',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AppTypography.helper,
            height: 1.5,
            color: AppColors.error,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _retryAnalysis(entry),
            icon: const Icon(Icons.refresh),
            label: const Text('重试分词'),
          ),
        ),
      ];
    }
    if (!_unidicConfigured) {
      return [
        Text(
          '尚未配置 UniDic，无法显示分词结果。',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AppTypography.helper,
          ),
        ),
      ];
    }
    return [Text('没有可显示的词。', style: theme.textTheme.bodySmall)];
  }
}
