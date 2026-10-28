import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models/ocr_model.dart';

class OcrModelException implements Exception {
  const OcrModelException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'OcrModelException($code): $message';
}

class OcrModelStatus {
  const OcrModelStatus({
    required this.setId,
    required this.installedFiles,
    required this.fileCount,
    required this.installedBytes,
    required this.totalBytes,
    required this.missingFiles,
  });

  final String setId;
  final int installedFiles;
  final int fileCount;
  final int installedBytes;
  final int totalBytes;
  final List<String> missingFiles;

  bool get isInstalled => installedFiles == fileCount;
  double get progress => totalBytes == 0 ? 0 : installedBytes / totalBytes;
}

class OcrModelDownloadProgress {
  const OcrModelDownloadProgress({
    required this.setId,
    required this.fileName,
    required this.fileIndex,
    required this.fileCount,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.overallProgress,
  });

  final String setId;
  final String fileName;
  final int fileIndex;
  final int fileCount;
  final int downloadedBytes;
  final int totalBytes;
  final double overallProgress;
}

class PaddleModelPaths {
  const PaddleModelPaths({
    required this.det,
    required this.rec,
    required this.keys,
  });

  final String det;
  final String rec;
  final String keys;
}

/// Downloads and verifies user-installed OCR models.
///
/// Model binaries are never bundled with the app. The manifest's file URLs are
/// tried in the listed order (hf-mirror first, Hugging Face second). A `.part`
/// file is resumed with an HTTP Range request and atomically renamed only
/// after size/SHA-256 verification.
class OcrModelManager {
  OcrModelManager({
    AssetBundle? bundle,
    Dio? dio,
    Future<Directory> Function()? rootDirectory,
  }) : _bundle = bundle ?? rootBundle,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 25),
               receiveTimeout: const Duration(seconds: 90),
               followRedirects: true,
             ),
           ),
       _rootDirectory = rootDirectory ?? _defaultRootDirectory;

  final AssetBundle _bundle;
  final Dio _dio;
  final Future<Directory> Function() _rootDirectory;

  /// Development/test escape hatch:
  /// `--dart-define=RIKAI_OCR_MODELS_DIR=/sdcard/Download/rikai-models`.
  /// Empty in normal builds; production always uses the app external files dir.
  static const String _modelsRootOverride = String.fromEnvironment(
    'RIKAI_OCR_MODELS_DIR',
  );

  static Future<Directory> _defaultRootDirectory() async {
    final external = await getExternalStorageDirectory();
    if (external != null) return external;
    return getApplicationSupportDirectory();
  }

  Future<OcrModelManifest> loadManifest() async {
    final raw = await _bundle.loadString('assets/models/manifest.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const OcrModelException('MANIFEST_INVALID', '模型清单格式无效');
    }
    try {
      return OcrModelManifest.fromJson(decoded);
    } on FormatException catch (error) {
      throw OcrModelException('MANIFEST_INVALID', error.message);
    }
  }

  Future<Directory> modelsRoot() async {
    final directory = _modelsRootOverride.isNotEmpty
        ? Directory(_modelsRootOverride)
        : Directory(p.join((await _rootDirectory()).path, 'models'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> setDirectory(OcrModelSet set) async {
    final root = await modelsRoot();
    final directory = Directory(p.join(root.path, set.id));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<OcrModelStatus> status(OcrModelSet set) async {
    final directory = await setDirectory(set);
    var installedBytes = 0;
    var installedFiles = 0;
    final missing = <String>[];
    for (final file in set.files) {
      final local = File(p.join(directory.path, file.name));
      final valid = await _isValidFile(local, file);
      if (valid) {
        installedFiles++;
        installedBytes += file.size;
      } else {
        missing.add(file.name);
      }
    }
    return OcrModelStatus(
      setId: set.id,
      installedFiles: installedFiles,
      fileCount: set.files.length,
      installedBytes: installedBytes,
      totalBytes: set.totalSize,
      missingFiles: missing,
    );
  }

  Future<PaddleModelPaths> paddlePaths(OcrModelManifest manifest) async {
    final set = manifest.sets['paddle_v5'];
    if (set == null) {
      throw const OcrModelException('MANIFEST_INVALID', '模型清单缺少 paddle_v5');
    }
    final directory = await setDirectory(set);
    final paths = <String, String>{};
    for (final file in set.files) {
      final local = File(p.join(directory.path, file.name));
      if (!await _isValidFile(local, file)) {
        throw OcrModelException(
          'MODEL_MISSING',
          '缺少 ${file.name}，请先在「OCR 模型」中下载或导入',
        );
      }
      paths[file.name] = local.path;
    }
    final det = paths['det.onnx'];
    final rec = paths['rec.onnx'];
    final keys = paths['keys.yml'];
    if (det == null || rec == null || keys == null) {
      throw const OcrModelException('MODEL_MISSING', 'PaddleOCR 模型文件不完整');
    }
    return PaddleModelPaths(det: det, rec: rec, keys: keys);
  }

  Future<void> downloadSet(
    OcrModelSet set, {
    String customMirror = '',
    void Function(OcrModelDownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final directory = await setDirectory(set);
    var completedBytes = 0;
    for (var index = 0; index < set.files.length; index++) {
      final file = set.files[index];
      final target = File(p.join(directory.path, file.name));
      if (await _isValidFile(target, file)) {
        completedBytes += file.size;
        _reportProgress(
          onProgress,
          set,
          file,
          index,
          completedBytes,
          file.size,
        );
        continue;
      }
      if (target.existsSync()) {
        await target.delete();
      }
      await _downloadFile(
        set: set,
        file: file,
        directory: directory,
        completedBytes: completedBytes,
        fileIndex: index,
        onProgress: onProgress,
        cancelToken: cancelToken,
        customMirror: customMirror,
      );
      completedBytes += file.size;
      _reportProgress(onProgress, set, file, index, completedBytes, file.size);
    }
  }

  Future<void> _downloadFile({
    required OcrModelSet set,
    required OcrModelFile file,
    required Directory directory,
    required int completedBytes,
    required int fileIndex,
    void Function(OcrModelDownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
    required String customMirror,
  }) async {
    final target = File(p.join(directory.path, file.name));
    final part = File('${target.path}.part');
    Object? lastError;
    for (final url in _candidateUrls(file.urls, customMirror)) {
      _throwIfCancelled(cancelToken);
      try {
        await _downloadUrl(
          set: set,
          file: file,
          part: part,
          url: url,
          completedBytes: completedBytes,
          fileIndex: fileIndex,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        final shaError = await _validateDownloaded(part, file);
        if (shaError != null) {
          await part.delete();
          throw OcrModelException('MODEL_INVALID', shaError);
        }
        if (target.existsSync()) await target.delete();
        await part.rename(target.path);
        return;
      } catch (error) {
        lastError = error;
        if (error is OcrModelException && error.code == 'CANCELLED') rethrow;
        if (cancelToken?.isCancelled ?? false) {
          throw const OcrModelException('CANCELLED', '已取消模型下载');
        }
        // Try the next mirror; a partially downloaded file is resumed.
        continue;
      }
    }
    throw OcrModelException(
      'DOWNLOAD_FAILED',
      '${file.name} 下载失败：${_friendlyDownloadError(lastError)}',
    );
  }

  List<String> _candidateUrls(List<String> urls, String customMirror) {
    final trimmed = customMirror.trim();
    if (trimmed.isEmpty) return urls;
    final base = Uri.tryParse(trimmed.endsWith('/') ? trimmed : '$trimmed/');
    if (base == null || !base.hasScheme || base.host.isEmpty) return urls;
    final mirrored = <String>[];
    for (final raw in urls) {
      final source = Uri.tryParse(raw);
      if (source == null) continue;
      final path = source.path.startsWith('/')
          ? source.path.substring(1)
          : source.path;
      final candidate = base.resolve(path);
      mirrored.add(
        source.hasQuery
            ? candidate.replace(query: source.query).toString()
            : candidate.toString(),
      );
    }
    return [...mirrored, ...urls];
  }

  String _friendlyDownloadError(Object? error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '连接模型服务器超时，请检查网络或使用本地导入';
        case DioExceptionType.connectionError:
          return '无法连接模型服务器，请检查网络或使用本地导入';
        case DioExceptionType.badResponse:
          return '模型服务器返回错误（HTTP ${error.response?.statusCode}）';
        default:
          return '网络请求失败，请检查网络或使用本地导入';
      }
    }
    if (error is OcrModelException) return error.message;
    return '所有镜像均不可用';
  }

  Future<void> _downloadUrl({
    required OcrModelSet set,
    required OcrModelFile file,
    required File part,
    required String url,
    required int completedBytes,
    required int fileIndex,
    void Function(OcrModelDownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    var existing = part.existsSync() ? await part.length() : 0;
    if (existing > file.size) {
      await part.delete();
      existing = 0;
    }
    if (existing == file.size) return;

    final headers = <String, String>{
      if (existing > 0) HttpHeaders.rangeHeader: 'bytes=$existing-',
    };
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        validateStatus: (status) =>
            status == 200 || status == 206 || status == 416,
      ),
      cancelToken: cancelToken,
    );
    if (response.statusCode == 416 && existing == file.size) return;
    final body = response.data;
    if (body == null) {
      throw const OcrModelException('DOWNLOAD_FAILED', '下载响应为空');
    }
    if (response.statusCode == 200 && existing > 0) {
      await part.writeAsBytes(const [], flush: true);
      existing = 0;
    }
    final sink = part.openWrite(mode: FileMode.append);
    var received = existing;
    var lastReportMs = 0;
    try {
      await for (final chunk in body.stream) {
        _throwIfCancelled(cancelToken);
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (received == file.size || now - lastReportMs >= 100) {
          lastReportMs = now;
          _reportProgress(
            onProgress,
            set,
            file,
            fileIndex,
            completedBytes + (received - existing),
            received,
          );
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (received != file.size) {
      throw OcrModelException(
        'DOWNLOAD_INCOMPLETE',
        '${file.name} 下载不完整（$received/${file.size} 字节）',
      );
    }
  }

  Future<String?> _validateDownloaded(File part, OcrModelFile file) async {
    if (!part.existsSync()) return '下载文件不存在';
    final length = await part.length();
    if (length != file.size) {
      return '文件大小不匹配（$length/${file.size} 字节）';
    }
    final expected = file.sha256;
    if (expected == null || expected.isEmpty) return null;
    final actual = await sha256.bind(part.openRead()).first;
    if (actual.toString() != expected) return 'SHA-256 校验失败';
    return null;
  }

  Future<bool> _isValidFile(File file, OcrModelFile expected) async {
    if (!file.existsSync()) return false;
    final length = await file.length();
    if (length != expected.size) return false;
    final hash = expected.sha256;
    if (hash == null || hash.isEmpty) return true;
    try {
      final actual = await sha256.bind(file.openRead()).first;
      return actual.toString() == hash;
    } catch (_) {
      return false;
    }
  }

  Future<void> importSet(OcrModelSet set, List<PlatformFile> selected) async {
    final directory = await setDirectory(set);
    final byName = {
      for (final file in selected)
        if (file.path != null) file.name: file,
    };
    final missing = <String>[];
    for (final expected in set.files) {
      final sourcePath = byName[expected.name]?.path;
      if (sourcePath == null) {
        missing.add(expected.name);
        continue;
      }
      final source = File(sourcePath);
      if (!source.existsSync() || await source.length() != expected.size) {
        throw OcrModelException(
          'IMPORT_INVALID',
          '${expected.name} 大小不匹配，可能选择了错误的文件',
        );
      }
      final target = File(p.join(directory.path, expected.name));
      if (target.path != source.path) {
        if (target.existsSync()) await target.delete();
        await source.copy(target.path);
      }
      if (!await _isValidFile(target, expected)) {
        if (target.existsSync()) await target.delete();
        throw OcrModelException(
          'IMPORT_INVALID',
          '${expected.name} 校验失败，请确认文件未被修改',
        );
      }
    }
    if (missing.isNotEmpty) {
      throw OcrModelException(
        'IMPORT_INCOMPLETE',
        '仍缺少文件：${missing.join('、')}',
      );
    }
  }

  Future<void> deleteSet(OcrModelSet set) async {
    final directory = await setDirectory(set);
    for (final file in set.files) {
      final target = File(p.join(directory.path, file.name));
      if (target.existsSync()) await target.delete();
      final part = File('${target.path}.part');
      if (part.existsSync()) await part.delete();
    }
  }

  void _throwIfCancelled(CancelToken? token) {
    if (token?.isCancelled ?? false) {
      throw const OcrModelException('CANCELLED', '已取消模型下载');
    }
  }

  void _reportProgress(
    void Function(OcrModelDownloadProgress progress)? callback,
    OcrModelSet set,
    OcrModelFile file,
    int fileIndex,
    int downloadedBytes,
    int currentFileBytes,
  ) {
    if (callback == null) return;
    final overall = set.totalSize <= 0
        ? 0.0
        : (downloadedBytes / set.totalSize).clamp(0.0, 1.0);
    callback(
      OcrModelDownloadProgress(
        setId: set.id,
        fileName: file.name,
        fileIndex: fileIndex,
        fileCount: set.files.length,
        downloadedBytes: currentFileBytes,
        totalBytes: file.size,
        overallProgress: overall,
      ),
    );
  }
}
