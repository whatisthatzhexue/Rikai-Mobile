import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/agent/familiarization/dictionary_familiarization_service.dart';
import '../services/storage/agent_profile_inbox_store.dart';
import 'agent_providers.dart';

/// Production bootstrap overrides this with the SQLite-backed store. Tests
/// leave it null so the in-memory queue stays self-contained.
final agentProfileInboxPersistenceProvider =
    Provider<AgentProfileInboxPersistence?>((ref) => null);

/// One profile-save event. Hosts show a single toast per [id], so a save
/// produced while several Agent surfaces are mounted is never announced twice.
class AgentProfileSavedNotice {
  const AgentProfileSavedNotice({required this.id, required this.titles});

  final int id;
  final List<String> titles;
}

/// App-scoped queue of generated profiles awaiting an explicit user decision.
///
/// The queue survives Agent page disposal. A pending item is never auto-skipped
/// merely because the page is not mounted; only [resolve] or [cancelRun] may
/// complete its decision future.
class AgentProfileInboxState {
  const AgentProfileInboxState({
    this.pending = const <AgentProfileProposal>[],
    this.savedNotice,
  });

  final List<AgentProfileProposal> pending;

  /// The most recent save. A host that mounts later starts from the current
  /// id and therefore never replays an old toast.
  final AgentProfileSavedNotice? savedNotice;

  int get pendingCount => pending.length;

  List<AgentProfileProposal> forRun(String runId) => pending
      .where((proposal) => proposal.runId == runId)
      .toList(growable: false);

  AgentProfileProposal? get first => pending.isEmpty ? null : pending.first;

  AgentProfileInboxState copyWith({
    List<AgentProfileProposal>? pending,
    AgentProfileSavedNotice? savedNotice,
  }) => AgentProfileInboxState(
    pending: List<AgentProfileProposal>.unmodifiable(pending ?? this.pending),
    savedNotice: savedNotice ?? this.savedNotice,
  );
}

final agentProfileInboxProvider =
    NotifierProvider<AgentProfileInboxController, AgentProfileInboxState>(
      AgentProfileInboxController.new,
    );

class AgentProfileInboxController extends Notifier<AgentProfileInboxState> {
  final Map<String, Completer<ProfileConfirmation>> _decisions =
      <String, Completer<ProfileConfirmation>>{};
  AgentProfileInboxPersistence? _persistence;
  bool _disposed = false;
  bool _presenting = false;
  int _savedNoticeSerial = 0;
  int _claimedSavedNoticeId = 0;

  /// Only one page/subpage host may show a confirmation sheet at a time. This
  /// prevents the Agent page behind the profile manager from presenting the
  /// same proposal twice.
  bool tryClaimPresentation() {
    if (_presenting) return false;
    _presenting = true;
    return true;
  }

  void releasePresentation() {
    _presenting = false;
  }

  /// Returns true for the first host that handles [id]. Several Agent surfaces
  /// can be mounted at once (Agent page + profile manager/settings), but a
  /// saved profile must produce only one toast.
  bool claimSavedNotice(int id) {
    if (id <= _claimedSavedNoticeId) return false;
    _claimedSavedNoticeId = id;
    return true;
  }

  AgentProfileSavedNotice _nextSavedNotice(List<String> titles) {
    return AgentProfileSavedNotice(
      id: ++_savedNoticeSerial,
      titles: List<String>.unmodifiable(titles),
    );
  }

  @override
  AgentProfileInboxState build() {
    _disposed = false;
    _persistence = ref.watch(agentProfileInboxPersistenceProvider);
    final persistence = _persistence;
    if (persistence != null) {
      unawaited(_restore(persistence));
    }
    ref.onDispose(() {
      _disposed = true;
      for (final completer in _decisions.values) {
        if (!completer.isCompleted) {
          completer.complete(
            const ProfileConfirmation(
              action: ProfileConfirmationAction.skipOnce,
              markdown: '',
            ),
          );
        }
      }
      _decisions.clear();
    });
    return const AgentProfileInboxState();
  }

  Future<void> _restore(AgentProfileInboxPersistence persistence) async {
    try {
      final restored = await persistence.loadPendingProfiles();
      if (_disposed || restored.isEmpty) return;
      final known = <String>{for (final item in state.pending) item.id};
      final merged = <AgentProfileProposal>[
        ...state.pending,
        for (final proposal in restored)
          if (known.add(proposal.id)) proposal,
      ];
      state = state.copyWith(pending: merged);
    } catch (error, stack) {
      developer.log(
        'Failed to restore pending dictionary profiles',
        name: 'AgentProfileInbox',
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<void> _persistPending(List<AgentProfileProposal> proposals) async {
    final persistence = _persistence;
    if (persistence == null) return;
    for (final proposal in proposals) {
      try {
        await persistence.savePendingProfile(proposal);
      } catch (error, stack) {
        developer.log(
          'Failed to persist pending dictionary profile',
          name: 'AgentProfileInbox',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }

  Future<void> enqueue(List<AgentProfileProposal> proposals) async {
    if (proposals.isEmpty) return;
    final known = <String>{for (final item in state.pending) item.id};
    final added = <AgentProfileProposal>[
      for (final proposal in proposals)
        if (known.add(proposal.id)) proposal,
    ];
    if (added.isEmpty) return;
    state = state.copyWith(
      pending: <AgentProfileProposal>[...state.pending, ...added],
    );
    await _persistPending(added);
  }

  Future<List<ProfileConfirmation>> waitForAll(
    String runId,
    List<AgentProfileProposal> proposals,
  ) {
    // Register decision completers before enqueue yields to persistence, so
    // a cancel/clear immediately after waitForAll cannot strand the future.
    final futures = <Future<ProfileConfirmation>>[];
    for (final proposal in proposals) {
      final completer = _decisions.putIfAbsent(
        proposal.id,
        Completer<ProfileConfirmation>.new,
      );
      futures.add(completer.future);
    }
    unawaited(enqueue(proposals));
    return Future.wait(futures);
  }

  /// Saves every generated proposal without a sheet when the user enabled
  /// "不再询问". Runs still receive the decisions so their prompt can use the
  /// new Markdown immediately.
  Future<List<ProfileConfirmation>> autoAcceptAll(
    List<AgentProfileProposal> proposals,
  ) async {
    final decisions = <ProfileConfirmation>[];
    final savedTitles = <String>[];
    for (final proposal in proposals) {
      final decision = ProfileConfirmation(
        action: ProfileConfirmationAction.save,
        markdown: proposal.markdown,
      );
      try {
        await persistAgentProfileDecision(
          repository: ref.read(agentProfileRepositoryProvider),
          proposal: proposal,
          action: decision.action,
          markdown: decision.markdown,
        );
        savedTitles.add(proposal.title);
      } catch (error, stack) {
        developer.log(
          'Failed to auto-save dictionary profile',
          name: 'AgentProfileInbox',
          error: error,
          stackTrace: stack,
        );
      }
      decisions.add(decision);
    }
    final persistence = _persistence;
    if (persistence != null) {
      for (final proposal in proposals) {
        try {
          await persistence.deletePendingProfile(proposal.id);
        } catch (error, stack) {
          developer.log(
            'Failed to clear auto-accepted profile',
            name: 'AgentProfileInbox',
            error: error,
            stackTrace: stack,
          );
        }
      }
    }
    ref.invalidate(agentProfilesProvider);
    if (savedTitles.isNotEmpty) {
      state = state.copyWith(savedNotice: _nextSavedNotice(savedTitles));
    }
    return decisions;
  }

  /// Persists the explicit decision and releases the waiting run. The profile
  /// is written here rather than in the run so a proposal generated by the
  /// profile manager is saved by the same path.
  Future<void> resolve(String proposalId, ProfileConfirmation decision) async {
    AgentProfileProposal? proposal;
    for (final item in state.pending) {
      if (item.id == proposalId) {
        proposal = item;
        break;
      }
    }
    if (proposal == null) return;
    AgentProfileSavedNotice? savedNotice;
    try {
      await persistAgentProfileDecision(
        repository: ref.read(agentProfileRepositoryProvider),
        proposal: proposal,
        action: decision.action,
        markdown: decision.markdown,
        profile: decision.profile,
      );
      ref.invalidate(agentProfilesProvider);
      if (decision.action == ProfileConfirmationAction.save ||
          decision.action == ProfileConfirmationAction.saveAndNeverAsk) {
        savedNotice = _nextSavedNotice(<String>[proposal.title]);
      }
    } catch (error, stack) {
      developer.log(
        'Failed to persist dictionary profile decision',
        name: 'AgentProfileInbox',
        error: error,
        stackTrace: stack,
      );
    }
    final completer = _decisions.remove(proposalId);
    state = state.copyWith(
      pending: state.pending
          .where((item) => item.id != proposalId)
          .toList(growable: false),
      savedNotice: savedNotice,
    );
    final persistence = _persistence;
    if (persistence != null) {
      try {
        await persistence.deletePendingProfile(proposalId);
      } catch (error, stack) {
        developer.log(
          'Failed to clear resolved profile',
          name: 'AgentProfileInbox',
          error: error,
          stackTrace: stack,
        );
      }
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(decision);
    }
  }

  /// Resolves every pending proposal for a cancelled run as "skip once" so the
  /// orchestrator does not wait forever. Nothing is written to the store.
  void cancelRun(String runId) {
    final affected = state.forRun(runId);
    if (affected.isEmpty) return;
    state = state.copyWith(
      pending: state.pending
          .where((proposal) => proposal.runId != runId)
          .toList(growable: false),
    );
    for (final proposal in affected) {
      final completer = _decisions.remove(proposal.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(
          ProfileConfirmation(
            action: ProfileConfirmationAction.skipOnce,
            markdown: proposal.markdown,
          ),
        );
      }
    }
    final persistence = _persistence;
    if (persistence != null) {
      unawaited(_deletePendingForRun(persistence, runId));
    }
  }

  Future<void> _deletePendingForRun(
    AgentProfileInboxPersistence persistence,
    String runId,
  ) async {
    try {
      await persistence.deletePendingProfilesForRun(runId);
    } catch (error, stack) {
      developer.log(
        'Failed to clear cancelled profile queue',
        name: 'AgentProfileInbox',
        error: error,
        stackTrace: stack,
      );
    }
  }

  void clearAll() {
    for (final proposal in state.pending) {
      final completer = _decisions.remove(proposal.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(
          ProfileConfirmation(
            action: ProfileConfirmationAction.skipOnce,
            markdown: proposal.markdown,
          ),
        );
      }
    }
    _decisions.clear();
    final persistence = _persistence;
    if (persistence != null) {
      for (final proposal in state.pending) {
        unawaited(_deletePending(persistence, proposal.id));
      }
    }
    state = const AgentProfileInboxState();
  }

  Future<void> _deletePending(
    AgentProfileInboxPersistence persistence,
    String id,
  ) async {
    try {
      await persistence.deletePendingProfile(id);
    } catch (error, stack) {
      developer.log(
        'Failed to clear pending profile',
        name: 'AgentProfileInbox',
        error: error,
        stackTrace: stack,
      );
    }
  }
}
