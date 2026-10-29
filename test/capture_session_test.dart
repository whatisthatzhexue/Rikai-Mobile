import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/capture_photo.dart';
import 'package:rikai_mobile/state/capture_session.dart';
import 'package:rikai_ocr/rikai_ocr.dart';

CapturePhoto _photo(String id) => CapturePhoto(
  id: id,
  filePath: '/tmp/$id.jpg',
  source: CapturePhotoSource.camera,
  createdAt: DateTime(2026),
);

void main() {
  test('session keeps order, current index and per-photo OCR cache', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(captureSessionProvider.notifier);

    notifier.addPhotos([_photo('a'), _photo('b')]);
    expect(container.read(captureSessionProvider).currentIndex, 1);
    notifier.setMode(OcrMode.horizontal);
    expect(container.read(captureSessionProvider).mode, OcrMode.horizontal);
    notifier.setCurrentIndex(0);
    notifier.setOcrResult(
      'a',
      'auto@m1',
      const PhotoOcrResult(
        text: 'ありがとう',
        engine: 'paddle_v5',
        elapsedMs: 10,
        blocks: <OcrBlock>[],
      ),
    );
    expect(
      container
          .read(captureSessionProvider)
          .photos
          .first
          .ocrCache['auto@m1']
          ?.text,
      'ありがとう',
    );

    notifier.removePhotos({'b'});
    expect(container.read(captureSessionProvider).photos, hasLength(1));
    expect(container.read(captureSessionProvider).currentIndex, 0);
    expect(container.read(captureSessionProvider).mode, OcrMode.horizontal);
    notifier.clearOcrCache();
    expect(
      container.read(captureSessionProvider).photos.first.ocrCache,
      isEmpty,
    );
  });

  test('manual modes reuse a compatible auto result only', () {
    const paddle = PhotoOcrResult(
      text: 'ありがとう',
      engine: 'paddle_v5',
      elapsedMs: 10,
      blocks: <OcrBlock>[],
    );
    const manga = PhotoOcrResult(
      text: 'これはテストです',
      engine: 'manga_ocr',
      elapsedMs: 10,
      blocks: <OcrBlock>[],
    );
    const mixed = PhotoOcrResult(
      text: 'mixed',
      engine: 'paddle_v5+manga_ocr',
      elapsedMs: 10,
      blocks: <OcrBlock>[],
    );
    final photo = _photo('a')
        .withOcr(
          photoOcrCacheKey(mode: OcrMode.auto, fingerprint: 'm1'),
          paddle,
        )
        .withOcr(photoOcrCacheKey(mode: OcrMode.auto, fingerprint: 'm2'), manga)
        .withOcr(
          photoOcrCacheKey(mode: OcrMode.auto, fingerprint: 'm3'),
          mixed,
        );

    expect(
      photo.findOcrResult(mode: OcrMode.horizontal, fingerprint: 'm1'),
      same(paddle),
    );
    expect(
      photo.findOcrResult(mode: OcrMode.vertical, fingerprint: 'm2'),
      same(manga),
    );
    expect(
      photo.findOcrResult(mode: OcrMode.horizontal, fingerprint: 'm2'),
      isNull,
    );
    expect(
      photo.findOcrResult(mode: OcrMode.vertical, fingerprint: 'm3'),
      isNull,
    );
  });

  test('clearing one photo OCR keeps other photos and the session mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(captureSessionProvider.notifier);
    notifier.addPhotos([_photo('a'), _photo('b')]);
    notifier.setMode(OcrMode.vertical);
    notifier.setOcrResult(
      'a',
      'auto@m1',
      const PhotoOcrResult(
        text: 'a',
        engine: 'paddle_v5',
        elapsedMs: 10,
        blocks: <OcrBlock>[],
      ),
    );
    notifier.setOcrResult(
      'b',
      'auto@m1',
      const PhotoOcrResult(
        text: 'b',
        engine: 'paddle_v5',
        elapsedMs: 10,
        blocks: <OcrBlock>[],
      ),
    );

    notifier.clearPhotoOcr('a');
    final state = container.read(captureSessionProvider);
    expect(state.photos.first.ocrCache, isEmpty);
    expect(state.photos.last.ocrCache, hasLength(1));
    expect(state.mode, OcrMode.vertical);
  });
}
