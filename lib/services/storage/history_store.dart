import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models/corpus_entry.dart';

/// Minimal local corpus store used by the photo-set save action.
///
/// The full Phase 5 history UI/history lifecycle can extend this schema; the
/// important contract here is that no photo or text leaves the device.
class HistoryStore {
  Database? _database;
  int _sequence = 0;

  Future<Database> _db() async {
    final existing = _database;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final path = p.join(support.path, 'rikai_history.db');
    final database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            title TEXT NOT NULL,
            image_path TEXT NOT NULL,
            text TEXT NOT NULL,
            blocks_json TEXT NOT NULL,
            engine TEXT NOT NULL,
            mode TEXT NOT NULL,
            orientation TEXT NOT NULL
          )
        ''');
      },
    );
    _database = database;
    return database;
  }

  Future<Directory> _imagesDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'corpus', 'images'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<CorpusEntry> savePhoto({
    required String sourceImagePath,
    required String text,
    required String engine,
    required String mode,
    required String orientation,
    String blocksJson = '[]',
  }) async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}_${_sequence++}';
    final images = await _imagesDirectory();
    final extension = p.extension(sourceImagePath).isEmpty
        ? '.jpg'
        : p.extension(sourceImagePath).toLowerCase();
    final target = File(p.join(images.path, '$id$extension'));
    await File(sourceImagePath).copy(target.path);
    final title = _titleFor(text, now);
    final database = await _db();
    await database.insert('sessions', {
      'id': id,
      'created_at': now.millisecondsSinceEpoch,
      'title': title,
      'image_path': target.path,
      'text': text,
      'blocks_json': blocksJson,
      'engine': engine,
      'mode': mode,
      'orientation': orientation,
    });
    return CorpusEntry(
      id: id,
      createdAt: now,
      title: title,
      imagePath: target.path,
      text: text,
      engine: engine,
      mode: mode,
      orientation: orientation,
      blocksJson: blocksJson,
    );
  }

  String _titleFor(String text, DateTime now) {
    final firstLine = text
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) {
      return '照片 ${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
    }
    return firstLine.length <= 30 ? firstLine : firstLine.substring(0, 30);
  }

  Future<List<CorpusEntry>> list() async {
    final database = await _db();
    final rows = await database.query('sessions', orderBy: 'created_at DESC');
    return rows.map(CorpusEntry.fromMap).toList(growable: false);
  }

  Future<void> delete(CorpusEntry entry) async {
    final database = await _db();
    await database.delete('sessions', where: 'id = ?', whereArgs: [entry.id]);
    try {
      final image = File(entry.imagePath);
      if (image.existsSync()) await image.delete();
    } on FileSystemException {
      // The database record is authoritative; a stale image is harmless.
    }
  }

  Future<String> blocksJsonFor(Iterable<Object?>? blocks) async {
    return jsonEncode(blocks ?? const []);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
