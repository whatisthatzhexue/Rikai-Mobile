import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/annotation_rules.dart';
import 'package:lexicandy/core/models/token.dart';

Token _token(String surface, String kana, String pos1) {
  final features = List<String>.filled(Token.expectedFeatureCount, '*');
  features[0] = pos1;
  features[20] = kana;
  return Token.fromFeatures(
    surface: surface,
    features: features,
    start: 0,
    end: surface.length,
  );
}

void main() {
  test('built-in sets only enable the documented decorations', () {
    final token = _token('東京', 'トウキョウ', '名詞');

    final basic = AnnotationRuleSets.basic.evaluate(
      token,
      AnnotationTarget.reader,
      hasPitch: true,
    );
    expect(basic.ruby, isTrue);
    expect(basic.pitch, isFalse);

    final pitch = AnnotationRuleSets.pitch.evaluate(
      token,
      AnnotationTarget.reader,
      hasPitch: true,
    );
    expect(pitch.ruby, isTrue);
    expect(pitch.pitch, isTrue);

    final none = AnnotationRuleSets.none.evaluate(
      token,
      AnnotationTarget.reader,
      hasPitch: true,
    );
    expect(none.hasAny, isFalse);
  });

  test('target filtering and when conditions are applied', () {
    final set = AnnotationRuleSet.fromJson(<String, Object?>{
      'schema': 'rikai.annotation.rules.v1',
      'id': 'custom',
      'name': 'Custom',
      'version': 2,
      'targets': <String>['reader'],
      'rules': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'bold',
          'when': <String, Object?>{
            'pos1': <String>['名詞'],
            'hasReading': true,
          },
        },
      ],
    });
    final noun = _token('東京', 'トウキョウ', '名詞');
    final verb = _token('食べる', 'タベル', '動詞');

    expect(
      set.evaluate(noun, AnnotationTarget.reader, hasPitch: false).bold,
      isTrue,
    );
    expect(
      set.evaluate(verb, AnnotationTarget.reader, hasPitch: false).bold,
      isFalse,
    );
    expect(
      set.evaluate(noun, AnnotationTarget.photo, hasPitch: false).hasAny,
      isFalse,
    );
  });

  test('text/group and unknown nodes are rejected', () {
    Map<String, Object?> ruleSet(String type) => <String, Object?>{
      'id': 'bad',
      'name': 'Bad',
      'version': 1,
      'targets': <String>['reader'],
      'rules': <Map<String, Object?>>[
        <String, Object?>{'type': type},
      ],
    };

    expect(
      () => AnnotationRuleSet.fromJson(ruleSet('text')),
      throwsFormatException,
    );
    expect(
      () => AnnotationRuleSet.fromJson(ruleSet('group')),
      throwsFormatException,
    );
    expect(
      () => AnnotationRuleSet.fromJson(ruleSet('script')),
      throwsFormatException,
    );
    expect(
      () => AnnotationRuleSet.fromJson(<String, Object?>{
        'id': 'bad',
        'name': 'Bad',
        'version': 1,
        'targets': <String>['reader'],
        'rules': <Map<String, Object?>>[
          <String, Object?>{'type': 'ruby', 'children': <Object?>[]},
        ],
      }),
      throwsFormatException,
    );
  });

  test('unknown ids fall back to the basic built-in set', () {
    expect(AnnotationRuleSets.byId('missing').id, AnnotationRuleSets.basicId);
    expect(AnnotationRuleSets.byId(null).id, AnnotationRuleSets.basicId);
  });
}
