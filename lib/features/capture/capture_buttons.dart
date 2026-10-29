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
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: AppSizes.iconLarge,
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(
          Size.square(AppSizes.captureAction),
        ),
        minimumSize: const WidgetStatePropertyAll(
          Size.square(AppSizes.captureAction),
        ),
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
