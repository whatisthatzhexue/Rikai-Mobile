import '../../../core/models/agent/agent_profile.dart';

String profileToMarkdown(
  DictionaryProfile profile, [
  AgentProfileLanguage language = AgentProfileLanguage.chinese,
]) {
  final labels = switch (language) {
    AgentProfileLanguage.chinese => const _ProfileLabels(
      type: '类型',
      intro: '简介',
      languages: '语言',
      entryStructure: '条目结构',
      headwordFields: '见出し字段',
      definitionFields: '释义字段',
      features: '特征',
      search: '查询建议',
      exactForms: '可查形式',
      prefix: '前缀建议',
      recommended: '推荐查询',
      coverage: '覆盖样本',
      sampleEntries: '样本条数',
      entryCount: '词典词条',
      headwordScripts: '见出し文字',
      definitionScripts: '释义文字',
      featureCount: '结构特征',
      sampleTruncated: '样本提示',
      sampleLimitReached: '词典样本达上限，',
      unsampledProbes: ' 项检查未覆盖',
      strengthsCaveats: '强项 / 注意事项',
      strengths: '强项',
      caveats: '注意',
      confidence: '置信度',
      supported: '支持',
      uncertain: '不确定',
      joiner: '、',
    ),
    AgentProfileLanguage.english => const _ProfileLabels(
      type: 'Type',
      intro: 'Introduction',
      languages: 'Languages',
      entryStructure: 'Entry structure',
      headwordFields: 'Headword fields',
      definitionFields: 'Definition fields',
      features: 'Features',
      search: 'Search guidance',
      exactForms: 'Searchable forms',
      prefix: 'Prefix suggestions',
      recommended: 'Recommended queries',
      coverage: 'Coverage sample',
      sampleEntries: 'Sample entries',
      entryCount: 'Dictionary entries',
      headwordScripts: 'Headword scripts',
      definitionScripts: 'Definition scripts',
      featureCount: 'Structural features',
      sampleTruncated: 'Sample note',
      sampleLimitReached: 'Dictionary sample limit reached; ',
      unsampledProbes: ' check(s) not covered',
      strengthsCaveats: 'Strengths / caveats',
      strengths: 'Strengths',
      caveats: 'Caveats',
      confidence: 'Confidence',
      supported: 'supported',
      uncertain: 'unknown',
      joiner: ', ',
    ),
    AgentProfileLanguage.japanese => const _ProfileLabels(
      type: '種類',
      intro: '概要',
      languages: '言語',
      entryStructure: '項目構造',
      headwordFields: '見出し字段',
      definitionFields: '語義字段',
      features: '特徴',
      search: '検索のヒント',
      exactForms: '検索可能な形',
      prefix: '前方一致候補',
      recommended: '推奨クエリ',
      coverage: 'カバレッジ',
      sampleEntries: 'サンプル項目',
      entryCount: '辞書項目',
      headwordScripts: '見出し文字',
      definitionScripts: '語義文字',
      featureCount: '構造特徴',
      sampleTruncated: 'サンプルの注意',
      sampleLimitReached: '辞書サンプル上限、',
      unsampledProbes: ' 件の確認未実施',
      strengthsCaveats: '強み / 注意',
      strengths: '強み',
      caveats: '注意',
      confidence: '信頼度',
      supported: '対応',
      uncertain: '不明',
      joiner: '、',
    ),
  };
  final features = <String>[
    if (profile.entryStructure.hasRuby) 'ruby',
    if (profile.entryStructure.hasKanjiInfo) 'kanji',
    if (profile.entryStructure.hasExamples) 'examples',
    if (profile.entryStructure.hasAudio) 'audio',
    if (profile.entryStructure.hasImages) 'images',
  ].join(labels.joiner);
  final languageText = profile.languagePairs.isEmpty
      ? profile.languages.join(labels.joiner)
      : profile.languagePairs.map((pair) => pair.label).join(labels.joiner);
  final buffer = StringBuffer()..writeln('## ${profile.title}');
  if (profile.intro.isNotEmpty) {
    buffer
      ..writeln('- ${labels.intro}: ${profile.intro}')
      ..writeln('');
  }
  buffer
    ..writeln('- ${labels.type}: ${profile.kind}')
    ..writeln('- ${labels.languages}: $languageText')
    ..writeln('')
    ..writeln('### ${labels.entryStructure}')
    ..writeln(
      '- ${labels.headwordFields}: '
      '${profile.entryStructure.headwordFields.join(labels.joiner)}',
    )
    ..writeln(
      '- ${labels.definitionFields}: '
      '${profile.entryStructure.definitionFields.join(labels.joiner)}',
    )
    ..writeln('- ${labels.features}: $features')
    ..writeln('')
    ..writeln('### ${labels.search}')
    ..writeln(
      '- ${labels.exactForms}: '
      '${profile.searchBehavior.exactForms.join(labels.joiner)}',
    )
    ..writeln(
      '- ${labels.prefix}: '
      '${profile.searchBehavior.prefixSuggestions ? labels.supported : labels.uncertain}',
    )
    ..writeln(
      '- ${labels.recommended}: '
      '${profile.recommendedQueryForms.join(labels.joiner)}',
    );
  if (!profile.coverage.isEmpty) {
    buffer
      ..writeln('')
      ..writeln('### ${labels.coverage}')
      ..writeln('- ${labels.sampleEntries}: ${profile.coverage.sampleEntries}')
      ..writeln('- ${labels.entryCount}: ${profile.coverage.entryCount}')
      ..writeln(
        '- ${labels.headwordScripts}: '
        '${profile.coverage.headwordScripts.map((script) => _scriptLabel(script, language)).join(labels.joiner)}',
      )
      ..writeln(
        '- ${labels.definitionScripts}: '
        '${profile.coverage.definitionScripts.map((script) => _scriptLabel(script, language)).join(labels.joiner)}',
      )
      ..writeln('- ${labels.featureCount}: ${profile.coverage.featureCount}');
    if (profile.coverage.sampleTruncated) {
      buffer.writeln(
        '- ${labels.sampleTruncated}: ${labels.sampleLimitReached}'
        '${profile.coverage.unsampledProbeCount}${labels.unsampledProbes}',
      );
    }
  }
  buffer
    ..writeln('')
    ..writeln('### ${labels.strengthsCaveats}')
    ..writeln('- ${labels.strengths}: ${profile.strengths.join(labels.joiner)}')
    ..writeln('- ${labels.caveats}: ${profile.caveats.join(labels.joiner)}')
    ..writeln('')
    ..writeln('${labels.confidence}: ${profile.confidence.toStringAsFixed(2)}');
  return buffer.toString().trim();
}

/// Updates the human-readable language/language-pair line in an existing
/// profile Markdown while preserving every other user edit.
///
/// The profile sheet lets the user correct an automatically detected language
/// pair. The prompt consumes this Markdown, so changing only the structured
/// `DictionaryProfile` would not affect later answers.
String updateLanguagePairsMarkdown(
  String markdown,
  DictionaryProfile profile,
  AgentProfileLanguage language,
) {
  final label = switch (language) {
    AgentProfileLanguage.chinese => '语言',
    AgentProfileLanguage.english => 'Languages',
    AgentProfileLanguage.japanese => '言語',
  };
  final joiner = language == AgentProfileLanguage.english ? ', ' : '、';
  final value = profile.languagePairs.isEmpty
      ? profile.languages.join(joiner)
      : profile.languagePairs.map((pair) => pair.label).join(joiner);
  final line = '- $label: $value';
  final pattern = RegExp('^- ${RegExp.escape(label)}:.*\$', multiLine: true);
  if (pattern.hasMatch(markdown)) {
    return markdown.replaceFirstMapped(pattern, (_) => line);
  }
  // A user may have removed the line. Keep the correction discoverable by
  // inserting it right after the first heading instead of appending it at the
  // very bottom.
  final firstNewline = markdown.indexOf('\n');
  if (firstNewline >= 0) {
    return '${markdown.substring(0, firstNewline + 1)}$line\n'
        '${markdown.substring(firstNewline + 1)}';
  }
  return '$markdown\n$line';
}

String _scriptLabel(String script, AgentProfileLanguage language) {
  return switch (language) {
    AgentProfileLanguage.chinese => switch (script) {
      'han' => '汉字',
      'hiragana' => '平假名',
      'katakana' => '片假名',
      'latin' => '拉丁字母',
      'hangul' => '韩文',
      'cyrillic' => '西里尔字母',
      'greek' => '希腊字母',
      'thai' => '泰文',
      'arabic' => '阿拉伯文',
      _ => script,
    },
    AgentProfileLanguage.english => switch (script) {
      'han' => 'Han',
      'hiragana' => 'Hiragana',
      'katakana' => 'Katakana',
      'latin' => 'Latin',
      'hangul' => 'Hangul',
      'cyrillic' => 'Cyrillic',
      'greek' => 'Greek',
      'thai' => 'Thai',
      'arabic' => 'Arabic',
      _ => script,
    },
    AgentProfileLanguage.japanese => switch (script) {
      'han' => '漢字',
      'hiragana' => 'ひらがな',
      'katakana' => 'カタカナ',
      'latin' => 'ラテン文字',
      'hangul' => 'ハングル',
      'cyrillic' => 'キリル文字',
      'greek' => 'ギリシア文字',
      'thai' => 'タイ文字',
      'arabic' => 'アラビア文字',
      _ => script,
    },
  };
}

class _ProfileLabels {
  const _ProfileLabels({
    required this.type,
    required this.intro,
    required this.languages,
    required this.entryStructure,
    required this.headwordFields,
    required this.definitionFields,
    required this.features,
    required this.search,
    required this.exactForms,
    required this.prefix,
    required this.recommended,
    required this.coverage,
    required this.sampleEntries,
    required this.entryCount,
    required this.headwordScripts,
    required this.definitionScripts,
    required this.featureCount,
    required this.sampleTruncated,
    required this.sampleLimitReached,
    required this.unsampledProbes,
    required this.strengthsCaveats,
    required this.strengths,
    required this.caveats,
    required this.confidence,
    required this.supported,
    required this.uncertain,
    required this.joiner,
  });

  final String type;
  final String intro;
  final String languages;
  final String entryStructure;
  final String headwordFields;
  final String definitionFields;
  final String features;
  final String search;
  final String exactForms;
  final String prefix;
  final String recommended;
  final String coverage;
  final String sampleEntries;
  final String entryCount;
  final String headwordScripts;
  final String definitionScripts;
  final String featureCount;
  final String sampleTruncated;
  final String sampleLimitReached;
  final String unsampledProbes;
  final String strengthsCaveats;
  final String strengths;
  final String caveats;
  final String confidence;
  final String supported;
  final String uncertain;
  final String joiner;
}
