import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_provider.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:lexicandy/state/agent_profile_manager.dart';
import 'package:lexicandy/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dictionaryA = DictionaryInfo(
  id: 'dict-a',
  title: '词典 A',
  mdxPath: '/a.mdx',
);

const _dictionaryB = DictionaryInfo(
  id: 'dict-b',
  title: '词典 B',
  mdxPath: '/b.mdx',
);

const _provider = AgentProviderConfig(
  id: 'p1',
  kind: AgentProviderKind.openAiCompatible,
  displayName: 'Test',
  baseUrl: 'https://example.invalid',
  smallModel: 'small',
  complexModel: 'large',
  supportsStreaming: false,
);

class _FakeProfileManager extends AgentProfileManager {
  // `_ref` is private to the production library, so this cannot use a super
  // parameter.
  // ignore: use_super_parameters
  _FakeProfileManager(Ref ref, this.onGenerate) : super(ref);

  final Future<FamiliarizationGeneration> Function(List<DictionaryInfo>)
  onGenerate;
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<FamiliarizationGeneration> generate({
    required List<DictionaryInfo> dictionaries,
    required AgentProviderConfig provider,
  }) {
    calls.add(<String>[for (final dictionary in dictionaries) dictionary.id]);
    return onGenerate(dictionaries);
  }
}

const _emptyGeneration = FamiliarizationGeneration(
  results: <FamiliarizationResult>[],
  proposals: <AgentProfileProposal>[],
);

void main() {
  test(
    'regenerations overlap and the notice keeps every active title',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final pending = <String, Completer<FamiliarizationGeneration>>{};
      late _FakeProfileManager manager;

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProfileManagerProvider.overrideWith((ref) {
            manager = _FakeProfileManager(ref, (dictionaries) {
              final completer = Completer<FamiliarizationGeneration>();
              pending[dictionaries.single.id] = completer;
              return completer.future;
            });
            return manager;
          }),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        agentProfileRegenerationProvider.notifier,
      );

      final first = controller.start(
        dictionaries: <DictionaryInfo>[_dictionaryA],
        provider: _provider,
      );
      final second = controller.start(
        dictionaries: <DictionaryInfo>[_dictionaryB],
        provider: _provider,
      );

      expect(manager.calls, <List<String>>[
        <String>['dict-a'],
        <String>['dict-b'],
      ]);
      var state = container.read(agentProfileRegenerationProvider);
      expect(state.titles, <String>['词典 A', '词典 B']);
      expect(state.isGenerating('dict-a'), isTrue);
      expect(state.isGenerating('dict-b'), isTrue);

      // A dictionary that is already generating cannot be sent a second time.
      await controller.start(
        dictionaries: <DictionaryInfo>[_dictionaryA],
        provider: _provider,
      );
      expect(manager.calls, hasLength(2));

      pending['dict-a']!.complete(_emptyGeneration);
      await first;
      state = container.read(agentProfileRegenerationProvider);
      expect(state.titles, <String>['词典 B']);
      expect(state.isGenerating('dict-a'), isFalse);
      expect(state.isGenerating('dict-b'), isTrue);

      pending['dict-b']!.complete(_emptyGeneration);
      await second;
      state = container.read(agentProfileRegenerationProvider);
      expect(state.active, isFalse);
      expect(state.titles, isEmpty);
    },
  );
}
