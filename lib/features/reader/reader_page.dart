import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/no_scrollbar_behavior.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/mecab/mecab_service.dart';
import '../../services/storage/settings_store.dart';
import '../../state/providers.dart';
import '../lookup/lookup_sheet.dart';
import 'reader_block.dart';
import 'reader_lines.dart';
import 'reader_options.dart';

/// Arguments used by go_router when another feature opens the reader with new
/// text (for example after OCR).
class ReaderRouteArgs {
  const ReaderRouteArgs(this.text);

  final String text;
}

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({
    super.key,
    this.initialText = '',
    this.replaceDraft = false,
  });

  final String initialText;

  /// When true, [initialText] replaces the app-lifetime draft. OCR results use
  /// this; ordinary navigation keeps the user's previous draft.
  final bool replaceDraft;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late final TextEditingController _textController;
  late final bool _ownsTextController;
  final ScrollController _scrollController = ScrollController();

  List<Token> _tokens = const [];
  String? _analysedText;
  bool _busy = false;
  bool _controlsVisible = true;
  MecabException? _mecabError;
  Object? _unexpectedError;

  bool get _canHideControls =>
      _controlsVisible && _analysedText != null && _tokens.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // OCR text uses a page-local controller so it cannot overwrite the global
    // input draft or a lower ReaderPage in the navigation stack. The normal
    // text-entry route keeps the app-lifetime draft provider.
    _ownsTextController = widget.replaceDraft;
    if (_ownsTextController) {
      _textController = TextEditingController(text: widget.initialText);
    } else {
      _textController = ref.read(readerDraftControllerProvider);
      if (widget.initialText.trim().isNotEmpty &&
          _textController.text.trim().isEmpty) {
        _textController.value = TextEditingValue(
          text: widget.initialText,
          selection: TextSelection.collapsed(offset: widget.initialText.length),
        );
      }
    }
    if (_textController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    if (_ownsTextController) _textController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      setState(() {
        _tokens = const [];
        _analysedText = null;
        _mecabError = null;
        _unexpectedError = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    // A previous failure (missing path/permission) must not be cached when the
    // user retries after fixing it in settings.
    if (_mecabError != null || _unexpectedError != null) {
      ref.invalidate(mecabServiceProvider);
    }
    setState(() {
      _busy = true;
      _mecabError = null;
      _unexpectedError = null;
    });

    try {
      final service = await ref.read(mecabServiceProvider.future);
      final tokens = await service.analyze(text);
      if (!mounted) return;
      setState(() {
        _tokens = tokens;
        _analysedText = text;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } on MecabException catch (error) {
      if (!mounted) return;
      setState(() => _mecabError = error);
    } catch (error) {
      if (!mounted) return;
      setState(() => _unexpectedError = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyText() async {
    final text = _analysedText ?? _textController.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    RikaiToast.show(context, '已复制全文');
  }

  void _showTokenLookup(Token token) {
    // Opening a lookup must not leave the IME attached to the editor. The
    // sheet also clears focus after dismissal so tapping the scrim cannot
    // bounce the keyboard back.
    FocusManager.instance.primaryFocus?.unfocus();
    showTokenLookupSheet(context, token);
  }

  void _hideControls() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _controlsVisible = false);
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      // Keep the whole reading surface white. A grey page background under
      // the input/toolbar made a visible band when long results scrolled.
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('文本阅读'),
        actions: [
          const ReaderOptionsMenu(),
          IconButton(
            onPressed: () => context.push('/settings'),
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_controlsVisible)
              Container(
                key: const Key('reader-controls-surface'),
                decoration: const BoxDecoration(
                  // Keep the toolbar area white to match the reading surface;
                  // only a light hairline separates it from the results, like
                  // the line below the search field on the lookup page.
                  color: AppColors.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.divider,
                      width: AppSizes.borderWidth,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: TextField(
                        controller: _textController,
                        minLines: 2,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: theme.textTheme.bodyLarge,
                        decoration: const InputDecoration(
                          hintText: '例：何卒宜しくお願い致します。',
                          border: OutlineInputBorder(),
                          isDense: true,
                          // No opaque panel inside the field; the white toolbar
                          // stays visible behind it.
                          filled: false,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _canHideControls
                                  ? TextButton(
                                      onPressed: _hideControls,
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.textTertiary,
                                        minimumSize: const Size(
                                          0,
                                          AppSizes.control,
                                        ),
                                        padding: EdgeInsets.zero,
                                        textStyle: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.textTertiary,
                                            ),
                                      ),
                                      child: const Text('隐藏输入框'),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _busy ? null : _analyze,
                            icon: const Icon(
                              Icons.auto_awesome,
                              size: AppSizes.icon,
                            ),
                            label: const Text('分词'),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _copyText,
                                icon: const Icon(
                                  Icons.copy_all_outlined,
                                  size: AppSizes.iconSmall,
                                ),
                                label: const Text('复制'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_busy)
                      const LinearProgressIndicator(minHeight: AppSpacing.xxs),
                  ],
                ),
              ),
            if (!_controlsVisible)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.lg,
                    top: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                  ),
                  child: IconButton(
                    tooltip: '显示输入框',
                    onPressed: _showControls,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    constraints: const BoxConstraints.tightFor(
                      width: AppSizes.control,
                      height: AppSizes.control,
                    ),
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: AppSizes.icon,
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildContent(settings)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppSettings settings) {
    final mecabError = _mecabError;
    if (mecabError != null) {
      return _ErrorCard(
        icon: mecabError.code == MecabErrorCode.notConfigured
            ? Icons.folder_off_outlined
            : Icons.error_outline,
        title: mecabError.code == MecabErrorCode.notConfigured
            ? '尚未配置 UniDic'
            : '无法分词',
        message: mecabError.message,
        onRetry: _analyze,
        onOpenSettings: () => context.push('/settings'),
      );
    }

    final unexpectedError = _unexpectedError;
    if (unexpectedError != null) {
      return _ErrorCard(
        icon: Icons.error_outline,
        title: '分词失败',
        message: unexpectedError.toString(),
        onRetry: _analyze,
        onOpenSettings: () => context.push('/settings'),
      );
    }

    if (_busy && _tokens.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.md),
            Text('正在加载 UniDic 并分词…'),
          ],
        ),
      );
    }

    final analysedText = _analysedText;
    if (analysedText == null) {
      return const _EmptyState(
        icon: Icons.text_fields,
        title: '输入日文后点击「分词」',
        message: '首次分词会在后台加载分词功能，可能需要几秒钟。',
      );
    }
    if (_tokens.isEmpty) {
      return const _EmptyState(
        icon: Icons.info_outline,
        title: '没有可显示的词',
        message: '请确认输入内容包含日文字符。',
      );
    }

    final lines = buildReaderLines(analysedText, _tokens);
    return ScrollConfiguration(
      behavior: const NoScrollbarBehavior(),
      child: ListView.builder(
        controller: _scrollController,
        cacheExtent: 800,
        addAutomaticKeepAlives: false,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xxl,
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
              onTokenTap: _showTokenLookup,
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppSizes.heroIcon,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSizes.heroIcon, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('打开设置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
