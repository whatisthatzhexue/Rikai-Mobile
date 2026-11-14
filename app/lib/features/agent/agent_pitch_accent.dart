import 'package:flutter/material.dart';

import '../../core/models/agent/agent_pitch.dart';
import '../../core/ui/pitch_accent_overlay.dart';
import 'agent_rich_text.dart';

export '../../core/ui/pitch_accent_overlay.dart'
    show PitchAccentSegment, pitchAccentSegments, shouldDisplayPitch;

/// A word surface with a UniDic high/low pitch line above it.
///
/// When [reading] is present, the vertical order is pitch line → ruby reading
/// → base text, so a pitch line is always above the RUBY annotation rather
/// than between the reading and the base. The widget never draws a line when
/// [accent] is null or invalid. It is used only in word-note/dictionary-fact
/// rows; callers must not use it for the AI bubble, original quote, segment
/// prose, evidence or Markdown.
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
    return Semantics(
      label: plain,
      child: PitchAccentOverlay(accent: validAccent!, child: word),
    );
  }
}
