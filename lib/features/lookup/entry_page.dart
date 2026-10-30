import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/lookup_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/mdict/entry_renderer.dart';
import '../../state/providers.dart';
import 'entry_web_view.dart';
import 'lookup_actions.dart';

/// Dictionary entry page with one tab per hit dictionary.
class EntryPage extends ConsumerStatefulWidget {
  const EntryPage({
    super.key,
    required this.word,
    required this.groups,
    this.initialDictionaryId,
  });

  final String word;
  final List<DictionaryLookupGroup> groups;
  final String? initialDictionaryId;

  @override
  ConsumerState<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends ConsumerState<EntryPage>
    with SingleTickerProviderStateMixin {
  late final List<DictionaryLookupGroup> _groups;
  late final TabController _tabController;
  final Map<String, Future<RenderedEntry>> _renders = {};
  Animation<double>? _routeAnimation;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _groups = widget.groups
        .where((group) => group.hasHits)
        .toList(growable: false);

    final initialIndex = _groups.indexWhere(
      (group) => group.dictionary.id == widget.initialDictionaryId,
    );
    _tabController = TabController(
      length: _groups.isEmpty ? 1 : _groups.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    );

    for (final group in _groups) {
      _renders[group.dictionary.id] = _render(group);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeListener(_onRouteAnimation);
    _routeAnimation = animation;
    _routeAnimation?.addListener(_onRouteAnimation);
  }

  void _onRouteAnimation() {
    final status = _routeAnimation?.status;
    if (!mounted || status == null) return;
    if (status == AnimationStatus.reverse && !_leaving) {
      // Remove the platform WebView before the pop animation paints another
      // frame. Otherwise Android can briefly show the just-dismissed HTML.
      setState(() => _leaving = true);
    } else if (status == AnimationStatus.completed && _leaving) {
      setState(() => _leaving = false);
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeListener(_onRouteAnimation);
    _tabController.dispose();
    super.dispose();
  }

  Future<RenderedEntry> _render(DictionaryLookupGroup group) async {
    final cache = ref.read(entryRenderCacheProvider);
    final cacheKey = _renderCacheKey(group);
    final cached = cache.get(cacheKey);
    if (cached != null) return cached;

    final service = await ref.read(mdictServiceProvider.future);
    final cacheRoot = await getApplicationCacheDirectory();
    final renderer = EntryRenderer(
      cacheDirectory: Directory('${cacheRoot.path}/mdict'),
      resourceLoader: (key) =>
          service.readResource(dictionary: group.dictionary, key: key),
    );
    final rendered = await renderer.render(
      dictionary: group.dictionary,
      entries: group.entries,
    );
    cache.put(cacheKey, rendered);
    return rendered;
  }

  static String _renderCacheKey(DictionaryLookupGroup group) {
    final payload = group.entries
        .map(
          (entry) =>
              '${entry.matchedKey}\u0000${entry.headword}\u0000${entry.html}',
        )
        .join('\u0001');
    final digest = sha1.convert(utf8.encode(payload)).toString();
    return '${group.dictionary.id}:$digest';
  }

  void _retry(DictionaryLookupGroup group) {
    ref.invalidate(mdictServiceProvider);
    setState(() {
      _renders[group.dictionary.id] = _render(group);
    });
  }

  void _blockedExternalLink(String url) {
    if (!mounted) return;
    RikaiToast.show(context, '离线模式：已阻止外部链接');
  }

  void _openEntryLink(String word) {
    if (!mounted || word == widget.word) return;
    lookupAndOpenEntry(context, ref, word);
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.word)),
        body: const Center(child: Text('没有可显示的词条')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(widget.word, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: _groups.length > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final group in _groups)
                    Tab(text: group.dictionary.title),
                ],
              )
            : null,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [for (final group in _groups) _buildEntryTab(group)],
      ),
    );
  }

  Widget _buildEntryTab(DictionaryLookupGroup group) {
    if (_leaving) {
      return const ColoredBox(color: AppColors.surface);
    }
    final future = _renders[group.dictionary.id]!;
    return FutureBuilder<RenderedEntry>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _EntryError(
            message: snapshot.error.toString(),
            onRetry: () => _retry(group),
          );
        }
        final rendered = snapshot.data;
        if (rendered == null) {
          return const Center(child: Text('词条为空'));
        }
        return EntryWebView(
          html: rendered.html,
          baseUrl: rendered.baseUrl,
          onEntryLink: _openEntryLink,
          onExternalLink: _blockedExternalLink,
        );
      },
    );
  }
}

class _EntryError extends StatelessWidget {
  const _EntryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: AppSizes.emptyIcon,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('词条渲染失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: AppSizes.icon),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
