import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dict_reader/dict_reader.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_models.dart';
import '../../core/utils/text_normalizer.dart';
import 'mdd_key.dart';

enum MdictErrorCode {
  fileNotFound,
  invalidDictionary,
  unsupportedFormat,
  encrypted,
  lookupFailed,
  resourceFailed,
  disposed,
}

class MdictException implements Exception {
  const MdictException(this.code, this.message, {this.cause});

  final MdictErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'MdictException(${code.name}): $message';
}

/// Long-lived worker isolate holding one `DictReader` per open dictionary.
///
/// Dictionary files are opened lazily, in place, and never copied. The main
/// isolate sends path descriptors with every request; the worker caches open
/// readers by dictionary id.
class MdictService {
  MdictService._(this._isolate, this._receivePort);

  static const Duration initTimeout = Duration(seconds: 30);
  static const Duration requestTimeout = Duration(seconds: 90);
  static const Duration disposeTimeout = Duration(seconds: 2);

  final Isolate _isolate;
  final ReceivePort _receivePort;

  final Completer<void> _ready = Completer<void>();
  final Completer<void> _disposedSignal = Completer<void>();
  final Map<int, Completer<Map<Object?, Object?>>> _pending = {};

  StreamSubscription<Object?>? _subscription;
  SendPort? _commandPort;
  int _nextRequestId = 0;
  bool _disposed = false;
  bool _dead = false;

  static Future<MdictService> open() async {
    final receivePort = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<List<Object?>>(
        _mdictWorkerMain,
        <Object?>[receivePort.sendPort],
        debugName: 'rikai-mdict',
        onError: receivePort.sendPort,
      );
    } catch (error) {
      receivePort.close();
      throw MdictException(
        MdictErrorCode.lookupFailed,
        '无法启动词典线程',
        cause: error,
      );
    }

    final service = MdictService._(isolate, receivePort);
    service._subscription = receivePort.listen(service._onMessage);
    try {
      await service._ready.future.timeout(initTimeout);
      return service;
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  /// Opens an MDX header and returns metadata without keeping it cached.
  Future<DictionaryMetadata> probe(String mdxPath) async {
    final result = await _request(<String, Object?>{
      'cmd': 'probe',
      'path': mdxPath,
    });
    return DictionaryMetadata.fromMap(result);
  }

  /// Looks up [rawCandidates] in the given dictionaries.
  ///
  /// Candidates are normalized and expanded into width/case/kana variants.
  /// Each dictionary stops at the first candidate that yields hits.
  Future<LookupResult> lookup({
    required String query,
    required Iterable<String> rawCandidates,
    required List<DictionaryInfo> dictionaries,
    int maxEntriesPerDictionary = 0,
    int suggestionLimit = 30,
  }) async {
    final enabled = dictionaries.where((dict) => dict.enabled).toList();
    if (enabled.isEmpty) {
      return LookupResult(query: query, candidates: const [], groups: const []);
    }

    final raw = rawCandidates.where((value) => value.trim().isNotEmpty);
    final candidates = lookupCandidatesFor(raw.isEmpty ? [query] : raw);
    final result = await _request(<String, Object?>{
      'cmd': 'lookup',
      'dictionaries': enabled
          .map(_dictionaryDescriptor)
          .toList(growable: false),
      'candidates': candidates,
      'maxEntries': maxEntriesPerDictionary,
      'suggestionLimit': suggestionLimit,
    });

    final rawGroups = result['groups'];
    if (rawGroups is! List) {
      throw const MdictException(MdictErrorCode.lookupFailed, '词典返回格式异常');
    }

    final byId = {for (final dict in enabled) dict.id: dict};
    final groups = <DictionaryLookupGroup>[];
    for (final rawGroup in rawGroups) {
      if (rawGroup is! Map) continue;
      final dictionary = byId[rawGroup['id']];
      if (dictionary == null) continue;

      final rawEntries = rawGroup['entries'];
      final entries = <LookupEntry>[];
      if (rawEntries is List) {
        for (final rawEntry in rawEntries) {
          if (rawEntry is Map) entries.add(LookupEntry.fromMap(rawEntry));
        }
      }
      final rawSuggestions = rawGroup['suggestions'];
      final suggestions = rawSuggestions is List
          ? rawSuggestions.whereType<String>().toList(growable: false)
          : const <String>[];
      final rawError = rawGroup['error'];
      final error = rawError is Map
          ? rawError['message']?.toString() ?? '词典查询失败'
          : '';

      groups.add(
        DictionaryLookupGroup(
          dictionary: dictionary,
          entries: entries,
          suggestions: suggestions,
          error: error,
        ),
      );
    }

    return LookupResult(query: query, candidates: candidates, groups: groups);
  }

  /// Opens and initializes the given dictionaries in the worker without
  /// running a lookup. Used by the splash screen to remove the cold-start
  /// initialization delay from the first dictionary navigation.
  Future<void> warmUp(Iterable<DictionaryInfo> dictionaries) async {
    final enabled = dictionaries
        .where((dictionary) => dictionary.enabled && dictionary.isAvailable)
        .toList(growable: false);
    if (enabled.isEmpty) return;
    await _request(<String, Object?>{
      'cmd': 'warmup',
      'dictionaries': enabled
          .map(_dictionaryDescriptor)
          .toList(growable: false),
    });
  }

  /// Reads one MDD resource (image, font, ...) by the key found in entry HTML.
  Future<Uint8List?> readResource({
    required DictionaryInfo dictionary,
    required String key,
  }) async {
    final result = await _request(<String, Object?>{
      'cmd': 'resource',
      'dictionary': _dictionaryDescriptor(dictionary),
      'key': key,
    });
    if (result['found'] != true) return null;
    final data = result['data'];
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  Future<void> closeDictionary(String id) async {
    if (_disposed || _dead) return;
    try {
      await _request(<String, Object?>{'cmd': 'close', 'dictionaryId': id});
    } on MdictException {
      // Closing a dictionary that was never opened is not an error.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final commandPort = _commandPort;
    if (commandPort != null && !_dead) {
      commandPort.send(const <String, Object?>{'cmd': 'dispose'});
      try {
        await _disposedSignal.future.timeout(disposeTimeout);
      } on TimeoutException {
        // The isolate is killed below.
      }
    }

    const error = MdictException(MdictErrorCode.disposed, '词典服务已释放');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();

    await _subscription?.cancel();
    _subscription = null;
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  Future<Map<Object?, Object?>> _request(Map<String, Object?> message) async {
    if (_disposed) {
      throw const MdictException(MdictErrorCode.disposed, '词典服务已释放');
    }
    final commandPort = _commandPort;
    if (commandPort == null || _dead) {
      throw const MdictException(MdictErrorCode.lookupFailed, '词典服务未就绪');
    }

    final id = _nextRequestId++;
    final completer = Completer<Map<Object?, Object?>>();
    _pending[id] = completer;
    commandPort.send(<String, Object?>{...message, 'id': id});

    try {
      return await completer.future.timeout(requestTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw const MdictException(MdictErrorCode.lookupFailed, '词典操作超时');
    }
  }

  void _onMessage(Object? message) {
    if (message is List && message.length >= 2) {
      _failAll('词典线程异常：${message.first}');
      return;
    }
    if (message is! Map) return;

    final type = message['type'];
    if (type == 'ready') {
      final port = message['port'];
      if (port is SendPort) {
        _commandPort = port;
        if (!_ready.isCompleted) _ready.complete();
      }
      return;
    }
    if (type == 'disposed') {
      if (!_disposedSignal.isCompleted) _disposedSignal.complete();
      return;
    }

    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    final error = message['error'];
    if (error is Map) {
      final code = _errorCodeFromName(error['code']?.toString());
      completer.completeError(
        MdictException(code, error['message']?.toString() ?? '词典操作失败'),
      );
      return;
    }

    final ok = message['ok'];
    completer.complete(ok is Map ? ok : const <Object?, Object?>{});
  }

  void _failAll(String message) {
    _dead = true;
    final error = MdictException(MdictErrorCode.lookupFailed, message);
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  static Map<String, Object?> _dictionaryDescriptor(DictionaryInfo dict) => {
    'id': dict.id,
    'title': dict.title,
    'mdxPath': dict.mdxPath,
    'mddPaths': dict.mddPaths,
  };
}

MdictErrorCode _errorCodeFromName(String? name) {
  for (final code in MdictErrorCode.values) {
    if (code.name == name) return code;
  }
  return MdictErrorCode.lookupFailed;
}

class _OpenDictionary {
  _OpenDictionary({
    required this.id,
    required this.title,
    required this.mdxPath,
    required this.mddPaths,
    required this.mdx,
  });

  final String id;
  final String title;
  final String mdxPath;
  final List<String> mddPaths;
  final DictReader mdx;
  final Map<String, DictReader> mddReaders = {};
  final Set<String> failedMddPaths = {};

  Future<void> close() async {
    for (final reader in mddReaders.values) {
      await _safeClose(reader);
    }
    mddReaders.clear();
    await _safeClose(mdx);
  }
}

Future<void> _safeClose(DictReader reader) async {
  try {
    await reader.close();
  } catch (_) {
    // Best effort.
  }
}

Future<void> _mdictWorkerMain(List<Object?> args) async {
  final mainPort = args[0] as SendPort;
  final commandPort = ReceivePort();
  final openDictionaries = <String, _OpenDictionary>{};

  mainPort.send(<String, Object?>{
    'type': 'ready',
    'port': commandPort.sendPort,
  });

  await for (final message in commandPort) {
    if (message is! Map) continue;
    final command = message['cmd'];
    if (command == 'dispose') break;

    final id = message['id'];
    try {
      final result = await _handleCommand(command, message, openDictionaries);
      mainPort.send(<String, Object?>{'id': id, 'ok': result});
    } on MdictException catch (error) {
      mainPort.send(<String, Object?>{
        'id': id,
        'error': {'code': error.code.name, 'message': error.message},
      });
    } catch (error) {
      mainPort.send(<String, Object?>{
        'id': id,
        'error': {
          'code': MdictErrorCode.lookupFailed.name,
          'message': error.toString(),
        },
      });
    }
  }

  for (final dictionary in openDictionaries.values) {
    await dictionary.close();
  }
  commandPort.close();
  mainPort.send(const <String, Object?>{'type': 'disposed'});
}

Future<Map<String, Object?>> _handleCommand(
  Object? command,
  Map<dynamic, dynamic> message,
  Map<String, _OpenDictionary> openDictionaries,
) async {
  if (command == 'probe') {
    return _probe(message['path']?.toString() ?? '');
  }
  if (command == 'lookup') {
    return _lookup(message, openDictionaries);
  }
  if (command == 'warmup') {
    return _warmUp(message, openDictionaries);
  }
  if (command == 'resource') {
    return _readResource(message, openDictionaries);
  }
  if (command == 'close') {
    final id = message['dictionaryId']?.toString() ?? '';
    final dictionary = openDictionaries.remove(id);
    if (dictionary != null) await dictionary.close();
    return const <String, Object?>{'closed': true};
  }
  throw MdictException(MdictErrorCode.lookupFailed, '未知的词典命令：$command');
}

Future<Map<String, Object?>> _probe(String rawPath) async {
  final path = normalizeDictionaryPath(rawPath);
  if (!path.toLowerCase().endsWith('.mdx')) {
    throw const MdictException(
      MdictErrorCode.invalidDictionary,
      '请选择 .mdx 词典文件',
    );
  }
  final reader = await _openDictReader(path);
  try {
    return {
      'title': _titleFor(reader, path),
      'entryCount': reader.numEntries,
      'encoding': reader.header['Encoding'] ?? '',
      'engineVersion': reader.header['GeneratedByEngineVersion'] ?? '',
      'format': reader.header['Format'] ?? '',
      'fileSize': await File(path).length(),
    };
  } finally {
    await _safeClose(reader);
  }
}

Future<DictReader> _openDictReader(String path) async {
  final normalized = normalizeDictionaryPath(path);
  final file = File(normalized);
  if (!await file.exists()) {
    throw MdictException(MdictErrorCode.fileNotFound, '词典文件不存在：$normalized');
  }

  final reader = DictReader(normalized);
  try {
    await reader.initDict();
    _validateHeader(reader.header);
    return reader;
  } on MdictException {
    await _safeClose(reader);
    rethrow;
  } on String catch (message) {
    await _safeClose(reader);
    throw MdictException(MdictErrorCode.unsupportedFormat, '不支持的词典格式：$message');
  } catch (error) {
    await _safeClose(reader);
    throw MdictException(
      MdictErrorCode.invalidDictionary,
      '无法读取词典：$error',
      cause: error,
    );
  }
}

void _validateHeader(Map<String, String> header) {
  final versionText = header['GeneratedByEngineVersion'] ?? '';
  final version = double.tryParse(versionText);
  if (version != null && version >= 3.0) {
    throw MdictException(
      MdictErrorCode.unsupportedFormat,
      '暂不支持 MDict $versionText 词典',
    );
  }

  final encrypted = (header['Encrypted'] ?? 'No').trim().toLowerCase();
  if (encrypted.isNotEmpty && encrypted != 'no' && encrypted != '0') {
    throw MdictException(
      MdictErrorCode.encrypted,
      '暂不支持加密词典（Encrypted=${header['Encrypted']}）',
    );
  }
}

String _titleFor(DictReader reader, String path) {
  final title = (reader.header['Title'] ?? '').trim();
  return title.isEmpty ? dictionaryTitleFallback(path) : title;
}

Future<_OpenDictionary> _ensureOpen(
  Map<dynamic, dynamic> descriptor,
  Map<String, _OpenDictionary> openDictionaries,
) async {
  final mdxPath = normalizeDictionaryPath(
    descriptor['mdxPath']?.toString() ?? '',
  );
  final id = descriptor['id']?.toString().isNotEmpty == true
      ? descriptor['id'].toString()
      : DictionaryInfo.idForPath(mdxPath);
  final title = descriptor['title']?.toString().trim().isNotEmpty == true
      ? descriptor['title'].toString()
      : dictionaryTitleFallback(mdxPath);
  final rawMddPaths = descriptor['mddPaths'];
  final mddPaths = rawMddPaths is List
      ? rawMddPaths.whereType<String>().toList(growable: false)
      : const <String>[];

  final cached = openDictionaries[id];
  if (cached != null && cached.mdxPath == mdxPath) return cached;
  if (cached != null) {
    openDictionaries.remove(id);
    await cached.close();
  }

  final reader = await _openDictReader(mdxPath);
  final dictionary = _OpenDictionary(
    id: id,
    title: title,
    mdxPath: mdxPath,
    mddPaths: mddPaths,
    mdx: reader,
  );
  openDictionaries[id] = dictionary;
  return dictionary;
}

Future<Map<String, Object?>> _lookup(
  Map<dynamic, dynamic> message,
  Map<String, _OpenDictionary> openDictionaries,
) async {
  final rawDictionaries = message['dictionaries'];
  final rawCandidates = message['candidates'];
  if (rawDictionaries is! List || rawCandidates is! List) {
    throw const MdictException(MdictErrorCode.lookupFailed, '词典查询参数无效');
  }

  final candidates = rawCandidates.whereType<String>().toList(growable: false);
  final maxEntries = message['maxEntries'] as int? ?? 0;
  final suggestionLimit = message['suggestionLimit'] as int? ?? 30;
  final groups = <Map<String, Object?>>[];

  for (final rawDescriptor in rawDictionaries) {
    if (rawDescriptor is! Map) continue;
    final id = rawDescriptor['id']?.toString() ?? '';

    try {
      final dictionary = await _ensureOpen(rawDescriptor, openDictionaries);
      final entries = <LookupEntry>[];
      final seenRecords = <String>{};

      for (final candidate in candidates) {
        final hits = await dictionary.mdx.locateAll(candidate);
        if (hits.isEmpty) continue;

        for (final hit in hits) {
          if (maxEntries > 0 && entries.length >= maxEntries) break;
          final fingerprint =
              '${hit.keyText}|${hit.recordBlockOffset}|${hit.startOffset}|'
              '${hit.endOffset}';
          if (!seenRecords.add(fingerprint)) continue;
          try {
            entries.add(await _resolveEntry(dictionary.mdx, hit));
          } catch (error) {
            debugPrint('[MdictWorker] failed to read entry: $error');
          }
        }
        break;
      }

      var suggestions = <String>[];
      if (entries.isEmpty) {
        final seenSuggestions = <String>{};
        for (final candidate in candidates) {
          for (final suggestion in dictionary.mdx.search(
            candidate,
            limit: suggestionLimit,
          )) {
            if (seenSuggestions.add(suggestion)) suggestions.add(suggestion);
            if (suggestions.length >= suggestionLimit) break;
          }
          if (suggestions.isNotEmpty) break;
        }
      }

      groups.add({
        'id': id,
        'entries': entries.map((entry) => entry.toJson()).toList(),
        'suggestions': suggestions,
      });
    } on MdictException catch (error) {
      groups.add({
        'id': id,
        'entries': const <Object?>[],
        'suggestions': const <String>[],
        'error': {'code': error.code.name, 'message': error.message},
      });
    } catch (error) {
      groups.add({
        'id': id,
        'entries': const <Object?>[],
        'suggestions': const <String>[],
        'error': {
          'code': MdictErrorCode.lookupFailed.name,
          'message': error.toString(),
        },
      });
    }
  }

  return {'groups': groups};
}

Future<Map<String, Object?>> _warmUp(
  Map<dynamic, dynamic> message,
  Map<String, _OpenDictionary> openDictionaries,
) async {
  final rawDictionaries = message['dictionaries'];
  if (rawDictionaries is! List) {
    return const <String, Object?>{'opened': 0};
  }

  var opened = 0;
  final errors = <String>[];
  for (final rawDescriptor in rawDictionaries) {
    if (rawDescriptor is! Map) continue;
    try {
      await _ensureOpen(rawDescriptor, openDictionaries);
      opened++;
    } catch (error) {
      errors.add(error.toString());
    }
  }
  return {'opened': opened, 'errors': errors};
}

Future<LookupEntry> _resolveEntry(
  DictReader reader,
  RecordOffsetInfo hit, [
  int depth = 0,
]) async {
  final html = await reader.readOneMdx(hit);
  final redirect = RegExp(r'^@@@LINK=(.+)$').firstMatch(html.trim());
  if (redirect != null && depth < 3) {
    final target = redirect.group(1)!.trim();
    final next = await reader.locate(target);
    if (next != null) {
      final resolved = await _resolveEntry(reader, next, depth + 1);
      return LookupEntry(
        matchedKey: hit.keyText,
        headword: resolved.headword,
        html: resolved.html,
      );
    }
  }
  return LookupEntry(
    matchedKey: hit.keyText,
    headword: hit.keyText,
    html: html,
  );
}

Future<Map<String, Object?>> _readResource(
  Map<dynamic, dynamic> message,
  Map<String, _OpenDictionary> openDictionaries,
) async {
  final rawDescriptor = message['dictionary'];
  final key = message['key']?.toString() ?? '';
  if (rawDescriptor is! Map || key.isEmpty) {
    return const <String, Object?>{'found': false};
  }

  final dictionary = await _ensureOpen(rawDescriptor, openDictionaries);
  if (dictionary.mddPaths.isEmpty) {
    return const <String, Object?>{'found': false};
  }

  for (final candidate in mddKeyCandidates(key)) {
    for (final path in dictionary.mddPaths) {
      final reader = await _mddReader(dictionary, path);
      if (reader == null) continue;
      try {
        final hit = await reader.locate(candidate);
        if (hit == null) continue;
        final data = await reader.readOneMdd(hit);
        return {
          'found': true,
          'key': hit.keyText,
          'data': Uint8List.fromList(data),
        };
      } catch (error) {
        debugPrint(
          '[MdictWorker] failed to read MDD resource $candidate: $error',
        );
      }
    }
  }
  return const <String, Object?>{'found': false};
}

Future<DictReader?> _mddReader(_OpenDictionary dictionary, String path) async {
  final cached = dictionary.mddReaders[path];
  if (cached != null) return cached;
  if (dictionary.failedMddPaths.contains(path)) return null;

  try {
    final reader = await _openDictReader(path);
    dictionary.mddReaders[path] = reader;
    return reader;
  } catch (error) {
    dictionary.failedMddPaths.add(path);
    debugPrint('[MdictWorker] failed to open MDD $path: $error');
    return null;
  }
}
