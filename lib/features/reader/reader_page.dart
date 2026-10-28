import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/mecab/mecab_service.dart';
import '../../services/storage/settings_store.dart';
import '../../state/providers.dart';
import '../lookup/lookup_sheet.dart';
import 'reader_block.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, this.initialText = ''});

  final String initialText;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  late final TextEditingController _textController;
  final ScrollController _scrollController = ScrollController();

  List<Token> _tokens = const [];
  String? _analysedText;
  bool _busy = false;
  MecabException? _mecabError;
  Object? _unexpectedError;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    if (widget.initialText.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制全文')));
  }

  void _showTokenLookup(Token token) {
    showTokenLookupSheet(context, token);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('文本阅读'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '阅读选项',
            icon: const Icon(Icons.tune),
            onSelected: (value) {
              final notifier = ref.read(appSettingsProvider.notifier);
              if (value == 'furigana') {
                notifier.setShowFurigana(!settings.showFurigana);
              } else if (value.startsWith('size:')) {
                notifier.setReaderFontSize(
                  double.parse(value.substring('size:'.length)),
                );
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: 'furigana',
                checked: settings.showFurigana,
                child: const Text('显示注音'),
              ),
              const PopupMenuDivider(),
              for (final size in const [16.0, 20.0, 24.0, 28.0])
                CheckedPopupMenuItem<String>(
                  value: 'size:$size',
                  checked: settings.readerFontSize == size,
                  child: Text('字号 ${size.toInt()}'),
                ),
            ],
          ),
          IconButton(
            onPressed: _copyText,
            tooltip: '复制全文',
            icon: const Icon(Icons.copy_all_outlined),
          ),
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
                  hintText: '输入或粘贴日文，例如：食べた東京',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _analyze,
                    icon: const Icon(Icons.auto_awesome, size: AppSizes.icon),
                    label: const Text('分词'),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  if (_tokens.isNotEmpty && !_busy)
                    Text(
                      '${_tokens.length} 个词',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _copyText,
                    icon: const Icon(
                      Icons.copy_all_outlined,
                      size: AppSizes.iconSmall,
                    ),
                    label: const Text('复制'),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: AppSpacing.xxs),
            const SizedBox(height: AppSpacing.sm),
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
        message: '首次分词会在后台加载 UniDic，可能需要几秒钟。',
      );
    }
    if (_tokens.isEmpty) {
      return const _EmptyState(
        icon: Icons.info_outline,
        title: '没有可显示的词',
        message: '请确认输入内容包含日文字符。',
      );
    }

    final lines = _buildLines(analysedText, _tokens);
    return ListView.builder(
      controller: _scrollController,
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
    );
  }

  static List<_ReaderLine> _buildLines(String text, List<Token> tokens) {
    final lines = <_ReaderLine>[];
    var offset = 0;
    var tokenIndex = 0;
    for (final rawLine in text.split('\n')) {
      final lineEnd = offset + rawLine.length;
      final lineTokens = <Token>[];
      while (tokenIndex < tokens.length && tokens[tokenIndex].start < lineEnd) {
        final token = tokens[tokenIndex];
        if (token.start >= offset) lineTokens.add(token);
        tokenIndex++;
      }
      lines.add(_ReaderLine(tokens: lineTokens));
      offset = lineEnd + 1;
    }
    return lines;
  }
}

class _ReaderLine {
  const _ReaderLine({required this.tokens});

  final List<Token> tokens;
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
