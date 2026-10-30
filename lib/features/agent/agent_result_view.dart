import 'package:flutter/material.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart'
    show DictionaryProfileIssue;
import 'agent_fade_in.dart';

class AgentResultView extends StatelessWidget {
  const AgentResultView({
    super.key,
    required this.result,
    required this.onCitationTap,
    this.onRetryProfile,
  });

  final AgentRunResult result;
  final ValueChanged<AgentCitation> onCitationTap;
  final ValueChanged<DictionaryProfileIssue>? onRetryProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usedIds = result.validation.citationsUsed.toSet();
    final visibleCitations = usedIds.isEmpty
        ? result.citations
        : result.citations
              .where((citation) => usedIds.contains(citation.id))
              .toList(growable: false);
    final citations = <String, AgentCitation>{
      for (final citation in visibleCitations) citation.id: citation,
    };
    final citationNumbers = <String, int>{
      for (var index = 0; index < visibleCitations.length; index++)
        visibleCitations[index].id: index + 1,
    };
    final quotes = <String, AgentQuoteRef>{
      for (final quote in result.quotes) quote.id: quote,
    };
    final grouped = <int, List<AgentCitation>>{};
    for (final citation in visibleCitations) {
      grouped
          .putIfAbsent(citation.dictionaryOrder, () => <AgentCitation>[])
          .add(citation);
    }
    final orders = grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.evidence.truncated)
          Text(
            '部分内容超出预算，未全部分析',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        if (result.evidence.structureUnavailable)
          Text(
            '结构分析不可用（未配置 UniDic）；本次只提供译文和词典依据',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        if (result.evidence.dictionaryIssues.isNotEmpty)
          Text(
            '词典查询失败：'
            '${result.evidence.dictionaryIssues.map((issue) => issue.dictionaryTitle).join('、')}'
            '，结果可能不完整',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        if (!result.validation.valid)
          Text(
            '部分内容未通过校验，已移除无依据/无效引用的部分',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        if (result.profileWarnings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final warning in result.profileWarnings)
            Text(
              '词典档案未使用：$warning',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.warning,
              ),
            ),
        ],
        if (result.unavailableProfiles.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final issue in result.unavailableProfiles)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '${issue.title}：无档案（${issue.reason}），已按通用规则检索',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.warning,
                    ),
                  ),
                ),
                if (onRetryProfile != null)
                  TextButton(
                    onPressed: () => onRetryProfile!(issue),
                    child: const Text('重试此词典'),
                  ),
              ],
            ),
        ],
        if (result.quotes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionTitle('原文'),
          for (final quote in result.quotes)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                quote.text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: AgentTokens.body,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
        if (result.analysis.segments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionTitle('逐句理解'),
          for (final (index, segment) in result.analysis.segments.indexed)
            AgentFadeIn(
              index: index,
              child: _SegmentBlock(
                segment: segment,
                quote: quotes[segment.quoteId],
                citations: citations,
                citationNumbers: citationNumbers,
                onCitationTap: onCitationTap,
              ),
            ),
        ],
        if (result.analysis.interpretations.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionTitle('可能的理解'),
          for (final interpretation in result.analysis.interpretations)
            _InterpretationBlock(
              interpretation: interpretation,
              citations: citations,
              citationNumbers: citationNumbers,
              onCitationTap: onCitationTap,
            ),
        ],
        if (result.analysis.unresolved.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionTitle('未解决'),
          for (final unresolved in result.analysis.unresolved)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${unresolved.reason}（${unresolved.quoteId}）',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
        if (result.analysis.modelSupplements.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionTitle('模型补充'),
          for (final supplement in result.analysis.modelSupplements)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AgentTokens.supplementSurface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                supplement.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
        if (orders.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionTitle('词典依据'),
          for (final (index, order) in orders.indexed)
            AgentFadeIn(
              index: index,
              child: _EvidenceGroup(
                citations: grouped[order]!,
                citationNumbers: citationNumbers,
                onCitationTap: onCitationTap,
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: AgentTokens.section,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SegmentBlock extends StatelessWidget {
  const _SegmentBlock({
    required this.segment,
    required this.quote,
    required this.citations,
    required this.citationNumbers,
    required this.onCitationTap,
  });

  final AgentSegment segment;
  final AgentQuoteRef? quote;
  final Map<String, AgentCitation> citations;
  final Map<String, int> citationNumbers;
  final ValueChanged<AgentCitation> onCitationTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segmentCitationIds = <String>{
      for (final note in segment.wordNotes) ...note.citationIds,
      for (final note in segment.grammarNotes) ...note.citationIds,
    }.where(citations.containsKey).toList(growable: false)
      ..sort(
        (a, b) => (citationNumbers[a] ?? 0).compareTo(citationNumbers[b] ?? 0),
      );
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AgentTokens.cardPadding),
      decoration: BoxDecoration(
        color: AgentTokens.evidenceSurface,
        border: Border.all(color: AgentTokens.evidenceBorder),
        borderRadius: BorderRadius.circular(AgentTokens.evidenceRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quote != null)
            Text(
              quote!.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            segment.interpretation,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: AgentTokens.body,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ClaimBadge(
            epistemic: segment.epistemic,
            confidence: segment.confidence,
          ),
          for (final note in segment.wordNotes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '${note.surface}${note.reading.isEmpty ? '' : '（${note.reading}）'}：${note.sense}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          for (final note in segment.grammarNotes)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                note.explanation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          if (segmentCitationIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  for (final id in segmentCitationIds)
                    _CitationChip(
                      citation: citations[id]!,
                      number: citationNumbers[id]!,
                      onTap: onCitationTap,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ClaimBadge extends StatelessWidget {
  const _ClaimBadge({required this.epistemic, required this.confidence});

  final AgentEpistemic epistemic;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (epistemic) {
      AgentEpistemic.dictionaryFact => (
        '词典事实',
        AppColors.blue50,
        AppColors.blue700,
      ),
      AgentEpistemic.structuralAnalysis => (
        '结构分析',
        AppColors.surfaceMuted,
        AppColors.textPrimary,
      ),
      AgentEpistemic.contextInference => (
        '语境推断',
        AppColors.surfaceMuted,
        AppColors.warning,
      ),
      AgentEpistemic.translation => (
        '模型译文',
        AppColors.surfaceMuted,
        AppColors.textSecondary,
      ),
    };
    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.badge,
              color: foreground,
            ),
          ),
        ),
        Text(
          '置信度 ${(confidence.clamp(0, 1) * 100).round()}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.badge,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _InterpretationBlock extends StatelessWidget {
  const _InterpretationBlock({
    required this.interpretation,
    required this.citations,
    required this.citationNumbers,
    required this.onCitationTap,
  });

  final AgentInterpretation interpretation;
  final Map<String, AgentCitation> citations;
  final Map<String, int> citationNumbers;
  final ValueChanged<AgentCitation> onCitationTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${interpretation.label}：${interpretation.meaning}'
            '（${(interpretation.confidence * 100).round()}%）',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textPrimary,
            ),
          ),
          for (final id in interpretation.citationIds)
            if (citations[id] != null)
              _CitationChip(
                citation: citations[id]!,
                number: citationNumbers[id]!,
                onTap: onCitationTap,
              ),
        ],
      ),
    );
  }
}

class _EvidenceGroup extends StatelessWidget {
  const _EvidenceGroup({
    required this.citations,
    required this.citationNumbers,
    required this.onCitationTap,
  });

  final List<AgentCitation> citations;
  final Map<String, int> citationNumbers;
  final ValueChanged<AgentCitation> onCitationTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dictionary = citations.first;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AgentTokens.evidenceSurface,
        border: Border.all(color: AgentTokens.evidenceBorder),
        borderRadius: BorderRadius.circular(AgentTokens.evidenceRadius),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          title: Text(
            '${dictionary.dictionaryTitle} · ${citations.length} 条',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.evidenceTitle,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            for (final citation in citations)
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => onCitationTap(citation),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              citation.entryKey,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: AgentTokens.evidenceTitle,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '依据${citationNumbers[citation.id] ?? ''} · 查看',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: AgentTokens.citationChip,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        citation.snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: AgentTokens.helper,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({
    required this.citation,
    required this.number,
    required this.onTap,
  });

  final AgentCitation citation;
  final int number;
  final ValueChanged<AgentCitation> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '查看依据$number ${citation.headword}',
      child: GestureDetector(
        onTap: () => onTap(citation),
        child: Container(
          height: AgentTokens.citationChipHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AgentTokens.citationSurface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          alignment: Alignment.center,
          child: Text(
            '依据$number',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.citationChip,
              color: AgentTokens.citationText,
            ),
          ),
        ),
      ),
    );
  }
}
