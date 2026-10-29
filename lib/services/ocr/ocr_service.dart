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

  String? get fingerprint => _fingerprint;
  Map<String, Object?>? get readiness => _readiness;
  bool get mangaReady => _readiness?['mangaReady'] == true;
  bool get docOrientationReady => _readiness?['docOrientationReady'] == true;
  Stream<OcrProgress> get progress => _progress.stream;

  void _attachProgress() {
    _progressSubscription?.cancel();
    _progressSubscription = _ocr.progress.listen(
      _progress.add,
      onError: (_) {},
    );
  }

  Future<String> ensureReady(OcrModelManifest manifest) async {
    final paths = await _manager.runtimePaths(manifest);
    final nextFingerprint = await _manager.fingerprintForPaths(paths);
    if (_fingerprint == nextFingerprint) return nextFingerprint;

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

  Future<OcrResult> recognize({
    required String imagePath,
    OcrMode mode = OcrMode.auto,
  }) {
    return _ocr.recognize(imagePath: imagePath, mode: mode);
  }

  Future<void> cancel() => _ocr.cancel();

  Future<void> dispose() async {
    await _progressSubscription?.cancel();
    _progressSubscription = null;
    await _progress.close();
    await _ocr.dispose();
    _readiness = null;
    _fingerprint = null;
  }
}
