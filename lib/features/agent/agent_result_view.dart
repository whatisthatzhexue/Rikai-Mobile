import 'package:flutter/material.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/rich_text_tags.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart'
    show DictionaryProfileIssue;
import 'agent_fade_in.dart';

class AgentResultView extends StatelessWidget {
  const AgentResultView({
    super.key,
    required this.result,
    required this.onCitationTap,
    required this.strings,
    this.onRetryProfile,
  });

  final AgentRunResult result;
  final ValueChanged<AgentCitation> onCitationTap;
  final AgentUiStrings strings;
  final Future<void> Function(DictionaryProfileIssue)? onRetryProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCitations = result.adoptedCitations;
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

    final blocks = <Widget>[];
    if (result.evidence.truncated) {
      blocks.add(
        Text(
          strings.resultTruncated,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.helper,
            color: AppColors.warning,
          ),
        ),
      );
    }
    if (result.evidence.structureUnavailable) {
      blocks.add(
        Text(
          strings.structureUnavailable,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.helper,
            color: AppColors.warning,
          ),
        ),
      );
    }
    if (result.evidence.dictionaryIssues.isNotEmpty) {
      blocks.add(
        Text(
          strings.dictionaryLookupFailed(
            result.evidence.dictionaryIssues
                .map((issue) => issue.dictionaryTitle)
                .join('、'),
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.helper,
            color: AppColors.warning,
          ),
        ),
      );
    }
    if (!result.validation.valid) {
      blocks.add(
        Text(
          strings.validationPartial,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.helper,
            color: AppColors.warning,
          ),
        ),
      );
    }
    for (final warning in result.warnings) {
      blocks.add(
        Text(
          warning,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: AgentTokens.helper,
            color: AppColors.warning,
          ),
        ),
      );
    }
    if (result.profileWarnings.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.sm));
      for (final warning in result.profileWarnings) {
        blocks.add(
          Text(
            strings.profileWarning(warning),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.warning,
            ),
          ),
        );
      }
    }
    if (result.unavailableProfiles.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.sm));
      for (final issue in result.unavailableProfiles) {
        blocks.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  strings.noProfile(issue.title, issue.reason),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.warning,
                  ),
                ),
              ),
              if (onRetryProfile != null)
                _RetryProfileAction(
                  issue: issue,
                  strings: strings,
                  onRetry: onRetryProfile!,
                ),
            ],
          ),
        );
      }
    }
    if (result.quotes.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.originalText));
      for (final quote in result.quotes) {
        blocks.add(
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
        );
      }
    }
    if (result.analysis.segments.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.segmentUnderstanding));
      for (final (index, segment) in result.analysis.segments.indexed) {
        blocks.add(
          AgentFadeIn(
            index: index,
            enabled: index < AgentFadeIn.maxAnimatedItems,
            child: _SegmentBlock(
              segment: segment,
              quote: quotes[segment.quoteId],
              citations: citations,
              citationNumbers: citationNumbers,
              onCitationTap: onCitationTap,
              strings: strings,
            ),
          ),
        );
      }
    }
    if (result.analysis.interpretations.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.possibleUnderstandings));
      for (final interpretation in result.analysis.interpretations) {
        blocks.add(
          _InterpretationBlock(
            interpretation: interpretation,
            citations: citations,
            citationNumbers: citationNumbers,
            onCitationTap: onCitationTap,
            strings: strings,
          ),
        );
      }
    }
    if (result.analysis.unresolved.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.unresolvedTitle));
      for (final unresolved in result.analysis.unresolved) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              _unresolvedReason(unresolved, strings),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.warning,
              ),
            ),
          ),
        );
      }
    }
    if (result.analysis.modelSupplements.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.modelSupplements));
      for (final supplement in result.analysis.modelSupplements) {
        blocks.add(
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
        );
      }
    }
    if (orders.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.dictionaryEvidence));
      for (final (index, order) in orders.indexed) {
        blocks.add(
          AgentFadeIn(
            index: index,
            enabled: index < AgentFadeIn.maxAnimatedItems,
            child: _EvidenceGroup(
              citations: grouped[order]!,
              citationNumbers: citationNumbers,
              onCitationTap: onCitationTap,
              strings: strings,
            ),
          ),
        );
      }
    }

    // A long expanded analysis is built in small chunks across frames. The
    // first screenful appears immediately; later segments/evidence groups are
    // appended without blocking one frame on the whole result.
    return _ProgressiveResultBody(
      revision: Object.hash(result, strings.language),
      blocks: blocks,
    );
  }
}

/// Builds a bounded number of result blocks per frame. It keeps the existing
/// inline ExpansionTile UX while avoiding the single long frame that made the
/// expanded evidence card hitch on long results.
class _ProgressiveResultBody extends StatefulWidget {
  const _ProgressiveResultBody({required this.revision, required this.blocks});

  final int revision;
  final List<Widget> blocks;

  static const int initialCount = 4;
  static const int step = 3;

  @override
  State<_ProgressiveResultBody> createState() => _ProgressiveResultBodyState();
}

class _ProgressiveResultBodyState extends State<_ProgressiveResultBody> {
  late int _visibleCount;
  bool _chunkScheduled = false;

  @override
  void initState() {
    super.initState();
    _visibleCount = _min(
      _ProgressiveResultBody.initialCount,
      widget.blocks.length,
    );
    _scheduleNextChunk();
  }

  @override
  void didUpdateWidget(covariant _ProgressiveResultBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revision != oldWidget.revision) {
      _visibleCount = _min(
        _ProgressiveResultBody.initialCount,
        widget.blocks.length,
      );
      _scheduleNextChunk();
      return;
    }
    if (_visibleCount > widget.blocks.length) {
      _visibleCount = widget.blocks.length;
    } else if (widget.blocks.length > oldWidget.blocks.length &&
        _visibleCount < _ProgressiveResultBody.initialCount) {
      _visibleCount = _min(
        _ProgressiveResultBody.initialCount,
        widget.blocks.length,
      );
      _scheduleNextChunk();
    }
  }

  void _scheduleNextChunk() {
    if (_chunkScheduled || _visibleCount >= widget.blocks.length) return;
    _chunkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chunkScheduled = false;
      if (!mounted || _visibleCount >= widget.blocks.length) return;
      setState(() {
        _visibleCount = _min(
          _visibleCount + _ProgressiveResultBody.step,
          widget.blocks.length,
        );
      });
      _scheduleNextChunk();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.blocks.take(_visibleCount).toList(growable: false),
    );
  }

  static int _min(int left, int right) => left < right ? left : right;
}

class _RetryProfileAction extends StatefulWidget {
  const _RetryProfileAction({
    required this.issue,
    required this.strings,
    required this.onRetry,
  });

  final DictionaryProfileIssue issue;
  final AgentUiStrings strings;
  final Future<void> Function(DictionaryProfileIssue) onRetry;

  @override
  State<_RetryProfileAction> createState() => _RetryProfileActionState();
}

class _RetryProfileActionState extends State<_RetryProfileAction> {
  bool _loading = false;

  Future<void> _retry() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onRetry(widget.issue);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Semantics(
        label: widget.strings.retryingProfile,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SizedBox(
            width: AppSizes.iconSmall,
            height: AppSizes.iconSmall,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return TextButton(
      onPressed: _retry,
      child: Text(widget.strings.retryThisDictionary),
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
    required this.strings,
  });

  final AgentSegment segment;
  final AgentQuoteRef? quote;
  final Map<String, AgentCitation> citations;
  final Map<String, int> citationNumbers;
  final ValueChanged<AgentCitation> onCitationTap;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segmentCitationIds =
        <String>{
          for (final note in segment.wordNotes) ...note.citationIds,
          for (final note in segment.grammarNotes) ...note.citationIds,
        }.where(citations.containsKey).toList(growable: false)..sort(
          (a, b) =>
              (citationNumbers[a] ?? 0).compareTo(citationNumbers[b] ?? 0),
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
            stripYomiTags(segment.interpretation),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: AgentTokens.body,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ClaimBadge(
            epistemic: segment.epistemic,
            confidence: segment.confidence,
            strings: strings,
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
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final id in segmentCitationIds)
                    _CitationChip(
                      citation: citations[id]!,
                      number: citationNumbers[id]!,
                      onTap: onCitationTap,
                      strings: strings,
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
  const _ClaimBadge({
    required this.epistemic,
    required this.confidence,
    required this.strings,
  });

  final AgentEpistemic epistemic;
  final double confidence;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (epistemic) {
      AgentEpistemic.dictionaryFact => (
        strings.epistemicDictionaryFact,
        AppColors.blue50,
        AppColors.blue700,
      ),
      AgentEpistemic.structuralAnalysis => (
        strings.epistemicStructural,
        AppColors.surfaceMuted,
        AppColors.textPrimary,
      ),
      AgentEpistemic.contextInference => (
        strings.epistemicInference,
        AppColors.surfaceMuted,
        AppColors.warning,
      ),
      AgentEpistemic.translation => (
        strings.epistemicTranslation,
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
          strings.confidence((confidence.clamp(0, 1) * 100).round()),
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
    required this.strings,
  });

  final AgentInterpretation interpretation;
  final Map<String, AgentCitation> citations;
  final Map<String, int> citationNumbers;
  final ValueChanged<AgentCitation> onCitationTap;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
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
                strings: strings,
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
    required this.strings,
  });

  final List<AgentCitation> citations;
  final Map<String, int> citationNumbers;
  final ValueChanged<AgentCitation> onCitationTap;
  final AgentUiStrings strings;

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
            '${dictionary.dictionaryTitle} · '
            '${strings.evidenceEntryCount(citations.length)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.evidenceTitle,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            _ProgressiveResultBody(
              revision: Object.hashAll(citations),
              blocks: [
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
                              _CitationChip(
                                citation: citation,
                                number: citationNumbers[citation.id] ?? 0,
                                onTap: onCitationTap,
                                strings: strings,
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
          ],
        ),
      ),
    );
  }
}

String _unresolvedReason(AgentUnresolved unresolved, AgentUiStrings strings) {
  final trimmed = unresolved.reason.trim();
  if (trimmed.isEmpty) return strings.unresolvedFallback;
  // Quote IDs are an internal trace; never show `（q1）` to the user.
  final withoutQuoteId = trimmed.replaceFirst(
    RegExp(r'\s*[（(]\s*q\d+\s*[）)]\s*$'),
    '',
  );
  return withoutQuoteId.trim().isEmpty
      ? strings.unresolvedFallback
      : withoutQuoteId.trim();
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({
    required this.citation,
    required this.number,
    required this.onTap,
    required this.strings,
  });

  final AgentCitation citation;
  final int number;
  final ValueChanged<AgentCitation> onTap;
  final AgentUiStrings strings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: strings.citationSemantics(number, citation.headword),
      child: GestureDetector(
        onTap: () => onTap(citation),
        child: Container(
          height: AgentTokens.citationChipHeight,
          constraints: const BoxConstraints(
            minWidth: AgentTokens.citationChipMinWidth,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AgentTokens.citationSurface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                strings.citationLabel(number),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AgentTokens.citationChip,
                  color: AgentTokens.citationText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
