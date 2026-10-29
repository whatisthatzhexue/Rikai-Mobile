/// OCR model catalog parsed from `assets/models/manifest.json`.
class OcrModelManifest {
  const OcrModelManifest({
    required this.version,
    required this.defaultMirrors,
    required this.sets,
  });

  final int version;
  final List<String> defaultMirrors;
  final Map<String, OcrModelSet> sets;

  factory OcrModelManifest.fromJson(Map<String, dynamic> json) {
    final rawSets = json['sets'];
    if (rawSets is! Map) {
      throw const FormatException('OCR manifest is missing "sets"');
    }
    final sets = <String, OcrModelSet>{};
    for (final entry in rawSets.entries) {
      final id = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) continue;
      sets[id] = OcrModelSet.fromJson(id, Map<String, dynamic>.from(raw));
    }
    if (sets.isEmpty) {
      throw const FormatException('OCR manifest has no model sets');
    }
    return OcrModelManifest(
      version: (json['version'] as num?)?.toInt() ?? 1,
      defaultMirrors: ((json['defaultMirrors'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      sets: sets,
    );
  }
}

class OcrModelSet {
  const OcrModelSet({
    required this.id,
    required this.displayName,
    required this.license,
    required this.files,
    this.licenseUrl = '',
    this.licenseNote = '',
    this.requiresAcceptance = false,
  });

  final String id;
  final String displayName;
  final String license;
  final String licenseUrl;
  final String licenseNote;
  final bool requiresAcceptance;
  final List<OcrModelFile> files;

  int get totalSize => files.fold(0, (sum, file) => sum + file.size);

  factory OcrModelSet.fromJson(String id, Map<String, dynamic> json) {
    final rawFiles = json['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw FormatException('OCR model set "$id" has no files');
    }
    final files = rawFiles
        .whereType<Map>()
        .map((file) => OcrModelFile.fromJson(Map<String, dynamic>.from(file)))
        .toList(growable: false);
    if (files.isEmpty) {
      throw FormatException('OCR model set "$id" has no valid files');
    }
    return OcrModelSet(
      id: id,
      displayName: (json['displayName'] as String?) ?? id,
      license: (json['license'] as String?) ?? 'UNKNOWN',
      licenseUrl: (json['licenseUrl'] as String?) ?? '',
      licenseNote: (json['licenseNote'] as String?) ?? '',
      requiresAcceptance: (json['requiresAcceptance'] as bool?) ?? false,
      files: files,
    );
  }
}

class OcrModelFile {
  const OcrModelFile({
    required this.name,
    required this.urls,
    required this.size,
    this.sha256,
  });

  final String name;
  final List<String> urls;
  final int size;
  final String? sha256;

  factory OcrModelFile.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final urls = ((json['urls'] as List<dynamic>?) ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final size = (json['size'] as num?)?.toInt() ?? 0;
    if (name == null || name.trim().isEmpty || urls.isEmpty || size <= 0) {
      throw const FormatException('OCR manifest contains an invalid file');
    }
    return OcrModelFile(
      name: name,
      urls: urls,
      size: size,
      sha256: (json['sha256'] as String?)?.toLowerCase(),
    );
  }
}
