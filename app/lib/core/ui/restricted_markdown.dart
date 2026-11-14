import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A deliberately small Markdown renderer for user-editable dictionary
/// profiles.
///
/// Supported: paragraphs, headings, bullet lists, bold, italic and inline
/// code. Everything else is shown literally. There are no links, images,
/// HTML, iframes, style attributes or autolinks, so untrusted profile text
/// cannot trigger network/file access or script execution.
class RestrictedMarkdown extends StatelessWidget {
  const RestrictedMarkdown({
    super.key,
    required this.text,
    this.maxChars = 20000,
  });

  final String text;
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = maxChars > 0 && text.length > maxChars
        ? '${text.substring(0, maxChars)}…'
        : text;
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: AgentTokens.body,
      height: 1.5,
      color: AppColors.textPrimary,
    );
    final blocks = _parseBlocks(source, theme, baseStyle);
    if (blocks.isEmpty) {
      return Text('', style: baseStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  List<Widget> _parseBlocks(
    String source,
    ThemeData theme,
    TextStyle? baseStyle,
  ) {
    final blocks = <Widget>[];
    final paragraph = StringBuffer();

    void flushParagraph() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Text.rich(
            TextSpan(style: baseStyle, children: _parseInline(text, baseStyle)),
          ),
        ),
      );
    }

    for (final rawLine in source.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        flushParagraph();
        final level = heading.group(1)!.length;
        final headingText = heading.group(2)!.trim();
        final style =
            switch (level) {
              1 => theme.textTheme.titleLarge,
              2 => theme.textTheme.titleMedium,
              _ => theme.textTheme.titleSmall,
            }?.copyWith(
              fontSize: level == 1
                  ? AppTypography.sectionHeading
                  : AgentTokens.evidenceTitle,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            );
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.xxs,
            ),
            child: Text.rich(
              TextSpan(
                style: style,
                children: _parseInline(headingText, style),
              ),
            ),
          ),
        );
        continue;
      }
      final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: baseStyle),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: baseStyle,
                      children: _parseInline(bullet.group(1)!, baseStyle),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      if (paragraph.isNotEmpty) paragraph.write('\n');
      paragraph.write(line);
    }
    flushParagraph();
    return blocks;
  }
}

/// Parses only bold, italic and inline-code markers. Unmatched markers remain
/// literal, so malformed or unknown syntax cannot disappear or become a link.
List<InlineSpan> _parseInline(String text, TextStyle? style) {
  final spans = <InlineSpan>[];
  var index = 0;
  while (index < text.length) {
    final bold = text.indexOf('**', index);
    final italic = text.indexOf('*', index);
    final code = text.indexOf('`', index);
    final next = _firstNonNegative(<int>[bold, italic, code]);
    if (next < 0) {
      spans.add(TextSpan(text: text.substring(index)));
      break;
    }
    if (next > index) spans.add(TextSpan(text: text.substring(index, next)));
    if (next == bold) {
      final close = text.indexOf('**', next + 2);
      if (close > next + 2) {
        spans.add(
          TextSpan(
            text: text.substring(next + 2, close),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
        index = close + 2;
        continue;
      }
    } else if (next == code) {
      final close = text.indexOf('`', next + 1);
      if (close > next + 1) {
        spans.add(
          TextSpan(
            text: text.substring(next + 1, close),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );
        index = close + 1;
        continue;
      }
    } else {
      final close = text.indexOf('*', next + 1);
      if (close > next + 1) {
        spans.add(
          TextSpan(
            text: text.substring(next + 1, close),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
        index = close + 1;
        continue;
      }
    }
    spans.add(TextSpan(text: text[next]));
    index = next + 1;
  }
  return spans;
}

int _firstNonNegative(List<int> values) {
  var result = -1;
  for (final value in values) {
    if (value < 0) continue;
    if (result < 0 || value < result) result = value;
  }
  return result;
}
