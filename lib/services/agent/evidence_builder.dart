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
    final dictionaryOrder = _dictionaryRanks(dictionaries);

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
        // Punctuation/symbols are shown as context but never become lookup
        // targets. They almost always miss and used to consume both a target
        // slot and citation budget.
        if (token.isPunctuationOrSymbol) continue;
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
    // Content words first: the short-text citation cap is derived from their
    // count, so grammar patterns/function words must not consume the budget
    // before the words the user is reading.
    final targets = <_LookupTarget>[
      ...tokenTargets.values.where((target) => target.content),
      ...rawOnlyTargets,
      ...patternTargets,
      ...tokenTargets.values.where((target) => !target.content),
    ];
    final selectedTargets = targets.take(maxTargets).toList(growable: false);
    if (targets.length > selectedTargets.length) truncated = true;

    // Short inputs should not prefetch the full 60-entry budget. The breadth
    // pass grants one entry per content-word target per dictionary; for a
    // short text that is the natural ceiling. Function words/patterns may
    // still be looked up, but they cannot push the bundle to 60 on their own.
    final contentTargetCount = selectedTargets
        .whereType<_TokenTarget>()
        .where((target) => target.content)
        .length;
    final shortText = selectedTargets.length < limits.shortTextTargetThreshold;
    final shortTextTargetCount = contentTargetCount > 0
        ? contentTargetCount
        : selectedTargets.length;
    final shortTextLimit = shortTextTargetCount * dictionaries.length;
    final citationLimit = shortText
        ? (shortTextLimit < maxCitations ? shortTextLimit : maxCitations)
        : maxCitations;

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
      selectedTargets[index].ordinal = index;
    }

    // Breadth pass: one best entry per target per dictionary. The default
    // depth pass is off, so this is the complete initial evidence set; extra
    // senses are only fetched by an explicit follow-up.
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
      final groups = _groupsInRotation(
        result.groups,
        target.ordinal,
        dictionaryOrder,
      );
      // Breadth = one best entry per dictionary for this target. Previously it
      // stopped after the first dictionary, which made the first dictionary
      // dominate short inputs once the depth pass filled the rest.
      for (final group in groups) {
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
            break;
          }
          if (citations.count >= citationLimit) {
            if (citationLimit == maxCitations) truncated = true;
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
          if (citations.count >= citationLimit) {
            if (citationLimit == maxCitations) truncated = true;
            return true;
          }
          // One entry per dictionary; continue to the next dictionary.
          break;
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
      final groups = _groupsInRotation(
        result.groups,
        target.ordinal,
        dictionaryOrder,
      );
      for (final group in groups) {
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
          if (citations.count >= citationLimit) {
            if (citationLimit == maxCitations) truncated = true;
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
          if (citations.count >= citationLimit) {
            if (citationLimit == maxCitations) truncated = true;
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
        if (limits.enableDepthPass && result.hasHits) {
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

    var modeIndex = 0;
    for (final mode in _lookupModes) {
      if (capReached) break;
      if (isCancelled?.call() == true) {
        throw const AgentCapabilityException(
          AgentToolErrorCode.toolCancelled,
          '已取消',
        );
      }
      if (citations.count >= citationLimit) {
        if (citationLimit == maxCitations) truncated = true;
        break;
      }
      // Exact runs for every target. Later modes run only for targets that
      // still have no citation, so once exact/prefix finds a result we stop
      // paying for suffix/incremental scans on that target.
      final isFirstMode = modeIndex == 0;
      final batchTargets = <_LookupTarget>[];
      final batchRequests = <LookupRequest>[];
      for (final target in selectedTargets) {
        if (isCancelled?.call() == true) {
          throw const AgentCapabilityException(
            AgentToolErrorCode.toolCancelled,
            '已取消',
          );
        }
        if (!isFirstMode &&
            (!target.content || target.citationIds.isNotEmpty)) {
          continue;
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
      modeIndex++;
      if (capReached) break;
    }

    // Depth is opt-in. The default pipeline stops after the one-entry breadth
    // pass; the second/third entry is only useful for an explicit multi-sense
    // follow-up and otherwise just bloats the prompt.
    if (limits.enableDepthPass &&
        !capReached &&
        citations.count < citationLimit) {
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
    if (limits.enableDepthPass &&
        !capReached &&
        citations.count < citationLimit) {
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
        maxCitations: citationLimit,
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
    int perDictionaryLimit = 1,
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
    final dictionaryOrder = _dictionaryRanks(dictionaries);
    if (order.isEmpty || dictionaries.isEmpty || maxNewCitations <= 0) {
      return result;
    }

    final perQuery = <String, Map<String, int>>{
      for (final query in order) query: <String, int>{},
    };
    final queryIds = <String, Set<String>>{
      for (final query in order) query: <String>{},
    };
    // Coverage supplements are normally breadth work (one entry per
    // dictionary per query). An explicit sense/usage/example gap may request
    // a second entry for that query, which is the on-demand depth path.
    final effectivePerDictionaryLimit = perDictionaryLimit < 1
        ? 1
        : perDictionaryLimit;
    var newCount = 0;
    var capReached = false;
    final batchSize = limits.lookupBatchSize <= 0 ? 1 : limits.lookupBatchSize;
    final batchQueries = <String>[];
    final batchQueryIndexes = <int>[];
    final batchRequests = <LookupRequest>[];

    void applyLookup(String query, int queryIndex, LookupResult lookup) {
      final counts = perQuery[query]!;
      final groups = _groupsInRotation(
        lookup.groups,
        queryIndex,
        dictionaryOrder,
      );
      for (final group in groups) {
        if (group.error.isNotEmpty) {
          onDictionaryError?.call(group.dictionary, group.error);
        }
        var remaining =
            effectivePerDictionaryLimit - (counts[group.dictionary.id] ?? 0);
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
            if ((counts[dictionary.id] ?? 0) < effectivePerDictionaryLimit)
              dictionary,
        ];
        if (eligible.isEmpty) continue;
        batchQueries.add(query);
        batchQueryIndexes.add(queryIndex);
        batchRequests.add(
          _requestFor(
            <String>[query],
            eligible,
            mode,
            maxEntriesPerDictionary: effectivePerDictionaryLimit,
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

  /// Content words and grammar patterns may need fuzzy modes; particles and
  /// other function words are exact-only so they cannot trigger expensive
  /// suffix/incremental scans.
  bool get content;

  var toolCallId = '';
  var ordinal = 0;

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
  @override
  final bool content;
}

class _PatternTarget extends _LookupTarget {
  _PatternTarget({required this.evidenceIndex, required this.candidates});

  final int evidenceIndex;
  @override
  final List<String> candidates;

  @override
  bool get content => true;
}

String _targetKey(List<String> candidates) => candidates.join('\u0000');

/// Rank by the user-visible [DictionaryInfo.order], not by the caller's list
/// position. The Agent UI supplies a sorted list, but tests and integrations
/// may pass dictionaries in another order.
Map<String, int> _dictionaryRanks(List<DictionaryInfo> dictionaries) {
  final ordered = List<DictionaryInfo>.of(dictionaries)
    ..sort((left, right) => left.order.compareTo(right.order));
  return <String, int>{
    for (var index = 0; index < ordered.length; index++)
      ordered[index].id: index,
  };
}

/// Rotates lookup groups by the target/query ordinal so the global citation
/// budget is not consumed by the first dictionary in user order.
///
/// The result is a stable permutation: groups are ordered by their position in
/// the user dictionary list, starting at `start % dictionaryCount` and wrapping
/// around. Unknown groups keep their original relative order after known ones.
List<DictionaryLookupGroup> _groupsInRotation(
  List<DictionaryLookupGroup> groups,
  int start,
  Map<String, int> dictionaryOrder,
) {
  if (groups.length <= 1 || dictionaryOrder.isEmpty) return groups;
  final count = dictionaryOrder.length;
  final rotation = start % count;
  final indexes = List<int>.generate(groups.length, (index) => index);
  indexes.sort((left, right) {
    final leftOrder =
        dictionaryOrder[groups[left].dictionary.id] ?? (count + left);
    final rightOrder =
        dictionaryOrder[groups[right].dictionary.id] ?? (count + right);
    final leftRotated = (leftOrder - rotation) % count;
    final rightRotated = (rightOrder - rotation) % count;
    if (leftRotated != rightRotated) {
      return leftRotated.compareTo(rightRotated);
    }
    return left.compareTo(right);
  });
  return <DictionaryLookupGroup>[for (final index in indexes) groups[index]];
}

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
