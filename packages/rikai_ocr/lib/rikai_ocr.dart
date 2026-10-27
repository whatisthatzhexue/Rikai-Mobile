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
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;
  final String orientation;

  factory OcrBlock.fromMap(Map<dynamic, dynamic> map) => OcrBlock(
        text: (map['text'] as String?) ?? '',
        left: (map['left'] as num?)?.toDouble() ?? 0,
        top: (map['top'] as num?)?.toDouble() ?? 0,
        right: (map['right'] as num?)?.toDouble() ?? 0,
        bottom: (map['bottom'] as num?)?.toDouble() ?? 0,
        confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
        orientation: (map['orientation'] as String?) ?? 'unknown',
      );
}

/// Result of one OCR run.
class OcrResult {
  const OcrResult({
    required this.engine,
    required this.elapsedMs,
    required this.blocks,
  });

  final String engine;
  final int elapsedMs;
  final List<OcrBlock> blocks;

  factory OcrResult.fromMap(Map<dynamic, dynamic> map) {
    final rawBlocks = (map['blocks'] as List<dynamic>?) ?? const [];
    return OcrResult(
      engine: (map['engine'] as String?) ?? 'unknown',
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      blocks: rawBlocks
          .whereType<Map<dynamic, dynamic>>()
          .map(OcrBlock.fromMap)
          .toList(growable: false),
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
  RikaiOcr({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('rikai/ocr');

  final MethodChannel _channel;

  Future<void> initialize({
    required String detModelPath,
    required String recModelPath,
    required String keysPath,
    String? mangaEncoderPath,
    String? mangaDecoderPath,
    String? mangaVocabPath,
    String? docOrientationPath,
    String? textLineOrientationPath,
  }) async {
    await _invoke('initialize', {
      'detModelPath': detModelPath,
      'recModelPath': recModelPath,
      'keysPath': keysPath,
      'mangaEncoderPath': ?mangaEncoderPath,
      'mangaDecoderPath': ?mangaDecoderPath,
      'mangaVocabPath': ?mangaVocabPath,
      'docOrientationPath': ?docOrientationPath,
      'textLineOrientationPath': ?textLineOrientationPath,
    });
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

  Future<void> dispose() async {
    await _channel.invokeMethod<void>('dispose');
  }

  Future<dynamic> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<dynamic>(method, args);
    } on PlatformException catch (error) {
      throw OcrException(
        error.code,
        error.message ?? 'OCR plugin error',
      );
    }
  }
}
