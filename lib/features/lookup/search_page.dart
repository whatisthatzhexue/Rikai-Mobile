import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_match_mode.dart';
import '../../core/models/lookup_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/page_route.dart';
import '../../core/utils/text_normalizer.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/lookup_preferences.dart';
import '../../state/lookup_search.dart';
import '../../state/providers.dart';
import 'dictionary_filter_bar.dart';
import 'entry_page.dart';
import 'lookup_mode_menu.dart';
import 'lookup_result_list.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // App-lifetime controllers/providers keep the query and results when the
    // user briefly leaves the page.
    _controller = ref.read(lookupQueryControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshAfterExternalSelectionChange();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    if (ref.read(appSettingsProvider).lookupMatchMode !=
        LookupMatchMode.incremental) {
      return;
    }
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) return;
    // Incremental mode searches while typing; the short delay keeps the
    // MDict worker from being flooded on every keystroke.
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _search(null, false);
    });
  }

  Future<void> _refreshAfterExternalSelectionChange() async {
    final search = ref.read(lookupSearchProvider);
    if (search.lastQuery.isEmpty) return;
    final enabled = ref.read(enabledDictionariesProvider);
    final preferences = ref.read(lookupPreferencesProvider);
    final selected = preferences.selectedDictionaries(enabled);
    final signature = selected.map((dictionary) => dictionary.id).toList()
      ..sort();
    final mode = ref.read(appSettingsProvider).lookupMatchMode;
    if (signature.join(',') != search.selectionSignature ||
        mode != search.matchMode) {
      await ref.read(lookupSearchProvider.notifier).search(search.lastQuery);
    }
  }

  Future<void> _search([
    String? queryOverride,
    bool dismissKeyboard = true,
  ]) async {
    _searchDebounce?.cancel();
    final query = (queryOverride ?? _controller.text).trim();
    if (query.isEmpty) return;
    if (queryOverride != null && queryOverride != _controller.text) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    if (dismissKeyboard) FocusScope.of(context).unfocus();
    await ref.read(lookupSearchProvider.notifier).search(query);
  }

  void _openEntry(DictionaryLookupGroup group, LookupEntry entry) {
    FocusScope.of(context).unfocus();
    final word = ref.read(lookupSearchProvider).lastQuery;
    Navigator.of(context).push(
      RikaiPageRoute<void>(
        builder: (context) => EntryPage(
          word: word,
          groups: [
            DictionaryLookupGroup(
              dictionary: group.dictionary,
              entries: [entry],
            ),
          ],
          initialDictionaryId: group.dictionary.id,
        ),
      ),
    );
  }

  void _openAll(DictionaryLookupGroup group) {
    FocusScope.of(context).unfocus();
    final word = ref.read(lookupSearchProvider).lastQuery;
    Navigator.of(context).push(
      RikaiPageRoute<void>(
        builder: (context) => EntryPage(
          word: word,
          groups: [group],
          initialDictionaryId: group.dictionary.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = ref.watch(enabledDictionariesProvider);
    final preferences = ref.watch(lookupPreferencesProvider);
    final search = ref.watch(lookupSearchProvider);
    final selected = preferences.selectedDictionaries(enabled);
    final selectedIds = selected.map((dictionary) => dictionary.id).toSet();

    // A filter changed from the reader sheet (or anywhere else) should refresh
    // the existing result instead of leaving stale hits on screen.
    ref.listen<LookupPreferences>(lookupPreferencesProvider, (previous, next) {
      if (previous?.signature == next.signature) return;
      final query = ref.read(lookupSearchProvider).lastQuery;
      if (query.isNotEmpty) {
        unawaited(ref.read(lookupSearchProvider.notifier).search(query));
      }
    });
    ref.listen(appSettingsProvider.select((s) => s.lookupMatchMode), (
      previous,
      next,
    ) {
      if (previous == next) return;
      _searchDebounce?.cancel();
      final query = ref.read(lookupSearchProvider).lastQuery;
      if (query.isNotEmpty) {
        unawaited(ref.read(lookupSearchProvider.notifier).search(query));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('查词'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: DictionarySelectionModeToggle(
              mode: preferences.mode,
              onDark: true,
              onChanged: (mode) =>
                  ref.read(lookupPreferencesProvider.notifier).setMode(mode),
            ),
          ),
          IconButton(
            tooltip: '词典管理',
            onPressed: () {
              FocusScope.of(context).unfocus();
              context.push('/dictionaries');
            },
            icon: const Icon(Icons.library_books_outlined),
          ),
          const LookupModeMenu(),
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
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _search(),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  hintText: '搜索……',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: search.busy ? null : '查询',
                    onPressed: search.busy ? null : _search,
                    icon: search.busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
            ),
            if (enabled.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: DictionaryFilterBar(
                  dictionaries: enabled,
                  selectedIds: selectedIds,
                  mode: preferences.mode,
                  onToggle: (id) => ref
                      .read(lookupPreferencesProvider.notifier)
                      .toggle(id, enabled),
                  onSelectAll: () =>
                      ref.read(lookupPreferencesProvider.notifier).selectAll(),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            const Divider(height: 1),
            Expanded(child: _buildBody(theme, enabled, selected, search)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    List<DictionaryInfo> enabled,
    List<DictionaryInfo> selected,
    LookupSearchState search,
  ) {
    if (enabled.isEmpty) {
      return _SearchEmpty(
        icon: Icons.library_books_outlined,
        title: '尚未添加 MDict 词典',
        message: '添加 .mdx 词典后即可搜索词条。词典按原路径读取，不复制文件。',
        actionLabel: '管理词典',
        onAction: () => context.push('/dictionaries'),
      );
    }
    if (selected.isEmpty) {
      return _SearchEmpty(
        icon: Icons.filter_alt_off_outlined,
        title: '请选择至少一本词典',
        message: '使用上方的词典标签选择本次查询使用的词典。',
        actionLabel: '全选',
        onAction: () =>
            ref.read(lookupPreferencesProvider.notifier).selectAll(),
      );
    }

    final error = search.error;
    if (error != null) {
      return _SearchError(
        message: _errorText(error),
        onRetry: () =>
            _search(search.lastQuery.isEmpty ? null : search.lastQuery),
      );
    }
    if (search.busy && search.result == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.md),
            Text('正在查询…'),
          ],
        ),
      );
    }

    final result = search.result;
    if (result == null) {
      return const _SearchEmpty(
        icon: Icons.search,
        title: '输入词条开始查询',
        message: '支持汉字、假名、全半角与活用形；结果会按词典分组显示。',
      );
    }

    if (result.hasHits) {
      return LookupHitList(
        groups: result.hitGroups,
        onOpenEntry: _openEntry,
        onOpenAll: _openAll,
      );
    }

    final lastQuery = search.lastQuery;
    final variants = lookupCandidatesFor([lastQuery])
        .where((candidate) => candidate != lastQuery)
        .take(8)
        .toList(growable: false);
    final suggestionGroups = result.groups
        .where((group) => group.suggestions.isNotEmpty)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Text('未找到「$lastQuery」', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text('可以尝试假名变体或以下词典建议。', style: theme.textTheme.bodySmall),
        if (variants.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('假名变体', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final variant in variants)
                ActionChip(
                  label: Text(variant),
                  onPressed: () => _search(variant),
                ),
            ],
          ),
        ],
        if (suggestionGroups.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('词典建议', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final group in suggestionGroups) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                group.dictionary.title,
                style: theme.textTheme.labelMedium,
              ),
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final suggestion in group.suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => _search(suggestion),
                  ),
              ],
            ),
          ],
        ],
        if (result.groups.any((group) => group.error.isNotEmpty)) ...[
          const SizedBox(height: AppSpacing.lg),
          for (final group in result.groups)
            if (group.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${group.dictionary.title}：${group.error}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
        ],
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(
          onPressed: () => _search(lastQuery.isEmpty ? null : lastQuery),
          icon: const Icon(Icons.refresh, size: AppSizes.icon),
          label: const Text('重新查询'),
        ),
      ],
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: AppSizes.emptyIcon,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: AppSizes.emptyIcon,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('查询失败', style: theme.textTheme.titleMedium),
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

String _errorText(Object error) {
  if (error is MdictException) return error.message;
  return error.toString();
}
