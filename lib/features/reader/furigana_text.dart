import 'package:flutter/material.dart';

/// Small reading aid rendered above a token's surface form.
///
/// The widget always reserves the same height so chips with and without
/// readings align on their baseline.
class FuriganaText extends StatelessWidget {
  const FuriganaText({
    super.key,
    required this.text,
    required this.fontSize,
    this.color,
  });

  final String text;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final height = fontSize * 1.2;
    if (text.isEmpty) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.1,
          color: color ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
