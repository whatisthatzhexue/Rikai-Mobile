import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_rich_text.dart';

void main() {
  testWidgets(
    'renders ruby, bold and underline without changing the base text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentRichText(
              text:
                  '[RUBY=（なにとぞ）、]何卒[/RUBY] [BOLD]标题[/BOLD] '
                  '[UNDERLINE]重点[/UNDERLINE]',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );

      expect(find.text('なにとぞ'), findsOneWidget);
      expect(find.text('何卒'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('なにとぞ')).style?.color,
        AgentTokens.rubyReadingColor,
      );

      final spans = buildAgentRichTextSpans(
        '[RUBY=（なにとぞ）、]何卒[/RUBY] [BOLD]标题[/BOLD] '
        '[UNDERLINE]重点[/UNDERLINE]',
        const TextStyle(fontSize: 16),
      );
      final ruby = spans.whereType<WidgetSpan>().single;
      expect(ruby.alignment, PlaceholderAlignment.baseline);
      final bold = spans.whereType<TextSpan>().firstWhere(
        (span) => span.text == '标题',
      );
      expect(bold.style?.fontWeight, FontWeight.w600);
      final underline = spans.whereType<TextSpan>().firstWhere(
        (span) => span.text == '重点',
      );
      expect(underline.style?.decoration, TextDecoration.underline);
      expect(
        underline.style?.decorationColor,
        AgentTokens.richTextUnderlineColor,
      );
      expect(
        underline.style?.decorationThickness,
        AgentTokens.richTextUnderlineThickness,
      );
    },
  );

  testWidgets('aligns the base baseline to the surrounding line', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentRichText(
            text: '[RUBY=なにとぞ]何卒[/RUBY]',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    final rubyFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_RubySpanWidget',
    );
    final rubyBox = tester.renderObject<RenderBox>(rubyFinder);
    final baseBox = tester.renderObject<RenderBox>(find.text('何卒'));
    final readingBox = tester.renderObject<RenderBox>(find.text('なにとぞ'));
    final baseBaseline = baseBox.getDryBaseline(
      baseBox.constraints,
      TextBaseline.alphabetic,
    );
    final rubyBaseline = rubyBox.getDryBaseline(
      rubyBox.constraints,
      TextBaseline.alphabetic,
    );

    expect(baseBaseline, isNotNull);
    expect(rubyBaseline, isNotNull);
    expect(
      rubyBaseline!,
      closeTo(readingBox.size.height + baseBaseline!, 0.01),
    );
    final rubyRect = tester.getRect(rubyFinder);
    final baseRect = tester.getRect(find.text('何卒'));
    final readingRect = tester.getRect(find.text('なにとぞ'));
    expect(baseRect.bottom, closeTo(rubyRect.bottom, 0.01));
    expect(readingRect.top, closeTo(rubyRect.top, 0.01));
  });

  testWidgets('aligns the ruby base with a neighboring text baseline', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 16);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text('あ', style: style),
              AgentRichText(text: '[RUBY=なにとぞ]何卒[/RUBY]', style: style),
            ],
          ),
        ),
      ),
    );

    final reference = tester.renderObject<RenderBox>(find.text('あ'));
    final base = tester.renderObject<RenderBox>(find.text('何卒'));
    final referenceBaseline =
        tester.getRect(find.text('あ')).top +
        (reference.getDryBaseline(
              reference.constraints,
              TextBaseline.alphabetic,
            ) ??
            0);
    final baseBaseline =
        tester.getRect(find.text('何卒')).top +
        (base.getDryBaseline(base.constraints, TextBaseline.alphabetic) ?? 0);
    expect(baseBaseline, closeTo(referenceBaseline, 0.01));
  });

  testWidgets('renders only one copy of a parenthetical reading', (
    tester,
  ) async {
    for (final text in <String>[
      '[RUBY=いま]今（いま）[/RUBY]：现在、此刻',
      '[RUBY=いま]今[/RUBY]（いま）：现在、此刻',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentRichText(
              text: text,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );

      expect(find.text('今'), findsOneWidget);
      expect(find.text('いま'), findsOneWidget);
      expect(find.textContaining('（いま）'), findsNothing);
    }
  });

  testWidgets('bold applies to ruby reading but underline does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentRichText(
            text: '[BOLD][UNDERLINE][RUBY=かんじ]漢字[/RUBY][/UNDERLINE][/BOLD]',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    final base = tester.widget<Text>(find.text('漢字'));
    final reading = tester.widget<Text>(find.text('かんじ'));
    expect(base.style?.fontWeight, FontWeight.w600);
    expect(base.style?.decoration, TextDecoration.underline);
    expect(reading.style?.fontWeight, FontWeight.w600);
    expect(reading.style?.decoration, TextDecoration.none);
  });

  testWidgets('renders plain text unchanged', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentRichText(text: '普通文本', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
    expect(find.text('普通文本', findRichText: true), findsOneWidget);
  });
}
