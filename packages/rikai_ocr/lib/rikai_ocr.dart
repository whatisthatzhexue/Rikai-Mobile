import 'dart:async';

import 'package:flutter/services.dart';

/// How the OCR pipeline should interpret the image.
enum OcrMode { auto, horizontal, vertical }

/// A single recognized text block returned by the native pipeline.
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = 1.0,
    this.orientation = 'unknown',
    this.points = const [],
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;
  final String orientation;

  /// Quad corners as `[x0, y0, x1, y1, ...]`, if supplied by the backend.
  final List<double> points;

  factory OcrBlock.fromMap(Map<dynamic, dynamic> map) => OcrBlock(
    text: (map['text'] as String?) ?? '',
    left: (map['left'] as num?)?.toDouble() ?? 0,
    top: (map['top'] as num?)?.toDouble() ?? 0,
    right: (map['right'] as num?)?.toDouble() ?? 0,
    bottom: (map['bottom'] as num?)?.toDouble() ?? 0,
    confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
    orientation: (map['orientation'] as String?) ?? 'unknown',
    points: ((map['points'] as List<dynamic>?) ?? const [])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList(growable: false),
  );
}

/// Progress event emitted by the native OCR pipeline.
class OcrProgress {
  const OcrProgress({
    required this.stage,
    required this.current,
    required this.total,
    required this.progress,
  });

  final String stage;
  final int current;
  final int total;
  final double progress;

  factory OcrProgress.fromMap(Map<dynamic, dynamic> map) => OcrProgress(
    stage: (map['stage'] as String?) ?? 'unknown',
    current: (map['current'] as num?)?.toInt() ?? 0,
    total: (map['total'] as num?)?.toInt() ?? 0,
    progress: (map['progress'] as num?)?.toDouble() ?? 0,
  );
}

/// Result of one OCR run.
class OcrResult {
  const OcrResult({
    required this.engine,
    required this.elapsedMs,
    required this.blocks,
    this.width = 0,
    this.height = 0,
  });

  final String engine;
  final int elapsedMs;
  final List<OcrBlock> blocks;

  /// Size of the decoded/EXIF-corrected image used for OCR coordinates.
  final int width;
  final int height;

  factory OcrResult.fromMap(Map<dynamic, dynamic> map) {
    final rawBlocks = (map['blocks'] as List<dynamic>?) ?? const [];
    return OcrResult(
      engine: (map['engine'] as String?) ?? 'unknown',
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      blocks: rawBlocks
          .whereType<Map<dynamic, dynamic>>()
          .map(OcrBlock.fromMap)
          .toList(growable: false),
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Thrown when the native OCR pipeline cannot run.
class OcrException implements Exception {
  const OcrException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'OcrException($code): $message';
}

/// Dart facade over the Android ONNX Runtime OCR plugin.
///
/// Model files are managed by the Dart-side [ModelManager]; this class only
/// receives local paths. No network access happens in the native plugin.
class RikaiOcr {
  RikaiOcr({MethodChannel? channel, EventChannel? progressChannel})
    : _channel = channel ?? const MethodChannel('rikai/ocr'),
      _progressChannel =
          progressChannel ?? const EventChannel('rikai/ocr_progress');

  final MethodChannel _channel;
  final EventChannel _progressChannel;
  String? _initializedKey;
  Map<String, Object?>? _readiness;

  /// Native pipeline stage events. Subscribe before calling [recognize].
  Stream<OcrProgress> get progress => _progressChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => OcrProgress.fromMap(event as Map<dynamic, dynamic>));

  Future<Map<String, Object?>> initialize({
    required String detModelPath,
    required String recModelPath,
    required String keysPath,
    String? mangaEncoderPath,
    String? mangaDecoderPath,
    String? mangaVocabPath,
    String? docOrientationPath,
    String? textLineOrientationPath,
  }) async {
    final args = <String, dynamic>{
      'detModelPath': detModelPath,
      'recModelPath': recModelPath,
      'keysPath': keysPath,
      'mangaEncoderPath': ?mangaEncoderPath,
      'mangaDecoderPath': ?mangaDecoderPath,
      'mangaVocabPath': ?mangaVocabPath,
      'docOrientationPath': ?docOrientationPath,
      'textLineOrientationPath': ?textLineOrientationPath,
    };
    final key = args.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\u0000');
    final cached = _readiness;
    if (cached != null && _initializedKey == key) return cached;
    final raw = await _invoke('initialize', args);
    if (raw is! Map) {
      throw const OcrException(
        'bad_result',
        'Native OCR returned no readiness',
      );
    }
    final readiness = raw.map((key, value) => MapEntry(key.toString(), value));
    _initializedKey = key;
    _readiness = readiness;
    return readiness;
  }

  /// Preloads optional native sessions for [mode].
  ///
  /// This is best-effort background work; the next [recognize] call still
  /// lazily loads anything that is missing. Horizontal mode must not load
  /// MangaOCR.
  Future<Map<String, Object?>> prepare({required OcrMode mode}) async {
    final raw = await _invoke('prepare', {'mode': mode.name});
    if (raw is! Map) {
      throw const OcrException(
        'bad_result',
        'Native OCR returned no readiness',
      );
    }
    final readiness = raw.map((key, value) => MapEntry(key.toString(), value));
    _readiness = readiness;
    return readiness;
  }

  Future<OcrResult> recognize({
    required String imagePath,
    OcrMode mode = OcrMode.auto,
  }) async {
    final raw = await _invoke('recognize', {
      'imagePath': imagePath,
      'mode': mode.name,
    });
    if (raw is! Map) {
      throw const OcrException('bad_result', 'Native OCR returned no result');
    }
    return OcrResult.fromMap(raw);
  }

  Future<void> cancel() async {
    await _invoke('cancel');
  }

  Future<void> dispose() async {
    try {
      await _invoke('dispose');
    } finally {
      _initializedKey = null;
      _readiness = null;
    }
  }

  Future<dynamic> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<dynamic>(method, args);
    } on PlatformException catch (error) {
      throw OcrException(error.code, error.message ?? 'OCR plugin error');
    }
  }
}
