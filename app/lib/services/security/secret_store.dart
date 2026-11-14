import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../agent/ports/agent_capability_exception.dart';
import '../agent/ports/secret_port.dart';
import '../../core/models/agent/agent_tool.dart';

/// Android Keystore-backed secret storage for provider API keys.
///
/// Keys never go through SharedPreferences, SQLite, logs or exports.
class FlutterSecureStorageSecretStore implements SecretPort {
  FlutterSecureStorageSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (error) {
      throw AgentCapabilityException(
        AgentToolErrorCode.notConfigured,
        '无法读取安全存储',
        cause: error,
      );
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (error) {
      throw AgentCapabilityException(
        AgentToolErrorCode.notConfigured,
        '无法写入安全存储',
        cause: error,
      );
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (error) {
      throw AgentCapabilityException(
        AgentToolErrorCode.notConfigured,
        '无法清除安全存储',
        cause: error,
      );
    }
  }
}

/// Test/fake implementation; never used by production wiring.
class InMemorySecretStore implements SecretPort {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

String agentProviderSecretKey(String providerId) =>
    'rikai.agent.provider.$providerId.api_key';
