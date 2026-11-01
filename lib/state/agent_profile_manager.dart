import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/agent/agent_profile.dart';
import '../core/models/agent/agent_provider.dart';
import '../core/models/dict_info.dart';
import '../services/agent/familiarization/dictionary_familiarization_service.dart';
import 'agent_profile_inbox.dart';
import 'agent_providers.dart';
import 'agent_run_services.dart';
import 'providers.dart';

/// App-level profile generation used by the dictionary-profile manager.
///
/// Generation and persistence are separate: generated proposals go to the
/// shared [agentProfileInboxProvider], where the user's decision is persisted
/// by the same code path as run-generated profiles.
class AgentProfileManager {
  const AgentProfileManager(this._ref);

  final Ref _ref;

  Future<FamiliarizationGeneration> generate({
    required List<DictionaryInfo> dictionaries,
    required AgentProviderConfig provider,
  }) async {
    final settings = _ref.read(appSettingsProvider);
    final services = await _ref.read(agentRunServicesProvider)(
      needsOcr: false,
      isCancelled: () => false,
    );
    if (services == null) {
      throw StateError('Agent services are unavailable');
    }
    final smallModel = provider.smallModel.trim().isEmpty
        ? provider.complexModel
        : provider.smallModel;
    final familiarizer = DictionaryFamiliarizationService(
      samplePort: services.samplePort,
      repository: services.profileRepository,
      llm: services.llmFactory(provider),
      smallModel: smallModel,
      profileLanguage: AgentProfileLanguage.fromWire(
        settings.agentProfileLanguage,
      ),
    );
    return familiarizer.generateMany(
      dictionaries,
      force: true,
      runId: 'profile-manager-${DateTime.now().microsecondsSinceEpoch}',
    );
  }
}

final agentProfileManagerProvider = Provider<AgentProfileManager>(
  (ref) => AgentProfileManager(ref),
);

class AgentProfileRegenerationState {
  const AgentProfileRegenerationState({
    this.active = false,
    this.titles = const <String>[],
    this.error,
  });

  final bool active;
  final List<String> titles;
  final String? error;

  static const idle = AgentProfileRegenerationState();
}

/// App-scoped profile regeneration. Keeping the request here (instead of page
/// State) means leaving the manager never loses an in-flight generation or
/// causes the same dictionary to be generated twice on re-entry.
class AgentProfileRegenerationController
    extends Notifier<AgentProfileRegenerationState> {
  int _serial = 0;

  @override
  AgentProfileRegenerationState build() => AgentProfileRegenerationState.idle;

  Future<void> start({
    required List<DictionaryInfo> dictionaries,
    required AgentProviderConfig provider,
  }) async {
    if (state.active || dictionaries.isEmpty) return;
    final pendingIds = ref
        .read(agentProfileInboxProvider)
        .pending
        .map((proposal) => proposal.dictionaryId)
        .toSet();
    final targets = dictionaries
        .where((dictionary) => !pendingIds.contains(dictionary.id))
        .toList(growable: false);
    if (targets.isEmpty) return;

    final serial = ++_serial;
    state = AgentProfileRegenerationState(
      active: true,
      titles: <String>[for (final dictionary in targets) dictionary.title],
    );
    try {
      final generation = await ref
          .read(agentProfileManagerProvider)
          .generate(dictionaries: targets, provider: provider);
      if (serial != _serial) return;
      final inbox = ref.read(agentProfileInboxProvider.notifier);
      if (ref.read(appSettingsProvider).agentProfilesAutoAccept) {
        await inbox.autoAcceptAll(generation.proposals);
      } else {
        inbox.enqueue(generation.proposals);
      }
      ref.invalidate(agentProfilesProvider);
      state = AgentProfileRegenerationState(
        error: generation.issues.isEmpty
            ? null
            : generation.issues.first.reason,
      );
    } catch (_) {
      if (serial != _serial) return;
      state = const AgentProfileRegenerationState(
        error: 'profile_regenerate_failed',
      );
    }
  }

  void clearError() {
    if (state.error == null) return;
    state = AgentProfileRegenerationState(
      active: state.active,
      titles: state.titles,
    );
  }
}

final agentProfileRegenerationProvider =
    NotifierProvider<
      AgentProfileRegenerationController,
      AgentProfileRegenerationState
    >(AgentProfileRegenerationController.new);
