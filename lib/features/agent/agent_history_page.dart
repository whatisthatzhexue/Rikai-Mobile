import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/agent/agent_history.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/rikai_toast.dart';
import '../../core/utils/date_format.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../state/agent_history_recorder.dart';
import '../../state/providers.dart';

// Stable keys keep each AppBar action's element tied to the action itself when
// the selection actions are inserted before the mode toggle.
const _historySelectAllActionKey = ValueKey<String>(
  'agent-history-action-select-all',
);
const _historyDeleteSelectedActionKey = ValueKey<String>(
  'agent-history-action-delete-selected',
);
const _historySelectionModeActionKey = ValueKey<String>(
  'agent-history-action-selection-mode',
);

class AgentHistoryPage extends ConsumerStatefulWidget {
  const AgentHistoryPage({super.key});

  @override
  ConsumerState<AgentHistoryPage> createState() => _AgentHistoryPageState();
}

class _AgentHistoryPageState extends ConsumerState<AgentHistoryPage> {
  late Future<List<AgentHistoryEntry>> _entries;
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _entries = _load();
  }

  Future<List<AgentHistoryEntry>> _load() {
    return ref.read(agentHistoryRepositoryProvider).listHistory();
  }

  void _reload() {
    setState(() {
      _entries = _load();
    });
  }

  AgentUiStrings _strings() {
    final settings = ref.watch(appSettingsProvider);
    return AgentUiStrings.of(
      resolveAgentUiLanguage(
        AgentResponseLanguage.fromWire(settings.agentResponseLanguage),
      ),
    );
  }

  Future<void> _open(AgentHistoryEntry entry) async {
    await context.push(
      '/agent-history/detail/${Uri.encodeComponent(entry.runId)}',
    );
    if (mounted) _reload();
  }

  Future<void> _delete(AgentHistoryEntry entry, AgentUiStrings strings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.historyDeleteTitle),
        content: Text(strings.historyDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(agentHistoryRepositoryProvider)
          .deleteHistoryRun(entry.runId);
    } catch (_) {
      if (mounted) RikaiToast.show(context, strings.historyLoadFailed);
      return;
    }
    if (!mounted) return;
    RikaiToast.show(context, strings.historyDeleted);
    _reload();
  }

  void _toggleSelectionMode() {
    setState(() {
      _selecting = !_selecting;
      if (!_selecting) _selected.clear();
    });
  }

  void _toggleSelected(String runId) {
    setState(() {
      if (!_selected.add(runId)) _selected.remove(runId);
      _selecting = true;
    });
  }

  Future<void> _selectAll() async {
    try {
      final entries = await _entries;
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(entries.map((entry) => entry.runId));
      });
    } catch (_) {
      // The list already shows its load-error state; no extra toast here.
    }
  }

  Future<void> _deleteSelected(AgentUiStrings strings) async {
    final selected = Set<String>.of(_selected);
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.historyDeleteSelectedTitle),
        content: Text(strings.historyDeleteSelectedBody(selected.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(agentHistoryRepositoryProvider)
          .deleteHistoryRuns(selected);
    } catch (_) {
      if (mounted) RikaiToast.show(context, strings.historyLoadFailed);
      return;
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
      _entries = _load();
    });
    RikaiToast.show(context, strings.historyDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings();
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.historyTitle),
        actions: [
          if (_selecting) ...[
            IconButton(
              key: _historySelectAllActionKey,
              tooltip: strings.historySelectAll,
              onPressed: _selectAll,
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              key: _historyDeleteSelectedActionKey,
              tooltip: strings.historyDeleteSelected,
              onPressed: _selected.isEmpty
                  ? null
                  : () => _deleteSelected(strings),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          // Keep the mode toggle as the rightmost action in both states so the
          // selection actions do not replace the tapped button's element.
          IconButton(
            key: _historySelectionModeActionKey,
            tooltip: _selecting
                ? strings.historyExitSelection
                : strings.historySelectMode,
            onPressed: _toggleSelectionMode,
            icon: Icon(_selecting ? Icons.close : Icons.checklist),
          ),
        ],
      ),
      body: FutureBuilder<List<AgentHistoryEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _HistoryMessage(
              icon: Icons.error_outline,
              title: strings.historyLoadFailed,
              actionLabel: strings.retry,
              onAction: _reload,
            );
          }
          final entries = snapshot.data ?? const <AgentHistoryEntry>[];
          if (entries.isEmpty) {
            return _HistoryMessage(
              icon: Icons.history,
              title: strings.historyEmptyTitle,
              body: strings.historyEmptyBody,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: entries.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _HistoryRow(
                entry: entry,
                strings: strings,
                selecting: _selecting,
                selected: _selected.contains(entry.runId),
                onTap: () {
                  if (_selecting) {
                    _toggleSelected(entry.runId);
                  } else {
                    _open(entry);
                  }
                },
                onDelete: () => _delete(entry, strings),
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.strings,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final AgentHistoryEntry entry;
  final AgentUiStrings strings;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = formatCorpusDate(entry.finishedAt ?? entry.startedAt);
    final mode = entry.mode == AgentMode.strict
        ? strings.strictShort
        : strings.looseShort;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AgentTokens.historyRowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: selecting
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (selecting)
                Checkbox(value: selected, onChanged: (_) => onTap()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.isEmpty
                          ? strings.historyUntitled
                          : entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: AgentTokens.historyTitle,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          date,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: AgentTokens.historyMeta,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          mode,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: AgentTokens.historyMeta,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (entry.providerLabel.isNotEmpty)
                          Text(
                            entry.providerLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: AgentTokens.historyMeta,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        _HistoryStatusChip(
                          status: entry.status,
                          strings: strings,
                        ),
                        if (entry.imageCount > 0)
                          Text(
                            strings.historyImageCount(entry.imageCount),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: AgentTokens.historyMeta,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  tooltip: strings.delete,
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: AgentTokens.actionIcon,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryStatusChip extends StatelessWidget {
  const _HistoryStatusChip({required this.status, required this.strings});

  final AgentHistoryStatus status;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AgentHistoryStatus.done => (
        strings.historyStatusDone,
        AgentTokens.historyDone,
      ),
      AgentHistoryStatus.error => (
        strings.historyStatusError,
        AgentTokens.historyError,
      ),
      AgentHistoryStatus.cancelled => (
        strings.historyStatusCancelled,
        AgentTokens.historyCancelled,
      ),
      AgentHistoryStatus.interrupted => (
        strings.historyStatusInterrupted,
        AgentTokens.historyInterrupted,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: AgentTokens.historyStatus,
          color: color,
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
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
              size: AgentTokens.historyEmptyIcon,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: AgentTokens.body,
                color: AppColors.textPrimary,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
