import '../../../core/models/agent/agent_profile.dart';

String profileToMarkdown(
  DictionaryProfile profile, [
  AgentProfileLanguage language = AgentProfileLanguage.chinese,
]) {
  final labels = switch (language) {
    AgentProfileLanguage.chinese => const _ProfileLabels(
      type: '类型',
      languages: '语言',
      entryStructure: '条目结构',
      headwordFields: '见出し字段',
      definitionFields: '释义字段',
      features: '特征',
      search: '查询建议',
      exactForms: '可查形式',
      prefix: '前缀建议',
      recommended: '推荐查询',
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
      languages: 'Languages',
      entryStructure: 'Entry structure',
      headwordFields: 'Headword fields',
      definitionFields: 'Definition fields',
      features: 'Features',
      search: 'Search guidance',
      exactForms: 'Searchable forms',
      prefix: 'Prefix suggestions',
      recommended: 'Recommended queries',
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
      languages: '言語',
      entryStructure: '項目構造',
      headwordFields: '見出し字段',
      definitionFields: '語義字段',
      features: '特徴',
      search: '検索のヒント',
      exactForms: '検索可能な形',
      prefix: '前方一致候補',
      recommended: '推奨クエリ',
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
  final buffer = StringBuffer()
    ..writeln('## ${profile.title}')
    ..writeln('- ${labels.type}: ${profile.kind}')
    ..writeln('- ${labels.languages}: ${profile.languages.join(labels.joiner)}')
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
    )
    ..writeln('')
    ..writeln('### ${labels.strengthsCaveats}')
    ..writeln('- ${labels.strengths}: ${profile.strengths.join(labels.joiner)}')
    ..writeln('- ${labels.caveats}: ${profile.caveats.join(labels.joiner)}')
    ..writeln('')
    ..writeln('${labels.confidence}: ${profile.confidence.toStringAsFixed(2)}');
  return buffer.toString().trim();
}

class _ProfileLabels {
  const _ProfileLabels({
    required this.type,
    required this.languages,
    required this.entryStructure,
    required this.headwordFields,
    required this.definitionFields,
    required this.features,
    required this.search,
    required this.exactForms,
    required this.prefix,
    required this.recommended,
    required this.strengthsCaveats,
    required this.strengths,
    required this.caveats,
    required this.confidence,
    required this.supported,
    required this.uncertain,
    required this.joiner,
  });

  final String type;
  final String languages;
  final String entryStructure;
  final String headwordFields;
  final String definitionFields;
  final String features;
  final String search;
  final String exactForms;
  final String prefix;
  final String recommended;
  final String strengthsCaveats;
  final String strengths;
  final String caveats;
  final String confidence;
  final String supported;
  final String uncertain;
  final String joiner;
}
