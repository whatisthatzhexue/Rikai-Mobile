import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_profile.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:lexicandy/services/agent/familiarization/profile_repository.dart';
import 'package:lexicandy/services/storage/agent_profile_inbox_store.dart';
import 'package:lexicandy/services/storage/agent_store.dart';
import 'package:lexicandy/state/agent_profile_inbox.dart';
import 'package:lexicandy/state/agent_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AgentProfileProposal _proposal({
  String id = 'p1',
  String runId = 'run-1',
  String title = 'テスト辞典',
}) {
  return AgentProfileProposal(
    id: id,
    dictionary: DictionaryInfo(id: 'dict-1', title: title, mdxPath: ''),
    fingerprint: 'fp-1',
    profile: DictionaryProfile(
      dictionaryId: 'dict-1',
      title: title,
      kind: 'monolingual',
      entryStructure: const DictionaryEntryStructure(),
      searchBehavior: const DictionarySearchBehavior(),
    ),
    markdown: '# profile',
    runId: runId,
    modelId: 'small',
    promptVersion: 2,
    schemaVersion: 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}

class _FakePersistence implements AgentProfileInboxPersistence {
  _FakePersistence(this.pending);

  final List<AgentProfileProposal> pending;
  final List<String> saved = <String>[];
  final List<String> deleted = <String>[];
  final List<String> deletedRuns = <String>[];

  @override
  Future<List<AgentProfileProposal>> loadPendingProfiles() async =>
      List<AgentProfileProposal>.of(pending);

  @override
  Future<void> savePendingProfile(AgentProfileProposal proposal) async {
    saved.add(proposal.id);
    pending.add(proposal);
  }

  @override
  Future<void> deletePendingProfile(String id) async {
    deleted.add(id);
    pending.removeWhere((proposal) => proposal.id == id);
  }

  @override
  Future<void> deletePendingProfilesForRun(String runId) async {
    deletedRuns.add(runId);
    pending.removeWhere((proposal) => proposal.runId == runId);
  }
}

void main() {
  group('AgentStore profile inbox', () {
    late AgentStore store;

    setUp(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AgentStore.debugDatabasePath = ':memory:';
      store = AgentStore();
    });

    tearDown(() async {
      await store.close();
      AgentStore.debugDatabasePath = null;
    });

    test('saves, restores and deletes pending proposals', () async {
      final proposal = _proposal();
      await store.savePendingProfile(proposal);

      final pending = await store.loadPendingProfiles();
      expect(pending, hasLength(1));
      expect(pending.single.id, 'p1');
      expect(pending.single.dictionaryId, 'dict-1');
      expect(pending.single.title, 'テスト辞典');
      expect(pending.single.markdown, '# profile');
      expect(pending.single.runId, 'run-1');
      expect(pending.single.modelId, 'small');

      await store.deletePendingProfile('p1');
      expect(await store.loadPendingProfiles(), isEmpty);
    });

    test('deletes pending proposals for one run', () async {
      await store.savePendingProfile(_proposal(id: 'p1'));
      await store.savePendingProfile(_proposal(id: 'p2'));
      await store.savePendingProfile(_proposal(id: 'p3', runId: 'run-2'));

      await store.deletePendingProfilesForRun('run-1');
      final pending = await store.loadPendingProfiles();
      expect(pending.map((item) => item.id), <String>['p3']);
    });
  });

  test('inbox restores, persists, resolves and clears the queue', () async {
    final proposal = _proposal();
    final persistence = _FakePersistence(<AgentProfileProposal>[proposal]);
    final container = ProviderContainer(
      overrides: [
        agentProfileInboxPersistenceProvider.overrideWithValue(persistence),
        agentProfileRepositoryProvider.overrideWithValue(
          InMemoryDictionaryProfileRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(agentProfileInboxProvider.notifier);
    await pumpEventQueue();
    expect(container.read(agentProfileInboxProvider).pendingCount, 1);

    final added = _proposal(id: 'p2', title: '追加辞典');
    container.read(agentProfileInboxProvider.notifier).enqueue(
      <AgentProfileProposal>[added],
    );
    await pumpEventQueue();
    expect(persistence.saved, contains('p2'));
    expect(container.read(agentProfileInboxProvider).pendingCount, 2);

    await container
        .read(agentProfileInboxProvider.notifier)
        .resolve(
          'p2',
          const ProfileConfirmation(
            action: ProfileConfirmationAction.save,
            markdown: '# saved',
          ),
        );
    expect(persistence.deleted, contains('p2'));
    expect(container.read(agentProfileInboxProvider).pendingCount, 1);

    container.read(agentProfileInboxProvider.notifier).cancelRun('run-1');
    await pumpEventQueue();
    expect(persistence.deletedRuns, contains('run-1'));
    expect(container.read(agentProfileInboxProvider).pending, isEmpty);
  });
}
