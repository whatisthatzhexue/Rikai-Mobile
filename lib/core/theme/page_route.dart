import 'package:flutter/material.dart';

/// Material route with a shorter slide-over transition than the framework
/// default. Platform views (WebView, camera) can drop frames during long
/// transitions on some devices; 220 ms keeps the same visual language without
/// the visible stutter.
class RikaiPageRoute<T> extends MaterialPageRoute<T> {
  RikaiPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);
}
