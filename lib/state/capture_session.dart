import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

import '../core/models/capture_photo.dart';
import '../services/capture/capture_storage.dart';

class CaptureSessionNotifier extends Notifier<CaptureSessionState> {
  @override
  CaptureSessionState build() => const CaptureSessionState();

  void addPhotos(List<CapturePhoto> photos, {bool selectLast = true}) {
    if (photos.isEmpty) return;
    final next = [...state.photos, ...photos];
    state = CaptureSessionState(
      photos: next,
      currentIndex: selectLast ? next.length - 1 : state.currentIndex,
      mode: state.mode,
    );
  }

  void setCurrentIndex(int index) {
    if (state.photos.isEmpty) return;
    state = state.copyWith(
      currentIndex: index.clamp(0, state.photos.length - 1),
    );
  }

  void setMode(OcrMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  void removePhotos(Set<String> ids) {
    if (ids.isEmpty) return;
    final next = state.photos
        .where((photo) => !ids.contains(photo.id))
        .toList(growable: false);
    final current = state.currentIndex;
    state = CaptureSessionState(
      photos: next,
      currentIndex: next.isEmpty ? 0 : current.clamp(0, next.length - 1),
      mode: state.mode,
    );
  }

  void setOcrResult(String photoId, String cacheKey, PhotoOcrResult result) {
    final index = state.photos.indexWhere((photo) => photo.id == photoId);
    if (index < 0) return;
    final next = state.photos.toList();
    next[index] = next[index].withOcr(cacheKey, result);
    state = state.copyWith(photos: next);
  }

  void clearPhotoOcr(String photoId) {
    final index = state.photos.indexWhere((photo) => photo.id == photoId);
    if (index < 0) return;
    final next = state.photos.toList();
    next[index] = next[index].withoutOcr();
    state = state.copyWith(photos: next);
  }

  void clearOcrCache() {
    state = state.copyWith(
      photos: state.photos
          .map((photo) => photo.withoutOcr())
          .toList(growable: false),
    );
  }

  void clear() {
    state = const CaptureSessionState();
  }
}

final captureSessionProvider =
    NotifierProvider<CaptureSessionNotifier, CaptureSessionState>(
      CaptureSessionNotifier.new,
    );

final captureStorageProvider = Provider<CaptureStorage>((ref) {
  return CaptureStorage();
});
