import 'package:path/path.dart' as p;

enum DictionaryScanStatus { scanning, importable, existing, unsupported }

class DictionaryScanEntry {
  const DictionaryScanEntry({
    required this.path,
    required this.fileName,
    required this.folder,
    required this.size,
    required this.mddPaths,
    required this.cssPaths,
    required this.title,
    this.status = DictionaryScanStatus.scanning,
    this.message = '',
  });

  final String path;
  final String fileName;
  final String folder;
  final int size;
  final List<String> mddPaths;
  final List<String> cssPaths;
  final String title;
  final DictionaryScanStatus status;
  final String message;

  DictionaryScanEntry copyWith({
    String? title,
    DictionaryScanStatus? status,
    String? message,
  }) {
    return DictionaryScanEntry(
      path: path,
      fileName: fileName,
      folder: folder,
      size: size,
      mddPaths: mddPaths,
      cssPaths: cssPaths,
      title: title ?? this.title,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

class DictionaryScanResult {
  const DictionaryScanResult(this.entries);

  final List<DictionaryScanEntry> entries;
}

String scanEntryTitleFallback(String path) {
  final name = p.basenameWithoutExtension(path);
  return name.isEmpty ? p.basename(path) : name;
}
