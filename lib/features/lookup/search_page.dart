import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/text_normalizer.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/providers.dart';
import 'entry_page.dart';
import 'lookup_actions.dart';
import 'lookup_result_list.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();

  LookupResult? _result;
  Object? _error;
  bool _busy = false;
  Set<String>? _selectedIds;
  String _lastQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<DictionaryInfo> _selectedFor(List<DictionaryInfo> enabled) {
    final selected = _selectedIds;
    if (selected == null) return enabled;
    return enabled
        .where((dictionary) => selected.contains(dictionary.id))
        .toList(growable: false);
  }

  Future<void> _search([String? queryOverride]) async {
    final query = (queryOverride ?? _controller.text).trim();
    if (query.isEmpty) return;
    if (queryOverride != null) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    final dictionaries = _selectedFor(ref.read(enabledDictionariesProvider));
    if (dictionaries.isEmpty) {
      setState(() {
        _result = null;
        _error = const MdictException(
          MdictErrorCode.lookupFailed,
          '请先选择至少一本可用的 MDict 词典',
        );
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _lastQuery = query;
    });

    try {
      final result = await performLookup(
        ref,
        query,
        rawCandidates: [query],
        dictionaries: dictionaries,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleDictionary(DictionaryInfo dictionary) {
    final enabled = ref.read(enabledDictionariesProvider);
    final current = _selectedIds ?? enabled.map((entry) => entry.id).toSet();
    final next = {...current};
    if (!next.add(dictionary.id)) next.remove(dictionary.id);
    setState(() => _selectedIds = next);
    if (_lastQuery.isNotEmpty) _search(_lastQuery);
  }

  void _openEntry(DictionaryLookupGroup group, LookupEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EntryPage(
          word: _lastQuery,
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EntryPage(
          word: _lastQuery,
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
    final selected = _selectedFor(enabled);
    final selectedIds = selected.map((dictionary) => dictionary.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('查词'),
        actions: [
          IconButton(
            tooltip: '词典管理',
            onPressed: () => context.push('/dictionaries'),
            icon: const Icon(Icons.library_books_outlined),
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
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: '搜索……',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: '查询',
                          onPressed: _search,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                ),
              ),
            ),
            if (enabled.length > 1)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: enabled.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final dictionary = enabled[index];
                    return FilterChip(
                      label: Text(dictionary.title),
                      selected: selectedIds.contains(dictionary.id),
                      onSelected: (_) => _toggleDictionary(dictionary),
                    );
                  },
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            const Divider(height: 1),
            Expanded(child: _buildBody(theme, enabled, selected)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    List<DictionaryInfo> enabled,
    List<DictionaryInfo> selected,
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
        onAction: () {
          setState(() {
            _selectedIds = enabled.map((dictionary) => dictionary.id).toSet();
          });
          if (_lastQuery.isNotEmpty) _search(_lastQuery);
        },
      );
    }

    final error = _error;
    if (error != null) {
      return _SearchError(
        message: _errorText(error),
        onRetry: () => _search(_lastQuery.isEmpty ? null : _lastQuery),
      );
    }
    if (_busy && _result == null) {
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

    final result = _result;
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

    final variants = lookupCandidatesFor([_lastQuery])
        .where((candidate) => candidate != _lastQuery)
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
        Text('未找到「$_lastQuery」', style: theme.textTheme.titleMedium),
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
          onPressed: () => _search(_lastQuery.isEmpty ? null : _lastQuery),
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
