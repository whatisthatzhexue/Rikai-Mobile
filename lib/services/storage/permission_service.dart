import 'package:flutter/services.dart';

/// Storage permission state reported by the Android host.
class StorageAccessStatus {
  const StorageAccessStatus({
    required this.sdkInt,
    required this.allFilesAccess,
    required this.legacyRead,
  });

  static const StorageAccessStatus unknown = StorageAccessStatus(
    sdkInt: 0,
    allFilesAccess: false,
    legacyRead: false,
  );

  final int sdkInt;
  final bool allFilesAccess;
  final bool legacyRead;

  /// All Files Access is required on Android 11+ (API 30). Older releases use
  /// the READ_EXTERNAL_STORAGE runtime permission.
  bool get granted => sdkInt >= 30 ? allFilesAccess : legacyRead;

  factory StorageAccessStatus.fromMap(Map<Object?, Object?> map) {
    return StorageAccessStatus(
      sdkInt: map['sdkInt'] as int? ?? 0,
      allFilesAccess: map['allFilesAccess'] as bool? ?? false,
      legacyRead: map['legacyRead'] as bool? ?? false,
    );
  }
}

/// MethodChannel bridge to the Android storage-permission implementation.
///
/// `permission_handler` was removed because its Android Kotlin DSL fails to
/// compile with this toolchain; the native channel is the supported path.
class PermissionService {
  const PermissionService();

  static const MethodChannel _channel = MethodChannel(
    'rikai/storage_permission',
  );

  Future<StorageAccessStatus> getStatus() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getStorageAccessStatus',
      );
      if (map == null) return StorageAccessStatus.unknown;
      return StorageAccessStatus.fromMap(map);
    } on PlatformException {
      return StorageAccessStatus.unknown;
    } on MissingPluginException {
      return StorageAccessStatus.unknown;
    }
  }

  /// Opens the All Files Access system settings page on Android 11+ and
  /// resolves with the current state. The definitive state is re-read when the
  /// app resumes.
  Future<bool> requestAllFilesAccess() async {
    final result = await _channel.invokeMethod<bool>('requestAllFilesAccess');
    return result ?? false;
  }

  /// Requests READ_EXTERNAL_STORAGE on Android 10 and below.
  Future<bool> requestLegacyReadPermission() async {
    final result = await _channel.invokeMethod<bool>(
      'requestLegacyReadPermission',
    );
    return result ?? false;
  }

  Future<void> openAppSettings() async {
    await _channel.invokeMethod<void>('openAppSettings');
  }
}
