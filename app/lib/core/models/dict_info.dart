import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Trims whitespace, strips a `file://` prefix and trailing separators.
String normalizeDictionaryPath(String input) {
  var path = input.trim();
  if (path.startsWith('file://')) {
    path = path.substring('file://'.length);
  }
  while (path.length > 1 && (path.endsWith('/') || path.endsWith(r'\'))) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String dictionaryFileName(String path) {
  final normalized = normalizeDictionaryPath(path);
  final slash = normalized.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

String dictionaryTitleFallback(String path) {
  final name = dictionaryFileName(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

final RegExp _debugTitlePattern = RegExp(
  r'^(instance of\b|exception\b|error\b|typeerror\b|nosuchmethoderror\b|'
  r'mdictexception\b)',
  caseSensitive: false,
);

/// Drops Dart error/debug strings that a failing MDX header parser may expose
/// as its title, and falls back to the file name instead.
String displayDictionaryTitle(String rawTitle, String path) {
  final title = rawTitle.trim();
  if (title.isEmpty || _debugTitlePattern.hasMatch(title)) {
    return dictionaryTitleFallback(path);
  }
  return title;
}

/// Metadata returned by the MDict worker after opening an MDX header.
class DictionaryMetadata {
  const DictionaryMetadata({
    required this.title,
    required this.entryCount,
    required this.encoding,
    required this.engineVersion,
    required this.format,
    required this.fileSize,
  });

  final String title;
  final int entryCount;
  final String encoding;
  final String engineVersion;
  final String format;
  final int fileSize;

  factory DictionaryMetadata.fromMap(Map<Object?, Object?> map) {
    return DictionaryMetadata(
      title: map['title'] as String? ?? '',
      entryCount: map['entryCount'] as int? ?? 0,
      encoding: map['encoding'] as String? ?? '',
      engineVersion: map['engineVersion'] as String? ?? '',
      format: map['format'] as String? ?? '',
      fileSize: map['fileSize'] as int? ?? 0,
    );
  }
}

/// A user-supplied MDict dictionary. Files are read in place.
class DictionaryInfo {
  const DictionaryInfo({
    required this.id,
    required this.title,
    required this.mdxPath,
    this.mddPaths = const [],
    this.cssPaths = const [],
    this.entryCount = 0,
    this.encoding = '',
    this.engineVersion = '',
    this.enabled = true,
    this.order = 0,
    this.lastValidatedAt,
    this.lastError = '',
  });

  final String id;
  final String title;
  final String mdxPath;
  final List<String> mddPaths;
  final List<String> cssPaths;
  final int entryCount;
  final String encoding;
  final String engineVersion;
  final bool enabled;
  final int order;
  final DateTime? lastValidatedAt;
  final String lastError;

  /// Stable id derived from the normalized MDX path.
  static String idForPath(String path) {
    final normalized = normalizeDictionaryPath(path);
    final digest = sha1.convert(utf8.encode(normalized)).toString();
    return digest.substring(0, 16);
  }

  bool get isAvailable => lastError.isEmpty;
  bool get hasResources => mddPaths.isNotEmpty;

  DictionaryInfo copyWith({
    String? title,
    String? mdxPath,
    List<String>? mddPaths,
    List<String>? cssPaths,
    int? entryCount,
    String? encoding,
    String? engineVersion,
    bool? enabled,
    int? order,
    DateTime? lastValidatedAt,
    String? lastError,
  }) {
    return DictionaryInfo(
      id: id,
      title: title ?? this.title,
      mdxPath: mdxPath ?? this.mdxPath,
      mddPaths: mddPaths ?? this.mddPaths,
      cssPaths: cssPaths ?? this.cssPaths,
      entryCount: entryCount ?? this.entryCount,
      encoding: encoding ?? this.encoding,
      engineVersion: engineVersion ?? this.engineVersion,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'mdxPath': mdxPath,
    'mddPaths': mddPaths,
    'cssPaths': cssPaths,
    'entryCount': entryCount,
    'encoding': encoding,
    'engineVersion': engineVersion,
    'enabled': enabled,
    'order': order,
    'lastValidatedAt': lastValidatedAt?.toIso8601String(),
    'lastError': lastError,
  };

  factory DictionaryInfo.fromJson(Map<String, Object?> json) {
    final mdxPath = json['mdxPath'] as String? ?? '';
    return DictionaryInfo(
      id: json['id'] as String? ?? '',
      title: displayDictionaryTitle(
        json['title'] as String? ?? '',
        mdxPath,
      ),
      mdxPath: mdxPath,
      mddPaths: _stringList(json['mddPaths']),
      cssPaths: _stringList(json['cssPaths']),
      entryCount: json['entryCount'] as int? ?? 0,
      encoding: json['encoding'] as String? ?? '',
      engineVersion: json['engineVersion'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
      lastValidatedAt: DateTime.tryParse(
        json['lastValidatedAt'] as String? ?? '',
      ),
      lastError: json['lastError'] as String? ?? '',
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }
}
