import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_models.dart';
import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/providers.dart';
import '../settings/dictionary_page.dart';
import 'entry_page.dart';
import 'lookup_result_list.dart';

/// Opens the token lookup sheet from the reader.
Future<void> showTokenLookupSheet(BuildContext context, Token token) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => LookupSheet(token: token),
  );
}

class LookupSheet extends ConsumerStatefulWidget {
  const LookupSheet({super.key, required this.token});

  final Token token;

  @override
  ConsumerState<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends ConsumerState<LookupSheet> {
  late List<DictionaryInfo> _enabled;
  late Set<String> _selectedIds;
  late String _query;

  LookupResult? _result;
  Object? _error;
  bool _busy = false;

  Token get _token => widget.token;

  @override
  void initState() {
    super.initState();
    _query = _token.surface;
    _enabled = ref.read(enabledDictionariesProvider);
    _selectedIds = _enabled.map((dictionary) => dictionary.id).toSet();
    if (_enabled.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _load(_token.lookupCandidates);
      });
    }
  }

  Future<void> _load(List<String> rawCandidates) async {
    final dictionaries = _enabled
        .where((dictionary) => _selectedIds.contains(dictionary.id))
        .toList(growable: false);
    if (dictionaries.isEmpty) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _error = null;
        _busy = false;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = await ref.read(mdictServiceProvider.future);
      final result = await service.lookup(
        query: _query,
        rawCandidates: rawCandidates,
        dictionaries: dictionaries,
        maxEntriesPerDictionary: ref
            .read(appSettingsProvider)
            .maxEntriesPerDictionary,
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
    setState(() {
      if (!_selectedIds.add(dictionary.id)) {
        _selectedIds.remove(dictionary.id);
      }
    });
    _load(_token.lookupCandidates);
  }

  void _searchSuggestion(String suggestion) {
    setState(() => _query = suggestion);
    _load([suggestion]);
  }

  void _openEntry(DictionaryLookupGroup group, LookupEntry entry) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => EntryPage(
          word: _query,
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
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => EntryPage(
          word: _query,
          groups: [group],
          initialDictionaryId: group.dictionary.id,
        ),
      ),
    );
  }

  void _openDictionaryManagement() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(builder: (context) => const DictionaryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.8;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _token.surface,
                        style: theme.textTheme.headlineSmall,
                      ),
                      if (_token.reading.isNotEmpty)
                        Text(
                          _token.reading,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _token.posLabel.isEmpty ? '词性未知' : _token.posLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (_enabled.length > 1)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: _enabled.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final dictionary = _enabled[index];
                  return FilterChip(
                    label: Text(dictionary.title),
                    selected: _selectedIds.contains(dictionary.id),
                    onSelected: (_) => _toggleDictionary(dictionary),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildContent(theme)),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_enabled.isEmpty) {
      return _EmptyState(
        icon: Icons.library_books_outlined,
        title: '尚未添加 MDict 词典',
        message: '添加 .mdx 词典后即可点击词语查询。词典按原路径读取，不复制文件。',
        actionLabel: '管理词典',
        onAction: _openDictionaryManagement,
      );
    }
    if (_selectedIds.isEmpty) {
      return _EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '请选择至少一本词典',
        message: '使用上方的词典标签选择本次查询使用的词典。',
        actionLabel: '全选',
        onAction: () {
          setState(() {
            _selectedIds = _enabled.map((dictionary) => dictionary.id).toSet();
          });
          _load(_token.lookupCandidates);
        },
      );
    }

    final error = _error;
    if (error != null) {
      return _ErrorState(
        message: _errorText(error),
        onRetry: () => _load(_token.lookupCandidates),
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
      return const Center(child: CircularProgressIndicator());
    }

    if (result.hasHits) {
      return LookupHitList(
        groups: result.hitGroups,
        onOpenEntry: _openEntry,
        onOpenAll: _openAll,
      );
    }

    return _NoHitList(
      query: _query,
      result: result,
      token: _token,
      onSuggestion: _searchSuggestion,
      onRetry: () => _load(_token.lookupCandidates),
    );
  }
}

class _NoHitList extends StatelessWidget {
  const _NoHitList({
    required this.query,
    required this.result,
    required this.token,
    required this.onSuggestion,
    required this.onRetry,
  });

  final String query;
  final LookupResult result;
  final Token token;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestionGroups = result.groups
        .where((group) => group.suggestions.isNotEmpty)
        .toList(growable: false);
    final candidateGroups = token.lookupCandidates
        .where((candidate) => candidate != query)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Text('未找到「$query」', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text('可以尝试词元、假名变体，或先添加更多词典。', style: theme.textTheme.bodySmall),
        if (candidateGroups.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('换用词形查询', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final candidate in candidateGroups.take(8))
                ActionChip(
                  label: Text(candidate),
                  onPressed: () => onSuggestion(candidate),
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
                    onPressed: () => onSuggestion(suggestion),
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
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: AppSizes.icon),
          label: const Text('重新查询'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

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
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
