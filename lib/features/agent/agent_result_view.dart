import 'package:flutter/material.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_pitch.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/rich_text_tags.dart';
import '../../services/agent/agent_run.dart';
import '../../services/agent/agent_ui_strings.dart';
import '../../services/agent/familiarization/dictionary_familiarization_service.dart'
    show DictionaryProfileIssue;
import 'agent_fade_in.dart';
import 'agent_pitch_accent.dart';
import 'agent_rich_text.dart';

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
    final noAnalysisReason = result.analysis.noAnalysisReason.trim();
    if (noAnalysisReason.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            border: Border.all(color: AppColors.warning),
            borderRadius: BorderRadius.circular(AgentTokens.evidenceRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.noAnalysisTitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              AgentRichText(
                text: stripYomiTags(localReadingsToRuby(noAnalysisReason)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.body,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
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
      final richOriginal = result.richOriginalText;
      if (richOriginal != null && richOriginal.isNotEmpty) {
        blocks.add(
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: AgentRichText(
              text: stripYomiTags(richOriginal),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: AgentTokens.body,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      } else {
        for (final quote in result.quotes) {
          blocks.add(
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: AgentRichText(
                text: stripYomiTags(localReadingsToRuby(quote.text)),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: AgentTokens.body,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          );
        }
      }
    }
    if (result.analysis.segments.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.segmentUnderstanding));
      // A quote can carry several epistemically different segments. Render
      // the quote once per group so the same sentence is not repeated for
      // every fact/structure/inference block.
      final segmentGroups = <String, List<(int, AgentSegment)>>{};
      for (final (index, segment) in result.analysis.segments.indexed) {
        segmentGroups
            .putIfAbsent(segment.quoteId, () => <(int, AgentSegment)>[])
            .add((index, segment));
      }
      for (final entry in segmentGroups.entries) {
        final quote = quotes[entry.key];
        if (quote != null) {
          blocks.add(
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              padding: const EdgeInsets.all(AgentTokens.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AgentTokens.evidenceRadius),
              ),
              child: AgentRichText(
                text: stripYomiTags(localReadingsToRuby(quote.text)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }
        for (final (index, segment) in entry.value) {
          blocks.add(
            AgentFadeIn(
              index: index,
              enabled: index < AgentFadeIn.maxAnimatedItems,
              child: _SegmentBlock(
                segment: segment,
                richInterpretation: index < result.richSegmentTexts.length
                    ? result.richSegmentTexts[index]
                    : '',
                richNotes: index < result.richSegmentNotes.length
                    ? result.richSegmentNotes[index]
                    : '',
                quote: null,
                pitchAccents: result.pitchAccents,
                citations: citations,
                citationNumbers: citationNumbers,
                onCitationTap: onCitationTap,
                strings: strings,
              ),
            ),
          );
        }
      }
    }
    if (result.analysis.interpretations.isNotEmpty) {
      blocks.add(const SizedBox(height: AppSpacing.md));
      blocks.add(_SectionTitle(strings.possibleUnderstandings));
      final interpretationCitationSets = <List<String>>[
        for (final interpretation in result.analysis.interpretations)
          interpretation.citationIds
              .where(citations.containsKey)
              .toList(growable: false),
      ];
      final firstInterpretationCitations = interpretationCitationSets.first;
      final sharedInterpretationCitations =
          firstInterpretationCitations.isNotEmpty &&
          interpretationCitationSets.every(
            (ids) =>
                ids.length == firstInterpretationCitations.length &&
                ids.toSet().containsAll(firstInterpretationCitations),
          );
      final sharedInterpretationIds = sharedInterpretationCitations
          ? (firstInterpretationCitations.toList()..sort(
              (a, b) =>
                  (citationNumbers[a] ?? 0).compareTo(citationNumbers[b] ?? 0),
            ))
          : const <String>[];
      for (final interpretation in result.analysis.interpretations) {
        blocks.add(
          _InterpretationBlock(
            interpretation: interpretation,
            citations: citations,
            citationNumbers: citationNumbers,
            onCitationTap: onCitationTap,
            strings: strings,
            showCitations: !sharedInterpretationCitations,
          ),
        );
      }
      if (sharedInterpretationIds.isNotEmpty) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Wrap(
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.start,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final id in sharedInterpretationIds)
                  if (citations[id] != null && citationNumbers[id] != null)
                    _CitationChip(
                      citation: citations[id]!,
                      number: citationNumbers[id]!,
                      onTap: onCitationTap,
                      strings: strings,
                    ),
              ],
            ),
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
            child: AgentRichText(
              text: stripYomiTags(
                localReadingsToRuby(_unresolvedReason(unresolved, strings)),
              ),
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
            child: AgentRichText(
              text: stripYomiTags(localReadingsToRuby(supplement.text)),
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
    // appended without blocking one frame on the whole result. Rich-text
    // updates keep the same revision: replacing the result object with
    // display-only formatting must not collapse the already-built blocks or
    // reset the user's scroll position.
    return _ProgressiveResultBody(
      revision: Object.hash(
        result.analysis,
        result.validation,
        result.evidence,
        result.quotes,
        result.sources,
        result.warnings,
        result.profileWarnings,
        result.unavailableProfiles,
        strings.language,
      ),
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
      // Keep the already-visible blocks across result revisions. Resetting to
      // initialCount here shrinks the list, which makes the ListView clamp the
      // scroll offset to the top and reads as a full page reload.
      if (_visibleCount > widget.blocks.length) {
        _visibleCount = widget.blocks.length;
      }
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
    required this.richInterpretation,
    required this.richNotes,
    required this.quote,
    required this.pitchAccents,
    required this.citations,
    required this.citationNumbers,
    required this.onCitationTap,
    required this.strings,
  });

  final AgentSegment segment;
  final String richInterpretation;
  final String richNotes;
  final AgentQuoteRef? quote;
  final Map<String, AgentPitchAccent> pitchAccents;
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
            AgentRichText(
              text: stripYomiTags(localReadingsToRuby(quote!.text)),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          AgentRichText(
            text: stripYomiTags(
              richInterpretation.isEmpty
                  ? localReadingsToRuby(segment.interpretation)
                  : richInterpretation,
            ),
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
          if (richNotes.isNotEmpty) ...[
            _PitchNotes(
              notes: segment.wordNotes,
              accents: pitchAccents,
              strings: strings,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: AgentTokens.helper,
                color: AppColors.textPrimary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: AgentRichText(
                text: stripYomiTags(richNotes),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AgentTokens.helper,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ] else ...[
            for (final note in segment.wordNotes)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: _WordNoteLine(
                  note: note,
                  accent: pitchAccents[note.tokenId],
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            for (final note in segment.grammarNotes)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: AgentRichText(
                  text: stripYomiTags(localReadingsToRuby(note.explanation)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: AgentTokens.helper,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
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

class _WordNoteLine extends StatelessWidget {
  const _WordNoteLine({
    required this.note,
    required this.accent,
    required this.style,
  });

  final AgentWordNote note;
  final AgentPitchAccent? accent;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final validAccent = accent;
    if (!shouldDisplayPitch(
      surface: note.surface,
      reading: note.reading,
      accent: validAccent,
    )) {
      final reading = note.reading.trim();
      final display = reading.isEmpty || reading == note.surface
          ? note.surface
          : '$reading【${note.surface}】';
      return AgentRichText(
        text: localReadingsToRuby('$display：${note.sense}'),
        style: style,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        AgentPitchAccentText(
          surface: note.surface,
          reading: note.reading,
          accent: validAccent,
          style: style ?? const TextStyle(),
        ),
        Flexible(
          child: AgentRichText(
            text: localReadingsToRuby('：${note.sense}'),
            style: style,
          ),
        ),
      ],
    );
  }
}

class _PitchNotes extends StatelessWidget {
  const _PitchNotes({
    required this.notes,
    required this.accents,
    required this.strings,
    required this.style,
  });

  final List<AgentWordNote> notes;
  final Map<String, AgentPitchAccent> accents;
  final AgentUiStrings strings;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final note in notes) {
      final accent = accents[note.tokenId];
      if (!shouldDisplayPitch(
        surface: note.surface,
        reading: note.reading,
        accent: accent,
      )) {
        continue;
      }
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AgentPitchAccentText(
              surface: note.surface,
              reading: note.reading,
              accent: accent,
              style: style ?? const TextStyle(),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _BadgeChip(
            label: strings.pitchInfoLabel,
            background: AgentTokens.pitchInfoBadgeSurface,
            foreground: AgentTokens.pitchInfoBadgeText,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: items,
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        _BadgeChip(
          label: label,
          background: background,
          foreground: foreground,
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
    this.showCitations = true,
  });

  final AgentInterpretation interpretation;
  final Map<String, AgentCitation> citations;
  final Map<String, int> citationNumbers;
  final ValueChanged<AgentCitation> onCitationTap;
  final AgentUiStrings strings;
  final bool showCitations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AgentRichText(
            text: stripYomiTags(localReadingsToRuby(interpretation.meaning)),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AgentTokens.helper,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _BadgeChip(
                label: strings.situationLabel(interpretation.label),
                background: AppColors.successSurface,
                foreground: AppColors.success,
              ),
              Text(
                strings.possibility(
                  (interpretation.confidence.clamp(0, 1) * 100).round(),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AgentTokens.badge,
                  color: AppColors.textSecondary,
                ),
              ),
              if (showCitations)
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
