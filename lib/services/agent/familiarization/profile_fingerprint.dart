import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/agent/agent_profile.dart';
import '../../../core/models/dict_info.dart';

const int dictionaryProfileSchemaVersion = 1;
const int dictionaryProfilePromptVersion = 1;
const int unidicProfileSchemaVersion = 1;

/// Stable dictionary fingerprint; file stat changes invalidate a profile.
Future<String> dictionaryProfileFingerprint(
  DictionaryInfo dictionary, {
  int promptVersion = dictionaryProfilePromptVersion,
  int schemaVersion = dictionaryProfileSchemaVersion,
  AgentProfileLanguage language = AgentProfileLanguage.chinese,
}) async {
  var statPart = 'missing';
  try {
    final stat = await File(dictionary.mdxPath).stat();
    statPart = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  } catch (_) {
    // A missing file keeps the fingerprint stable but the profile is stale.
  }
  final raw =
      '${dictionary.id}|$statPart|${dictionary.entryCount}|'
      '${dictionary.encoding}|$promptVersion|$schemaVersion|'
      '${language.wireName}';
  return sha1.convert(utf8.encode(raw)).toString();
}

String unidicPathHash(String path) {
  return sha1
      .convert(utf8.encode(UnidicPathNormalizer.normalize(path)))
      .toString();
}

/// Stable UniDic fingerprint from the two large runtime files.
Future<String> unidicProfileFingerprint(
  String path, {
  String version = '',
  int schemaVersion = unidicProfileSchemaVersion,
}) async {
  final normalized = UnidicPathNormalizer.normalize(path);
  final stats = <String>[];
  for (final name in <String>['sys.dic', 'matrix.bin', 'char.bin', 'unk.dic']) {
    final file = File(p.join(normalized, name));
    try {
      final stat = await file.stat();
      stats.add('$name:${stat.size}:${stat.modified.millisecondsSinceEpoch}');
    } catch (_) {
      stats.add('$name:missing');
    }
  }
  final raw = '$normalized|${stats.join('|')}|$version|$schemaVersion';
  return sha1.convert(utf8.encode(raw)).toString();
}

abstract final class UnidicPathNormalizer {
  static String normalize(String raw) {
    var path = raw.trim();
    if (path.startsWith('file://')) {
      path = path.substring('file://'.length);
    }
    while (path.length > 1 && (path.endsWith('/') || path.endsWith(r'\'))) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}
