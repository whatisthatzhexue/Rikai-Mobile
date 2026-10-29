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
import '../../core/utils/format_bytes.dart';

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
    this.directoryPath = '',
    this.directoryAvailable = true,
    this.directoryError = '',
  });

  final String setId;
  final int installedFiles;
  final int fileCount;
  final int installedBytes;
  final int totalBytes;
  final List<String> missingFiles;
  final String directoryPath;
  final bool directoryAvailable;
  final String directoryError;

  bool get isInstalled =>
      directoryAvailable && fileCount > 0 && installedFiles == fileCount;
  double get progress => totalBytes == 0 ? 0 : installedBytes / totalBytes;
}

class OcrModelDirectoryCheck {
  const OcrModelDirectoryCheck({
    required this.ok,
    this.message = '',
    this.availableBytes,
  });

  final bool ok;
  final String message;
  final int? availableBytes;
}

class OcrModelMigrationProgress {
  const OcrModelMigrationProgress({
    required this.fileName,
    required this.copiedBytes,
    required this.totalBytes,
  });

  final String fileName;
  final int copiedBytes;
  final int totalBytes;

  double get progress => totalBytes <= 0 ? 0 : copiedBytes / totalBytes;
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
    Future<String> Function()? modelsDirectory,
    Future<int?> Function(String path)? availableSpace,
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
       _rootDirectory = rootDirectory ?? _defaultRootDirectory,
       _modelsDirectory = modelsDirectory,
       _availableSpace = availableSpace;

  final AssetBundle _bundle;
  final Dio _dio;
  final Future<Directory> Function() _rootDirectory;
  final Future<String> Function()? _modelsDirectory;
  final Future<int?> Function(String path)? _availableSpace;

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

  /// Absolute path of the model directory currently configured.
  ///
  /// This is a pure path resolution (no directory creation, no IO side effect),
  /// so it is safe to call for UI display and status checks.
  Future<OcrModelDirectoryCheck> validateModelsDirectory(
    String path, {
    int requiredBytes = 0,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return const OcrModelDirectoryCheck(ok: false, message: '目录路径为空');
    }
    final directory = Directory(trimmed);
    try {
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      final probe = File(
        p.join(
          directory.path,
          '.rikai_write_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probe.writeAsBytes(const [0], flush: true);
      await probe.delete();
      final available = _availableSpace == null
          ? null
          : await _availableSpace(trimmed);
      if (requiredBytes > 0 && available != null && available < requiredBytes) {
        return OcrModelDirectoryCheck(
          ok: false,
          message: '目录剩余空间不足（需要 ${formatBytes(requiredBytes)}）',
          availableBytes: available,
        );
      }
      return OcrModelDirectoryCheck(ok: true, availableBytes: available);
    } on FileSystemException catch (error) {
      return OcrModelDirectoryCheck(
        ok: false,
        message: '目录不可读写：${error.message}',
      );
    }
  }

  Future<void> migrateModels({
    required List<OcrModelSet> sets,
    required String destinationPath,
    bool move = false,
    void Function(OcrModelMigrationProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sourcePath = await modelsDirectoryPath();
    if (p.normalize(sourcePath) == p.normalize(destinationPath)) return;
    final totalBytes = sets.fold<int>(0, (sum, set) => sum + set.totalSize);
    var copiedBytes = 0;
    for (final set in sets) {
      final sourceDirectory = Directory(p.join(sourcePath, set.id));
      final destinationDirectory = Directory(p.join(destinationPath, set.id));
      if (!destinationDirectory.existsSync()) {
        await destinationDirectory.create(recursive: true);
      }
      for (final file in set.files) {
        if (isCancelled?.call() ?? false) {
          throw const OcrModelException('CANCELLED', '已取消模型迁移');
        }
        final source = File(p.join(sourceDirectory.path, file.name));
        final destination = File(p.join(destinationDirectory.path, file.name));
        if (!source.existsSync()) {
          copiedBytes += file.size;
          continue;
        }
        if (await _isValidFile(destination, file)) {
          copiedBytes += file.size;
          onProgress?.call(
            OcrModelMigrationProgress(
              fileName: file.name,
              copiedBytes: copiedBytes,
              totalBytes: totalBytes,
            ),
          );
          continue;
        }
        if (destination.existsSync()) await destination.delete();
        final temp = File('${destination.path}.migrating');
        if (temp.existsSync()) await temp.delete();
        final input = source.openRead();
        final output = temp.openWrite();
        var fileCopied = 0;
        try {
          await for (final chunk in input) {
            if (isCancelled?.call() ?? false) {
              throw const OcrModelException('CANCELLED', '已取消模型迁移');
            }
            output.add(chunk);
            fileCopied += chunk.length;
            onProgress?.call(
              OcrModelMigrationProgress(
                fileName: file.name,
                copiedBytes: copiedBytes + fileCopied,
                totalBytes: totalBytes,
              ),
            );
          }
          await output.flush();
        } finally {
          await output.close();
        }
        if (!await _isValidFile(temp, file)) {
          if (temp.existsSync()) await temp.delete();
          throw OcrModelException('MIGRATION_INVALID', '${file.name} 迁移后校验失败');
        }
        await temp.rename(destination.path);
        copiedBytes += file.size;
        onProgress?.call(
          OcrModelMigrationProgress(
            fileName: file.name,
            copiedBytes: copiedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
    }
    if (move) {
      for (final set in sets) {
        final sourceDirectory = Directory(p.join(sourcePath, set.id));
        for (final file in set.files) {
          final source = File(p.join(sourceDirectory.path, file.name));
          if (source.existsSync()) {
            try {
              await source.delete();
            } on FileSystemException {
              // Keep the source if removal is not permitted; the destination
              // copy is already complete.
            }
          }
        }
      }
    }
  }

  Future<String> modelsDirectoryPath() async {
    final custom = _modelsDirectory == null ? '' : await _modelsDirectory();
    if (custom.trim().isNotEmpty) return Directory(custom.trim()).path;
    if (_modelsRootOverride.isNotEmpty) {
      return Directory(_modelsRootOverride).path;
    }
    return p.join((await _rootDirectory()).path, 'models');
  }

  Future<Directory> modelsRoot({bool create = false}) async {
    final directory = Directory(await modelsDirectoryPath());
    if (create && !directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> setDirectory(OcrModelSet set, {bool create = false}) async {
    final root = await modelsRoot(create: create);
    final directory = Directory(p.join(root.path, set.id));
    if (create && !directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<OcrModelStatus> status(OcrModelSet set) async {
    final path = await modelsDirectoryPath();
    var installedBytes = 0;
    var installedFiles = 0;
    final missing = <String>[];
    try {
      final directory = await setDirectory(set);
      if (directory.existsSync()) {
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
      } else {
        missing.addAll(set.files.map((file) => file.name));
      }
    } on FileSystemException catch (error) {
      return OcrModelStatus(
        setId: set.id,
        installedFiles: 0,
        fileCount: set.files.length,
        installedBytes: 0,
        totalBytes: set.totalSize,
        missingFiles: set.files.map((file) => file.name).toList(),
        directoryPath: path,
        directoryAvailable: false,
        directoryError: error.message,
      );
    }
    return OcrModelStatus(
      setId: set.id,
      installedFiles: installedFiles,
      fileCount: set.files.length,
      installedBytes: installedBytes,
      totalBytes: set.totalSize,
      missingFiles: missing,
      directoryPath: path,
    );
  }

  Future<String> paddleFingerprint(OcrModelManifest manifest) async {
    final paths = await paddlePaths(manifest);
    final parts = <String>[];
    for (final path in [paths.det, paths.rec, paths.keys]) {
      try {
        final stat = await File(path).stat();
        parts.add('$path:${stat.size}:${stat.modified.millisecondsSinceEpoch}');
      } catch (_) {
        parts.add('$path:unknown');
      }
    }
    return parts.join('|');
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
    final directory = await setDirectory(set, create: true);
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
    if (response.statusCode == 416) {
      // The server no longer considers the partial file a valid range (for
      // example the upstream file changed). Never append the error body.
      if (part.existsSync()) await part.delete();
      throw const OcrModelException(
        'DOWNLOAD_INCOMPLETE',
        '续传位置失效，正在从其他镜像重新下载',
      );
    }
    if (response.statusCode == 206) {
      final contentRange = response.headers.value(
        HttpHeaders.contentRangeHeader,
      );
      final match = contentRange == null
          ? null
          : RegExp(r'bytes\s+(\d+)-').firstMatch(contentRange);
      final responseStart = match == null
          ? null
          : int.tryParse(match.group(1)!);
      if (responseStart != null && responseStart != existing) {
        if (part.existsSync()) await part.delete();
        throw const OcrModelException(
          'DOWNLOAD_INCOMPLETE',
          '续传响应与本地进度不一致，已重新开始下载',
        );
      }
    }
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
    if (selected.isEmpty) {
      throw const OcrModelException('IMPORT_INCOMPLETE', '没有选择文件');
    }
    final directory = await setDirectory(set, create: true);
    final missing = <OcrModelFile>[];
    for (final expected in set.files) {
      final target = File(p.join(directory.path, expected.name));
      if (!await _isValidFile(target, expected)) missing.add(expected);
    }
    if (missing.isEmpty) return;

    // Upstream Paddle downloads are named inference.onnx/inference.yml for
    // both roles. Match exact manifest names first, then disambiguate by the
    // pinned file size and extension. Det and rec have different sizes.
    final candidates = <_ImportCandidate>[];
    for (final file in selected) {
      final path = file.path;
      if (path == null) continue;
      final source = File(path);
      if (!source.existsSync()) continue;
      final length = await file.length() ?? await source.length();
      if (length <= 0) continue;
      candidates.add(
        _ImportCandidate(name: file.name, path: path, length: length),
      );
    }
    final used = <String>{};
    final assignments = <OcrModelFile, _ImportCandidate>{};
    for (final expected in missing) {
      _ImportCandidate? match;
      for (final candidate in candidates) {
        if (used.contains(candidate.path)) continue;
        if (candidate.name.toLowerCase() == expected.name.toLowerCase()) {
          match = candidate;
          break;
        }
      }
      if (match == null) {
        for (final candidate in candidates) {
          if (used.contains(candidate.path)) continue;
          if (candidate.length == expected.size &&
              _compatibleExtension(candidate.name, expected.name)) {
            match = candidate;
            break;
          }
        }
      }
      if (match == null) continue;
      assignments[expected] = match;
      used.add(match.path);
    }
    final unresolved = missing
        .where((file) => !assignments.containsKey(file))
        .map((file) => file.name)
        .toList();
    if (unresolved.isNotEmpty) {
      throw OcrModelException(
        'IMPORT_INCOMPLETE',
        '仍缺少文件：${unresolved.join('、')}。'
            '请选择 det.onnx（inference.onnx，约 4.8MB）、'
            'rec.onnx（inference.onnx，约 16.5MB）和 keys.yml（inference.yml）。',
      );
    }

    // Validate all copies before replacing any live file, so a bad selection
    // cannot leave the model directory in a half-imported state.
    final staged = <OcrModelFile, File>{};
    try {
      for (final entry in assignments.entries) {
        final expected = entry.key;
        final candidate = entry.value;
        final target = File(p.join(directory.path, expected.name));
        final temp = File('${target.path}.importing');
        if (temp.existsSync()) await temp.delete();
        if (candidate.path == target.path) {
          // Should be unreachable because the target was invalid, but keep a
          // safe copy path for an exotic picker result.
          final backup = File('${target.path}.import-source');
          if (backup.existsSync()) await backup.delete();
          await target.rename(backup.path);
          await backup.rename(temp.path);
        } else {
          await File(candidate.path).copy(temp.path);
        }
        if (!await _isValidFile(temp, expected)) {
          throw OcrModelException(
            'IMPORT_INVALID',
            '${candidate.name} 校验失败，可能不是 ${expected.name}',
          );
        }
        staged[expected] = temp;
      }
      for (final entry in staged.entries) {
        final target = File(p.join(directory.path, entry.key.name));
        if (target.existsSync()) await target.delete();
        await entry.value.rename(target.path);
      }
      staged.clear();
    } finally {
      for (final temp in staged.values) {
        if (temp.existsSync()) await temp.delete();
      }
    }
  }

  bool _compatibleExtension(String candidate, String expected) {
    final candidateExtension = p.extension(candidate).toLowerCase();
    final expectedExtension = p.extension(expected).toLowerCase();
    if (expectedExtension == '.onnx') return candidateExtension == '.onnx';
    if (expectedExtension == '.yml' || expectedExtension == '.yaml') {
      return candidateExtension == '.yml' ||
          candidateExtension == '.yaml' ||
          candidateExtension == '.txt';
    }
    return candidateExtension == expectedExtension;
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

class _ImportCandidate {
  const _ImportCandidate({
    required this.name,
    required this.path,
    required this.length,
  });

  final String name;
  final String path;
  final int length;
}
