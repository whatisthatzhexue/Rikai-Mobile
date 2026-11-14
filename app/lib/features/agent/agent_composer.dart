import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_ui_strings.dart';
import 'agent_thumbnail.dart';

Widget buildAgentComposer(
  BuildContext context, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required List<String> imagePaths,
  required bool running,
  required bool canSend,
  required VoidCallback onPickImage,
  required ValueChanged<String> onRemoveImage,
  required VoidCallback onSend,
  required VoidCallback onStop,
  required AgentUiStrings strings,
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
        if (imagePaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (var index = 0; index < imagePaths.length; index++)
                      Stack(
                        key: ValueKey('agent-composer-image-$index'),
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: Image.file(
                              File(imagePaths[index]),
                              width: AgentTokens.imageThumbnail,
                              height: AgentTokens.imageThumbnail,
                              cacheWidth: agentThumbnailCacheSize(
                                context,
                                AgentTokens.imageThumbnail,
                              ),
                              cacheHeight: agentThumbnailCacheSize(
                                context,
                                AgentTokens.imageThumbnail,
                              ),
                              filterQuality: FilterQuality.low,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  Container(
                                    width: AgentTokens.imageThumbnail,
                                    height: AgentTokens.imageThumbnail,
                                    color: AppColors.surfaceMuted,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      size: AppSizes.icon,
                                    ),
                                  ),
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: Semantics(
                              button: true,
                              label: strings.removeImage,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: running
                                    ? null
                                    : () => onRemoveImage(imagePaths[index]),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: AppColors.textPrimary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: AppColors.onHeader,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    strings.imageLocalOnly,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AgentTokens.helper,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: strings.pickImage,
              onPressed: running ? null : onPickImage,
              icon: const Icon(
                Icons.add_photo_alternate_outlined,
                size: AppSizes.iconLarge,
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: AgentTokens.composerMaxLines,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: AgentTokens.body,
                ),
                decoration: InputDecoration(
                  hintText: strings.inputHint,
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
