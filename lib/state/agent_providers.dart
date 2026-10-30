import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/agent/agent_provider.dart';
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

final agentGrammarCatalogProvider = FutureProvider<GrammarPatternCatalog>(
  (ref) => loadGrammarPatterns(),
  retry: (retryCount, error) => null,
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
