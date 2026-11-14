import 'package:flutter/material.dart';

/// Small staggered fade for validated result items. It only runs after the
/// result has passed validation; it never animates raw streamed tagged text.
class AgentFadeIn extends StatelessWidget {
  const AgentFadeIn({
    super.key,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  /// Only the first few result blocks animate. A long expanded analysis must
  /// not start dozens of opacity/translate animations in the same frame.
  static const int maxAnimatedItems = 4;

  final int index;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final start = (index * 0.08).clamp(0.0, 0.55).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Interval(start, 1, curve: Curves.easeOut),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 6),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
