import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/agent/agent_profile.dart';
import '../core/models/agent/agent_provider.dart';
import '../services/agent/agent_image_picker.dart';
import '../services/agent/familiarization/profile_repository.dart';
import '../services/agent/grammar_patterns.dart';
import '../services/agent/ports/secret_port.dart';
import '../services/security/secret_store.dart';
import '../services/storage/agent_store.dart';

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

class SelectedAgentProviderNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) {
    state = id;
  }
}

final selectedAgentProviderProvider =
    NotifierProvider<SelectedAgentProviderNotifier, String?>(
      SelectedAgentProviderNotifier.new,
    );
