import 'package:flutter/material.dart';

import '../../core/models/agent/agent_pitch.dart';
import '../../core/theme/app_tokens.dart';
import 'agent_rich_text.dart';

/// A word surface with a UniDic high/low pitch line above it.
///
/// When [reading] is present, the vertical order is pitch line → ruby reading
/// → base text, so a pitch line is always above the RUBY annotation rather
/// than between the reading and the base. The widget never draws a line when
/// [accent] is null or invalid. It is used only in word-note/dictionary-fact
/// rows; callers must not use it for the AI bubble, original quote, segment
/// prose, evidence or Markdown.
final RegExp _kanjiPattern = RegExp(r'[㐀-䶿一-鿿豈-﫿]');

/// Whether a word may show a pitch line at all.
///
/// A kanji surface without a distinct reading (empty or identical to the
/// surface) is excluded because the reading, and therefore the pitch, may be
/// ambiguous (multi-reading kanji). Pure-kana words remain eligible.
bool shouldDisplayPitch({
  required String surface,
  required String reading,
  required AgentPitchAccent? accent,
}) {
  if (accent == null || !accent.isValid) return false;
  final normalizedSurface = surface.trim();
  if (normalizedSurface.isEmpty) return false;
  final normalizedReading = reading.trim();
  final hasReading =
      normalizedReading.isNotEmpty && normalizedReading != normalizedSurface;
  final hasKanji = _kanjiPattern.hasMatch(surface);
  return !(hasKanji && !hasReading);
}

class AgentPitchAccentText extends StatelessWidget {
  const AgentPitchAccentText({
    super.key,
    required this.surface,
    required this.accent,
    required this.style,
    this.reading = '',
  });

  final String surface;
  final String reading;
  final AgentPitchAccent? accent;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final normalizedSurface = surface.trim();
    final normalizedReading = reading.trim();
    final hasReading =
        normalizedReading.isNotEmpty && normalizedReading != normalizedSurface;
    final plain = hasReading ? '$surface（$reading）' : surface;
    final word = hasReading
        ? AgentRichText(
            text: '[RUBY=$reading]$surface[/RUBY]',
            style: style,
            maxLines: 1,
          )
        : Text(surface, maxLines: 1, softWrap: false, style: style);
    final validAccent = accent;
    if (!shouldDisplayPitch(
      surface: surface,
      reading: reading,
      accent: validAccent,
    )) {
      return word;
    }
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 2.0).toDouble();
    final lineHeight = AgentTokens.pitchAccentHeight * scale;
    // Reuse AgentRichText's existing Ruby layout unchanged; only the pitch
    // line is overlaid above it and does not participate in line height.
    return Semantics(
      label: plain,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          word,
          Positioned(
            left: 0,
            right: 0,
            top: -lineHeight,
            height: lineHeight,
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _PitchAccentPainter(
                  accent: validAccent!,
                  color: AgentTokens.pitchAccentColor,
                  strokeWidth: AgentTokens.pitchAccentLine * scale,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PitchAccentPainter extends CustomPainter {
  const _PitchAccentPainter({
    required this.accent,
    required this.color,
    required this.strokeWidth,
  });

  final AgentPitchAccent accent;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (accent.moraCount < 2 || size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final segment = size.width / accent.moraCount;
    final highY = strokeWidth / 2 + 1;
    final lowY = size.height - strokeWidth / 2 - 1;
    double? previousY;
    for (var index = 0; index < accent.moraCount; index++) {
      final y = accent.moraPattern[index] == 'H' ? highY : lowY;
      final x = segment * index;
      if (previousY != null && previousY != y) {
        canvas.drawLine(Offset(x, previousY), Offset(x, y), paint);
      }
      canvas.drawLine(Offset(x, y), Offset(x + segment, y), paint);
      previousY = y;
    }
  }

  @override
  bool shouldRepaint(_PitchAccentPainter oldDelegate) {
    return oldDelegate.accent.accentType != accent.accentType ||
        oldDelegate.accent.moraPattern != accent.moraPattern ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
