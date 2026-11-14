import '../../core/models/agent/agent_evidence.dart';

/// Projects an evidence bundle onto one dictionary for conditional fan-out.
///
/// Source text, tokens and grammar patterns stay intact so the model can still
/// use UniDic structure; only citation ids from other dictionaries are removed.
AgentEvidenceBundle evidenceForDictionary(
  AgentEvidenceBundle evidence,
  String dictionaryId,
) {
  final citations = evidence.citations
      .where((citation) => citation.dictionaryId == dictionaryId)
      .toList(growable: false);
  final citationIds = <String>{for (final citation in citations) citation.id};
  final sources = <AgentSourceEvidence>[
    for (final source in evidence.sources)
      AgentSourceEvidence(
        id: source.id,
        kind: source.kind,
        text: source.text,
        tokens: <AgentTokenEvidence>[
          for (final token in source.tokens)
            AgentTokenEvidence(
              id: token.id,
              surface: token.surface,
              reading: token.reading,
              lemma: token.lemma,
              pos: token.pos,
              start: token.start,
              end: token.end,
              content: token.content,
              lookupCandidates: token.lookupCandidates,
              citationIds: token.citationIds
                  .where(citationIds.contains)
                  .toList(growable: false),
            ),
        ],
      ),
  ];
  final patterns = <AgentGrammarPatternEvidence>[
    for (final pattern in evidence.patterns)
      AgentGrammarPatternEvidence(
        id: pattern.id,
        surface: pattern.surface,
        tokenIds: pattern.tokenIds,
        start: pattern.start,
        end: pattern.end,
        citationIds: pattern.citationIds
            .where(citationIds.contains)
            .toList(growable: false),
      ),
  ];
  return AgentEvidenceBundle(
    sources: sources,
    patterns: patterns,
    citations: citations,
    truncated: evidence.truncated,
    structureUnavailable: evidence.structureUnavailable,
    dictionaryIssues: evidence.dictionaryIssues
        .where((issue) => issue.dictionaryId == dictionaryId)
        .toList(growable: false),
    pitchAccents: evidence.pitchAccents,
    budget: AgentEvidenceBudget(
      sourceChars: evidence.budget.sourceChars,
      uniqueTargets: evidence.budget.uniqueTargets,
      targetsWithCitations: _countCitedTargets(
        sources: sources,
        patterns: patterns,
        citationIds: citationIds,
        maxTargets: evidence.budget.uniqueTargets,
      ),
      citations: citations.length,
      maxTargets: evidence.budget.maxTargets,
      maxCitations: evidence.budget.maxCitations,
    ),
  );
}

int _countCitedTargets({
  required List<AgentSourceEvidence> sources,
  required List<AgentGrammarPatternEvidence> patterns,
  required Set<String> citationIds,
  required int maxTargets,
}) {
  if (citationIds.isEmpty || maxTargets <= 0) return 0;
  var count = 0;
  for (final source in sources) {
    for (final token in source.tokens) {
      if (token.citationIds.any(citationIds.contains)) count++;
    }
  }
  for (final pattern in patterns) {
    if (pattern.citationIds.any(citationIds.contains)) count++;
  }
  return count > maxTargets ? maxTargets : count;
}
