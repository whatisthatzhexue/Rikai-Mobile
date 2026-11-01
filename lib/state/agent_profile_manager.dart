import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/agent/agent_profile.dart';
import '../core/models/agent/agent_provider.dart';
import '../core/models/dict_info.dart';
import '../services/agent/familiarization/dictionary_familiarization_service.dart';
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
