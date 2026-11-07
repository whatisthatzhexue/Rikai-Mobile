import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/utils/rich_text_tags.dart';
import 'agent_run.dart';
import 'agent_ui_strings.dart';

/// Builds the copyable Markdown for a completed Agent result.
///
/// It contains only user-visible structured content: no raw provider output,
/// hidden reasoning, local image paths, HTML or API details.
String buildAgentResultMarkdown(AgentRunResult result, AgentUiStrings strings) {
  final citations = result.adoptedCitations;
  final citationNumbers = <String, int>{
    for (var index = 0; index < citations.length; index++)
      citations[index].id: index + 1,
  };
  final quotes = <String, String>{
    for (final quote in result.quotes) quote.id: quote.text,
  };
  final buffer = StringBuffer();

  if (result.quotes.isNotEmpty) {
    buffer
      ..writeln('## ${strings.originalText}')
      ..writeln();
    final richOriginal = result.richOriginalText;
    if (richOriginal != null && richOriginal.isNotEmpty) {
      buffer
        ..writeln('> ${richTextToPlain(richOriginal)}')
        ..writeln();
    } else {
      for (final quote in result.quotes) {
        buffer
          ..writeln('> ${richTextToPlain(quote.text)}')
          ..writeln();
      }
    }
  }

  final noAnalysisReason = result.analysis.noAnalysisReason.trim();
  if (noAnalysisReason.isNotEmpty) {
    buffer
      ..writeln('## ${strings.noAnalysisTitle}')
      ..writeln()
      ..writeln(richTextToPlain(noAnalysisReason))
      ..writeln();
  }
  if (result.evidence.truncated) {
    buffer
      ..writeln('- ${strings.resultTruncated}')
      ..writeln(
        '- ${strings.evidenceTruncatedCounts(result.evidence.citations.length, result.validation.citationsUsed.length, result.evidence.budget.maxCitations)}',
      )
      ..writeln();
  }
  if (result.analysis.truncated) {
    buffer
      ..writeln('- ${strings.analysisTruncated}')
      ..writeln();
  }

  if (result.analysis.translation.isNotEmpty) {
    buffer
      ..writeln('## ${strings.translationTitle}')
      ..writeln();
    for (final item in result.analysis.translation) {
      buffer.writeln('- ${richTextToPlain(item.text)}');
    }
    buffer.writeln();
  }

  if (result.analysis.segments.isNotEmpty) {
    buffer
      ..writeln('## ${strings.segmentUnderstanding}')
      ..writeln();
    final segmentGroups = <String, List<(int, AgentSegment)>>{};
    for (final (index, segment) in result.analysis.segments.indexed) {
      segmentGroups
          .putIfAbsent(segment.quoteId, () => <(int, AgentSegment)>[])
          .add((index, segment));
    }
    for (final entry in segmentGroups.entries) {
      final quote = quotes[entry.key];
      if (quote != null && quote.isNotEmpty) {
        buffer
          ..writeln('> $quote')
          ..writeln();
      }
      for (final (index, segment) in entry.value) {
        final rich = index < result.richSegmentTexts.length
            ? result.richSegmentTexts[index]
            : '';
        buffer
          ..writeln(
            richTextToPlain(rich.isEmpty ? segment.interpretation : rich),
          )
          ..writeln();
        final epistemic = switch (segment.epistemic) {
          AgentEpistemic.dictionaryFact => strings.epistemicDictionaryFact,
          AgentEpistemic.structuralAnalysis => strings.epistemicStructural,
          AgentEpistemic.contextInference => strings.epistemicInference,
          AgentEpistemic.translation => strings.epistemicTranslation,
        };
        buffer.writeln(
          '- $epistemic · ${strings.confidence((segment.confidence.clamp(0, 1) * 100).round())}',
        );
        final richNotes = index < result.richSegmentNotes.length
            ? result.richSegmentNotes[index]
            : '';
        if (richNotes.isNotEmpty) {
          for (final line in richTextToPlain(richNotes).split('\n')) {
            if (line.trim().isNotEmpty) buffer.writeln('- ${line.trim()}');
          }
        } else {
          for (final note in segment.wordNotes) {
            final reading = note.reading.trim();
            final display = reading.isEmpty || reading == note.surface
                ? note.surface
                : '$reading【${note.surface}】';
            buffer.writeln('- $display：${note.sense}');
          }
          for (final note in segment.grammarNotes) {
            buffer.writeln('- ${note.explanation}');
          }
        }
        final ids =
            <String>{
              for (final note in segment.wordNotes) ...note.citationIds,
              for (final note in segment.grammarNotes) ...note.citationIds,
            }.where(citationNumbers.containsKey).toList(growable: false)..sort(
              (a, b) => citationNumbers[a]!.compareTo(citationNumbers[b]!),
            );
        if (ids.isNotEmpty) {
          buffer.writeln(
            '- ${ids.map((id) => strings.citationLabel(citationNumbers[id]!)).join(' ')}',
          );
        }
        buffer.writeln();
      }
    }
  }

  if (result.analysis.interpretations.isNotEmpty) {
    buffer
      ..writeln('## ${strings.possibleUnderstandings}')
      ..writeln();
    for (final interpretation in result.analysis.interpretations) {
      buffer.writeln(
        '- ${interpretation.label}：${interpretation.meaning}'
        '（${(interpretation.confidence * 100).round()}%）',
      );
    }
    buffer.writeln();
  }

  if (result.analysis.unresolved.isNotEmpty) {
    buffer
      ..writeln('## ${strings.unresolvedTitle}')
      ..writeln();
    for (final unresolved in result.analysis.unresolved) {
      buffer.writeln('- ${_unresolvedReason(unresolved.reason, strings)}');
    }
    buffer.writeln();
  }

  if (result.analysis.modelSupplements.isNotEmpty) {
    buffer
      ..writeln('## ${strings.modelSupplements}')
      ..writeln();
    for (final supplement in result.analysis.modelSupplements) {
      buffer.writeln('- ${supplement.text}');
    }
    buffer.writeln();
  }

  if (citations.isNotEmpty) {
    buffer
      ..writeln('## ${strings.dictionaryEvidence}')
      ..writeln();
    final grouped = <int, List<AgentCitation>>{};
    for (final citation in citations) {
      grouped
          .putIfAbsent(citation.dictionaryOrder, () => <AgentCitation>[])
          .add(citation);
    }
    final orders = grouped.keys.toList()..sort();
    for (final order in orders) {
      final group = grouped[order]!;
      buffer.writeln('### ${group.first.dictionaryTitle}');
      for (final citation in group) {
        final number = citationNumbers[citation.id] ?? 0;
        final title = citation.displayTitle.isEmpty
            ? strings.citationTitleFallback
            : citation.displayTitle;
        buffer.writeln(
          '- ${strings.citationLabel(number)} · $title：'
          '${citation.snippet}',
        );
      }
      buffer.writeln();
    }
  }

  return buffer.toString().trimRight();
}

String _unresolvedReason(String reason, AgentUiStrings strings) {
  final trimmed = reason.trim();
  if (trimmed.isEmpty) return strings.unresolvedFallback;
  final withoutQuoteId = trimmed.replaceFirst(
    RegExp(r'\s*[（(]\s*q\d+\s*[）)]\s*$'),
    '',
  );
  return withoutQuoteId.trim().isEmpty
      ? strings.unresolvedFallback
      : withoutQuoteId.trim();
}
