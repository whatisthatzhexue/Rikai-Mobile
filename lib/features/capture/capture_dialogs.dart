import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

class DeletePhotoChoice {
  const DeletePhotoChoice({
    required this.confirmed,
    required this.deleteOriginal,
  });

  final bool confirmed;
  final bool deleteOriginal;
}

Future<DeletePhotoChoice?> showDeletePhotoDialog(
  BuildContext context, {
  required int count,
  required bool allowOriginal,
}) {
  var deleteOriginal = false;
  return showDialog<DeletePhotoChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(count <= 1 ? '从照片集中删除这张照片？' : '删除所选 $count 张照片？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('照片会从当前照片集移除。'),
            if (allowOriginal) ...[
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: deleteOriginal,
                onChanged: (value) =>
                    setState(() => deleteOriginal = value ?? false),
                title: const Text('同时删除原文件'),
                subtitle: const Text('无法获得系统删除授权时，只移除照片集副本。'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              DeletePhotoChoice(
                confirmed: true,
                deleteOriginal: deleteOriginal,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: AppColors.onHeader,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    ),
  );
}
