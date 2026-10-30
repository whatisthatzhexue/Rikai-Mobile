import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../core/models/token.dart';

class GrammarPattern {
  const GrammarPattern({
    required this.id,
    required this.surface,
    required this.tokenPattern,
    this.kind = '',
    this.note = '',
  });

  final String id;
  final String surface;
  final List<String> tokenPattern;
  final String kind;
  final String note;

  factory GrammarPattern.fromJson(Map<String, Object?> json) {
    final rawPattern = json['token_pattern'];
    return GrammarPattern(
      id: json['id']?.toString() ?? '',
      surface: json['surface']?.toString() ?? '',
      tokenPattern: rawPattern is List
          ? rawPattern.whereType<String>().toList(growable: false)
          : const <String>[],
      kind: json['kind']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
    );
  }
}

class GrammarPatternMatch {
  const GrammarPatternMatch({
    required this.pattern,
    required this.startTokenIndex,
    required this.endTokenIndex,
    required this.start,
    required this.end,
  });

  final GrammarPattern pattern;
  final int startTokenIndex;
  final int endTokenIndex;
  final int start;
  final int end;

  String get surface => pattern.surface;
}

class GrammarPatternCatalog {
  GrammarPatternCatalog(Iterable<GrammarPattern> patterns)
    : patterns = List<GrammarPattern>.unmodifiable(
        patterns.where((pattern) => pattern.tokenPattern.isNotEmpty).toList()
          ..sort(
            (a, b) => b.tokenPattern.length.compareTo(a.tokenPattern.length),
          ),
      );

  final List<GrammarPattern> patterns;

  factory GrammarPatternCatalog.fromJson(Map<String, Object?> json) {
    final rawPatterns = json['patterns'];
    return GrammarPatternCatalog(
      rawPatterns is List
          ? rawPatterns.whereType<Map>().map(
              (value) => GrammarPattern.fromJson(
                value.map((key, item) => MapEntry(key.toString(), item)),
              ),
            )
          : const <GrammarPattern>[],
    );
  }

  /// Longest-match-first, non-overlapping matches.
  List<GrammarPatternMatch> match(List<Token> tokens) {
    final matches = <GrammarPatternMatch>[];
    var index = 0;
    while (index < tokens.length) {
      GrammarPattern? best;
      for (final pattern in patterns) {
        if (index + pattern.tokenPattern.length > tokens.length) continue;
        var matched = true;
        for (var offset = 0; offset < pattern.tokenPattern.length; offset++) {
          final part = pattern.tokenPattern[offset];
          final token = tokens[index + offset];
          if (token.surface != part && token.lemma != part) {
            matched = false;
            break;
          }
        }
        if (matched) {
          best = pattern;
          break;
        }
      }
      if (best == null) {
        index++;
        continue;
      }
      final endIndex = index + best.tokenPattern.length;
      matches.add(
        GrammarPatternMatch(
          pattern: best,
          startTokenIndex: index,
          endTokenIndex: endIndex,
          start: tokens[index].start,
          end: tokens[endIndex - 1].end,
        ),
      );
      index = endIndex;
    }
    return matches;
  }
}

Future<GrammarPatternCatalog> loadGrammarPatterns({
  AssetBundle? bundle,
  String path = 'assets/agent/grammar_patterns_ja.json',
}) async {
  try {
    final raw = await (bundle ?? rootBundle).loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return GrammarPatternCatalog.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
  } catch (_) {
    // Missing/invalid asset is non-fatal; the orchestrator can still run
    // token-level lookups without grammar patterns.
  }
  return GrammarPatternCatalog(const <GrammarPattern>[]);
}
