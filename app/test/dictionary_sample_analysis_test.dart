import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/dictionary_sample.dart';
import 'package:lexicandy/services/agent/familiarization/dictionary_sample_analysis.dart';

DictionarySampleEntry _entry(
  String headword,
  String snippet, {
  DictionarySampleFeatures features = const DictionarySampleFeatures(),
}) {
  return DictionarySampleEntry(
    matchedKey: headword,
    headword: headword,
    snippet: snippet,
    features: features,
  );
}

DictionarySample _sample(
  String title,
  List<DictionarySampleEntry> entries, {
  int entryCount = 1000,
  bool truncated = false,
  List<String> unsampledProbes = const <String>[],
}) {
  return DictionarySample(
    dictionaryId: 'dict_a',
    metadata: DictionarySampleMetadata(title: title, entryCount: entryCount),
    entries: entries,
    truncated: truncated,
    unsampledProbes: unsampledProbes,
  );
}

void main() {
  test('detects a Japanese monolingual dictionary', () {
    final analysis = analyzeDictionarySample(
      _sample('国語辞典', <DictionarySampleEntry>[
        _entry('食べる', 'たべる。食事をする。'),
        _entry('美しい', 'きれいだ。'),
      ]),
    );

    expect(analysis.languagePairs.first.label, 'ja→ja');
    expect(analysis.languagePairs.first.confidence, greaterThan(0.6));
    expect(analysis.coverage.sampleEntries, 2);
    expect(analysis.coverage.entryCount, 1000);
  });

  test('detects ja to zh from a title and Han-only definitions', () {
    final analysis = analyzeDictionarySample(
      _sample('日中辞典', <DictionarySampleEntry>[_entry('食べる', '吃；用餐。')]),
    );

    expect(analysis.languagePairs.first.label, 'ja→zh');
  });

  test('detects zh to ja from a title and kana definitions', () {
    final analysis = analyzeDictionarySample(
      _sample('中日辞典', <DictionarySampleEntry>[_entry('吃', 'たべる。食事をする。')]),
    );

    expect(analysis.languagePairs.first.label, 'zh→ja');
  });

  test('detects ja to en and en to ja dictionaries', () {
    final jaEn = analyzeDictionarySample(
      _sample('和英辞典', <DictionarySampleEntry>[
        _entry('食べる', 'to eat; to have a meal'),
      ]),
    );
    final enJa = analyzeDictionarySample(
      _sample('英和辞典', <DictionarySampleEntry>[_entry('eat', 'たべる。食事をする。')]),
    );

    expect(jaEn.languagePairs.first.label, 'ja→en');
    expect(enJa.languagePairs.first.label, 'en→ja');
  });

  test('uses model languages when the title is not decisive', () {
    final analysis = analyzeDictionarySample(
      _sample('標準辞典', <DictionarySampleEntry>[_entry('食べる', '吃；用餐。')]),
      modelLanguages: const <String>['ja', 'zh'],
    );

    expect(analysis.languagePairs.first.label, 'ja→zh');
  });

  test('supports a three-script title without contradictory pairs', () {
    final analysis = analyzeDictionarySample(
      _sample('日中英辞典', <DictionarySampleEntry>[_entry('食べる', '吃；to eat')]),
    );

    final labels = analysis.languagePairs.map((pair) => pair.label).toSet();
    expect(labels, containsAll(<String>['ja→zh', 'ja→en']));
    expect(labels, isNot(contains('zh→en')));
  });

  test('reports coverage scripts and feature counts without a model', () {
    final analysis = analyzeDictionarySample(
      _sample('国語辞典', <DictionarySampleEntry>[
        _entry(
          '食べる',
          'たべる。食事をする。',
          features: const DictionarySampleFeatures(
            hasRuby: true,
            hasExamples: true,
          ),
        ),
      ]),
    );

    expect(
      analysis.coverage.headwordScripts,
      containsAll(<String>['han', 'hiragana']),
    );
    expect(
      analysis.coverage.definitionScripts,
      containsAll(<String>['han', 'hiragana']),
    );
    expect(analysis.coverage.featureCount, 2);
  });

  test('an empty sample yields no pair and empty coverage', () {
    final analysis = analyzeDictionarySample(
      _sample('', const <DictionarySampleEntry>[], entryCount: 0),
    );

    expect(analysis.languagePairs, isEmpty);
    expect(analysis.coverage.isEmpty, isTrue);
  });

  test('keeps explicit truncation diagnostics in coverage', () {
    final analysis = analyzeDictionarySample(
      _sample(
        '国語辞典',
        <DictionarySampleEntry>[_entry('食べる', 'たべる。食事をする。')],
        truncated: true,
        unsampledProbes: const <String>['は', 'です'],
      ),
    );

    expect(analysis.coverage.isEmpty, isFalse);
    expect(analysis.coverage.sampleTruncated, isTrue);
    expect(analysis.coverage.unsampledProbeCount, 2);
    expect(analysis.coverage.toJson()['sample_truncated'], isTrue);
    expect(analysis.coverage.toJson()['unsampled_probe_count'], 2);
  });
}
