import 'package:rikai_ocr/rikai_ocr.dart';

enum CapturePhotoSource { camera, gallery }

/// One OCR result cached for a photo, mode and model fingerprint.
class PhotoOcrResult {
  const PhotoOcrResult({
    required this.text,
    required this.engine,
    required this.elapsedMs,
    required this.blocks,
  });

  final String text;
  final String engine;
  final int elapsedMs;
  final List<OcrBlock> blocks;

  factory PhotoOcrResult.fromOcrResult(OcrResult result, String text) {
    return PhotoOcrResult(
      text: text,
      engine: result.engine,
      elapsedMs: result.elapsedMs,
      blocks: result.blocks,
    );
  }
}

/// A photo in the current capture session. Files are private session copies.
class CapturePhoto {
  const CapturePhoto({
    required this.id,
    required this.filePath,
    required this.source,
    required this.createdAt,
    this.originalPath,
    this.ocrCache = const {},
  });

  final String id;
  final String filePath;
  final String? originalPath;
  final CapturePhotoSource source;
  final DateTime createdAt;
  final Map<String, PhotoOcrResult> ocrCache;

  CapturePhoto copyWith({
    String? filePath,
    String? originalPath,
    CapturePhotoSource? source,
    DateTime? createdAt,
    Map<String, PhotoOcrResult>? ocrCache,
  }) {
    return CapturePhoto(
      id: id,
      filePath: filePath ?? this.filePath,
      originalPath: originalPath ?? this.originalPath,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      ocrCache: ocrCache ?? this.ocrCache,
    );
  }

  CapturePhoto withOcr(String key, PhotoOcrResult result) {
    final next = Map<String, PhotoOcrResult>.from(ocrCache);
    next[key] = result;
    return copyWith(ocrCache: next);
  }

  CapturePhoto withoutOcr() => copyWith(ocrCache: const {});
}

class CaptureSessionState {
  const CaptureSessionState({this.photos = const [], this.currentIndex = 0});

  final List<CapturePhoto> photos;
  final int currentIndex;

  bool get isEmpty => photos.isEmpty;
  int get length => photos.length;
  CapturePhoto? get current =>
      photos.isEmpty ? null : photos[currentIndex.clamp(0, photos.length - 1)];

  CaptureSessionState copyWith({
    List<CapturePhoto>? photos,
    int? currentIndex,
  }) {
    final nextPhotos = photos ?? this.photos;
    final index = currentIndex ?? this.currentIndex;
    return CaptureSessionState(
      photos: nextPhotos,
      currentIndex: nextPhotos.isEmpty
          ? 0
          : index.clamp(0, nextPhotos.length - 1),
    );
  }
}

String photoOcrCacheKey({required OcrMode mode, required String fingerprint}) {
  return '${mode.name}@$fingerprint';
}
