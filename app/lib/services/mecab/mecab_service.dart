import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:mecab_for_dart/mecab_dart.dart';

import '../../core/models/token.dart';
import 'mecab_output_parser.dart';
import 'unidic_validator.dart';

/// Error categories surfaced by [MecabService].
enum MecabErrorCode {
  notConfigured,
  invalidDictionary,
  initFailed,
  analyzeFailed,
  disposed,
}

class MecabException implements Exception {
  const MecabException(this.code, this.message, {this.cause});

  final MecabErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'MecabException(${code.name}): $message';
}

/// Long-lived MeCab worker backed by a user-supplied UniDic directory.
///
/// The 1.3 GB dictionary is mmap'ed by MeCab inside a dedicated isolate; the
/// service never reads it into Dart memory and never writes to the UniDic
/// directory. A private `mecabrc` is created under the app's support directory
/// and passed to MeCab via `-r` in the options string.
class MecabService {
  MecabService._(this.dictDir, this.rcPath, this._isolate, this._receivePort);

  static const Duration initTimeout = Duration(seconds: 90);
  static const Duration analyzeTimeout = Duration(seconds: 60);
  static const Duration disposeTimeout = Duration(seconds: 2);

  final String dictDir;
  final String rcPath;

  final Isolate _isolate;
  final ReceivePort _receivePort;

  final Completer<void> _ready = Completer<void>();
  final Completer<void> _disposedSignal = Completer<void>();
  final Map<int, Completer<List<Token>>> _pending = {};

  StreamSubscription<Object?>? _subscription;
  SendPort? _commandPort;
  int _nextRequestId = 0;
  bool _disposed = false;
  bool _dead = false;

  /// Validates [dictDir], creates a private rc file and starts the worker.
  static Future<MecabService> open({
    required String dictDir,
    required String rcDirectory,
  }) async {
    final path = UnidicValidator.normalizePath(dictDir);
    final validation = await UnidicValidator.validate(path);
    if (!validation.isValid) {
      throw MecabException(
        MecabErrorCode.invalidDictionary,
        validation.summary,
      );
    }

    final File rcFile;
    try {
      final directory = Directory(rcDirectory);
      await directory.create(recursive: true);
      rcFile = File('${directory.path}/mecabrc');
      await rcFile.writeAsString('charset = UTF-8\n', flush: true);
    } on FileSystemException catch (error) {
      throw MecabException(
        MecabErrorCode.initFailed,
        '无法创建私有 mecabrc：${error.message}',
        cause: error,
      );
    }

    // The vendored generateArgs() parses this string on spaces and strips
    // double quotes, so quote the path and drop any embedded quotes.
    final safeRcPath = rcFile.path.replaceAll('"', '');
    final options = '-r "$safeRcPath"';

    final receivePort = ReceivePort();
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<List<Object?>>(
        _mecabWorkerMain,
        <Object?>[receivePort.sendPort, path, options],
        debugName: 'rikai-mecab',
        onError: receivePort.sendPort,
      );
    } catch (error) {
      receivePort.close();
      throw MecabException(MecabErrorCode.initFailed, '无法启动分词线程', cause: error);
    }

    final service = MecabService._(path, rcFile.path, isolate, receivePort);
    service._subscription = receivePort.listen(service._onMessage);
    try {
      await service._ready.future.timeout(initTimeout);
      return service;
    } on TimeoutException {
      await service.dispose();
      throw const MecabException(
        MecabErrorCode.initFailed,
        '加载 UniDic 超时（请确认目录可读且文件完整）',
      );
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  /// Tokenizes [text], one MeCab invocation per line to preserve line breaks.
  Future<List<Token>> analyze(String text) async {
    if (_disposed) {
      throw const MecabException(MecabErrorCode.disposed, '分词服务已释放');
    }
    if (text.isEmpty) return const <Token>[];
    final commandPort = _commandPort;
    if (commandPort == null || _dead) {
      throw const MecabException(MecabErrorCode.analyzeFailed, '分词服务未就绪');
    }

    final id = _nextRequestId++;
    final completer = Completer<List<Token>>();
    _pending[id] = completer;
    commandPort.send(<String, Object?>{
      'cmd': 'analyze',
      'id': id,
      'text': text,
    });

    try {
      return await completer.future.timeout(analyzeTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw const MecabException(MecabErrorCode.analyzeFailed, '分词超时');
    }
  }

  /// Stops the worker and releases the mmap'ed dictionary.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final commandPort = _commandPort;
    if (commandPort != null && !_dead) {
      commandPort.send(const <String, Object?>{'cmd': 'dispose'});
      try {
        await _disposedSignal.future.timeout(disposeTimeout);
      } on TimeoutException {
        // The isolate is killed below; MeCab's mmap is released with it.
      }
    }

    const error = MecabException(MecabErrorCode.disposed, '分词服务已释放');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();

    await _subscription?.cancel();
    _subscription = null;
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  void _onMessage(Object? message) {
    // Uncaught worker errors arrive as a two-element list from onError.
    if (message is List && message.length >= 2) {
      _failAll('分词线程异常：${message.first}');
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
    if (type == 'initError') {
      if (!_ready.isCompleted) {
        _ready.completeError(
          MecabException(
            MecabErrorCode.initFailed,
            message['error']?.toString() ?? 'MeCab 初始化失败',
          ),
        );
      }
      return;
    }
    if (type == 'disposed') {
      if (!_disposedSignal.isCompleted) _disposedSignal.complete();
      return;
    }

    final id = message['id'];
    if (id is int) _completeRequest(id, message);
  }

  void _completeRequest(int id, Map<dynamic, dynamic> message) {
    final completer = _pending.remove(id);
    if (completer == null) return;

    final error = message['error'];
    if (error != null) {
      completer.completeError(
        MecabException(MecabErrorCode.analyzeFailed, error.toString()),
      );
      return;
    }

    final rawTokens = message['tokens'];
    if (rawTokens is! List) {
      completer.completeError(
        const MecabException(MecabErrorCode.analyzeFailed, '分词返回格式异常'),
      );
      return;
    }

    try {
      final tokens = <Token>[];
      var degraded = 0;
      for (final item in rawTokens) {
        final token = _tokenFromWire(item);
        if (!token.hasStandardLayout) degraded++;
        tokens.add(token);
      }
      if (degraded > 0) {
        debugPrint(
          '[MecabService] $degraded token(s) do not use the supported '
          '29-field UniDic layout; readings are disabled for them.',
        );
      }
      completer.complete(List.unmodifiable(tokens));
    } catch (error) {
      completer.completeError(
        MecabException(
          MecabErrorCode.analyzeFailed,
          '分词结果解析失败：$error',
          cause: error,
        ),
      );
    }
  }

  static Token _tokenFromWire(Object? item) {
    if (item is! Map) {
      throw const FormatException('token payload is not a map');
    }
    final rawFeatures = item['features'];
    final features = rawFeatures is List
        ? rawFeatures
              .map((value) => value?.toString() ?? '')
              .toList(growable: false)
        : const <String>[];
    final surface = item['surface'];
    final start = item['start'];
    final end = item['end'];
    return Token.fromFeatures(
      surface: surface is String ? surface : '',
      features: features,
      start: start is int ? start : 0,
      end: end is int ? end : 0,
    );
  }

  void _failAll(String message) {
    _dead = true;
    final error = MecabException(MecabErrorCode.analyzeFailed, message);
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }
}

/// Worker isolate entry point. Keeps one MeCab model alive for its lifetime.
Future<void> _mecabWorkerMain(List<Object?> args) async {
  final mainPort = args[0] as SendPort;
  final dictDir = args[1] as String;
  final options = args[2] as String;

  final commandPort = ReceivePort();
  final Mecab engine;
  try {
    engine = await Mecab.create(dictDir: dictDir, options: options);
    // Mecab.create() does not report a null native handle reliably; a real
    // probe is the cheapest way to confirm the dictionary actually loaded.
    final probe = engine.rawParse('テスト');
    if (probe.isEmpty) {
      throw StateError('MeCab 初始化后分词结果为空');
    }
  } catch (error) {
    commandPort.close();
    mainPort.send(<String, Object?>{
      'type': 'initError',
      'error': error.toString(),
    });
    return;
  }

  mainPort.send(<String, Object?>{
    'type': 'ready',
    'port': commandPort.sendPort,
  });

  await for (final message in commandPort) {
    if (message is! Map) continue;
    final command = message['cmd'];
    if (command == 'dispose') break;
    if (command != 'analyze') continue;

    final id = message['id'];
    try {
      final text = message['text'] as String? ?? '';
      final tokens = _analyzeText(engine, text);
      mainPort.send(<String, Object?>{'id': id, 'tokens': tokens});
    } catch (error) {
      mainPort.send(<String, Object?>{'id': id, 'error': error.toString()});
    }
  }

  try {
    engine.dispose();
  } catch (_) {
    // Best effort; the isolate is about to exit.
  }
  commandPort.close();
  mainPort.send(const <String, Object?>{'type': 'disposed'});
}

List<Map<String, Object?>> _analyzeText(Mecab engine, String text) {
  final tokens = <Map<String, Object?>>[];
  var lineStart = 0;
  for (final line in text.split('\n')) {
    if (line.isNotEmpty) {
      _analyzeLine(engine, line, lineStart, tokens);
    }
    lineStart += line.length + 1;
  }
  return tokens;
}

void _analyzeLine(
  Mecab engine,
  String line,
  int lineStart,
  List<Map<String, Object?>> sink,
) {
  // Do not use Mecab.parse()/TokenNode here: they split features on every
  // comma and break quoted UniDic fields such as
  // "動詞%F2@1,形容詞%F4@-2".
  final nodes = parseMecabOutput(engine.rawParse(line));
  var cursor = 0;
  for (final node in nodes) {
    final surface = node.surface;
    if (surface.isEmpty || surface == 'EOS') continue;

    var index = line.indexOf(surface, cursor);
    if (index < 0) index = cursor;
    if (index > line.length) index = line.length;
    final rawEnd = index + surface.length;
    final end = rawEnd > line.length ? line.length : rawEnd;
    cursor = end;

    sink.add(<String, Object?>{
      'surface': surface,
      'features': node.features,
      'start': lineStart + index,
      'end': lineStart + end,
    });
  }
}
