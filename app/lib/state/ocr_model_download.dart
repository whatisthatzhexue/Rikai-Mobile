import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/ocr_model.dart';
import '../services/ocr/model_manager.dart';
import 'providers.dart';

enum OcrModelDownloadStatus { downloading, completed, cancelled, failed }

class OcrModelDownloadState {
  const OcrModelDownloadState({
    required this.setId,
    required this.displayName,
    required this.status,
    required this.startedAt,
    this.progress = 0,
    this.fileName = '',
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error = '',
    this.finishedAt,
  });

  final String setId;
  final String displayName;
  final OcrModelDownloadStatus status;
  final double progress;
  final String fileName;
  final int downloadedBytes;
  final int totalBytes;
  final String error;
  final DateTime startedAt;
  final DateTime? finishedAt;

  bool get isDownloading => status == OcrModelDownloadStatus.downloading;

  OcrModelDownloadState copyWith({
    String? displayName,
    OcrModelDownloadStatus? status,
    double? progress,
    String? fileName,
    int? downloadedBytes,
    int? totalBytes,
    String? error,
    DateTime? finishedAt,
  }) {
    return OcrModelDownloadState(
      setId: setId,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      fileName: fileName ?? this.fileName,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

/// Injected in tests and as a seam around the concrete model manager.
typedef OcrModelDownloadRunner =
    Future<void> Function(
      OcrModelSet set, {
      required String customMirror,
      required CancelToken cancelToken,
      required void Function(OcrModelDownloadProgress progress) onProgress,
    });

final ocrModelDownloadRunnerProvider = Provider<OcrModelDownloadRunner>((ref) {
  final manager = ref.watch(ocrModelManagerProvider);
  return (
    set, {
    required customMirror,
    required cancelToken,
    required onProgress,
  }) {
    return manager.downloadSet(
      set,
      customMirror: customMirror,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  };
});

/// App-scoped OCR model download ownership.
///
/// The model page is only a subscriber. Leaving the page never cancels or
/// forgets an active download; returning shows the latest progress again.
class OcrModelDownloadController
    extends Notifier<Map<String, OcrModelDownloadState>> {
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};

  @override
  Map<String, OcrModelDownloadState> build() {
    ref.onDispose(() {
      for (final token in _tokens.values) {
        token.cancel('应用关闭');
      }
      _tokens.clear();
    });
    return const <String, OcrModelDownloadState>{};
  }

  Future<void> start(OcrModelSet set) async {
    final existing = state[set.id];
    if (existing?.isDownloading ?? false) return;

    final token = CancelToken();
    _tokens[set.id] = token;
    final startedAt = DateTime.now();
    _replace(
      OcrModelDownloadState(
        setId: set.id,
        displayName: set.displayName,
        status: OcrModelDownloadStatus.downloading,
        startedAt: startedAt,
      ),
    );

    try {
      final runner = ref.read(ocrModelDownloadRunnerProvider);
      await runner(
        set,
        customMirror: ref.read(appSettingsProvider).ocrMirror,
        cancelToken: token,
        onProgress: (progress) {
          final current = state[set.id];
          if (current == null ||
              current.status != OcrModelDownloadStatus.downloading ||
              token.isCancelled) {
            return;
          }
          _replace(
            current.copyWith(
              progress: progress.overallProgress.clamp(0, 1),
              fileName: progress.fileName,
              downloadedBytes: progress.downloadedBytes,
              totalBytes: progress.totalBytes,
            ),
          );
        },
      );
      if (token.isCancelled) {
        _markCancelled(set.id);
        return;
      }
      final current = state[set.id];
      if (current == null) return;
      _replace(
        current.copyWith(
          status: OcrModelDownloadStatus.completed,
          progress: 1,
          finishedAt: DateTime.now(),
        ),
      );
    } on OcrModelException catch (error) {
      if (error.code == 'CANCELLED' || token.isCancelled) {
        _markCancelled(set.id);
      } else {
        _markFailed(set.id, error.message);
      }
    } catch (error) {
      if (token.isCancelled) {
        _markCancelled(set.id);
      } else {
        _markFailed(set.id, error.toString());
      }
    } finally {
      _tokens.remove(set.id);
    }
  }

  void cancel(String setId) {
    final token = _tokens[setId];
    if (token == null || token.isCancelled) return;
    token.cancel('用户取消下载');
    _markCancelled(setId);
  }

  void dismiss(String setId) {
    final current = state[setId];
    if (current == null || current.isDownloading) return;
    final next = Map<String, OcrModelDownloadState>.from(state)..remove(setId);
    state = Map.unmodifiable(next);
  }

  void _markCancelled(String setId) {
    final current = state[setId];
    if (current == null) return;
    _replace(
      current.copyWith(
        status: OcrModelDownloadStatus.cancelled,
        error: '已取消下载',
        finishedAt: DateTime.now(),
      ),
    );
  }

  void _markFailed(String setId, String message) {
    final current = state[setId];
    if (current == null) return;
    _replace(
      current.copyWith(
        status: OcrModelDownloadStatus.failed,
        error: message,
        finishedAt: DateTime.now(),
      ),
    );
  }

  void _replace(OcrModelDownloadState task) {
    state = Map.unmodifiable(<String, OcrModelDownloadState>{
      ...state,
      task.setId: task,
    });
  }
}

final ocrModelDownloadControllerProvider =
    NotifierProvider<
      OcrModelDownloadController,
      Map<String, OcrModelDownloadState>
    >(OcrModelDownloadController.new);
