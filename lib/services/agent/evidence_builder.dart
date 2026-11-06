import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_pitch.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/models/dict_info.dart';
import '../../core/models/lookup_match_mode.dart';
import '../../core/models/lookup_models.dart';
import '../../core/models/lookup_request.dart';
import '../../core/models/token.dart';
import '../../core/utils/html_text.dart';
import '../../core/utils/script_language.dart';
import '../../core/utils/text_normalizer.dart';
import '../mecab/unidic_accent_parser.dart';
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
    final pitchAccents = <String, AgentPitchAccent>{};
    final tokenTargets = <String, _TokenTarget>{};
    final rawTargets = <_TokenTarget>[];
    final rawKeys = <String>{};
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
      final useJapaneseTokenizer = shouldUseJapaneseTokenizer(text);
      List<Token> tokens;
      try {
        tokens = text.isEmpty || !useJapaneseTokenizer
            ? const <Token>[]
            : await tokenizePort.analyze(text);
        if (!useJapaneseTokenizer && text.trim().isNotEmpty) {
          // Clearly non-Japanese source: keep bounded raw-surface lookup, but
          // never claim UniDic token/grammar structure for it.
          structureUnavailable = true;
        }
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
        final pitch = parseUnidicAccent(
          accentType: token.accentTypeRaw,
          reading: token.reading,
        );
        if (pitch != null) pitchAccents[id] = pitch;
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

      // UniDic is optional. When it is unavailable or returns no tokens, keep
      // word-level lookup alive with bounded raw-surface targets instead of
      // silently producing an empty evidence bundle.
      if (text.trim().isNotEmpty && tokens.isEmpty) {
        structureUnavailable = true;
        if (rawTargets.length < maxTargets) {
          for (final candidates in _rawSurfaceCandidates(
            text,
            maxTargets - rawTargets.length,
          )) {
            final key = candidates.join('\u0000');
            if (!rawKeys.add(key)) continue;
            rawTargets.add(
              _TokenTarget(
                candidates: candidates,
                tokenIds: const <String>[],
                content: true,
              ),
            );
            if (rawTargets.length >= maxTargets) break;
          }
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

    final rawOnlyTargets = <_TokenTarget>[
      for (final target in rawTargets)
        if (!tokenTargets.containsKey(_targetKey(target.candidates))) target,
    ];
    final targets = <_LookupTarget>[
      ...patternTargets,
      ...tokenTargets.values.where((target) => target.content),
      ...rawOnlyTargets,
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

    // F6 breadth pass: give every target at most one citation before granting
    // extra senses/dictionaries. The old target-by-target 3-entry fetch let
    // early words consume the global citation budget, so later targets (and
    // the model) received too little useful evidence.
    var capReached = false;
    final batchSize = limits.lookupBatchSize <= 0 ? 1 : limits.lookupBatchSize;
    final storedResults = <_StoredLookup>[];

    void recordGroupErrors(LookupResult result) {
      for (final group in result.groups) {
        if (group.error.isNotEmpty) {
          recordLookupFailure(group.dictionary, group.error);
        }
      }
    }

    bool applyBreadth(_LookupTarget target, LookupResult result) {
      recordGroupErrors(result);
      if (target.citationIds.isNotEmpty) return false;
      for (final group in result.groups) {
        var remaining =
            maxEntriesPerDictionary -
            (target.perDictionary[group.dictionary.id] ?? 0);
        if (remaining <= 0) continue;
        for (final entry in group.entries) {
          final entryKey = entry.headword.isEmpty
              ? entry.matchedKey
              : entry.headword;
          if (entryKey.isEmpty) continue;
          final existing = citations.find(group.dictionary.id, entryKey);
          if (existing != null) {
            target.citationIds.add(existing.id);
            target.perDictionary[group.dictionary.id] =
                (target.perDictionary[group.dictionary.id] ?? 0) + 1;
            return false;
          }
          if (citations.count >= maxCitations) {
            truncated = true;
            return true;
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
          onProgress?.call(citations.count);
          if (citations.count >= maxCitations) {
            truncated = true;
            return true;
          }
          // One citation per target is enough for the breadth pass.
          return false;
        }
      }
      return false;
    }

    bool applyDepth(
      _LookupTarget target,
      LookupResult result, {
      required bool firstPerDictionaryOnly,
    }) {
      recordGroupErrors(result);
      for (final group in result.groups) {
        final current = target.perDictionary[group.dictionary.id] ?? 0;
        if (firstPerDictionaryOnly && current > 0) continue;
        var remaining = maxEntriesPerDictionary - current;
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
            if (firstPerDictionaryOnly) break;
            continue;
          }
          if (citations.count >= maxCitations) {
            truncated = true;
            return true;
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
          remaining--;
          onProgress?.call(citations.count);
          if (citations.count >= maxCitations) {
            truncated = true;
            return true;
          }
          if (firstPerDictionaryOnly) break;
        }
      }
      return false;
    }

    Future<void> flushBreadthBatch(
      List<_LookupTarget> targets,
      List<LookupRequest> requests,
    ) async {
      if (requests.isEmpty) return;
      final results = await _lookupBatch(
        List<LookupRequest>.of(requests),
        onDictionaryError: recordLookupFailure,
      );
      for (var index = 0; index < results.length; index++) {
        final result = results[index];
        if (result.hasHits) {
          storedResults.add(
            _StoredLookup(target: targets[index], result: result),
          );
        }
        if (applyBreadth(targets[index], result)) {
          capReached = true;
          break;
        }
      }
    }

    for (final mode in _lookupModes) {
      if (capReached) break;
      if (isCancelled?.call() == true) {
        throw const AgentCapabilityException(
          AgentToolErrorCode.toolCancelled,
          '已取消',
        );
      }
      if (citations.count >= maxCitations) {
        truncated = true;
        break;
      }
      // Query every target in every mode so the depth pass can reuse later
      // modes (prefix/suffix/incremental and other dictionaries). The breadth
      // pass itself still issues at most one citation per target.
      final batchTargets = <_LookupTarget>[];
      final batchRequests = <LookupRequest>[];
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

        batchTargets.add(target);
        batchRequests.add(_requestFor(target.candidates, eligible, mode));
        if (batchRequests.length >= batchSize) {
          await flushBreadthBatch(batchTargets, batchRequests);
          batchTargets.clear();
          batchRequests.clear();
          if (capReached) break;
        }
      }
      if (!capReached && batchRequests.isNotEmpty) {
        await flushBreadthBatch(batchTargets, batchRequests);
      }
      if (capReached) break;
    }

    // Depth pass, the first round: add one entry from each dictionary that is
    // not represented yet. This keeps multi-dictionary evidence diverse before
    // granting a second/third sense from the same dictionary.
    if (!capReached && citations.count < maxCitations) {
      for (final stored in storedResults) {
        if (isCancelled?.call() == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        if (applyDepth(
          stored.target,
          stored.result,
          firstPerDictionaryOnly: true,
        )) {
          capReached = true;
          break;
        }
      }
    }
    // Depth pass, the second round: use the remaining budget for extra senses
    // up to the per-target/per-dictionary cap.
    if (!capReached && citations.count < maxCitations) {
      for (final stored in storedResults) {
        if (isCancelled?.call() == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        if (applyDepth(
          stored.target,
          stored.result,
          firstPerDictionaryOnly: false,
        )) {
          capReached = true;
          break;
        }
      }
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
      pitchAccents: Map<String, AgentPitchAccent>.unmodifiable(pitchAccents),
      budget: AgentEvidenceBudget(
        sourceChars: sourceChars,
        uniqueTargets: selectedTargets.length,
        targetsWithCitations: selectedTargets
            .where((target) => target.citationIds.isNotEmpty)
            .length,
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
    // Coverage supplements are breadth work: one entry per dictionary per
    // missing query is enough to fill a gap. Additional senses are left to
    // the model's next MISSING query instead of consuming several slots now.
    const perDictionaryLimit = 1;
    var newCount = 0;
    var capReached = false;
    final batchSize = limits.lookupBatchSize <= 0 ? 1 : limits.lookupBatchSize;
    final batchQueries = <String>[];
    final batchQueryIndexes = <int>[];
    final batchRequests = <LookupRequest>[];

    void applyLookup(String query, int queryIndex, LookupResult lookup) {
      final counts = perQuery[query]!;
      for (final group in lookup.groups) {
        if (group.error.isNotEmpty) {
          onDictionaryError?.call(group.dictionary, group.error);
        }
        var remaining = perDictionaryLimit - (counts[group.dictionary.id] ?? 0);
        if (remaining <= 0) continue;
        for (final entry in group.entries) {
          if (remaining <= 0) break;
          final entryKey = entry.headword.isEmpty
              ? entry.matchedKey
              : entry.headword;
          if (entryKey.isEmpty) continue;
          if (excludedKeys.contains('${group.dictionary.id}\u0000$entryKey')) {
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
            return;
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
          counts[group.dictionary.id] = (counts[group.dictionary.id] ?? 0) + 1;
          remaining--;
          newCount++;
          onProgress?.call(citations.count);
          if (newCount >= maxNewCitations) {
            capReached = true;
            return;
          }
        }
      }
    }

    Future<void> flushBatch() async {
      if (batchRequests.isEmpty) return;
      final results = await _lookupBatch(
        List<LookupRequest>.of(batchRequests),
        onDictionaryError: onDictionaryError,
      );
      for (var index = 0; index < results.length; index++) {
        applyLookup(
          batchQueries[index],
          batchQueryIndexes[index],
          results[index],
        );
        if (capReached) break;
      }
      batchQueries.clear();
      batchQueryIndexes.clear();
      batchRequests.clear();
    }

    for (final mode in _lookupModes) {
      if (capReached) break;
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
            if ((counts[dictionary.id] ?? 0) < perDictionaryLimit) dictionary,
        ];
        if (eligible.isEmpty) continue;
        batchQueries.add(query);
        batchQueryIndexes.add(queryIndex);
        batchRequests.add(
          _requestFor(
            <String>[query],
            eligible,
            mode,
            maxEntriesPerDictionary: perDictionaryLimit,
          ),
        );
        if (batchRequests.length >= batchSize) {
          await flushBatch();
          if (capReached) break;
        }
      }
      if (!capReached) await flushBatch();
      if (capReached) break;
    }
    return result;
  }

  LookupRequest _requestFor(
    List<String> candidates,
    List<DictionaryInfo> dictionaries,
    LookupMatchMode mode, {
    int? maxEntriesPerDictionary,
  }) {
    return LookupRequest(
      query: candidates.first,
      rawCandidates: candidates,
      dictionaries: dictionaries,
      matchMode: mode,
      maxEntriesPerDictionary:
          maxEntriesPerDictionary ?? this.maxEntriesPerDictionary,
      suggestionLimit: 5,
    );
  }

  Future<LookupResult> _lookupRequest(
    LookupRequest request, {
    void Function(DictionaryInfo dictionary, String message)? onDictionaryError,
  }) async {
    try {
      return await lookupPort.lookup(request);
    } catch (_) {
      for (final dictionary in request.dictionaries) {
        onDictionaryError?.call(dictionary, '词典查询失败');
      }
      return LookupResult(
        query: request.query,
        candidates: request.rawCandidates,
        groups: const <DictionaryLookupGroup>[],
      );
    }
  }

  Future<List<LookupResult>> _lookupBatch(
    List<LookupRequest> requests, {
    void Function(DictionaryInfo dictionary, String message)? onDictionaryError,
  }) async {
    if (requests.isEmpty) return const <LookupResult>[];
    final port = lookupPort;
    if (port is BatchLookupPort) {
      try {
        return await (port as BatchLookupPort).lookupMany(requests);
      } catch (_) {
        for (final request in requests) {
          for (final dictionary in request.dictionaries) {
            onDictionaryError?.call(dictionary, '词典查询失败');
          }
        }
        return <LookupResult>[
          for (final request in requests)
            LookupResult(
              query: request.query,
              candidates: request.rawCandidates,
              groups: const <DictionaryLookupGroup>[],
            ),
        ];
      }
    }
    // Fakes and integrations that only implement LookupPort keep the old
    // one-request-at-a-time behavior.
    final results = <LookupResult>[];
    for (final request in requests) {
      results.add(
        await _lookupRequest(request, onDictionaryError: onDictionaryError),
      );
    }
    return results;
  }

  static String _sourceText(AgentSourceInput source) {
    if (source.isImage) return source.selectedVariant?.text ?? '';
    return source.text;
  }
}

class _StoredLookup {
  const _StoredLookup({required this.target, required this.result});

  final _LookupTarget target;
  final LookupResult result;
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

String _targetKey(List<String> candidates) => candidates.join('\u0000');

/// Bounded word-like candidates for the UniDic-unavailable fallback.
///
/// Japanese has no spaces, so this deliberately mixes whole punctuation/line
/// chunks with short bounded windows. It is best-effort only: it never invents
/// tokens, never claims structure, and is capped by [maxTargets].
List<List<String>> _rawSurfaceCandidates(String text, int limit) {
  if (limit <= 0) return const <List<String>>[];
  final normalized = normalizeLookupText(text);
  final results = <List<String>>[];
  final seen = <String>{};

  void add(String raw) {
    if (results.length >= limit) return;
    final surface = raw.trim();
    if (surface.length < 2) return;
    final candidates = lookupCandidatesFor(<String>[surface]);
    if (candidates.isEmpty) return;
    if (!seen.add(_targetKey(candidates))) return;
    results.add(candidates);
  }

  for (final chunk in normalized.split(_rawSurfaceSplit)) {
    final value = chunk.trim();
    if (value.length < 2) continue;
    if (value.length <= 12) add(value);
    final maxWindow = value.length < 6 ? value.length : 6;
    for (var length = maxWindow; length >= 2; length--) {
      for (var start = 0; start + length <= value.length; start++) {
        add(value.substring(start, start + length));
        if (results.length >= limit) return results;
      }
    }
  }
  return results;
}

final _rawSurfaceSplit = RegExp(
  r'[\s、。，．・：；！？「」『』（）［］｛｝【】〈〉《》〔〕…‥〜～,.;:!?/\\|]+',
);
