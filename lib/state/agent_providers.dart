import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/agent/agent_limits.dart';
import '../core/models/agent/agent_profile.dart';
import '../core/models/agent/agent_provider.dart';
import '../core/models/dict_info.dart';
import '../services/agent/agent_background_service.dart';
import '../services/agent/agent_image_picker.dart';
import '../services/agent/agent_provider_tester.dart';
import '../services/agent/evidence_cache.dart';
import '../services/agent/familiarization/profile_fingerprint.dart';
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

/// Explicit provider connectivity test. Injectable so widget tests never open
/// a real HTTP connection or read a real API key.
final agentProviderTesterProvider = Provider<AgentProviderTester>(
  (ref) => AgentProviderTester(secrets: ref.watch(secretStoreProvider)),
);

/// App-scoped text-run evidence cache. It is memory-only and survives page
/// navigation but not process death.
final agentEvidenceCacheProvider = Provider<AgentEvidenceCache>(
  (ref) => AgentEvidenceCache(),
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

/// Reference-counted foreground-service hold.
///
/// The Android service is process-global. An Agent run and a profile
/// generation can overlap (for example the deferred first-run profiles while
/// the user opens the profile manager), so neither may stop the service while
/// the other still needs it. The lease starts on the first hold and stops only
/// after the last one is released.
class AgentBackgroundLease {
  AgentBackgroundLease(this._port);

  final AgentBackgroundPort _port;
  int _holds = 0;

  /// Serializes platform start/stop calls. Without this, a new run acquiring
  /// while the previous release is stopping the service could issue
  /// start-after-stop in the opposite order and leave the service off.
  Future<void> _tail = Future<void>.value();

  Future<void> _serialize(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((_) {});
    return next;
  }

  Future<void> acquire() {
    _holds++;
    if (_holds != 1) return Future<void>.value();
    return _serialize(_port.start);
  }

  Future<void> release() {
    if (_holds <= 0) return Future<void>.value();
    _holds--;
    if (_holds != 0) return Future<void>.value();
    return _serialize(_port.stop);
  }

  Future<void> releaseAll() {
    if (_holds == 0) return Future<void>.value();
    _holds = 0;
    return _serialize(_port.stop);
  }
}

final agentBackgroundLeaseProvider = Provider<AgentBackgroundLease>((ref) {
  final lease = AgentBackgroundLease(ref.watch(agentBackgroundServiceProvider));
  ref.onDispose(() => unawaited(lease.releaseAll()));
  return lease;
});

/// Dependency seam for profile freshness checks. Production uses the real
/// file-stat based fingerprint; tests can override it to avoid real I/O.
typedef DictionaryProfileFingerprintBuilder =
    Future<String> Function(
      DictionaryInfo dictionary, {
      required int promptVersion,
      required int schemaVersion,
      required AgentProfileLanguage language,
    });

final dictionaryProfileFingerprintProvider =
    Provider<DictionaryProfileFingerprintBuilder>(
      (ref) => dictionaryProfileFingerprint,
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
