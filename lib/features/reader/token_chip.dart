import 'package:flutter/material.dart';

import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import 'furigana_text.dart';

/// One tappable word in the reader.
///
/// Content words get a tinted background and brand-blue text; particles,
/// auxiliaries and punctuation stay black. The reading line uses the brand
/// blue. The reader avoids grey text so the page feels calm and legible.
class TokenChip extends StatelessWidget {
  const TokenChip({
    super.key,
    required this.token,
    required this.fontSize,
    required this.showFurigana,
    this.onTap,
  });

  final Token token;
  final double fontSize;
  final bool showFurigana;
  final ValueChanged<Token>? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final punctuation = token.isPunctuationOrSymbol;
    final contentWord = token.isContentWord;

    final Color background;
    final Color foreground;
    if (punctuation) {
      background = Colors.transparent;
      foreground = scheme.onSurface;
    } else if (contentWord) {
      background = scheme.primaryContainer.withValues(alpha: 0.75);
      foreground = scheme.onPrimaryContainer;
    } else {
      background = Colors.transparent;
      foreground = scheme.onSurface;
    }

    final reading = showFurigana && !punctuation && token.hasDistinctReading
        ? token.reading
        : '';
    final tap = punctuation ? null : onTap;

    return Semantics(
      label: reading.isEmpty ? token.surface : '${token.surface}，读音 $reading',
      button: tap != null,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap == null ? null : () => tap(token),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: punctuation ? 0 : AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FuriganaText(
                  text: reading,
                  fontSize: fontSize * 0.55,
                  color: scheme.primary,
                ),
                Text(
                  token.surface,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.15,
                    color: foreground,
                    fontWeight: contentWord ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
