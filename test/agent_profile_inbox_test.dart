import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_repository.dart';
import 'package:rikai_mobile/state/agent_profile_inbox.dart';
import 'package:rikai_mobile/state/agent_providers.dart';

const _profile = DictionaryProfile(
  dictionaryId: 'dict-a',
  title: 'A',
  kind: '国語辞典',
  entryStructure: DictionaryEntryStructure(),
  searchBehavior: DictionarySearchBehavior(),
);

AgentProfileProposal _proposal(String id, {String dictionaryId = 'dict-a'}) {
  return AgentProfileProposal(
    id: id,
    dictionary: DictionaryInfo(
      id: dictionaryId,
      title: dictionaryId,
      mdxPath: '/$dictionaryId.mdx',
    ),
    fingerprint: 'fp-$dictionaryId',
    profile: _profile,
    markdown: 'profile $dictionaryId',
    runId: 'run-1',
    modelId: 'small',
    promptVersion: 1,
    schemaVersion: 1,
  );
}

void main() {
  test(
    'the queue waits for every proposal and persists only explicit saves',
    () async {
      final repository = InMemoryDictionaryProfileRepository();
      final container = ProviderContainer(
        overrides: [
          agentProfileRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final inbox = container.read(agentProfileInboxProvider.notifier);
      final first = _proposal('p1', dictionaryId: 'dict-a');
      final second = _proposal('p2', dictionaryId: 'dict-b');

      final decisions = inbox.waitForAll('run-1', <AgentProfileProposal>[
        first,
        second,
      ]);
      expect(container.read(agentProfileInboxProvider).pendingCount, 2);

      await inbox.resolve(
        first.id,
        const ProfileConfirmation(
          action: ProfileConfirmationAction.save,
          markdown: 'edited profile',
        ),
      );
      expect(container.read(agentProfileInboxProvider).pendingCount, 1);
      final saved = await repository.load('dict-a');
      expect(saved?.markdown, 'edited profile');
      expect(saved?.status, DictionaryProfileStatus.confirmed);
      expect(await repository.load('dict-b'), isNull);

      await inbox.resolve(
        second.id,
        const ProfileConfirmation(
          action: ProfileConfirmationAction.skipOnce,
          markdown: '',
        ),
      );
      final result = await decisions;
      expect(result, hasLength(2));
      expect(result.first.action, ProfileConfirmationAction.save);
      expect(result.last.action, ProfileConfirmationAction.skipOnce);
      expect(container.read(agentProfileInboxProvider).pending, isEmpty);
      expect(await repository.load('dict-b'), isNull);
    },
  );

  test(
    'cancelling a run releases the queue without writing profiles',
    () async {
      final repository = InMemoryDictionaryProfileRepository();
      final container = ProviderContainer(
        overrides: [
          agentProfileRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final inbox = container.read(agentProfileInboxProvider.notifier);
      final proposal = _proposal('p1');

      final decisions = inbox.waitForAll('run-1', <AgentProfileProposal>[
        proposal,
      ]);
      inbox.cancelRun('run-1');
      final result = await decisions;

      expect(result.single.action, ProfileConfirmationAction.skipOnce);
      expect(container.read(agentProfileInboxProvider).pending, isEmpty);
      expect(await repository.load('dict-a'), isNull);
    },
  );
}
