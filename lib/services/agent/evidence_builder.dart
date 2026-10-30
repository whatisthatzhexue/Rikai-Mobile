import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
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

/// Builds one bounded evidence bundle for all sources in a run.
class EvidenceBuilder {
  const EvidenceBuilder({
    required this.tokenizePort,
    required this.lookupPort,
    required this.grammar,
    required this.citations,
    this.maxTargets = 120,
    this.maxCitations = 60,
    this.maxEntriesPerDictionary = 3,
  });

  final TokenizePort tokenizePort;
  final LookupPort lookupPort;
  final GrammarPatternCatalog grammar;
  final CitationRegistry citations;
  final int maxTargets;
  final int maxCitations;
  final int maxEntriesPerDictionary;

  Future<AgentEvidenceBundle> build({
    required List<AgentSourceInput> sources,
    required List<DictionaryInfo> dictionaries,
    int maxSourceChars = 6000,
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

    var targetIndex = 0;
    for (final target in selectedTargets) {
      if (isCancelled?.call() == true) {
        throw const AgentCapabilityException(
          AgentToolErrorCode.toolCancelled,
          '已取消',
        );
      }
      targetIndex++;
      final toolCallId = 'evidence-$targetIndex';
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

      final result = await _lookup(
        target.candidates,
        dictionaries,
        LookupMatchMode.exact,
        onDictionaryError: recordLookupFailure,
      );
      final fallback = result.hasHits
          ? result
          : await _lookup(
              target.candidates,
              dictionaries,
              LookupMatchMode.prefix,
              onDictionaryError: recordLookupFailure,
            );
      final ids = <String>[];
      for (final group in fallback.groups) {
        if (group.error.isNotEmpty) {
          recordLookupFailure(group.dictionary, group.error);
        }
        for (final entry in group.entries) {
          final entryKey = entry.headword.isEmpty
              ? entry.matchedKey
              : entry.headword;
          if (entryKey.isEmpty) continue;
          final existing = citations.find(group.dictionary.id, entryKey);
          if (existing != null) {
            if (!ids.contains(existing.id)) ids.add(existing.id);
            continue;
          }
          if (citations.citations.length >= maxCitations) {
            truncated = true;
            break;
          }
          final citation = citations.issue(
            toolCallId: toolCallId,
            dictionary: group.dictionary,
            entryKey: entryKey,
            matchedKey: entry.matchedKey,
            headword: entry.headword.isEmpty ? entryKey : entry.headword,
            snippet: htmlToPlainText(entry.html, maxLength: 400),
          );
          ids.add(citation.id);
        }
      }
      if (target is _TokenTarget) {
        for (final tokenId in target.tokenIds) {
          target.citationIds[tokenId] = ids;
        }
      } else if (target is _PatternTarget) {
        final current = patternEvidence[target.evidenceIndex];
        patternEvidence[target.evidenceIndex] = AgentGrammarPatternEvidence(
          id: current.id,
          surface: current.surface,
          tokenIds: current.tokenIds,
          start: current.start,
          end: current.end,
          citationIds: ids,
        );
      }
      onProgress?.call(citations.citations.length);
    }

    final tokensWithCitations = <String, List<String>>{};
    for (final target in tokenTargets.values) {
      tokensWithCitations.addAll(target.citationIds);
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

    if (sourceChars > maxSourceChars) truncated = true;
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
  const _LookupTarget();

  List<String> get candidates;
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
  final Map<String, List<String>> citationIds = <String, List<String>>{};
}

class _PatternTarget extends _LookupTarget {
  const _PatternTarget({required this.evidenceIndex, required this.candidates});

  final int evidenceIndex;
  @override
  final List<String> candidates;
}
