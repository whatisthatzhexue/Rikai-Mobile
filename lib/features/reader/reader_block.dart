import 'package:flutter/material.dart';

import '../../core/models/token.dart';
import 'token_chip.dart';

/// A line of tokens wrapped to the available width.
class ReaderBlock extends StatelessWidget {
  const ReaderBlock({
    super.key,
    required this.tokens,
    required this.fontSize,
    required this.showFurigana,
    this.onTokenTap,
  });

  final List<Token> tokens;
  final double fontSize;
  final bool showFurigana;
  final ValueChanged<Token>? onTokenTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final token in tokens)
          TokenChip(
            token: token,
            fontSize: fontSize,
            showFurigana: showFurigana,
            onTap: onTokenTap,
          ),
      ],
    );
  }
}
