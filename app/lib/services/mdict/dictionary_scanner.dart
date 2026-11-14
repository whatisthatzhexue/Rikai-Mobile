import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../core/models/dictionary_scan.dart';

/// Recursively discovers `.mdx` files without blocking the UI isolate.
class DictionaryScanner {
  const DictionaryScanner();

  Future<List<DictionaryScanEntry>> scan(
    String root, {
    Set<String> existingPaths = const {},
  }) async {
    final raw = await Isolate.run(() => _scanSync(root));
    final existing = existingPaths
        .map((path) => p.normalize(path).toLowerCase())
        .toSet();
    final entries = <DictionaryScanEntry>[];
    for (final map in raw) {
      final path = map['path']! as String;
      final isExisting = existing.contains(p.normalize(path).toLowerCase());
      entries.add(
        DictionaryScanEntry(
          path: path,
          fileName: map['fileName']! as String,
          folder: map['folder']! as String,
          size: map['size']! as int,
          mddPaths: (map['mddPaths']! as List).cast<String>(),
          cssPaths: (map['cssPaths']! as List).cast<String>(),
          title: map['title']! as String,
          status: isExisting
              ? DictionaryScanStatus.existing
              : DictionaryScanStatus.scanning,
          message: isExisting ? '已在词典库中' : '',
        ),
      );
    }
    return entries;
  }
}

List<Map<String, Object?>> _scanSync(String root) {
  final directory = Directory(root);
  if (!directory.existsSync()) return const [];
  final files = <String>[];
  final seen = <String>{};
  try {
    final entities = directory.listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      if (entity is! File) continue;
      final path = p.normalize(entity.path);
      if (!seen.add(path)) continue;
      files.add(path);
    }
  } on FileSystemException {
    return const [];
  }

  final byFolder = <String, List<String>>{};
  for (final file in files) {
    byFolder.putIfAbsent(p.dirname(file), () => []).add(file);
  }

  final result = <Map<String, Object?>>[];
  for (final entry in byFolder.entries) {
    final folder = entry.key;
    final folderFiles = entry.value;
    for (final path in folderFiles.where(
      (file) => p.extension(file).toLowerCase() == '.mdx',
    )) {
      final basename = p.basenameWithoutExtension(path).toLowerCase();
      final mddPaths = folderFiles
          .where(
            (file) =>
                p.extension(file).toLowerCase() == '.mdd' &&
                p.basenameWithoutExtension(file).toLowerCase() == basename,
          )
          .toList(growable: false);
      final cssPaths = folderFiles
          .where((file) => p.extension(file).toLowerCase() == '.css')
          .toList(growable: false);
      int size;
      try {
        size = File(path).lengthSync();
      } on FileSystemException {
        size = 0;
      }
      result.add({
        'path': path,
        'fileName': p.basename(path),
        'folder': folder,
        'size': size,
        'mddPaths': mddPaths,
        'cssPaths': cssPaths,
        'title': scanEntryTitleFallback(path),
      });
    }
  }
  result.sort(
    (a, b) => (a['path']! as String).toLowerCase().compareTo(
      (b['path']! as String).toLowerCase(),
    ),
  );
  return result;
}
