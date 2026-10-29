import 'package:flutter/services.dart';

/// Reads free space for a directory without adding a third-party dependency.
class StorageSpaceService {
  const StorageSpaceService();

  static const MethodChannel _channel = MethodChannel('rikai/storage_space');

  Future<int?> availableBytes(String path) async {
    try {
      return await _channel.invokeMethod<int>('getAvailableBytes', {
        'path': path,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
