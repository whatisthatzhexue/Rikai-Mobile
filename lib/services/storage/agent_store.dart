import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models/agent/agent_json.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../agent/familiarization/profile_repository.dart';

/// Local SQLite store for Agent sessions, evidence and dictionary profiles.
///
/// All data stays on-device. API keys are never stored here; they belong to
/// `SecretStore` (Android Keystore).
class AgentStore
    implements DictionaryProfileRepository, UnidicProfileRepository {
  Database? _database;

  Future<Database> _db() async {
    final existing = _database;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final database = await openDatabase(
      p.join(support.path, 'rikai_agent.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE agent_providers (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            display_name TEXT NOT NULL,
            base_url TEXT NOT NULL,
            small_model TEXT NOT NULL,
            complex_model TEXT NOT NULL,
            timeout_seconds INTEGER NOT NULL,
            capabilities_json TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE agent_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            mode TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            small_model TEXT NOT NULL,
            complex_model TEXT NOT NULL,
            dictionary_ids_json TEXT NOT NULL,
            dictionary_mode TEXT NOT NULL,
            status TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE agent_runs (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            finished_at INTEGER,
            error_code TEXT NOT NULL,
            input_summary TEXT NOT NULL,
            truncated INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE agent_messages (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content_markdown TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            model_id TEXT NOT NULL,
            stage TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE agent_tool_calls (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            tool_name TEXT NOT NULL,
            tool_version TEXT NOT NULL,
            input_json_redacted TEXT NOT NULL,
            result_json TEXT NOT NULL,
            status TEXT NOT NULL,
            elapsed_ms INTEGER NOT NULL,
            error_code TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE agent_source_versions (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            source_id TEXT NOT NULL,
            image_id TEXT,
            variant_id TEXT,
            origin TEXT NOT NULL,
            text TEXT NOT NULL,
            blocks_json TEXT NOT NULL,
            engine TEXT NOT NULL,
            mode TEXT NOT NULL,
            confidence REAL NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE agent_citations (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            dictionary_id TEXT NOT NULL,
            dictionary_order INTEGER NOT NULL,
            entry_key TEXT NOT NULL,
            matched_key TEXT NOT NULL,
            headword TEXT NOT NULL,
            snippet TEXT NOT NULL,
            source_id TEXT NOT NULL,
            tool_call_id TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE dictionary_profiles (
            dictionary_id TEXT PRIMARY KEY,
            title TEXT NOT NULL DEFAULT '',
            fingerprint TEXT NOT NULL,
            profile_json TEXT NOT NULL,
            markdown TEXT NOT NULL,
            status TEXT NOT NULL,
            confirmed_at INTEGER,
            model_id TEXT NOT NULL,
            prompt_version INTEGER NOT NULL,
            schema_version INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE unidic_profiles (
            unidic_path_hash TEXT PRIMARY KEY,
            fingerprint TEXT NOT NULL,
            profile_json TEXT NOT NULL,
            markdown TEXT NOT NULL,
            confirmed_at INTEGER,
            schema_version INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE annotation_rule_sets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            version INTEGER NOT NULL,
            rules_json TEXT NOT NULL,
            enabled INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_agent_runs_session ON agent_runs(session_id)',
        );
        await db.execute(
          'CREATE INDEX idx_agent_messages_run ON agent_messages(run_id)',
        );
        await db.execute(
          'CREATE INDEX idx_agent_citations_run ON agent_citations(run_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE dictionary_profiles "
            "ADD COLUMN title TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
    _database = database;
    return database;
  }

  @override
  Future<StoredDictionaryProfile?> load(String dictionaryId) async {
    final db = await _db();
    final rows = await db.query(
      'dictionary_profiles',
      where: 'dictionary_id = ?',
      whereArgs: <Object?>[dictionaryId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final profileJson = agentMap(
      _tryDecode(row['profile_json'] as String? ?? ''),
    );
    final rawConfirmed = row['confirmed_at'] as int?;
    return StoredDictionaryProfile(
      dictionaryId: dictionaryId,
      title: row['title'] as String? ?? '',
      fingerprint: row['fingerprint'] as String? ?? '',
      markdown: row['markdown'] as String? ?? '',
      status: DictionaryProfileStatus.fromWire(row['status']),
      profile: profileJson.isEmpty
          ? null
          : DictionaryProfile.fromJson(profileJson),
      confirmedAt: rawConfirmed == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(rawConfirmed),
      modelId: row['model_id'] as String? ?? '',
      promptVersion: (row['prompt_version'] as int?) ?? 1,
      schemaVersion: (row['schema_version'] as int?) ?? 1,
    );
  }

  @override
  Future<void> save(StoredDictionaryProfile profile) async {
    final db = await _db();
    await db.insert('dictionary_profiles', <String, Object?>{
      'dictionary_id': profile.dictionaryId,
      'title': profile.title,
      'fingerprint': profile.fingerprint,
      'profile_json': jsonEncode(profile.profile?.toJson() ?? const {}),
      'markdown': profile.markdown,
      'status': profile.status.wireName,
      'confirmed_at': profile.confirmedAt?.millisecondsSinceEpoch,
      'model_id': profile.modelId,
      'prompt_version': profile.promptVersion,
      'schema_version': profile.schemaVersion,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String dictionaryId) async {
    final db = await _db();
    await db.delete(
      'dictionary_profiles',
      where: 'dictionary_id = ?',
      whereArgs: <Object?>[dictionaryId],
    );
  }

  /// Lists stored profiles for the Agent profile manager, newest first.
  Future<List<StoredDictionaryProfile>> listDictionaryProfiles() async {
    final db = await _db();
    final rows = await db.query(
      'dictionary_profiles',
      orderBy: 'confirmed_at DESC, dictionary_id ASC',
    );
    return <StoredDictionaryProfile>[
      for (final row in rows) _profileFromRow(row),
    ];
  }

  /// Replaces the editable Markdown while keeping the fingerprint/status so
  /// the profile remains valid for the same dictionary version.
  Future<void> updateProfileMarkdown(
    String dictionaryId,
    String markdown,
  ) async {
    final db = await _db();
    await db.update(
      'dictionary_profiles',
      <String, Object?>{
        'markdown': markdown,
        'confirmed_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'dictionary_id = ?',
      whereArgs: <Object?>[dictionaryId],
    );
  }

  Future<void> deleteDictionaryProfiles(List<String> dictionaryIds) async {
    if (dictionaryIds.isEmpty) return;
    final db = await _db();
    final placeholders = List<String>.filled(
      dictionaryIds.length,
      '?',
    ).join(',');
    await db.delete(
      'dictionary_profiles',
      where: 'dictionary_id IN ($placeholders)',
      whereArgs: dictionaryIds,
    );
  }

  StoredDictionaryProfile _profileFromRow(Map<String, Object?> row) {
    final profileJson = agentMap(
      _tryDecode(row['profile_json'] as String? ?? ''),
    );
    final rawConfirmed = row['confirmed_at'] as int?;
    return StoredDictionaryProfile(
      dictionaryId: row['dictionary_id'] as String? ?? '',
      title: row['title'] as String? ?? '',
      fingerprint: row['fingerprint'] as String? ?? '',
      markdown: row['markdown'] as String? ?? '',
      status: DictionaryProfileStatus.fromWire(row['status']),
      profile: profileJson.isEmpty
          ? null
          : DictionaryProfile.fromJson(profileJson),
      confirmedAt: rawConfirmed == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(rawConfirmed),
      modelId: row['model_id'] as String? ?? '',
      promptVersion: (row['prompt_version'] as int?) ?? 1,
      schemaVersion: (row['schema_version'] as int?) ?? 1,
    );
  }

  @override
  Future<StoredUnidicProfile?> loadUnidic(String unidicPathHash) async {
    final db = await _db();
    final rows = await db.query(
      'unidic_profiles',
      where: 'unidic_path_hash = ?',
      whereArgs: <Object?>[unidicPathHash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final rawConfirmed = row['confirmed_at'] as int?;
    return StoredUnidicProfile(
      unidicPathHash: unidicPathHash,
      fingerprint: row['fingerprint'] as String? ?? '',
      profile: UnidicProfile.fromJson(
        agentMap(_tryDecode(row['profile_json'] as String? ?? '')),
      ),
      markdown: row['markdown'] as String? ?? '',
      confirmedAt: rawConfirmed == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(rawConfirmed),
    );
  }

  @override
  Future<void> saveUnidic(StoredUnidicProfile profile) async {
    final db = await _db();
    await db.insert('unidic_profiles', <String, Object?>{
      'unidic_path_hash': profile.unidicPathHash,
      'fingerprint': profile.fingerprint,
      'profile_json': jsonEncode(profile.profile.toJson()),
      'markdown': profile.markdown,
      'confirmed_at': profile.confirmedAt?.millisecondsSinceEpoch,
      'schema_version': profile.profile.schemaVersion,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteUnidic(String unidicPathHash) async {
    final db = await _db();
    await db.delete(
      'unidic_profiles',
      where: 'unidic_path_hash = ?',
      whereArgs: <Object?>[unidicPathHash],
    );
  }

  Future<List<AgentProviderConfig>> listProviders() async {
    final db = await _db();
    final rows = await db.query('agent_providers', orderBy: 'updated_at DESC');
    return <AgentProviderConfig>[
      for (final row in rows)
        AgentProviderConfig.fromJson(<String, Object?>{
          'id': row['id'],
          'kind': row['kind'],
          'display_name': row['display_name'],
          'base_url': row['base_url'],
          'small_model': row['small_model'],
          'complex_model': row['complex_model'],
          'timeout_seconds': row['timeout_seconds'],
          'capabilities': agentMap(
            _tryDecode(row['capabilities_json'] as String? ?? ''),
          ),
        }),
    ];
  }

  Future<void> saveProvider(AgentProviderConfig provider) async {
    final db = await _db();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('agent_providers', <String, Object?>{
      'id': provider.id,
      'kind': provider.kind.wireName,
      'display_name': provider.displayName,
      'base_url': provider.baseUrl,
      'small_model': provider.smallModel,
      'complex_model': provider.complexModel,
      'timeout_seconds': provider.timeoutSeconds,
      'capabilities_json': jsonEncode(<String, Object?>{
        'streaming': provider.supportsStreaming,
        'max_output_tokens': provider.maxOutputTokens,
      }),
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteProvider(String id) async {
    final db = await _db();
    await db.delete(
      'agent_providers',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  static Object? _tryDecode(String raw) {
    if (raw.isEmpty) return const <String, Object?>{};
    try {
      return jsonDecode(raw);
    } catch (_) {
      return const <String, Object?>{};
    }
  }
}
