import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Round floating action used for delete/save on both the single-photo and
/// multi-select pages, so the two pages share the same visual language.
class CaptureRoundButton extends StatelessWidget {
  const CaptureRoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.onPressed,
    this.foreground = AppColors.onHeader,
    this.size = AppSizes.captureAction,
    this.iconSize = AppSizes.iconLarge,
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      style: ButtonStyle(
        fixedSize: WidgetStatePropertyAll(Size.square(size)),
        minimumSize: WidgetStatePropertyAll(Size.square(size)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(CircleBorder()),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return background.withValues(alpha: 0.4);
          }
          return background;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return foreground.withValues(alpha: 0.65);
          }
          return foreground;
        }),
      ),
      icon: Icon(icon),
    );
  }
}

/// Deep-blue photo overlay copy action shared by the photo set and corpus
/// detail pages.
class PhotoCopyButton extends StatelessWidget {
  const PhotoCopyButton({
    super.key,
    required this.onPressed,
    this.label = '复制文本',
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.header,
        foregroundColor: AppColors.onHeader,
        disabledBackgroundColor: AppColors.header.withValues(alpha: 0.4),
        minimumSize: const Size(0, AppSizes.control),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      icon: const Icon(Icons.copy_all_outlined, size: AppSizes.iconSmall),
      label: Text(label),
    );
  }
}

/// Bottom page navigation shared by the photo set and the corpus detail page.
///
/// The fixed [AppSizes.captureAction] height puts the arrow centre at the same
/// height as the screen-corner delete/save actions.
class CapturePageNavigation extends StatelessWidget {
  const CapturePageNavigation({
    super.key,
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    this.previousTooltip = '上一张',
    this.nextTooltip = '下一张',
  });

  final int index;
  final int count;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String previousTooltip;
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: SizedBox(
        height: AppSizes.captureAction,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: previousTooltip,
              onPressed: index > 0 ? onPrevious : null,
              icon: const Icon(Icons.arrow_back),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text('${index + 1}/$count'),
            ),
            IconButton(
              tooltip: nextTooltip,
              onPressed: index < count - 1 ? onNext : null,
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }
}
