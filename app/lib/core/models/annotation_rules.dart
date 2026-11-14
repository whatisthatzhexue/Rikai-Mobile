import 'token.dart';

/// Where an annotation rule set may be applied.
enum AnnotationTarget {
  reader('reader'),
  photo('photo'),
  corpus('corpus');

  const AnnotationTarget(this.wireName);

  final String wireName;

  static AnnotationTarget? fromWire(Object? value) {
    for (final target in values) {
      if (target.wireName == value) return target;
    }
    return null;
  }
}

/// Decoration kinds supported by the safe annotation AST v1.
enum AnnotationKind {
  ruby('ruby'),
  pitch('pitch'),
  bold('bold'),
  underline('underline');

  const AnnotationKind(this.wireName);

  final String wireName;

  static AnnotationKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// One safe `when` condition. All populated fields must match (AND); list
/// values are OR alternatives. There is deliberately no expression language.
class AnnotationCondition {
  const AnnotationCondition({
    this.pos1 = const <String>[],
    this.pos2 = const <String>[],
    this.pos3 = const <String>[],
    this.pos4 = const <String>[],
    this.lemma = const <String>[],
    this.surface = const <String>[],
    this.hasReading,
    this.hasPitch,
    this.target,
  });

  final List<String> pos1;
  final List<String> pos2;
  final List<String> pos3;
  final List<String> pos4;
  final List<String> lemma;
  final List<String> surface;
  final bool? hasReading;
  final bool? hasPitch;
  final AnnotationTarget? target;

  bool matches(
    Token token,
    AnnotationTarget activeTarget, {
    required bool hasPitch,
  }) {
    if (!_matchesList(pos1, token.pos1)) return false;
    if (!_matchesList(pos2, token.pos2)) return false;
    if (!_matchesList(pos3, token.pos3)) return false;
    if (!_matchesList(pos4, token.pos4)) return false;
    if (!_matchesList(lemma, token.lemma)) return false;
    if (!_matchesList(surface, token.surface)) return false;
    if (hasReading != null && hasReading != token.hasDistinctReading) {
      return false;
    }
    if (this.hasPitch != null && this.hasPitch != hasPitch) return false;
    if (target != null && target != activeTarget) return false;
    return true;
  }

  static bool _matchesList(List<String> allowed, String value) {
    return allowed.isEmpty || allowed.contains(value);
  }
}

class AnnotationRule {
  const AnnotationRule({
    required this.kind,
    this.condition = const AnnotationCondition(),
  });

  final AnnotationKind kind;
  final AnnotationCondition condition;
}

/// Safe, deterministic annotation rule set. The evaluator never executes user
/// code, reads files, makes network calls or asks a model.
class AnnotationRuleSet {
  const AnnotationRuleSet({
    required this.id,
    required this.name,
    required this.version,
    required this.targets,
    required this.rules,
  });

  static const int maxRules = 64;

  final String id;
  final String name;
  final int version;
  final List<AnnotationTarget> targets;
  final List<AnnotationRule> rules;

  bool supports(AnnotationTarget target) => targets.contains(target);

  AnnotationPlan evaluate(
    Token token,
    AnnotationTarget target, {
    required bool hasPitch,
  }) {
    if (!supports(target)) return const AnnotationPlan();
    var ruby = false;
    var pitch = false;
    var bold = false;
    var underline = false;
    for (final rule in rules) {
      if (!rule.condition.matches(token, target, hasPitch: hasPitch)) {
        continue;
      }
      switch (rule.kind) {
        case AnnotationKind.ruby:
          ruby = true;
        case AnnotationKind.pitch:
          pitch = true;
        case AnnotationKind.bold:
          bold = true;
        case AnnotationKind.underline:
          underline = true;
      }
    }
    return AnnotationPlan(
      ruby: ruby,
      pitch: pitch,
      bold: bold,
      underline: underline,
    );
  }

  /// Parses a safe JSON rule set. `text`/`group` and unknown node types are
  /// rejected; callers must keep the previous valid set on failure.
  factory AnnotationRuleSet.fromJson(Map<String, Object?> json) {
    final schema = json['schema'];
    if (schema != null && schema != 'rikai.annotation.rules.v1') {
      throw const FormatException('unsupported annotation schema');
    }
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) {
      throw const FormatException('annotation id/name is required');
    }
    final rawTargets = json['targets'];
    if (rawTargets is! List || rawTargets.isEmpty) {
      throw const FormatException('annotation targets are required');
    }
    final targets = <AnnotationTarget>[
      for (final raw in rawTargets) ?AnnotationTarget.fromWire(raw),
    ];
    if (targets.length != rawTargets.length || targets.length > 3) {
      throw const FormatException('unknown annotation target');
    }
    final rawRules = json['rules'];
    if (rawRules is! List || rawRules.length > maxRules) {
      throw const FormatException('invalid annotation rules');
    }
    final rules = <AnnotationRule>[];
    for (final rawRule in rawRules) {
      if (rawRule is! Map) {
        throw const FormatException('invalid annotation rule');
      }
      final rule = rawRule.map((key, value) => MapEntry(key.toString(), value));
      if (rule.keys.any((key) => key != 'type' && key != 'when')) {
        throw const FormatException('unsupported annotation rule property');
      }
      final kind = AnnotationKind.fromWire(rule['type']);
      if (kind == null) {
        throw FormatException('unsupported annotation node ${rule['type']}');
      }
      final when = rule['when'];
      if (when != null && when is! Map) {
        throw const FormatException('invalid annotation condition');
      }
      rules.add(
        AnnotationRule(
          kind: kind,
          condition: _conditionFromJson(
            when is Map
                ? when.map((key, value) => MapEntry(key.toString(), value))
                : const <String, Object?>{},
          ),
        ),
      );
    }
    final version = json['version'];
    return AnnotationRuleSet(
      id: id,
      name: name,
      version: version is int && version > 0 ? version : 1,
      targets: List<AnnotationTarget>.unmodifiable(targets),
      rules: List<AnnotationRule>.unmodifiable(rules),
    );
  }

  static AnnotationCondition _conditionFromJson(Map<String, Object?> json) {
    const allowed = <String>{
      'pos1',
      'pos2',
      'pos3',
      'pos4',
      'lemma',
      'surface',
      'hasReading',
      'hasPitch',
      'target',
    };
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('unsupported annotation condition');
    }
    List<String> strings(String key) {
      final raw = json[key];
      if (raw == null) return const <String>[];
      if (raw is! List || raw.length > 16) {
        throw FormatException('invalid annotation condition $key');
      }
      return List<String>.unmodifiable(raw.map((value) => value.toString()));
    }

    bool? boolean(String key) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is! bool) {
        throw FormatException('invalid annotation condition $key');
      }
      return raw;
    }

    final rawTarget = json['target'];
    final target = rawTarget == null
        ? null
        : AnnotationTarget.fromWire(rawTarget);
    if (rawTarget != null && target == null) {
      throw const FormatException('invalid annotation condition target');
    }
    return AnnotationCondition(
      pos1: strings('pos1'),
      pos2: strings('pos2'),
      pos3: strings('pos3'),
      pos4: strings('pos4'),
      lemma: strings('lemma'),
      surface: strings('surface'),
      hasReading: boolean('hasReading'),
      hasPitch: boolean('hasPitch'),
      target: target,
    );
  }
}

class AnnotationPlan {
  const AnnotationPlan({
    this.ruby = false,
    this.pitch = false,
    this.bold = false,
    this.underline = false,
  });

  final bool ruby;
  final bool pitch;
  final bool bold;
  final bool underline;

  bool get hasAny => ruby || pitch || bold || underline;
}

/// Built-in rule sets. They are intentionally small: no user editor and no
/// arbitrary `text`/`group` nodes in P6.7 v1.
abstract final class AnnotationRuleSets {
  static const String basicId = 'furigana';
  static const String pitchId = 'furigana_pitch';
  static const String noneId = 'none';

  static const AnnotationRuleSet basic = AnnotationRuleSet(
    id: basicId,
    name: '基础注音',
    version: 1,
    targets: <AnnotationTarget>[
      AnnotationTarget.reader,
      AnnotationTarget.photo,
      AnnotationTarget.corpus,
    ],
    rules: <AnnotationRule>[
      AnnotationRule(
        kind: AnnotationKind.ruby,
        condition: AnnotationCondition(hasReading: true),
      ),
    ],
  );

  static const AnnotationRuleSet pitch = AnnotationRuleSet(
    id: pitchId,
    name: '注音 + 音调',
    version: 1,
    targets: <AnnotationTarget>[
      AnnotationTarget.reader,
      AnnotationTarget.photo,
      AnnotationTarget.corpus,
    ],
    rules: <AnnotationRule>[
      AnnotationRule(
        kind: AnnotationKind.ruby,
        condition: AnnotationCondition(hasReading: true),
      ),
      AnnotationRule(
        kind: AnnotationKind.pitch,
        condition: AnnotationCondition(hasPitch: true),
      ),
    ],
  );

  static const AnnotationRuleSet none = AnnotationRuleSet(
    id: noneId,
    name: '关闭标注',
    version: 1,
    targets: <AnnotationTarget>[
      AnnotationTarget.reader,
      AnnotationTarget.photo,
      AnnotationTarget.corpus,
    ],
    rules: <AnnotationRule>[],
  );

  static const List<AnnotationRuleSet> all = <AnnotationRuleSet>[
    basic,
    pitch,
    none,
  ];

  /// The "none" set is kept for migration/internal fallback only. The visible
  /// menu uses "显示注音" to turn annotations off, so listing "关闭标注" would
  /// duplicate that control.
  static const List<AnnotationRuleSet> selectable = <AnnotationRuleSet>[
    basic,
    pitch,
  ];

  static AnnotationRuleSet byId(String? id) {
    for (final ruleSet in all) {
      if (ruleSet.id == id) return ruleSet;
    }
    return basic;
  }
}
