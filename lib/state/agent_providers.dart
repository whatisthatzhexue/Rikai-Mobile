import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/agent/agent_limits.dart';
import '../core/models/agent/agent_profile.dart';
import '../core/models/agent/agent_provider.dart';
import '../services/agent/agent_background_service.dart';
import '../services/agent/agent_image_picker.dart';
import '../services/agent/familiarization/profile_repository.dart';
import '../services/agent/grammar_patterns.dart';
import '../services/agent/ports/secret_port.dart';
import '../services/security/secret_store.dart';
import '../services/storage/agent_store.dart';
import 'providers.dart';

/// Request-level policy snapshot. Tests may override it to disable the F7
/// coverage pass or tighten budgets; production uses the standard policy.
final agentLimitsProvider = Provider<AgentLimits>(
  (ref) => AgentLimits.standard,
);

final agentStoreProvider = Provider<AgentStore>((ref) {
  final store = AgentStore();
  ref.onDispose(store.close);
  return store;
});

final secretStoreProvider = Provider<SecretPort>((ref) {
  return FlutterSecureStorageSecretStore();
});

final agentProvidersProvider = FutureProvider<List<AgentProviderConfig>>(
  (ref) => ref.watch(agentStoreProvider).listProviders(),
  retry: (retryCount, error) => null,
);

final agentProfilesProvider = FutureProvider<List<StoredDictionaryProfile>>(
  (ref) => ref.watch(agentStoreProvider).listDictionaryProfiles(),
  retry: (retryCount, error) => null,
);

/// Profile persistence seam so the inbox can be tested without opening SQLite.
final agentProfileRepositoryProvider = Provider<DictionaryProfileRepository>(
  (ref) => ref.watch(agentStoreProvider),
);

final agentGrammarCatalogProvider = FutureProvider<GrammarPatternCatalog>(
  (ref) => loadGrammarPatterns(),
  retry: (retryCount, error) => null,
);

final agentImagePickerProvider = Provider<AgentImagePicker>(
  (ref) => PlatformAgentImagePicker(),
);

final agentBackgroundServiceProvider = Provider<AgentBackgroundPort>(
  (ref) => const PlatformAgentBackgroundService(),
);

/// App-wide selected model service. It is persisted in SharedPreferences so
/// leaving the Agent page or restarting the app keeps the user's choice; the
/// Agent run itself still snapshots the resolved provider config.
class SelectedAgentProviderNotifier extends Notifier<String?> {
  static const _key = 'agent_selected_provider_id';

  late SharedPreferences _preferences;

  @override
  String? build() {
    _preferences = ref.watch(sharedPreferencesProvider);
    final stored = _preferences.getString(_key);
    return stored == null || stored.trim().isEmpty ? null : stored.trim();
  }

  void select(String? id) {
    final next = id == null || id.trim().isEmpty ? null : id.trim();
    state = next;
    if (next == null) {
      _preferences.remove(_key);
    } else {
      _preferences.setString(_key, next);
    }
  }
}

final selectedAgentProviderProvider =
    NotifierProvider<SelectedAgentProviderNotifier, String?>(
      SelectedAgentProviderNotifier.new,
    );
