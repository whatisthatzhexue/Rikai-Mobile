import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/lexicandy_toast.dart';
import '../../core/utils/rich_text_tags.dart';
import '../../services/agent/agent_result_markdown.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/storage/agent_history_store.dart';
import '../../state/agent_history_recorder.dart';
import '../../state/providers.dart';
import 'agent_actions.dart';
import 'agent_rich_text.dart';
import 'agent_result_view.dart';

class AgentHistoryDetailPage extends ConsumerStatefulWidget {
  const AgentHistoryDetailPage({super.key, required this.runId});

  final String runId;

  @override
  ConsumerState<AgentHistoryDetailPage> createState() =>
      _AgentHistoryDetailPageState();
}

class _AgentHistoryDetailPageState
    extends ConsumerState<AgentHistoryDetailPage> {
  late Future<AgentHistoryDetail?> _detail;
  AgentHistoryDetail? _loadedDetail;

  @override
  void initState() {
    super.initState();
    _detail = _load();
  }

  Future<AgentHistoryDetail?> _load() async {
    final detail = await ref
        .read(agentHistoryRepositoryProvider)
        .loadHistoryDetail(widget.runId);
    if (mounted && !identical(_loadedDetail, detail)) {
      setState(() => _loadedDetail = detail);
    }
    return detail;
  }

  Future<void> _copyResult(
    AgentUiStrings strings,
    AgentHistoryDetail detail,
  ) async {
    final result = detail.result;
    if (result == null) return;
    await Clipboard.setData(
      ClipboardData(text: buildAgentResultMarkdown(result, strings)),
    );
    if (mounted) LexiCandyToast.show(context, strings.copyDone);
  }

  AgentUiStrings _strings() {
    final settings = ref.watch(appSettingsProvider);
    return AgentUiStrings.of(
      resolveAgentUiLanguage(
        AgentResponseLanguage.fromWire(settings.agentResponseLanguage),
      ),
    );
  }

  Future<void> _delete(AgentUiStrings strings) async {
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
          .deleteHistoryRun(widget.runId);
    } catch (_) {
      if (mounted) LexiCandyToast.show(context, strings.historyLoadFailed);
      return;
    }
    if (!mounted) return;
    LexiCandyToast.show(context, strings.historyDeleted);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings();
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.historyTitle),
        actions: [
          if (_loadedDetail?.result != null)
            IconButton(
              tooltip: strings.copyResultMarkdown,
              onPressed: () => _copyResult(strings, _loadedDetail!),
              icon: const Icon(Icons.copy_outlined),
            ),
          IconButton(
            tooltip: strings.delete,
            onPressed: () => _delete(strings),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<AgentHistoryDetail?>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _HistoryDetailMessage(
              icon: Icons.error_outline,
              title: strings.historyLoadFailed,
              actionLabel: strings.retry,
              onAction: () => setState(() {
                _loadedDetail = null;
                _detail = _load();
              }),
            );
          }
          final detail = snapshot.data;
          if (detail == null) {
            return _HistoryDetailMessage(
              icon: Icons.history,
              title: strings.historyEmptyTitle,
              body: strings.historyEmptyBody,
            );
          }
          return _HistoryDetailBody(
            detail: detail,
            strings: strings,
            onCitationTap: (citation) => unawaited(
              openAgentCitation(
                context,
                ref,
                citation,
                fallbackSnippet: citation.snippet,
                uiLanguage: strings.language,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryDetailBody extends StatelessWidget {
  const _HistoryDetailBody({
    required this.detail,
    required this.strings,
    required this.onCitationTap,
  });

  final AgentHistoryDetail detail;
  final AgentUiStrings strings;
  final ValueChanged<AgentCitation> onCitationTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = detail.entry;
    final result = detail.result;
    final summary = result == null
        ? ''
        : stripYomiTags(
            localReadingsToRuby(agentSummarySource(result.analysis)),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            strings.historyReadOnly,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _SectionLabel(text: strings.historyQuestion),
        const SizedBox(height: AppSpacing.xs),
        Text(
          detail.userText.isEmpty ? entry.title : detail.userText,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: AgentTokens.body,
            color: AppColors.textPrimary,
          ),
        ),
        if (entry.imageCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            strings.historyImageCount(entry.imageCount),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        if (entry.errorCode.isNotEmpty && result == null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            strings.historyErrorMessageFor(entry.errorCode),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.error,
            ),
          ),
        ],
        if (detail.unsupportedFormat) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            strings.historyUnsupportedFormat,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        ],
        if (result == null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            strings.historyNoResult,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
        ] else ...[
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(text: strings.historyAssistantResult),
          const SizedBox(height: AppSpacing.xs),
          AgentRichText(
            text: summary,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: AgentTokens.body,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AgentResultView(
            result: result,
            onCitationTap: onCitationTap,
            strings: strings,
          ),
          _HistoryVariants(result: result, strings: strings),
        ],
      ],
    );
  }
}

class _HistoryVariants extends StatelessWidget {
  const _HistoryVariants({required this.result, required this.strings});

  final AgentRunResult result;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final imageSources = result.input.sources
        .where((source) => source.isImage)
        .toList(growable: false);
    if (imageSources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(text: strings.historyVariantsTitle),
        for (var index = 0; index < imageSources.length; index++)
          _HistorySourceVariants(
            source: imageSources[index],
            index: index,
            strings: strings,
          ),
      ],
    );
  }
}

class _HistorySourceVariants extends StatelessWidget {
  const _HistorySourceVariants({
    required this.source,
    required this.index,
    required this.strings,
  });

  final AgentSourceInput source;
  final int index;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${strings.historyVariantsTitle} ${index + 1}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textSecondary,
            ),
          ),
          for (final variant in source.variants)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Text(
                        '${variant.engine}/${variant.mode.name}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: AgentTokens.historyStatus,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (source.selectedVariant?.id == variant.id)
                        Text(
                          strings.historySelectedVariant,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: AgentTokens.historyStatus,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    variant.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: AgentTokens.evidenceTitle,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _HistoryDetailMessage extends StatelessWidget {
  const _HistoryDetailMessage({
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
