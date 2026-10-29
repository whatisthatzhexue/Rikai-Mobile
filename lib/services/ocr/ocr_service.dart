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

  String? get fingerprint => _fingerprint;
  Stream<OcrProgress> get progress => _progress.stream;

  void _attachProgress() {
    _progressSubscription?.cancel();
    _progressSubscription = _ocr.progress.listen(
      _progress.add,
      onError: (_) {},
    );
  }

  Future<String> ensureReady(OcrModelManifest manifest) async {
    final paths = await _manager.paddlePaths(manifest);
    final nextFingerprint = await _manager.paddleFingerprint(manifest);
    if (_fingerprint == nextFingerprint) return nextFingerprint;

    // Dispose the previous sessions so a file replaced at the same path is
    // actually reloaded.
    await _ocr.dispose();
    _ocr = RikaiOcr();
    _attachProgress();
    await _ocr.initialize(
      detModelPath: paths.det,
      recModelPath: paths.rec,
      keysPath: paths.keys,
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
  }
}
