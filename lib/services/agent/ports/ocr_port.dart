import 'package:rikai_ocr/rikai_ocr.dart';

/// Opaque image identity used by the Agent. A local path is never serialized.
abstract interface class OcrHandle {
  String get id;
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

  Future<OcrRun> recognize({required OcrHandle image, required OcrMode mode});

  bool get horizontalAvailable;
  bool get verticalAvailable;

  Future<void> cancel();
}
