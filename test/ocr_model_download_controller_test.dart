import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/ocr_model.dart';
import 'package:rikai_mobile/services/ocr/model_manager.dart';
import 'package:rikai_mobile/state/ocr_model_download.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _set = OcrModelSet(
  id: 'paddle_v5',
  displayName: 'PaddleOCR',
  license: 'Apache-2.0',
  files: <OcrModelFile>[
    OcrModelFile(
      name: 'det.onnx',
      urls: <String>['https://example.com/det.onnx'],
      size: 100,
    ),
  ],
);

void main() {
  test(
    'download progress survives outside the model page and completes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final progressStarted = Completer<void>();
      final finish = Completer<void>();
      CancelToken? token;

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          ocrModelDownloadRunnerProvider.overrideWithValue((
            set, {
            required customMirror,
            required cancelToken,
            required onProgress,
          }) async {
            token = cancelToken;
            onProgress(
              const OcrModelDownloadProgress(
                setId: 'paddle_v5',
                fileName: 'det.onnx',
                fileIndex: 0,
                fileCount: 1,
                downloadedBytes: 25,
                totalBytes: 100,
                overallProgress: 0.25,
              ),
            );
            progressStarted.complete();
            await finish.future;
          }),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        ocrModelDownloadControllerProvider.notifier,
      );
      final download = controller.start(_set);
      await progressStarted.future;
      await Future<void>.delayed(Duration.zero);

      final started = container.read(
        ocrModelDownloadControllerProvider,
      )[_set.id]!;
      expect(started.status, OcrModelDownloadStatus.downloading);
      expect(started.progress, 0.25);
      expect(started.fileName, 'det.onnx');
      expect(token, isNotNull);

      finish.complete();
      await download;
      final completed = container.read(
        ocrModelDownloadControllerProvider,
      )[_set.id]!;
      expect(completed.status, OcrModelDownloadStatus.completed);
      expect(completed.progress, 1);
      expect(completed.finishedAt, isNotNull);
    },
  );

  test(
    'cancel leaves a cancelled state instead of a page-owned spinner',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final started = Completer<void>();
      final finish = Completer<void>();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          ocrModelDownloadRunnerProvider.overrideWithValue((
            set, {
            required customMirror,
            required cancelToken,
            required onProgress,
          }) async {
            started.complete();
            await finish.future;
            if (cancelToken.isCancelled) {
              throw const OcrModelException('CANCELLED', '已取消模型下载');
            }
          }),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        ocrModelDownloadControllerProvider.notifier,
      );
      final download = controller.start(_set);
      await started.future;
      controller.cancel(_set.id);
      finish.complete();
      await download;

      final state = container.read(
        ocrModelDownloadControllerProvider,
      )[_set.id]!;
      expect(state.status, OcrModelDownloadStatus.cancelled);
      expect(state.error, '已取消下载');
    },
  );
}
