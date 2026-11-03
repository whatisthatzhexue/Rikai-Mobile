import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rikai_mobile/services/storage/agent_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates a v2 Agent DB to v3 history/profile-inbox schema', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('rikai-agent-db-');
    final path = p.join(directory.path, 'rikai_agent.db');
    addTearDown(() async {
      AgentStore.debugDatabasePath = null;
      await directory.delete(recursive: true);
    });

    final old = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
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
          CREATE TABLE annotation_rule_sets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            version INTEGER NOT NULL,
            rules_json TEXT NOT NULL,
            enabled INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
    await old.insert('agent_runs', <String, Object?>{
      'id': 'legacy-run',
      'session_id': 'legacy-session',
      'status': 'done',
      'started_at': 1000,
      'finished_at': 2000,
      'error_code': '',
      'input_summary': '旧记录',
      'truncated': 0,
    });
    await old.close();

    AgentStore.debugDatabasePath = path;
    final store = AgentStore();
    addTearDown(store.close);

    final runs = await store.debugRows('agent_runs');
    expect(runs, hasLength(1));
    expect(runs.single['id'], 'legacy-run');
    expect(runs.single['user_text'], '');
    expect(runs.single['image_count'], 0);
    expect(runs.single['result_json'], '');
    expect(runs.single['result_schema_version'], 0);
    expect(runs.single['mode'], 'strict');
    expect(runs.single['updated_at'], 0);

    final versions = await store.debugRows('agent_source_versions');
    expect(versions, isEmpty);
    final rules = await store.debugRows('annotation_rule_sets');
    expect(rules, isEmpty);
    final inbox = await store.debugRows('agent_profile_inbox');
    expect(inbox, isEmpty);
  });
}
