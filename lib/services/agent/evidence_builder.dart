import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/models/dict_info.dart';
import '../../core/models/lookup_match_mode.dart';
import '../../core/models/lookup_models.dart';
import '../../core/models/lookup_request.dart';
import '../../core/models/token.dart';
import '../../core/utils/html_text.dart';
import 'citation_registry.dart';
import 'grammar_patterns.dart';
import 'ports/agent_capability_exception.dart';
import 'ports/lookup_port.dart';
import 'ports/tokenize_port.dart';

const _lookupModes = <LookupMatchMode>[
  LookupMatchMode.exact,
  LookupMatchMode.prefix,
  LookupMatchMode.suffix,
  LookupMatchMode.incremental,
];

/// Builds one bounded evidence bundle for all sources in a run.
class EvidenceBuilder {
  const EvidenceBuilder({
    required this.tokenizePort,
    required this.lookupPort,
    required this.grammar,
    required this.citations,
    this.limits = AgentLimits.standard,
  });

  final TokenizePort tokenizePort;
  final LookupPort lookupPort;
  final GrammarPatternCatalog grammar;
  final CitationRegistry citations;
  final AgentLimits limits;

  int get maxTargets => limits.maxTargets;
  int get maxCitations => limits.maxEvidenceEntries;
  int get maxEntriesPerDictionary => limits.maxEntriesPerDictionary;

  Future<AgentEvidenceBundle> build({
    required List<AgentSourceInput> sources,
    required List<DictionaryInfo> dictionaries,
    int? maxSourceChars,
    bool Function()? isCancelled,
    void Function(int citations)? onProgress,
  }) async {
    citations.reset();
    final sourceEvidence = <AgentSourceEvidence>[];
    final patternEvidence = <AgentGrammarPatternEvidence>[];
    final tokenTargets = <String, _TokenTarget>{};
    final patternTargets = <_PatternTarget>[];
    var tokenCounter = 0;
    var patternCounter = 0;
    var sourceChars = 0;
    var truncated = false;
    var structureUnavailable = false;
    final dictionaryIssues = <String, AgentEvidenceDictionaryIssue>{};
    final sourceCharLimit = maxSourceChars ?? limits.maxSourceChars;

    for (final source in sources) {
      final text = _sourceText(source);
      final origin = source.isImage ? 'image_ocr' : 'user_text';
      sourceChars += text.length;
      List<Token> tokens;
      try {
        tokens = text.isEmpty
            ? const <Token>[]
            : await tokenizePort.analyze(text);
      } on AgentCapabilityException catch (error) {
        if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
        // UniDic is optional: keep looking words up / translating, but never
        // present structural analysis as if it were verified.
        tokens = const <Token>[];
        structureUnavailable = true;
      } catch (_) {
        tokens = const <Token>[];
        structureUnavailable = true;
      }
      final sourceTokens = <AgentTokenEvidence>[];
      final tokenIds = <String>[];
      for (final token in tokens) {
        final id = 't${++tokenCounter}';
        tokenIds.add(id);
        sourceTokens.add(
          AgentTokenEvidence(
            id: id,
            surface: token.surface,
            reading: token.reading,
            lemma: token.lemma,
            pos: token.posLabel,
            start: token.start,
            end: token.end,
            content: token.isContentWord,
            lookupCandidates: token.lookupCandidates.isEmpty
                ? <String>[token.surface]
                : token.lookupCandidates,
          ),
        );
        final candidates = token.lookupCandidates.isEmpty
            ? <String>[token.surface]
            : token.lookupCandidates;
        final key = candidates.join('\u0000');
        final existing = tokenTargets[key];
        if (existing == null) {
          tokenTargets[key] = _TokenTarget(
            candidates: candidates,
            tokenIds: <String>[id],
            content: token.isContentWord,
          );
        } else {
          existing.tokenIds.add(id);
        }
      }

      final matches = grammar.match(tokens);
      for (final match in matches) {
        final ids = tokenIds
            .sublist(match.startTokenIndex, match.endTokenIndex)
            .toList(growable: false);
        final patternId = 'p${++patternCounter}';
        final evidence = AgentGrammarPatternEvidence(
          id: patternId,
          surface: match.surface,
          tokenIds: ids,
          start: match.start,
          end: match.end,
        );
        patternEvidence.add(evidence);
        patternTargets.add(
          _PatternTarget(
            evidenceIndex: patternEvidence.length - 1,
            candidates: <String>[match.surface],
          ),
        );
      }
      sourceEvidence.add(
        AgentSourceEvidence(
          id: source.id,
          kind: origin,
          text: text,
          tokens: sourceTokens,
        ),
      );
    }

    final targets = <_LookupTarget>[
      ...patternTargets,
      ...tokenTargets.values.where((target) => target.content),
      ...tokenTargets.values.where((target) => !target.content),
    ];
    final selectedTargets = targets.take(maxTargets).toList(growable: false);
    if (targets.length > selectedTargets.length) truncated = true;

    void recordLookupFailure(DictionaryInfo dictionary, String message) {
      dictionaryIssues.putIfAbsent(
        dictionary.id,
        () => AgentEvidenceDictionaryIssue(
          dictionaryId: dictionary.id,
          dictionaryTitle: dictionary.title,
          code: AgentToolErrorCode.dictionaryLookupFailed.wireName,
          message: message,
        ),
      );
    }

    for (var index = 0; index < selectedTargets.length; index++) {
      selectedTargets[index].toolCallId = 'evidence-${index + 1}';
    }

    // F6: run one mode across every target before moving to the next mode.
    // Stop at the global cap, or when a mode adds no new unique citation.
    var capReached = false;
    for (final mode in _lookupModes) {
      if (capReached) break;
      var modeNew = 0;
      for (final target in selectedTargets) {
        if (isCancelled?.call() == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        final eligible = <DictionaryInfo>[
          for (final dictionary in dictionaries)
            if ((target.perDictionary[dictionary.id] ?? 0) <
                maxEntriesPerDictionary)
              dictionary,
        ];
        if (eligible.isEmpty) continue;

        final result = await _lookup(
          target.candidates,
          eligible,
          mode,
          onDictionaryError: recordLookupFailure,
        );
        for (final group in result.groups) {
          if (group.error.isNotEmpty) {
            recordLookupFailure(group.dictionary, group.error);
          }
          var remaining =
              maxEntriesPerDictionary -
              (target.perDictionary[group.dictionary.id] ?? 0);
          if (remaining <= 0) continue;
          for (final entry in group.entries) {
            if (remaining <= 0) break;
            final entryKey = entry.headword.isEmpty
                ? entry.matchedKey
                : entry.headword;
            if (entryKey.isEmpty) continue;
            final existing = citations.find(group.dictionary.id, entryKey);
            if (existing != null) {
              if (target.citationIds.add(existing.id)) {
                target.perDictionary[group.dictionary.id] =
                    (target.perDictionary[group.dictionary.id] ?? 0) + 1;
                remaining--;
              }
              continue;
            }
            if (citations.citations.length >= maxCitations) {
              truncated = true;
              capReached = true;
              break;
            }
            final citation = citations.issue(
              toolCallId: target.toolCallId,
              dictionary: group.dictionary,
              entryKey: entryKey,
              matchedKey: entry.matchedKey,
              headword: entry.headword.isEmpty ? entryKey : entry.headword,
              snippet: htmlToPlainText(
                entry.html,
                maxLength: limits.maxSnippetChars,
              ),
            );
            target.citationIds.add(citation.id);
            target.perDictionary[group.dictionary.id] =
                (target.perDictionary[group.dictionary.id] ?? 0) + 1;
            modeNew++;
            remaining--;
            onProgress?.call(citations.citations.length);
            if (citations.citations.length >= maxCitations) {
              truncated = true;
              capReached = true;
              break;
            }
          }
          if (capReached) break;
        }
        if (capReached) break;
      }
      if (capReached) break;
      if (modeNew == 0) break;
    }

    final tokensWithCitations = <String, List<String>>{};
    for (final target in selectedTargets) {
      if (target is _TokenTarget) {
        final ids = target.citationIds.toList(growable: false);
        for (final tokenId in target.tokenIds) {
          tokensWithCitations[tokenId] = ids;
        }
      } else if (target is _PatternTarget) {
        final current = patternEvidence[target.evidenceIndex];
        patternEvidence[target.evidenceIndex] = AgentGrammarPatternEvidence(
          id: current.id,
          surface: current.surface,
          tokenIds: current.tokenIds,
          start: current.start,
          end: current.end,
          citationIds: target.citationIds.toList(growable: false),
        );
      }
    }

    final finalSources = <AgentSourceEvidence>[
      for (final source in sourceEvidence)
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
                citationIds: tokensWithCitations[token.id] ?? const <String>[],
              ),
          ],
        ),
    ];

    if (sourceChars > sourceCharLimit) truncated = true;
    final sortedCitations = citations.citations.toList(growable: false)
      ..sort((a, b) {
        final order = a.dictionaryOrder.compareTo(b.dictionaryOrder);
        if (order != 0) return order;
        return a.entryKey.compareTo(b.entryKey);
      });
    return AgentEvidenceBundle(
      sources: finalSources,
      patterns: patternEvidence,
      citations: sortedCitations,
      truncated: truncated,
      structureUnavailable: structureUnavailable,
      dictionaryIssues: dictionaryIssues.values.toList(growable: false),
      budget: AgentEvidenceBudget(
        sourceChars: sourceChars,
        uniqueTargets: selectedTargets.length,
        citations: sortedCitations.length,
        maxTargets: maxTargets,
        maxCitations: maxCitations,
      ),
    );
  }

  /// F7: bounded supplementary lookup for traceable coverage queries. Uses the
  /// same mode order and per-dictionary cap as [build]. Existing citations are
  /// linked to the query but do not consume the global citation slots.
  Future<Map<String, List<AgentCitation>>> lookupExtraQueries({
    required List<String> queries,
    required List<DictionaryInfo> dictionaries,
    required int maxNewCitations,
    Set<String> excludedKeys = const <String>{},
    bool Function()? isCancelled,
    void Function(int citations)? onProgress,
    void Function(DictionaryInfo dictionary, String message)? onDictionaryError,
  }) async {
    final result = <String, List<AgentCitation>>{};
    final order = <String>[];
    final seen = <String>{};
    for (final raw in queries) {
      final query = raw.trim();
      if (query.isEmpty || !seen.add(query)) continue;
      order.add(query);
      result[query] = <AgentCitation>[];
    }
    if (order.isEmpty || dictionaries.isEmpty || maxNewCitations <= 0) {
      return result;
    }

    final perQuery = <String, Map<String, int>>{
      for (final query in order) query: <String, int>{},
    };
    final queryIds = <String, Set<String>>{
      for (final query in order) query: <String>{},
    };
    var newCount = 0;
    var capReached = false;

    for (final mode in _lookupModes) {
      if (capReached) break;
      var modeNew = 0;
      for (var queryIndex = 0; queryIndex < order.length; queryIndex++) {
        if (isCancelled?.call() == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        final query = order[queryIndex];
        final counts = perQuery[query]!;
        final eligible = <DictionaryInfo>[
          for (final dictionary in dictionaries)
            if ((counts[dictionary.id] ?? 0) < maxEntriesPerDictionary)
              dictionary,
        ];
        if (eligible.isEmpty) continue;
        final lookup = await _lookup(
          <String>[query],
          eligible,
          mode,
          onDictionaryError: onDictionaryError,
        );
        for (final group in lookup.groups) {
          if (group.error.isNotEmpty) {
            onDictionaryError?.call(group.dictionary, group.error);
          }
          var remaining =
              maxEntriesPerDictionary - (counts[group.dictionary.id] ?? 0);
          if (remaining <= 0) continue;
          for (final entry in group.entries) {
            if (remaining <= 0) break;
            final entryKey = entry.headword.isEmpty
                ? entry.matchedKey
                : entry.headword;
            if (entryKey.isEmpty) continue;
            if (excludedKeys.contains(
              '${group.dictionary.id}\u0000$entryKey',
            )) {
              continue;
            }
            final existing = citations.find(group.dictionary.id, entryKey);
            if (existing != null) {
              if (queryIds[query]!.add(existing.id)) {
                result[query]!.add(existing);
                counts[group.dictionary.id] =
                    (counts[group.dictionary.id] ?? 0) + 1;
                remaining--;
              }
              continue;
            }
            if (newCount >= maxNewCitations) {
              capReached = true;
              break;
            }
            final citation = citations.issue(
              toolCallId: 'coverage-${queryIndex + 1}',
              dictionary: group.dictionary,
              entryKey: entryKey,
              matchedKey: entry.matchedKey,
              headword: entry.headword.isEmpty ? entryKey : entry.headword,
              snippet: htmlToPlainText(
                entry.html,
                maxLength: limits.maxSnippetChars,
              ),
            );
            if (queryIds[query]!.add(citation.id)) {
              result[query]!.add(citation);
            }
            counts[group.dictionary.id] =
                (counts[group.dictionary.id] ?? 0) + 1;
            remaining--;
            newCount++;
            modeNew++;
            onProgress?.call(citations.citations.length);
            if (newCount >= maxNewCitations) {
              capReached = true;
              break;
            }
          }
          if (capReached) break;
        }
        if (capReached) break;
      }
      if (capReached) break;
      if (modeNew == 0) break;
    }
    return result;
  }

  Future<LookupResult> _lookup(
    List<String> candidates,
    List<DictionaryInfo> dictionaries,
    LookupMatchMode mode, {
    void Function(DictionaryInfo dictionary, String message)? onDictionaryError,
  }) async {
    try {
      return await lookupPort.lookup(
        LookupRequest(
          query: candidates.first,
          rawCandidates: candidates,
          dictionaries: dictionaries,
          matchMode: mode,
          maxEntriesPerDictionary: maxEntriesPerDictionary,
          suggestionLimit: 5,
        ),
      );
    } catch (_) {
      for (final dictionary in dictionaries) {
        onDictionaryError?.call(dictionary, '词典查询失败');
      }
      return LookupResult(
        query: candidates.first,
        candidates: candidates,
        groups: const <DictionaryLookupGroup>[],
      );
    }
  }

  static String _sourceText(AgentSourceInput source) {
    if (source.isImage) return source.selectedVariant?.text ?? '';
    return source.text;
  }
}

abstract class _LookupTarget {
  List<String> get candidates;

  var toolCallId = '';

  final Set<String> citationIds = <String>{};
  final Map<String, int> perDictionary = <String, int>{};
}

class _TokenTarget extends _LookupTarget {
  _TokenTarget({
    required this.candidates,
    required this.tokenIds,
    required this.content,
  });

  @override
  final List<String> candidates;
  final List<String> tokenIds;
  final bool content;
}

class _PatternTarget extends _LookupTarget {
  _PatternTarget({required this.evidenceIndex, required this.candidates});

  final int evidenceIndex;
  @override
  final List<String> candidates;
}
