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
    this.mode = OcrMode.auto,
    this.ocrCache = const {},
  });

  final String id;
  final String filePath;
  final String? originalPath;
  final CapturePhotoSource source;
  final DateTime createdAt;

  /// Per-photo OCR mode. A photo set may mix horizontal and vertical pages;
  /// keeping the mode on the photo prevents one page's choice from forcing
  /// every other page to re-recognize.
  final OcrMode mode;
  final Map<String, PhotoOcrResult> ocrCache;

  CapturePhoto copyWith({
    String? filePath,
    String? originalPath,
    CapturePhotoSource? source,
    DateTime? createdAt,
    OcrMode? mode,
    Map<String, PhotoOcrResult>? ocrCache,
  }) {
    return CapturePhoto(
      id: id,
      filePath: filePath ?? this.filePath,
      originalPath: originalPath ?? this.originalPath,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      mode: mode ?? this.mode,
      ocrCache: ocrCache ?? this.ocrCache,
    );
  }

  CapturePhoto withOcr(String key, PhotoOcrResult result) {
    final next = Map<String, PhotoOcrResult>.from(ocrCache);
    next[key] = result;
    return copyWith(ocrCache: next);
  }

  /// Exact cache lookup, then a safe manual-mode fallback.
  ///
  /// An auto result produced solely by Paddle is valid for manual horizontal,
  /// and a solely-MangaOCR result is valid for manual vertical. Mixed results
  /// never alias because they contain both layouts.
  PhotoOcrResult? findOcrResult({
    required OcrMode mode,
    required String fingerprint,
  }) {
    final exact =
        ocrCache[photoOcrCacheKey(mode: mode, fingerprint: fingerprint)];
    if (exact != null) return exact;
    if (mode != OcrMode.horizontal && mode != OcrMode.vertical) return null;
    final auto =
        ocrCache[photoOcrCacheKey(
          mode: OcrMode.auto,
          fingerprint: fingerprint,
        )];
    if (auto == null) return null;
    if (mode == OcrMode.horizontal && auto.engine == 'paddle_v5') return auto;
    if (mode == OcrMode.vertical && auto.engine == 'manga_ocr') return auto;
    return null;
  }

  CapturePhoto withoutOcr() => copyWith(ocrCache: const {});
}

class CaptureSessionState {
  const CaptureSessionState({
    this.photos = const [],
    this.currentIndex = 0,
    this.mode = OcrMode.auto,
  });

  final List<CapturePhoto> photos;
  final int currentIndex;

  /// OCR mode is session-level so leaving and reopening the photo set reuses
  /// the same cache keys instead of silently falling back to auto.
  final OcrMode mode;

  bool get isEmpty => photos.isEmpty;
  int get length => photos.length;
  CapturePhoto? get current =>
      photos.isEmpty ? null : photos[currentIndex.clamp(0, photos.length - 1)];

  CaptureSessionState copyWith({
    List<CapturePhoto>? photos,
    int? currentIndex,
    OcrMode? mode,
  }) {
    final nextPhotos = photos ?? this.photos;
    final index = currentIndex ?? this.currentIndex;
    return CaptureSessionState(
      photos: nextPhotos,
      currentIndex: nextPhotos.isEmpty
          ? 0
          : index.clamp(0, nextPhotos.length - 1),
      mode: mode ?? this.mode,
    );
  }
}

String photoOcrCacheKey({required OcrMode mode, required String fingerprint}) {
  return '${mode.name}@$fingerprint';
}
