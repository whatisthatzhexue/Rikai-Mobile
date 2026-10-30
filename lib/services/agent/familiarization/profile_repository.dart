import '../../../core/models/agent/agent_profile.dart';

abstract interface class DictionaryProfileRepository {
  Future<StoredDictionaryProfile?> load(String dictionaryId);

  Future<void> save(StoredDictionaryProfile profile);

  Future<void> delete(String dictionaryId);
}

abstract interface class UnidicProfileRepository {
  Future<StoredUnidicProfile?> loadUnidic(String unidicPathHash);

  Future<void> saveUnidic(StoredUnidicProfile profile);

  Future<void> deleteUnidic(String unidicPathHash);
}

class InMemoryDictionaryProfileRepository
    implements DictionaryProfileRepository {
  final Map<String, StoredDictionaryProfile> _values =
      <String, StoredDictionaryProfile>{};

  @override
  Future<StoredDictionaryProfile?> load(String dictionaryId) async =>
      _values[dictionaryId];

  @override
  Future<void> save(StoredDictionaryProfile profile) async {
    _values[profile.dictionaryId] = profile;
  }

  @override
  Future<void> delete(String dictionaryId) async {
    _values.remove(dictionaryId);
  }
}

class InMemoryUnidicProfileRepository implements UnidicProfileRepository {
  final Map<String, StoredUnidicProfile> _values =
      <String, StoredUnidicProfile>{};

  @override
  Future<StoredUnidicProfile?> loadUnidic(String unidicPathHash) async =>
      _values[unidicPathHash];

  @override
  Future<void> saveUnidic(StoredUnidicProfile profile) async {
    _values[profile.unidicPathHash] = profile;
  }

  @override
  Future<void> deleteUnidic(String unidicPathHash) async {
    _values.remove(unidicPathHash);
  }
}
