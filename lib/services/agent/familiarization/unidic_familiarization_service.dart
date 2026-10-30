import '../../../core/models/agent/agent_profile.dart';
import '../ports/tokenize_port.dart';
import 'profile_fingerprint.dart';
import 'profile_repository.dart';

/// Deterministic UniDic observations; no dictionary lookup is implied.
class UnidicFamiliarizationService {
  const UnidicFamiliarizationService({
    required TokenizePort tokenizePort,
    required UnidicProfileRepository repository,
    this.sampleSentences = const <String>[
      'これはテストです。',
      '食べた東京',
      '美しかったらしい',
      'コンピューターを使っている',
    ],
  }) : _tokenizePort = tokenizePort,
       _repository = repository;

  final TokenizePort _tokenizePort;
  final UnidicProfileRepository _repository;
  final List<String> sampleSentences;

  Future<UnidicProfile?> ensure(
    String unidicPath, {
    String version = '',
  }) async {
    if (unidicPath.trim().isEmpty) return null;
    final pathHash = unidicPathHash(unidicPath);
    final fingerprint = await unidicProfileFingerprint(
      unidicPath,
      version: version,
    );
    final existing = await _repository.loadUnidic(pathHash);
    if (existing != null && existing.fingerprint == fingerprint) {
      return existing.profile;
    }

    var featureLayout = 0;
    var tokenCount = 0;
    var readingCount = 0;
    for (final sentence in sampleSentences) {
      final tokens = await _tokenizePort.analyze(sentence);
      tokenCount += tokens.length;
      for (final token in tokens) {
        if (token.hasStandardLayout) featureLayout = token.features.length;
        if (token.reading.isNotEmpty) readingCount++;
      }
    }

    final profile = UnidicProfile(
      featureLayout: featureLayout == 0 ? 29 : featureLayout,
      observations: <String>[
        if (featureLayout > 0) 'UniDic feature layout: $featureLayout fields',
        'Tokens expose surface, reading, POS, lemma, and UTF-16 offsets.',
        'Readings prefer kana, then pron/lForm/surface fallbacks.',
        'Observed $tokenCount token(s); $readingCount have a reading.',
      ],
      schemaVersion: unidicProfileSchemaVersion,
    );
    final markdown = <String>[
      '# UniDic profile',
      '- Feature layout: ${profile.featureLayout}',
      for (final observation in profile.observations) '- $observation',
    ].join('\n');
    await _repository.saveUnidic(
      StoredUnidicProfile(
        unidicPathHash: pathHash,
        fingerprint: fingerprint,
        profile: profile,
        markdown: markdown,
        confirmedAt: DateTime.now(),
      ),
    );
    return profile;
  }
}
