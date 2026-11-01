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
    this.activeDictionaries = const <DictionaryInfo>[],
    this.error,
  });

  /// Every dictionary whose profile is currently being generated. Several
  /// independent generations may run at the same time.
  final List<DictionaryInfo> activeDictionaries;
  final String? error;

  static const idle = AgentProfileRegenerationState();

  bool get active => activeDictionaries.isNotEmpty;

  List<String> get titles => <String>[
    for (final dictionary in activeDictionaries) dictionary.title,
  ];

  bool isGenerating(String dictionaryId) =>
      activeDictionaries.any((dictionary) => dictionary.id == dictionaryId);
}

/// App-scoped profile regeneration. Keeping the requests here (instead of page
/// State) means leaving the manager never loses an in-flight generation.
/// Independent requests may overlap; the same dictionary can never be sent
/// twice until its earlier request finishes.
class AgentProfileRegenerationController
    extends Notifier<AgentProfileRegenerationState> {
  @override
  AgentProfileRegenerationState build() => AgentProfileRegenerationState.idle;

  Future<void> start({
    required List<DictionaryInfo> dictionaries,
    required AgentProviderConfig provider,
  }) async {
    if (dictionaries.isEmpty) return;
    final pendingIds = ref
        .read(agentProfileInboxProvider)
        .pending
        .map((proposal) => proposal.dictionaryId)
        .toSet();
    final seen = <String>{};
    final targets = <DictionaryInfo>[
      for (final dictionary in dictionaries)
        if (!pendingIds.contains(dictionary.id) &&
            !state.isGenerating(dictionary.id) &&
            seen.add(dictionary.id))
          dictionary,
    ];
    if (targets.isEmpty) return;

    state = AgentProfileRegenerationState(
      activeDictionaries: <DictionaryInfo>[
        ...state.activeDictionaries,
        ...targets,
      ],
    );

    try {
      final generation = await ref
          .read(agentProfileManagerProvider)
          .generate(dictionaries: targets, provider: provider);
      final inbox = ref.read(agentProfileInboxProvider.notifier);
      if (ref.read(appSettingsProvider).agentProfilesAutoAccept) {
        await inbox.autoAcceptAll(generation.proposals);
      } else {
        inbox.enqueue(generation.proposals);
      }
      ref.invalidate(agentProfilesProvider);
      _finish(
        targets,
        error: generation.issues.isEmpty
            ? null
            : generation.issues.first.reason,
      );
    } catch (_) {
      _finish(targets, error: 'profile_regenerate_failed');
    }
  }

  /// Removes only the finished batch from the progress list. Other generations
  /// keep running and stay visible in the notice above the list.
  void _finish(List<DictionaryInfo> targets, {String? error}) {
    final finished = <String>{for (final dictionary in targets) dictionary.id};
    state = AgentProfileRegenerationState(
      activeDictionaries: <DictionaryInfo>[
        for (final dictionary in state.activeDictionaries)
          if (!finished.contains(dictionary.id)) dictionary,
      ],
      error: error ?? state.error,
    );
  }

  void clearError() {
    if (state.error == null) return;
    state = AgentProfileRegenerationState(
      activeDictionaries: state.activeDictionaries,
    );
  }
}

final agentProfileRegenerationProvider =
    NotifierProvider<
      AgentProfileRegenerationController,
      AgentProfileRegenerationState
    >(AgentProfileRegenerationController.new);
