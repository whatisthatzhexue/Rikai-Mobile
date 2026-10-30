import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/ui/rikai_toast.dart';
import '../../state/providers.dart';

/// True when [path] is outside the app's private external directory and
/// therefore needs Android's All Files Access (or the legacy read permission).
bool pathNeedsAllFilesAccess(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) return false;
  if (!normalized.startsWith('/sdcard') &&
      !normalized.startsWith('/storage') &&
      !normalized.startsWith('/mnt/')) {
    return false;
  }
  return !normalized.contains('/Android/data/com.rikai.mobile/') &&
      !normalized.contains('/Android/obb/com.rikai.mobile/');
}

/// Asks the user to grant storage access before a selected path is used.
///
/// Returns true when the existing permission is sufficient. When the user
/// confirms, the system authorization page opens and this call returns false;
/// the caller should stop and let the user retry after returning.
Future<bool> ensurePathAccess(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  if (!pathNeedsAllFilesAccess(path)) return true;
  final service = ref.read(permissionServiceProvider);
  final status = await service.getStatus();
  if (status.sdkInt == 0 || status.granted) return true;
  if (!context.mounted) return false;

  FocusManager.instance.primaryFocus?.unfocus();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('需要访问文件'),
      content: const Text(
        '这个位置在应用专属目录之外，需要「所有文件访问」权限才能读取。\n\n'
        '授权后请返回本页，再次选择或校验。也可以把文件放到应用专属目录，'
        '这样不需要额外权限。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('去授权'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    if (status.sdkInt >= 30) {
      await service.requestAllFilesAccess();
    } else {
      await service.requestLegacyReadPermission();
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      RikaiToast.show(context, '无法打开授权页面：${error.message ?? error.code}');
    }
  }
  if (context.mounted) {
    RikaiToast.show(context, '授权后请返回并重试');
  }
  return false;
}
