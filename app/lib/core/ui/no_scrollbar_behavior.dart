import 'package:flutter/material.dart';

/// Scrollable behaviour for long token lists.
///
/// The Android scrollbar thumb is animated from the list's estimated extent.
/// Token rows wrap to different heights, so that estimate changes while the
/// user scrolls and the thumb visibly stutters. These reading surfaces scroll
/// by touch anyway, so the platform scrollbar is suppressed.
class NoScrollbarBehavior extends MaterialScrollBehavior {
  const NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
