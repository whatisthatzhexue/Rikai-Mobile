import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

Widget buildAgentComposer(
  BuildContext context, {
  required TextEditingController controller,
  required String? imagePath,
  required bool running,
  required bool canSend,
  required VoidCallback onPickImage,
  required VoidCallback onRemoveImage,
  required VoidCallback onSend,
  required VoidCallback onStop,
}) {
  final theme = Theme.of(context);
  return Container(
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.divider)),
    ),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Column(
      children: [
        if (imagePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.file(
                    File(imagePath),
                    width: AgentTokens.imageThumbnail,
                    height: AgentTokens.imageThumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => const Icon(
                      Icons.broken_image_outlined,
                      size: AgentTokens.imageThumbnail,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '图片仅在本机 OCR，不会上传',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '移除图片',
                  onPressed: running ? null : onRemoveImage,
                  icon: const Icon(Icons.close, size: AppSizes.icon),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: '选择图片',
              onPressed: running ? null : onPickImage,
              icon: const Icon(
                Icons.add_photo_alternate_outlined,
                size: AppSizes.iconLarge,
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: AgentTokens.composerMaxLines,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: AgentTokens.body,
                ),
                decoration: const InputDecoration(
                  hintText: '输入问题，或粘贴文本…',
                  filled: false,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: AgentTokens.composerButton,
              height: AgentTokens.composerButton,
              child: FilledButton(
                onPressed: running ? onStop : (canSend ? onSend : null),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onHeader,
                ),
                child: Icon(
                  running ? Icons.stop : Icons.arrow_upward,
                  size: AppSizes.icon,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
