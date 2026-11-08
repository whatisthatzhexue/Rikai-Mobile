import 'package:flutter/material.dart';

import '../../core/models/annotation_rules.dart';
import '../../core/models/token.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/pitch_accent_overlay.dart';
import '../../core/utils/rich_text_tags.dart';
import '../../services/mecab/unidic_accent_parser.dart';
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
    this.annotationRules = AnnotationRuleSets.basic,
    this.annotationTarget = AnnotationTarget.reader,
    this.suppressPitch = false,
    this.onTap,
  });

  final Token token;
  final double fontSize;
  final bool showFurigana;
  final AnnotationRuleSet annotationRules;
  final AnnotationTarget annotationTarget;

  /// A contextual UniDic sentence rule may suppress a single word's pitch
  /// line even when the token itself has valid accent data.
  final bool suppressPitch;
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

    final accent = parseUnidicAccent(
      accentType: token.accentTypeRaw,
      reading: token.reading,
    );
    final pitchCandidate = shouldDisplayPitch(
      surface: token.surface,
      reading: token.reading,
      accent: accent,
    );
    final plan = annotationRules.evaluate(
      token,
      annotationTarget,
      hasPitch: pitchCandidate,
    );
    final reading =
        showFurigana && plan.ruby && !punctuation && token.hasDistinctReading
        ? token.reading
        : '';
    final showPitch =
        showFurigana && plan.pitch && pitchCandidate && !suppressPitch;
    final tap = punctuation ? null : onTap;

    // Avoid a Material + InkWell for every token. A long result can contain
    // thousands of chips, and those extra layers made scrolling rebuild work
    // fall off the frame budget in batches. The visual treatment is unchanged;
    // only the ripple is omitted in favour of smooth reading.
    return Semantics(
      label: reading.isEmpty ? token.surface : '${token.surface}，读音 $reading',
      button: tap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap == null ? null : () => tap(token),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: punctuation ? 0 : AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: showPitch
                ? PitchAccentOverlay(
                    accent: accent!,
                    child: _TokenSurface(
                      surface: token.surface,
                      reading: reading,
                      fontSize: fontSize,
                      foreground: foreground,
                      readingColor: scheme.primary,
                      bold: contentWord || plan.bold,
                      underline: plan.underline,
                    ),
                  )
                : _TokenSurface(
                    surface: token.surface,
                    reading: reading,
                    fontSize: fontSize,
                    foreground: foreground,
                    readingColor: scheme.primary,
                    bold: contentWord || plan.bold,
                    underline: plan.underline,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Renders the token's reading only above the parts that need it.
///
/// A full-token furigana line repeats okurigana (`悩んでも` → `なやんでも`).
/// Splitting the surface at kana anchors keeps the reading over the unknown
/// kanji only (`悩（なや）んでも`), while every segment still reserves the
/// same furigana height so the base text stays on one line.
class _TokenSurface extends StatelessWidget {
  const _TokenSurface({
    required this.surface,
    required this.reading,
    required this.fontSize,
    required this.foreground,
    required this.readingColor,
    required this.bold,
    required this.underline,
  });

  final String surface;
  final String reading;
  final double fontSize;
  final Color foreground;
  final Color readingColor;
  final bool bold;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.15,
      color: foreground,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      decoration: underline ? TextDecoration.underline : null,
    );
    if (reading.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FuriganaText(
            text: '',
            fontSize: fontSize * 0.55,
            color: readingColor,
          ),
          Text(surface, style: baseStyle),
        ],
      );
    }
    final segments = minimalRubySegments(surface, reading);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final segment in segments)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FuriganaText(
                text: segment.reading ?? '',
                fontSize: fontSize * 0.55,
                color: readingColor,
              ),
              Text(segment.base, style: baseStyle),
            ],
          ),
      ],
    );
  }
}
