import '../../core/models/agent/agent_coverage.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/utils/text_normalizer.dart';

class AgentCoverageValidation {
  const AgentCoverageValidation({
    required this.missing,
    required this.duplicateGroups,
    this.droppedMissing = 0,
  });

  final List<AgentCoverageMissing> missing;
  final List<AgentCoverageDuplicateGroup> duplicateGroups;
  final int droppedMissing;
}

/// Keeps only missing queries that are traceable to the supplied source,
/// tokens, patterns or already retrieved dictionary entries.
AgentCoverageValidation validateCoverageReview({
  required AgentCoverageReview review,
  required AgentInputEnvelope input,
  required AgentEvidenceBundle evidence,
  required AgentLimits limits,
}) {
  final validRefs = <String>{
    for (final source in input.sources) source.id,
    for (final source in evidence.sources) source.id,
    for (final source in evidence.sources)
      for (final token in source.tokens) token.id,
    for (final pattern in evidence.patterns) pattern.id,
  };
  final sourceTexts = <String>[
    for (final source in evidence.sources)
      if (source.text.trim().isNotEmpty) source.text,
  ];
  final exactTerms = <String>{
    for (final source in evidence.sources)
      for (final token in source.tokens) ...<String>[
        token.surface,
        token.lemma,
        token.reading,
        ...token.lookupCandidates,
      ],
    for (final pattern in evidence.patterns) pattern.surface,
    for (final citation in evidence.citations) ...<String>[
      citation.entryKey,
      citation.headword,
      citation.matchedKey,
    ],
  }..removeWhere((term) => term.trim().isEmpty);

  // Queries whose word/reading is already covered by a citation or a token
  // with citation_ids must not trigger another lookup. This was a major source
  // of redundant coverage evidence and crowded out genuinely missing items.
  final coveredKeys = <String>{};
  void addCovered(String value) {
    final normalized = stripLookupKey(value);
    if (normalized.isNotEmpty) coveredKeys.add(normalized);
  }

  final citationIds = <String>{
    for (final citation in evidence.citations) citation.id,
  };
  for (final citation in evidence.citations) {
    addCovered(citation.entryKey);
    addCovered(citation.headword);
    addCovered(citation.matchedKey);
  }
  for (final source in evidence.sources) {
    for (final token in source.tokens) {
      if (!token.citationIds.any(citationIds.contains)) continue;
      addCovered(token.surface);
      addCovered(token.lemma);
      addCovered(token.reading);
      for (final candidate in token.lookupCandidates) {
        addCovered(candidate);
      }
    }
  }
  for (final pattern in evidence.patterns) {
    if (pattern.citationIds.any(citationIds.contains)) {
      addCovered(pattern.surface);
    }
  }
  const coveredQueryKinds = <AgentCoverageKind>{
    AgentCoverageKind.word,
    AgentCoverageKind.reading,
    AgentCoverageKind.grammar,
    AgentCoverageKind.context,
  };
  final seenQueries = <String>{};

  final missing = <AgentCoverageMissing>[];
  var dropped = 0;
  for (final item in review.missing) {
    if (missing.length >= limits.maxCoverageMissing) {
      dropped++;
      continue;
    }
    final query = item.query.trim();
    if (query.isEmpty || query.length > limits.maxCoverageQueryChars) {
      dropped++;
      continue;
    }
    final normalizedQuery = stripLookupKey(query);
    if (normalizedQuery.isEmpty) {
      continue;
    }
    final refs = <String>[
      for (final ref in item.sourceRefs)
        if (validRefs.contains(ref)) ref,
    ];
    if (refs.isEmpty) {
      dropped++;
      continue;
    }
    final knownTerm = exactTerms.contains(query);
    final traceable =
        knownTerm || sourceTexts.any((text) => text.contains(query));
    if (!traceable) {
      dropped++;
      continue;
    }
    // Compound/fixed-collocation expansion is word-only. A known term is
    // already bounded by the normal lookup path. An unknown form must be a
    // contiguous source span covering a small number of tokens; this is
    // language-agnostic (a long German compound is one token, while a whole
    // sentence is many) and avoids a hard-coded character count.
    if (item.kind == AgentCoverageKind.word &&
        !knownTerm &&
        !_hasBoundedCompoundSpan(
          query: query,
          evidence: evidence,
          maxTokens: limits.maxCoverageCompoundTokens,
        )) {
      dropped++;
      continue;
    }
    // Duplicate and already-covered queries are redundant, not malformed;
    // skip them without a user-visible "coverage unavailable" warning.
    if (!seenQueries.add(normalizedQuery)) continue;
    if (coveredQueryKinds.contains(item.kind) &&
        coveredKeys.contains(normalizedQuery)) {
      continue;
    }
    missing.add(
      AgentCoverageMissing(
        kind: item.kind,
        query: query,
        sourceRefs: List<String>.unmodifiable(refs),
        reason: item.reason,
        priority: item.priority.clamp(1, 5),
      ),
    );
  }
  missing.sort((a, b) => a.priority.compareTo(b.priority));

  return AgentCoverageValidation(
    missing: List<AgentCoverageMissing>.unmodifiable(missing),
    duplicateGroups: List<AgentCoverageDuplicateGroup>.unmodifiable(
      review.duplicateGroups.take(limits.maxCoverageDuplicateGroups),
    ),
    droppedMissing: dropped,
  );
}

/// Verifies model-suggested duplicate groups locally. Unknown dictionaries,
/// different entry keys, non-overlapping snippets and denser removals are
/// rejected; a citation kept by one group is never removed by another.
Set<String> verifyCoverageDuplicates({
  required AgentEvidenceBundle evidence,
  required List<AgentCoverageDuplicateGroup> groups,
}) {
  final byDictionaryAndKey = <String, List<AgentCitation>>{};
  for (final citation in evidence.citations) {
    for (final key in _citationKeys(citation)) {
      final normalized = stripLookupKey(key);
      if (normalized.isEmpty) continue;
      byDictionaryAndKey
          .putIfAbsent('${citation.dictionaryId}\u0000$normalized', () => [])
          .add(citation);
    }
  }

  final keptIds = <String>{};
  final removedIds = <String>{};
  for (final group in groups) {
    final keepMatches =
        byDictionaryAndKey['${group.dictionaryId}\u0000'
            '${stripLookupKey(group.keepEntryKey)}'] ??
        const <AgentCitation>[];
    if (keepMatches.isEmpty) continue;
    final keep = keepMatches.reduce(
      (a, b) => a.snippet.length >= b.snippet.length ? a : b,
    );
    keptIds.add(keep.id);
    for (final removeKey in group.removeEntryKeys) {
      final candidates =
          byDictionaryAndKey['${group.dictionaryId}\u0000'
              '${stripLookupKey(removeKey)}'] ??
          const <AgentCitation>[];
      for (final candidate in candidates) {
        if (candidate.id == keep.id) continue;
        // Keep the denser (longer) snippet; never remove a denser entry.
        if (candidate.snippet.length > keep.snippet.length) continue;
        // Different entry keys can still be duplicates (for example
        // “何卒” and “何卒（副）”), so the local proof is snippet overlap.
        if (!_mostlyOverlapping(keep.snippet, candidate.snippet)) continue;
        removedIds.add(candidate.id);
      }
    }
  }
  removedIds.removeAll(keptIds);
  return removedIds;
}

AgentEvidenceBundle pruneCoverageCitations({
  required AgentEvidenceBundle evidence,
  required Set<String> removeIds,
  required AgentLimits limits,
}) {
  if (removeIds.isEmpty) return evidence;
  final citations = evidence.citations
      .where((citation) => !removeIds.contains(citation.id))
      .toList(growable: false);
  return AgentEvidenceBundle(
    sources: <AgentSourceEvidence>[
      for (final source in evidence.sources)
        AgentSourceEvidence(
          id: source.id,
          kind: source.kind,
          text: source.text,
          tokens: <AgentTokenEvidence>[
            for (final token in source.tokens)
              _tokenWithCitations(
                token,
                token.citationIds.where((id) => !removeIds.contains(id)),
              ),
          ],
        ),
    ],
    patterns: <AgentGrammarPatternEvidence>[
      for (final pattern in evidence.patterns)
        AgentGrammarPatternEvidence(
          id: pattern.id,
          surface: pattern.surface,
          tokenIds: pattern.tokenIds,
          start: pattern.start,
          end: pattern.end,
          citationIds: pattern.citationIds
              .where((id) => !removeIds.contains(id))
              .toList(growable: false),
        ),
    ],
    citations: _sortedCitations(citations),
    truncated: evidence.truncated,
    structureUnavailable: evidence.structureUnavailable,
    dictionaryIssues: evidence.dictionaryIssues,
    budget: AgentEvidenceBudget(
      sourceChars: evidence.budget.sourceChars,
      uniqueTargets: evidence.budget.uniqueTargets,
      targetsWithCitations: evidence.budget.targetsWithCitations,
      citations: citations.length,
      maxTargets: limits.maxTargets,
      maxCitations: limits.maxEvidenceEntries,
    ),
  );
}

AgentEvidenceBundle mergeCoverageEvidence({
  required AgentEvidenceBundle evidence,
  required Map<String, List<AgentCitation>> citationsByQuery,
  required List<AgentCoverageMissing> missing,
  required AgentLimits limits,
}) {
  final byId = <String, AgentCitation>{
    for (final citation in evidence.citations) citation.id: citation,
  };
  for (final citations in citationsByQuery.values) {
    for (final citation in citations) {
      byId.putIfAbsent(citation.id, () => citation);
    }
  }
  final queryIds = <String, Set<String>>{
    for (final entry in citationsByQuery.entries)
      entry.key: <String>{for (final citation in entry.value) citation.id},
  };
  final additions = <String, Set<String>>{};
  for (final item in missing) {
    final ids = queryIds[item.query];
    if (ids == null || ids.isEmpty) continue;
    for (final ref in item.sourceRefs) {
      additions.putIfAbsent(ref, () => <String>{}).addAll(ids);
    }
  }
  final mergedCitations = _sortedCitations(byId.values.toList(growable: false));

  return AgentEvidenceBundle(
    sources: <AgentSourceEvidence>[
      for (final source in evidence.sources)
        AgentSourceEvidence(
          id: source.id,
          kind: source.kind,
          text: source.text,
          tokens: <AgentTokenEvidence>[
            for (final token in source.tokens)
              _tokenWithCitations(token, <String>{
                ...token.citationIds,
                ...?additions[token.id],
              }),
          ],
        ),
    ],
    patterns: <AgentGrammarPatternEvidence>[
      for (final pattern in evidence.patterns)
        AgentGrammarPatternEvidence(
          id: pattern.id,
          surface: pattern.surface,
          tokenIds: pattern.tokenIds,
          start: pattern.start,
          end: pattern.end,
          citationIds: <String>[
            ...{...pattern.citationIds, ...?additions[pattern.id]},
          ],
        ),
    ],
    citations: mergedCitations,
    truncated: evidence.truncated,
    structureUnavailable: evidence.structureUnavailable,
    dictionaryIssues: evidence.dictionaryIssues,
    budget: AgentEvidenceBudget(
      sourceChars: evidence.budget.sourceChars,
      uniqueTargets: evidence.budget.uniqueTargets,
      targetsWithCitations: evidence.budget.targetsWithCitations,
      citations: mergedCitations.length,
      maxTargets: limits.maxTargets,
      maxCitations: limits.maxEvidenceEntries,
    ),
  );
}

AgentTokenEvidence _tokenWithCitations(
  AgentTokenEvidence token,
  Iterable<String> citationIds,
) {
  return AgentTokenEvidence(
    id: token.id,
    surface: token.surface,
    reading: token.reading,
    lemma: token.lemma,
    pos: token.pos,
    start: token.start,
    end: token.end,
    content: token.content,
    lookupCandidates: token.lookupCandidates,
    citationIds: citationIds.toList(growable: false),
  );
}

List<AgentCitation> _sortedCitations(List<AgentCitation> citations) {
  final sorted = citations.toList(growable: false)
    ..sort((a, b) {
      final order = a.dictionaryOrder.compareTo(b.dictionaryOrder);
      if (order != 0) return order;
      return a.entryKey.compareTo(b.entryKey);
    });
  return sorted;
}

Set<String> _citationKeys(AgentCitation citation) => <String>{
  citation.entryKey,
  citation.headword,
  citation.matchedKey,
};

/// Whether [query] occurs as a contiguous source span covering at most
/// [maxTokens] tokens.
///
/// Returns false when the source has no tokens: without a tokenizer there is no
/// language-neutral way to distinguish a compound from a sentence, so callers
/// must fall back to known token/pattern/entry terms.
bool _hasBoundedCompoundSpan({
  required String query,
  required AgentEvidenceBundle evidence,
  required int maxTokens,
}) {
  if (maxTokens <= 0) return false;
  if (query.contains('\n') || query.contains('\r')) return false;
  for (final source in evidence.sources) {
    if (source.tokens.isEmpty) continue;
    final text = source.text;
    var start = text.indexOf(query);
    while (start >= 0) {
      final end = start + query.length;
      var overlapping = 0;
      for (final token in source.tokens) {
        if (token.start < end && token.end > start) {
          overlapping++;
          if (overlapping > maxTokens) break;
        }
      }
      if (overlapping > 0 && overlapping <= maxTokens) return true;
      start = text.indexOf(query, start + 1);
    }
  }
  return false;
}

bool _mostlyOverlapping(String a, String b) {
  final left = stripLookupKey(a);
  final right = stripLookupKey(b);
  if (left.isEmpty || right.isEmpty) return false;
  if (left.contains(right) || right.contains(left)) return true;
  if (left.length < 2 || right.length < 2) return false;
  final leftGrams = <String>{
    for (var index = 0; index < left.length - 1; index++)
      left.substring(index, index + 2),
  };
  final rightGrams = <String>{
    for (var index = 0; index < right.length - 1; index++)
      right.substring(index, index + 2),
  };
  final intersection = leftGrams.intersection(rightGrams).length;
  final union = leftGrams.union(rightGrams).length;
  return union > 0 && intersection / union >= 0.6;
}
