import 'dart:async';

import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/ocr_model.dart';
import 'model_manager.dart';

/// Long-lived OCR facade shared by the capture/photo-set pages.
///
/// Model sessions are kept open for the app lifetime. The fingerprint includes
/// the model paths and file metadata; when it changes the native sessions are
/// recreated even if the paths are unchanged.
class OcrService {
  OcrService(this._manager) {
    _attachProgress();
  }

  final OcrModelManager _manager;
  final StreamController<OcrProgress> _progress =
      StreamController<OcrProgress>.broadcast();
  RikaiOcr _ocr = RikaiOcr();
  StreamSubscription<OcrProgress>? _progressSubscription;
  String? _fingerprint;
  Map<String, Object?>? _readiness;
  Future<String>? _pendingReady;

  String? get fingerprint => _fingerprint;
  Map<String, Object?>? get readiness => _readiness;
  bool get paddleReady => _readiness?['engine'] == 'paddle_v5';

  /// True when a complete MangaOCR file set is configured. The native session
  /// is only created on demand (auto/vertical), not for horizontal-only use.
  bool get mangaAvailable =>
      _readiness?['mangaAvailable'] == true ||
      _readiness?['mangaReady'] == true;
  bool get mangaLoaded => _readiness?['mangaLoaded'] == true;

  /// Kept for existing UI/tests: availability, not session-loaded state.
  bool get mangaReady => mangaAvailable;
  bool get docOrientationReady =>
      _readiness?['docOrientationAvailable'] == true ||
      _readiness?['docOrientationReady'] == true;
  bool get textLineOrientationReady =>
      _readiness?['textLineOrientationAvailable'] == true ||
      _readiness?['textLineOrientationReady'] == true;
  Stream<OcrProgress> get progress => _progress.stream;

  void _attachProgress() {
    _progressSubscription?.cancel();
    _progressSubscription = _ocr.progress.listen(
      _progress.add,
      onError: (_) {},
    );
  }

  /// Initializes the mandatory PaddleOCR session and registers optional model
  /// paths. Optional MangaOCR/orientation sessions are created lazily by the
  /// native engine after the selected mode actually needs them.
  ///
  /// Pass [refresh] after returning from the model page so a replaced file at
  /// the same path is detected. Normal page re-entries reuse the session and
  /// cached stat fingerprint without touching the model files.
  Future<String> ensureReady(
    OcrModelManifest manifest, {
    bool refresh = false,
  }) {
    final pending = _pendingReady;
    if (pending != null) return pending;
    final known = _fingerprint;
    if (!refresh && known != null && _readiness != null) {
      return Future.value(known);
    }
    late final Future<String> future;
    future = _ensureReady(manifest).whenComplete(() {
      if (identical(_pendingReady, future)) _pendingReady = null;
    });
    _pendingReady = future;
    return future;
  }

  Future<String> _ensureReady(OcrModelManifest manifest) async {
    final paths = await _manager.runtimePaths(manifest);
    final nextFingerprint = await _manager.fingerprintForPaths(paths);
    if (_fingerprint == nextFingerprint && _readiness != null) {
      return nextFingerprint;
    }

    // Dispose the previous sessions so a file replaced at the same path is
    // actually reloaded.
    await _ocr.dispose();
    _ocr = RikaiOcr();
    _attachProgress();
    _readiness = await _ocr.initialize(
      detModelPath: paths.paddle.det,
      recModelPath: paths.paddle.rec,
      keysPath: paths.paddle.keys,
      mangaEncoderPath: paths.mangaEncoderPath,
      mangaDecoderPath: paths.mangaDecoderPath,
      mangaVocabPath: paths.mangaVocabPath,
      docOrientationPath: paths.docOrientationPath,
      textLineOrientationPath: paths.textLineOrientationPath,
    );
    _fingerprint = nextFingerprint;
    return nextFingerprint;
  }

  /// Loads the optional sessions needed by [mode] in the background.
  ///
  /// Call after a cached result is on screen or after returning from model
  /// settings. Horizontal mode never loads MangaOCR.
  Future<void> prewarm(
    OcrModelManifest manifest, {
    required OcrMode mode,
  }) async {
    try {
      await ensureReady(manifest);
      if (mode == OcrMode.horizontal) return;
      _readiness = await _ocr.prepare(mode: mode);
    } catch (_) {
      // The actual recognize() call surfaces model errors with a user-facing
      // message; background preload is best-effort.
    }
  }

  Future<OcrResult> recognize({
    required String imagePath,
    OcrMode mode = OcrMode.auto,
  }) {
    return _ocr.recognize(imagePath: imagePath, mode: mode);
  }

  Future<void> cancel() => _ocr.cancel();

  Future<void> dispose() async {
    _pendingReady = null;
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    await _progress.close();
    await _ocr.dispose();
    _readiness = null;
    _fingerprint = null;
  }
}
