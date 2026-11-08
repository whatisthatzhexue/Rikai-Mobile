import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_evidence.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_limits.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/services/agent/evidence_cache.dart';

const _dictionary = DictionaryInfo(
  id: 'dict-a',
  title: 'A',
  mdxPath: '/a.mdx',
  order: 0,
);

AgentRunRequest _request({String text = '何卒', bool image = false}) {
  return AgentRunRequest(
    sessionId: 's1',
    mode: AgentMode.strict,
    dictionaries: const <DictionaryInfo>[_dictionary],
    provider: const AgentProviderConfig(
      id: 'p1',
      kind: AgentProviderKind.openAiCompatible,
      displayName: 'P',
      baseUrl: 'https://example.com',
      smallModel: 'small',
      complexModel: 'complex',
    ),
    userText: text,
    images: image
        ? const <AgentImageInput>[
            AgentImageInput(id: 'img-1', localPath: '/tmp/one.jpg'),
          ]
        : const <AgentImageInput>[],
  );
}

void main() {
  test('text cache key is stable and changes with input', () {
    final limits = AgentLimits.standard;
    final first = agentEvidenceCacheKey(_request(), limits);
    final second = agentEvidenceCacheKey(_request(), limits);
    final changed = agentEvidenceCacheKey(_request(text: '何卒です'), limits);

    expect(first, isNotNull);
    expect(first, second);
    expect(first, isNot(changed));
  });

  test('image runs are not cached yet', () {
    expect(
      agentEvidenceCacheKey(_request(image: true), AgentLimits.standard),
      isNull,
    );
  });

  test('cache is an LRU with a bounded entry count', () {
    final cache = AgentEvidenceCache(maxEntries: 2);
    const empty = AgentEvidenceBundle(sources: <AgentSourceEvidence>[]);
    cache.put('a', empty);
    cache.put('b', empty);
    expect(cache.length, 2);
    cache.get('a');
    cache.put('c', empty);
    expect(cache.length, 2);
    expect(cache.get('a'), isNotNull);
    expect(cache.get('b'), isNull);
    expect(cache.get('c'), isNotNull);
  });
}
