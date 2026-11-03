import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models/agent/agent_history.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_json.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/dict_info.dart';
import '../agent/agent_run.dart';
import '../agent/familiarization/dictionary_familiarization_service.dart'
    show AgentProfileProposal;
import '../agent/familiarization/profile_repository.dart';
import 'agent_history_store.dart';
import 'agent_profile_inbox_store.dart';

/// Local SQLite store for Agent sessions, evidence and dictionary profiles.
///
/// All data stays on-device. API keys are never stored here; they belong to
/// `SecretStore` (Android Keystore).
class AgentStore
    implements
        DictionaryProfileRepository,
        UnidicProfileRepository,
        AgentHistoryRepository,
        AgentProfileInboxPersistence {
  /// Tests can point the store at an in-memory database and set the global
  /// sqflite factory to `databaseFactoryFfi`; production leaves this null.
  @visibleForTesting
  static String? debugDatabasePath;

  Database? _database;
  Future<Database>? _openingDatabase;

  Future<Database> _db() {
    final existing = _database;
    if (existing != null) return Future<Database>.value(existing);
    return _openingDatabase ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    try {
      final path =
          debugDatabasePath ??
          p.join(
            (await getApplicationSupportDirectory()).path,
            'rikai_agent.db',
          );
      final database = await openDatabase(
        path,
        version: 3,
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
            truncated INTEGER NOT NULL,
            user_text TEXT NOT NULL DEFAULT '',
            image_count INTEGER NOT NULL DEFAULT 0,
            result_json TEXT NOT NULL DEFAULT '',
            result_schema_version INTEGER NOT NULL DEFAULT 0,
            mode TEXT NOT NULL DEFAULT 'strict',
            provider_label TEXT NOT NULL DEFAULT '',
            small_model TEXT NOT NULL DEFAULT '',
            complex_model TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL DEFAULT 0
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
            confidence REAL NOT NULL,
            selected INTEGER NOT NULL DEFAULT 0,
            variant_order INTEGER NOT NULL DEFAULT 0
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
            builtin INTEGER NOT NULL DEFAULT 1,
            schema_version INTEGER NOT NULL DEFAULT 1,
            updated_at INTEGER NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE agent_profile_inbox (
            id TEXT PRIMARY KEY,
            run_id TEXT NOT NULL,
            dictionary_id TEXT NOT NULL,
            title TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            draft_json TEXT NOT NULL,
            markdown TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
          await db.execute(
            'CREATE INDEX idx_agent_runs_session ON agent_runs(session_id)',
          );
          await db.execute(
            'CREATE INDEX idx_agent_runs_started ON agent_runs(started_at)',
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
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE agent_runs "
              "ADD COLUMN user_text TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              'ALTER TABLE agent_runs '
              'ADD COLUMN image_count INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              "ALTER TABLE agent_runs "
              "ADD COLUMN result_json TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              'ALTER TABLE agent_runs '
              'ADD COLUMN result_schema_version INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              "ALTER TABLE agent_runs "
              "ADD COLUMN mode TEXT NOT NULL DEFAULT 'strict'",
            );
            await db.execute(
              "ALTER TABLE agent_runs "
              "ADD COLUMN provider_label TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              "ALTER TABLE agent_runs "
              "ADD COLUMN small_model TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              "ALTER TABLE agent_runs "
              "ADD COLUMN complex_model TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              'ALTER TABLE agent_runs '
              'ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE agent_source_versions '
              'ADD COLUMN selected INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE agent_source_versions '
              'ADD COLUMN variant_order INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE annotation_rule_sets '
              'ADD COLUMN builtin INTEGER NOT NULL DEFAULT 1',
            );
            await db.execute(
              'ALTER TABLE annotation_rule_sets '
              'ADD COLUMN schema_version INTEGER NOT NULL DEFAULT 1',
            );
            await db.execute('''
            CREATE TABLE IF NOT EXISTS agent_profile_inbox (
              id TEXT PRIMARY KEY,
              run_id TEXT NOT NULL,
              dictionary_id TEXT NOT NULL,
              title TEXT NOT NULL,
              fingerprint TEXT NOT NULL,
              draft_json TEXT NOT NULL,
              markdown TEXT NOT NULL,
              status TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_agent_runs_started '
              'ON agent_runs(started_at)',
            );
          }
        },
      );
      _database = database;
      return database;
    } finally {
      _openingDatabase = null;
    }
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

  @override
  Future<List<AgentProfileProposal>> loadPendingProfiles() async {
    final db = await _db();
    final rows = await db.query(
      'agent_profile_inbox',
      where: "status = 'pending'",
      orderBy: 'created_at ASC',
    );
    final proposals = <AgentProfileProposal>[];
    for (final row in rows) {
      try {
        final draft = agentMap(_tryDecode(row['draft_json'] as String? ?? ''));
        final profile = DictionaryProfile.fromJson(agentMap(draft['profile']));
        final dictionaryId =
            row['dictionary_id'] as String? ?? profile.dictionaryId;
        final title = row['title'] as String? ?? '';
        if (dictionaryId.isEmpty) continue;
        final rawCreatedAt = draft['created_at'] ?? row['created_at'];
        proposals.add(
          AgentProfileProposal(
            id: row['id'] as String? ?? '',
            dictionary: DictionaryInfo(
              id: dictionaryId,
              title: title,
              mdxPath: '',
            ),
            fingerprint: row['fingerprint'] as String? ?? '',
            profile: profile,
            markdown: row['markdown'] as String? ?? '',
            runId: row['run_id'] as String? ?? '',
            modelId: agentString(draft['model_id']),
            promptVersion: agentInt(draft['prompt_version'], 1),
            schemaVersion: agentInt(draft['schema_version'], 1),
            createdAt: rawCreatedAt is num
                ? DateTime.fromMillisecondsSinceEpoch(rawCreatedAt.toInt())
                : DateTime.now(),
          ),
        );
      } catch (_) {
        // A malformed pending row must not block the rest of the queue.
      }
    }
    return proposals;
  }

  @override
  Future<void> savePendingProfile(AgentProfileProposal proposal) async {
    final db = await _db();
    final now = DateTime.now().millisecondsSinceEpoch;
    final draft = <String, Object?>{
      'profile': proposal.profile.toJson(),
      'model_id': proposal.modelId,
      'prompt_version': proposal.promptVersion,
      'schema_version': proposal.schemaVersion,
      'created_at': proposal.createdAt.millisecondsSinceEpoch,
    };
    await db.insert('agent_profile_inbox', <String, Object?>{
      'id': proposal.id,
      'run_id': proposal.runId,
      'dictionary_id': proposal.dictionaryId,
      'title': proposal.title,
      'fingerprint': proposal.fingerprint,
      'draft_json': jsonEncode(draft),
      'markdown': proposal.markdown,
      'status': 'pending',
      'created_at': proposal.createdAt.millisecondsSinceEpoch,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deletePendingProfile(String id) async {
    final db = await _db();
    await db.delete(
      'agent_profile_inbox',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> deletePendingProfilesForRun(String runId) async {
    final db = await _db();
    await db.delete(
      'agent_profile_inbox',
      where: 'run_id = ?',
      whereArgs: <Object?>[runId],
    );
  }

  @override
  Future<int> markInterruptedRuns() async {
    final db = await _db();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      'agent_runs',
      <String, Object?>{
        'status': 'interrupted',
        'finished_at': now,
        'updated_at': now,
      },
      where:
          "status IN ('preparing','ocr','familiarizing','awaiting_profile',"
          "'tokenizing','reasoning','validating','running')",
    );
  }

  @override
  Future<void> saveHistoryRun({
    required String runId,
    required String sessionId,
    required String title,
    required String userText,
    required String status,
    required AgentMode mode,
    required String providerLabel,
    required String smallModel,
    required String complexModel,
    required int imageCount,
    required DateTime startedAt,
    DateTime? finishedAt,
    AgentRunResult? result,
    String errorCode = '',
  }) async {
    final db = await _db();
    final now = DateTime.now().millisecondsSinceEpoch;
    final safeTitle = title.trim().isEmpty ? '分析' : title.trim();
    final startedMs = startedAt.millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert('agent_sessions', <String, Object?>{
        'id': sessionId,
        'title': safeTitle,
        'created_at': startedMs,
        'updated_at': now,
        'mode': mode.wireName,
        'provider_id': '',
        'small_model': smallModel,
        'complex_model': complexModel,
        'dictionary_ids_json': '[]',
        'dictionary_mode': 'multi',
        'status': status,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'agent_sessions',
        <String, Object?>{
          'title': safeTitle,
          'updated_at': now,
          'mode': mode.wireName,
          'small_model': smallModel,
          'complex_model': complexModel,
          'status': status,
        },
        where: 'id = ?',
        whereArgs: <Object?>[sessionId],
      );

      final existing = await txn.query(
        'agent_runs',
        columns: <String>['result_json', 'result_schema_version', 'truncated'],
        where: 'id = ?',
        whereArgs: <Object?>[runId],
        limit: 1,
      );
      final existingRow = existing.isEmpty ? null : existing.first;
      final existingResult = existingRow?['result_json'] as String? ?? '';
      final resultJson = result == null
          ? existingResult
          : jsonEncode(<String, Object?>{
              'schema': 'rikai.agent.history-result.v1',
              'run_id': runId,
              'user_text': userText,
              'result': result.toJson(),
              'source_versions': result.sources
                  .map((source) => source.toJson())
                  .toList(),
              'citations': result.evidence.citations
                  .map((citation) => citation.toJson())
                  .toList(),
              'ocr_quality': result.ocrQuality.map(
                (imageId, quality) => MapEntry(imageId, quality.toJson()),
              ),
              'warnings': result.warnings,
            });
      final schemaVersion = result == null
          ? (existingRow?['result_schema_version'] as int? ?? 0)
          : 1;
      final truncated = result?.evidence.truncated == true
          ? 1
          : (existingRow?['truncated'] as int? ?? 0);

      await txn.insert('agent_runs', <String, Object?>{
        'id': runId,
        'session_id': sessionId,
        'status': status,
        'started_at': startedMs,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
        'error_code': errorCode,
        'input_summary': safeTitle,
        'truncated': truncated,
        'user_text': userText,
        'image_count': imageCount < 0 ? 0 : imageCount,
        'result_json': resultJson,
        'result_schema_version': schemaVersion,
        'mode': mode.wireName,
        'provider_label': providerLabel,
        'small_model': smallModel,
        'complex_model': complexModel,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (result == null) return;
      await txn.delete(
        'agent_source_versions',
        where: 'run_id = ?',
        whereArgs: <Object?>[runId],
      );
      await txn.delete(
        'agent_citations',
        where: 'run_id = ?',
        whereArgs: <Object?>[runId],
      );

      for (final source in result.input.sources) {
        if (source.isImage) {
          for (var index = 0; index < source.variants.length; index++) {
            final variant = source.variants[index];
            final selected = source.selectedVariant?.id == variant.id ? 1 : 0;
            await txn.insert(
              'agent_source_versions',
              <String, Object?>{
                'id': '$runId:${source.id}:${variant.id}',
                'run_id': runId,
                'source_id': source.id,
                'image_id': source.imageId,
                'variant_id': variant.id,
                'origin': variant.origin.wireName,
                'text': variant.text,
                'blocks_json': '[]',
                'engine': variant.engine,
                'mode': variant.mode.name,
                'confidence': variant.confidence,
                'selected': selected,
                'variant_order': index,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          continue;
        }
        await txn.insert('agent_source_versions', <String, Object?>{
          'id': '$runId:${source.id}:text',
          'run_id': runId,
          'source_id': source.id,
          'image_id': null,
          'variant_id': null,
          'origin': AgentQuoteOrigin.userText.wireName,
          'text': source.text,
          'blocks_json': '[]',
          'engine': '',
          'mode': '',
          'confidence': 0,
          'selected': 1,
          'variant_order': 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final citation in result.evidence.citations) {
        await txn.insert('agent_citations', <String, Object?>{
          'id': '$runId:${citation.id}',
          'run_id': runId,
          'message_id': '',
          'kind': citation.kind,
          'dictionary_id': citation.dictionaryId,
          'dictionary_order': citation.dictionaryOrder,
          'entry_key': citation.entryKey,
          'matched_key': citation.matchedKey,
          'headword': citation.headword,
          'snippet': citation.snippet,
          'source_id': '',
          'tool_call_id': citation.toolCallId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<List<AgentHistoryEntry>> listHistory() async {
    final db = await _db();
    final rows = await db.query(
      'agent_runs',
      columns: <String>[
        'id',
        'session_id',
        'status',
        'started_at',
        'finished_at',
        'error_code',
        'input_summary',
        'image_count',
        'result_json',
        'mode',
        'provider_label',
        'small_model',
        'complex_model',
      ],
      where: "status IN ('done','error','cancelled','interrupted')",
      orderBy: 'COALESCE(finished_at, started_at) DESC, started_at DESC',
    );
    return <AgentHistoryEntry>[
      for (final row in rows) _historyEntryFromRow(row),
    ];
  }

  @override
  Future<AgentHistoryDetail?> loadHistoryDetail(String runId) async {
    final db = await _db();
    final rows = await db.query(
      'agent_runs',
      where: 'id = ?',
      whereArgs: <Object?>[runId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final entry = _historyEntryFromRow(row);
    final userText = row['user_text'] as String? ?? '';
    final rawResult = row['result_json'] as String? ?? '';
    if (rawResult.isEmpty) {
      return AgentHistoryDetail(entry: entry, userText: userText);
    }
    final decoded = _tryDecode(rawResult);
    final map = agentMap(decoded);
    if (map.isEmpty) {
      return AgentHistoryDetail(
        entry: entry,
        userText: userText,
        unsupportedFormat: true,
      );
    }
    final schema = agentString(map['schema']);
    final Map<String, Object?> resultMap;
    var storedUserText = userText;
    if (schema == 'rikai.agent.history-result.v1') {
      resultMap = agentMap(map['result']);
      storedUserText = agentString(map['user_text'], userText);
    } else if (schema == AgentRunResult.resultSchema) {
      // Legacy rows written before the history wrapper was introduced.
      resultMap = map;
    } else {
      return AgentHistoryDetail(
        entry: entry,
        userText: userText,
        unsupportedFormat: true,
      );
    }
    if (resultMap.isEmpty) {
      return AgentHistoryDetail(
        entry: entry,
        userText: userText,
        unsupportedFormat: true,
      );
    }
    try {
      final result = AgentRunResult.fromJson(resultMap);
      return AgentHistoryDetail(
        entry: entry,
        userText: storedUserText.isEmpty
            ? result.input.userText
            : storedUserText,
        result: result,
      );
    } catch (_) {
      return AgentHistoryDetail(
        entry: entry,
        userText: userText,
        unsupportedFormat: true,
      );
    }
  }

  @override
  Future<void> deleteHistoryRun(String runId) =>
      deleteHistoryRuns(<String>[runId]);

  @override
  Future<void> deleteHistoryRuns(Iterable<String> runIds) async {
    final ids = runIds
        .where((runId) => runId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;
    final db = await _db();
    await db.transaction((txn) async {
      final sessionIds = <String>{};
      // Keep each IN clause below SQLite's variable limit on devices with a
      // very long history; the default limit is 999.
      for (var start = 0; start < ids.length; start += 400) {
        final end = start + 400 < ids.length ? start + 400 : ids.length;
        final chunk = ids.sublist(start, end);
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await txn.query(
          'agent_runs',
          columns: <String>['session_id'],
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
        for (final row in rows) {
          final sessionId = row['session_id'] as String?;
          if (sessionId != null && sessionId.isNotEmpty) {
            sessionIds.add(sessionId);
          }
        }
        await txn.delete(
          'agent_citations',
          where: 'run_id IN ($placeholders)',
          whereArgs: chunk,
        );
        await txn.delete(
          'agent_source_versions',
          where: 'run_id IN ($placeholders)',
          whereArgs: chunk,
        );
        await txn.delete(
          'agent_messages',
          where: 'run_id IN ($placeholders)',
          whereArgs: chunk,
        );
        await txn.delete(
          'agent_tool_calls',
          where: 'run_id IN ($placeholders)',
          whereArgs: chunk,
        );
        await txn.delete(
          'agent_runs',
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
      for (final sessionId in sessionIds) {
        final remaining = await txn.query(
          'agent_runs',
          columns: <String>['id'],
          where: 'session_id = ?',
          whereArgs: <Object?>[sessionId],
          limit: 1,
        );
        if (remaining.isNotEmpty) continue;
        await txn.delete(
          'agent_sessions',
          where: 'id = ?',
          whereArgs: <Object?>[sessionId],
        );
      }
    });
  }

  @override
  Future<void> clearHistory() async {
    final db = await _db();
    await db.transaction((txn) async {
      await txn.delete('agent_citations');
      await txn.delete('agent_source_versions');
      await txn.delete('agent_messages');
      await txn.delete('agent_tool_calls');
      await txn.delete('agent_runs');
      await txn.delete('agent_sessions');
    });
  }

  AgentHistoryEntry _historyEntryFromRow(Map<String, Object?> row) {
    final rawFinished = row['finished_at'];
    final finishedAt = rawFinished is num
        ? DateTime.fromMillisecondsSinceEpoch(rawFinished.toInt())
        : null;
    return AgentHistoryEntry(
      runId: row['id'] as String? ?? '',
      sessionId: row['session_id'] as String? ?? '',
      title: row['input_summary'] as String? ?? '',
      status: AgentHistoryStatus.fromWire(row['status']),
      mode: AgentMode.fromWire(row['mode']),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['started_at'] as int?) ?? 0,
      ),
      finishedAt: finishedAt,
      providerLabel: row['provider_label'] as String? ?? '',
      smallModel: row['small_model'] as String? ?? '',
      complexModel: row['complex_model'] as String? ?? '',
      imageCount: (row['image_count'] as int?) ?? 0,
      hasResult: (row['result_json'] as String? ?? '').isNotEmpty,
      errorCode: row['error_code'] as String? ?? '',
    );
  }

  @visibleForTesting
  Future<List<Map<String, Object?>>> debugRows(String table) async {
    final db = await _db();
    return db.query(table);
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
