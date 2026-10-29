import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns private copies of photos in the app's capture session directory.
class CaptureStorage {
  CaptureStorage({Future<Directory> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectory;
  int _sequence = 0;

  Future<Directory> sessionDirectory() async {
    final temp = await _temporaryDirectory();
    final directory = Directory(p.join(temp.path, 'rikai_capture'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> clearSessionDirectory() async {
    try {
      final directory = await sessionDirectory();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Ignore a stale file; the next capture can still proceed.
          }
        }
      }
    } on FileSystemException {
      // The session directory may be unavailable; capture will recreate it.
    }
  }

  Future<String> importPhoto(String sourcePath) async {
    final directory = await sessionDirectory();
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath).toLowerCase();
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}$extension';
    final target = File(p.join(directory.path, name));
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  /// Rotates a private session copy clockwise and overwrites it in place.
  /// The photo set clears that photo's OCR cache so the next run sees the new
  /// orientation. Device originals are never modified.
  Future<void> rotateSessionPhoto(String path, {int degrees = 90}) async {
    final directory = await sessionDirectory();
    final normalized = p.normalize(path);
    if (!p.isWithin(directory.path, normalized)) {
      throw FileSystemException('只能旋转照片集内的副本');
    }
    final file = File(normalized);
    if (!file.existsSync()) {
      throw FileSystemException('照片文件不存在');
    }
    final decoded = img.decodeImage(await file.readAsBytes());
    if (decoded == null) {
      throw FileSystemException('无法解码照片');
    }
    final rotated = img.copyRotate(decoded, angle: degrees);
    final extension = p.extension(normalized).toLowerCase();
    final encoded = extension == '.png'
        ? img.encodePng(rotated)
        : img.encodeJpg(rotated, quality: 95);
    await file.writeAsBytes(encoded, flush: true);
  }

  Future<void> deleteSessionFile(String path) async {
    try {
      final directory = await sessionDirectory();
      final normalized = p.normalize(path);
      if (!p.isWithin(directory.path, normalized)) return;
      final file = File(normalized);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Removing the session copy is best effort; the UI removes the entry.
    }
  }

  /// Attempts to delete the original picked file. image_picker commonly hands
  /// back a cache copy rather than a MediaStore URI, so callers must treat a
  /// false result as "only removed from the photo set".
  Future<bool> tryDeleteOriginal(String? path) async {
    if (path == null || path.isEmpty) return false;
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      await file.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
