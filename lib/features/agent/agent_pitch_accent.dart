import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
final RegExp _kanjiPattern = RegExp(r'[㐀-䶿一-鿿豈-﫿]');

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
    return Semantics(
      label: plain,
      child: _PitchAccentLayout(
        lineHeight: lineHeight,
        accent: validAccent!,
        color: AgentTokens.pitchAccentColor,
        strokeWidth: AgentTokens.pitchAccentLine * scale,
        child: word,
      ),
    );
  }
}

/// Paints the pitch line above the word without changing its layout size.
///
/// A plain [Stack] does not report a baseline, which made the word/ruby sit
/// below the neighbouring note text in baseline-aligned rows. This proxy
/// forwards the word's alphabetic baseline and paints the overlay in the
/// negative top area, so the line stays out of layout while the word keeps its
/// exact baseline.
class _PitchAccentLayout extends SingleChildRenderObjectWidget {
  const _PitchAccentLayout({
    required this.lineHeight,
    required this.accent,
    required this.color,
    required this.strokeWidth,
    required Widget super.child,
  });

  final double lineHeight;
  final AgentPitchAccent accent;
  final Color color;
  final double strokeWidth;

  @override
  _RenderPitchAccent createRenderObject(BuildContext context) {
    return _RenderPitchAccent(
      lineHeight: lineHeight,
      accent: accent,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPitchAccent renderObject,
  ) {
    renderObject
      ..lineHeight = lineHeight
      ..accent = accent
      ..color = color
      ..strokeWidth = strokeWidth;
  }
}

class _RenderPitchAccent extends RenderProxyBox {
  _RenderPitchAccent({
    required double lineHeight,
    required AgentPitchAccent accent,
    required Color color,
    required double strokeWidth,
  }) : _lineHeight = lineHeight,
       _accent = accent,
       _color = color,
       _strokeWidth = strokeWidth;

  double _lineHeight;
  AgentPitchAccent _accent;
  Color _color;
  double _strokeWidth;

  set lineHeight(double value) {
    if (_lineHeight == value) return;
    _lineHeight = value;
    markNeedsPaint();
  }

  set accent(AgentPitchAccent value) {
    if (_accent.accentType == value.accentType &&
        _accent.moraCount == value.moraCount &&
        _accent.moraPattern == value.moraPattern) {
      return;
    }
    _accent = value;
    markNeedsPaint();
  }

  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  set strokeWidth(double value) {
    if (_strokeWidth == value) return;
    _strokeWidth = value;
    markNeedsPaint();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return child?.getDistanceToActualBaseline(baseline);
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    return child?.getDryBaseline(constraints, baseline);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset);
    if (_lineHeight <= 0 || size.width <= 0) return;
    final paint = Paint()
      ..color = _color
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final lineTopLeft = Offset(offset.dx, offset.dy - _lineHeight);
    final lineSize = Size(size.width, _lineHeight);
    for (final segment in pitchAccentSegments(
      accent: _accent,
      size: lineSize,
      strokeWidth: _strokeWidth,
    )) {
      context.canvas.drawLine(
        lineTopLeft + segment.start,
        lineTopLeft + segment.end,
        paint,
      );
    }
  }
}

@visibleForTesting
typedef PitchAccentSegment = ({Offset start, Offset end});

/// Line segments for one pitch accent, relative to the overlay box.
///
/// The final drop is explicit: for odaka (accent type equals the mora count)
/// the fall happens after the last mora and therefore has no following mora
/// boundary inside the word. Without the extra segment the word simply ended
/// on the high line, hiding the accent nucleus.
@visibleForTesting
List<PitchAccentSegment> pitchAccentSegments({
  required AgentPitchAccent accent,
  required Size size,
  required double strokeWidth,
}) {
  if (accent.moraCount < 2 || size.width <= 0 || size.height <= 0) {
    return const <PitchAccentSegment>[];
  }
  final segment = size.width / accent.moraCount;
  final highY = strokeWidth / 2 + 1;
  final lowY = size.height - strokeWidth / 2 - 1;
  final segments = <PitchAccentSegment>[];
  double? previousY;
  for (var index = 0; index < accent.moraCount; index++) {
    final y = accent.moraPattern[index] == 'H' ? highY : lowY;
    final x = segment * index;
    if (previousY != null && previousY != y) {
      segments.add((start: Offset(x, previousY), end: Offset(x, y)));
    }
    segments.add((start: Offset(x, y), end: Offset(x + segment, y)));
    previousY = y;
  }
  if (accent.accentType == accent.moraCount &&
      accent.moraPattern.endsWith('H')) {
    // The final mora's horizontal segment ends exactly at size.width. Keep
    // the closing drop on that same x so it does not look shifted left.
    final endX = size.width;
    segments.add((start: Offset(endX, highY), end: Offset(endX, lowY)));
  }
  return segments;
}
