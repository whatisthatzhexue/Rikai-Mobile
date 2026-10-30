import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Lightweight, non-blocking message shown near the bottom of the screen.
///
/// Unlike a [SnackBar], the toast is wrapped in an [IgnorePointer], so controls
/// underneath it remain tappable while the message is visible.
abstract final class RikaiToast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (message.trim().isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _remove();
    final theme = Theme.of(context);
    final entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Material(
                color: AppColors.textPrimary,
                elevation: 0,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () {
      if (identical(_entry, entry)) _remove();
    });
  }

  static void _remove() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}
