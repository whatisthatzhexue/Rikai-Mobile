import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/rich_text_tags.dart';

/// Renders the validated rich-text summary. The caller must only pass text
/// whose tag-stripped form equals the original summary; malformed or modified
/// output is rejected before this widget is built.
class AgentRichText extends StatelessWidget {
  const AgentRichText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final effectiveStyle = style ?? const TextStyle();
    return Text.rich(
      TextSpan(
        style: effectiveStyle,
        children: buildAgentRichTextSpans(text, effectiveStyle),
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

List<InlineSpan> buildAgentRichTextSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  final matches = richTextTagPattern.allMatches(text).toList(growable: false);
  var cursor = 0;
  var bold = false;
  var underline = false;

  TextStyle effectiveStyle() => style.copyWith(
    fontWeight: bold ? FontWeight.w600 : style.fontWeight,
    decoration: underline ? TextDecoration.underline : style.decoration,
    decorationColor: underline
        ? AgentTokens.richTextUnderlineColor
        : style.decorationColor,
  );

  void addText(String value) {
    if (value.isEmpty) return;
    spans.add(TextSpan(text: value, style: effectiveStyle()));
  }

  var index = 0;
  while (index < matches.length) {
    final match = matches[index];
    addText(text.substring(cursor, match.start));
    final tag = (match.group(1) ?? '').toLowerCase();
    if (tag.startsWith('ruby=')) {
      var closeIndex = -1;
      for (var probe = index + 1; probe < matches.length; probe++) {
        if ((matches[probe].group(1) ?? '').toLowerCase() == '/ruby') {
          closeIndex = probe;
          break;
        }
      }
      if (closeIndex < 0) {
        addText(match.group(0) ?? '');
        cursor = match.end;
        index++;
        continue;
      }
      final close = matches[closeIndex];
      final reading = (match.group(1) ?? '').substring('ruby='.length).trim();
      final base = text.substring(match.end, close.start);
      if (reading.isEmpty || base.isEmpty) {
        addText(text.substring(match.start, close.end));
      } else {
        spans.add(_rubySpan(base, reading, effectiveStyle()));
      }
      cursor = close.end;
      index = closeIndex + 1;
      continue;
    }
    if (tag == 'bold') {
      bold = true;
    } else if (tag == '/bold') {
      bold = false;
    } else if (tag == 'underline') {
      underline = true;
    } else if (tag == '/underline') {
      underline = false;
    } else {
      addText(match.group(0) ?? '');
    }
    cursor = match.end;
    index++;
  }
  addText(text.substring(cursor));
  return spans;
}

InlineSpan _rubySpan(String base, String reading, TextStyle baseStyle) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Semantics(
      label: '$base（$reading）',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            reading,
            style: baseStyle.copyWith(
              fontSize: AgentTokens.rubyReadingSize,
              color: AgentTokens.rubyReadingColor,
              height: 1,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
          Text(base, style: baseStyle.copyWith(height: 1.1)),
        ],
      ),
    ),
  );
}
