import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_models.dart';
import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/page_route.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/lookup_preferences.dart';
import '../../state/providers.dart';
import '../settings/dictionary_page.dart';
import 'dictionary_filter_bar.dart';
import 'entry_page.dart';
import 'lookup_result_list.dart';

/// Opens the token lookup sheet from the reader.
Future<void> showTokenLookupSheet(BuildContext context, Token token) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        FocusScope(autofocus: true, child: LookupSheet(token: token)),
  ).whenComplete(() {
    // Dismissing via drag or scrim must not restore focus to the editor.
    FocusManager.instance.primaryFocus?.unfocus();
  });
}

class LookupSheet extends ConsumerStatefulWidget {
  const LookupSheet({super.key, required this.token});

  final Token token;

  @override
  ConsumerState<LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends ConsumerState<LookupSheet> {
  late String _query;

  LookupResult? _result;
  Object? _error;
  bool _busy = false;

  Token get _token => widget.token;

  @override
  void initState() {
    super.initState();
    _query = _token.surface;
    if (ref.read(enabledDictionariesProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _load(_token.lookupCandidates);
      });
    }
  }

  Future<void> _load(List<String> rawCandidates) async {
    final enabled = ref.read(enabledDictionariesProvider);
    final dictionaries = ref
        .read(lookupPreferencesProvider)
        .selectedDictionaries(enabled);
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

  void _toggleDictionary(String id, List<DictionaryInfo> enabled) {
    ref.read(lookupPreferencesProvider.notifier).toggle(id, enabled);
    _load(_token.lookupCandidates);
  }

  void _selectAllDictionaries(List<DictionaryInfo> enabled) {
    ref.read(lookupPreferencesProvider.notifier).selectAll();
    _load(_token.lookupCandidates);
  }

  void _searchSuggestion(String suggestion) {
    setState(() => _query = suggestion);
    _load([suggestion]);
  }

  void _openEntry(DictionaryLookupGroup group, LookupEntry entry) {
    // Keep the lookup sheet below the entry page. Closing it here made users
    // lose the result list and forced another word lookup after returning.
    Navigator.of(context).push(
      RikaiPageRoute<void>(
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
    Navigator.of(context).push(
      RikaiPageRoute<void>(
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
      RikaiPageRoute<void>(builder: (context) => const DictionaryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.8;
    final enabled = ref.watch(enabledDictionariesProvider);
    final preferences = ref.watch(lookupPreferencesProvider);
    final selected = preferences.selectedDictionaries(enabled);
    final selectedIds = selected.map((dictionary) => dictionary.id).toSet();

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _token.surface,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: DictionarySelectionModeToggle(
                        mode: preferences.mode,
                        onChanged: (mode) => ref
                            .read(lookupPreferencesProvider.notifier)
                            .setMode(mode),
                      ),
                    ),
                  ],
                ),
                // Do not repeat the reading when it is identical to the
                // surface (e.g. ありがとう). Only distinct readings are shown
                // in the blue reading line.
                if (_token.hasDistinctReading)
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
                onToggle: (id) => _toggleDictionary(id, enabled),
                onSelectAll: () => _selectAllDictionaries(enabled),
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildContent(theme, enabled, selected)),
        ],
      ),
    );
  }

  Widget _buildContent(
    ThemeData theme,
    List<DictionaryInfo> enabled,
    List<DictionaryInfo> selected,
  ) {
    if (enabled.isEmpty) {
      return _EmptyState(
        icon: Icons.library_books_outlined,
        title: '尚未添加 MDict 词典',
        message: '添加 .mdx 词典后即可点击词语查询。词典按原路径读取，不复制文件。',
        actionLabel: '管理词典',
        onAction: _openDictionaryManagement,
      );
    }
    if (selected.isEmpty) {
      return _EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '请选择至少一本词典',
        message: '使用上方的词典标签选择本次查询使用的词典。',
        actionLabel: '全选',
        onAction: () => _selectAllDictionaries(enabled),
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
