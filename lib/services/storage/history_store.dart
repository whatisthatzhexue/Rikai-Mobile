import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/models/corpus_entry.dart';

/// Local corpus store used by the photo-set and text-reader save actions.
///
/// Photos are copied into the app support directory as compressed JPEGs, texts
/// remain in SQLite, and every operation is local to the device. Deleting or
/// clearing a record also removes its copied image.
class HistoryStore {
  HistoryStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;
  Database? _database;
  int _sequence = 0;

  Future<Database> _db() async {
    final existing = _database;
    if (existing != null) return existing;
    final support = await _supportDirectory();
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
    final support = await _supportDirectory();
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
    final imagePath = await _storeImage(sourceImagePath, id);
    return _insert(
      id: id,
      createdAt: now,
      imagePath: imagePath,
      text: text,
      engine: engine,
      mode: mode,
      orientation: orientation,
      blocksJson: blocksJson,
    );
  }

  /// Saves a text-only session from the reader. It has no photo, so the corpus
  /// detail page renders the tokenized text without a photo pane.
  Future<CorpusEntry> saveText({
    required String text,
    required String engine,
    required String mode,
    required String orientation,
    String blocksJson = '[]',
  }) async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}_${_sequence++}';
    return _insert(
      id: id,
      createdAt: now,
      imagePath: '',
      text: text,
      engine: engine,
      mode: mode,
      orientation: orientation,
      blocksJson: blocksJson,
    );
  }

  Future<CorpusEntry> _insert({
    required String id,
    required DateTime createdAt,
    required String imagePath,
    required String text,
    required String engine,
    required String mode,
    required String orientation,
    required String blocksJson,
  }) async {
    final title = _titleFor(text, createdAt);
    final database = await _db();
    await database.insert('sessions', {
      'id': id,
      'created_at': createdAt.millisecondsSinceEpoch,
      'title': title,
      'image_path': imagePath,
      'text': text,
      'blocks_json': blocksJson,
      'engine': engine,
      'mode': mode,
      'orientation': orientation,
    });
    return CorpusEntry(
      id: id,
      createdAt: createdAt,
      title: title,
      imagePath: imagePath,
      text: text,
      engine: engine,
      mode: mode,
      orientation: orientation,
      blocksJson: blocksJson,
    );
  }

  /// Copies the source into the private corpus directory, baking EXIF rotation
  /// and shrinking the longest edge to 2048 px as a quality-85 JPEG. If the
  /// source cannot be decoded (for example an unsupported HEIC), it is copied
  /// unchanged so saving never fails because of image conversion.
  Future<String> _storeImage(String sourceImagePath, String id) async {
    final images = await _imagesDirectory();
    final target = File(p.join(images.path, '$id.jpg'));
    try {
      final bytes = await File(sourceImagePath).readAsBytes();
      final encoded = await Isolate.run(() => _compressToJpeg(bytes));
      if (encoded != null && encoded.isNotEmpty) {
        await target.writeAsBytes(encoded, flush: true);
        return target.path;
      }
    } catch (_) {
      // Fall through to a byte-for-byte copy.
    }
    final extension = p.extension(sourceImagePath).isEmpty
        ? '.jpg'
        : p.extension(sourceImagePath).toLowerCase();
    final fallback = File(p.join(images.path, '$id$extension'));
    await File(sourceImagePath).copy(fallback.path);
    return fallback.path;
  }

  /// Packs an image as a corpus JPEG. Exposed separately so the resize/encode
  /// contract can be tested without opening the SQLite database.
  static Uint8List? compressCorpusImage(Uint8List bytes) {
    return _compressToJpeg(bytes);
  }

  static Uint8List? _compressToJpeg(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var image = img.bakeOrientation(decoded);
    final longest = math.max(image.width, image.height);
    if (longest > 2048) {
      final scale = 2048 / longest;
      image = img.copyResize(
        image,
        width: math.max(1, (image.width * scale).round()),
        height: math.max(1, (image.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }
    return img.encodeJpg(image, quality: 85);
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
    final rows = await database.query(
      'sessions',
      orderBy: 'created_at DESC, rowid DESC',
    );
    return rows.map(CorpusEntry.fromMap).toList(growable: false);
  }

  Future<void> delete(CorpusEntry entry) async {
    final database = await _db();
    await database.delete('sessions', where: 'id = ?', whereArgs: [entry.id]);
    try {
      final image = File(entry.imagePath);
      if (entry.imagePath.isNotEmpty && image.existsSync()) {
        await image.delete();
      }
    } on FileSystemException {
      // The database record is authoritative; a stale image is harmless.
    }
  }

  /// Deletes every corpus record and every copied image. Returns the number of
  /// text/photo sessions that were removed.
  Future<int> clear() async {
    final database = await _db();
    final rows = await database.query('sessions', columns: ['image_path']);
    await database.delete('sessions');
    for (final row in rows) {
      final path = row['image_path'] as String? ?? '';
      if (path.isEmpty) continue;
      try {
        final image = File(path);
        if (image.existsSync()) await image.delete();
      } on FileSystemException {
        // Best effort; the database is already cleared.
      }
    }
    try {
      final images = await _imagesDirectory();
      await for (final entity in images.list(followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Ignore a file another save is still writing.
          }
        }
      }
    } on FileSystemException {
      // Missing directory means there is nothing left to clean.
    }
    return rows.length;
  }

  /// Total size of the stored corpus photos, used by storage settings.
  Future<int> imageBytes() async {
    try {
      final images = await _imagesDirectory();
      var total = 0;
      await for (final entity in images.list(followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } on FileSystemException {
            // Skip a file that disappeared during the scan.
          }
        }
      }
      return total;
    } on FileSystemException {
      return 0;
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
