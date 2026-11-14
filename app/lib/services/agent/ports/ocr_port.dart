import 'package:rikai_ocr/rikai_ocr.dart';

/// Opaque image identity used by the Agent. A local path is never serialized.
abstract interface class OcrHandle {
  String get id;
}

/// Native OCR engine identifiers used by the Agent combination matrix.
abstract final class OcrEngineId {
  static const String paddleV5 = 'paddle_v5';
  static const String mangaOcr = 'manga_ocr';
}

/// The only handle type that can resolve a local image for on-device OCR.
class LocalOcrHandle implements OcrHandle {
  const LocalOcrHandle({required this.id, required this.localPath});

  @override
  final String id;
  final String localPath;
}

/// One on-device OCR result. [text] is already composed/normalized.
class OcrRun {
  const OcrRun({
    required this.engine,
    required this.mode,
    required this.text,
    required this.elapsedMs,
    this.confidence = 0,
    this.blocks = const <OcrBlock>[],
  });

  final String engine;
  final OcrMode mode;
  final String text;
  final int elapsedMs;
  final double confidence;
  final List<OcrBlock> blocks;
}

abstract interface class OcrPort {
  Future<void> ensureReady();

  /// Runs OCR with an optional engine constraint. `null` keeps the native
  /// best-of behaviour. When [engine] is set, the adapter must return that
  /// engine or fail; callers use this to build distinct model/orientation
  /// combinations instead of silently receiving the same model three times.
  Future<OcrRun> recognize({
    required OcrHandle image,
    required OcrMode mode,
    String? engine,
  });

  bool get horizontalAvailable;
  bool get verticalAvailable;

  Future<void> cancel();
}
