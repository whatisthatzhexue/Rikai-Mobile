import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/theme/app_tokens.dart';
import 'package:lexicandy/features/agent/agent_rich_text.dart';

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
      final ruby = spans.whereType<WidgetSpan>().firstWhere(
        (span) => span.child.runtimeType.toString() != '_UnderlineSpanWidget',
      );
      expect(ruby.alignment, PlaceholderAlignment.baseline);
      final bold = spans.whereType<TextSpan>().firstWhere(
        (span) => span.text == '标题',
      );
      expect(bold.style?.fontWeight, FontWeight.w600);
      final underline = spans.whereType<WidgetSpan>().firstWhere(
        (span) => span.child.runtimeType.toString() == '_UnderlineSpanWidget',
      );
      final underlineWidget = underline.child as dynamic;
      expect(underlineWidget.color, AgentTokens.richTextUnderlineColor);
      expect(underlineWidget.thickness, AgentTokens.richTextUnderlineThickness);
      final underlineText = tester.widget<Text>(find.text('重点'));
      // The underline is painted at a baseline-relative offset, not via
      // font-specific TextDecoration metrics (which differ for `；`).
      expect(underlineText.style?.decoration, TextDecoration.none);
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

  testWidgets('renders only one copy of a reading annotation', (tester) async {
    for (final text in <String>[
      '[RUBY=いま]今【いま】[/RUBY]：现在、此刻',
      '[RUBY=いま]今[/RUBY]【いま】：现在、此刻',
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
      expect(find.textContaining('【いま】'), findsNothing);
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
    // The custom underline painter is outside the RUBY widget, so the base
    // itself has no font decoration and the reading is never underlined.
    expect(base.style?.decoration, TextDecoration.none);
    expect(reading.style?.fontWeight, FontWeight.w600);
    expect(reading.style?.decoration, TextDecoration.none);
    final underlineFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_UnderlineSpanWidget',
    );
    expect(underlineFinder, findsOneWidget);
    final render = tester.renderObject(underlineFinder) as dynamic;
    expect(render.paintCount, greaterThan(0));
    expect(render.lastPaintedBaseline, isNotNull);
  });

  testWidgets('uses the same custom underline for kanji and punctuation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentRichText(
            text: '[UNDERLINE]漢字；[/UNDERLINE]',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    expect(find.text('漢字；'), findsOneWidget);
    final underlineFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_UnderlineSpanWidget',
    );
    expect(underlineFinder, findsOneWidget);
    expect(
      tester.widget<Text>(find.text('漢字；')).style?.decoration,
      TextDecoration.none,
    );
    final render = tester.renderObject(underlineFinder) as dynamic;
    expect(render.paintCount, greaterThan(0));
    expect(render.lastPaintedBaseline, isNotNull);
  });

  testWidgets('aligns an inline ruby base to the paragraph baseline', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 16, height: 1.5);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentRichText(text: 'あ[RUBY=なにとぞ]何卒[/RUBY]い', style: style),
        ),
      ),
    );

    final paragraphFinder = find.byType(RichText).first;
    final paragraph = tester.renderObject<RenderBox>(paragraphFinder);
    final paragraphBaseline =
        tester.getRect(paragraphFinder).top +
        (paragraph.getDryBaseline(
              paragraph.constraints,
              TextBaseline.alphabetic,
            ) ??
            0);
    final base = tester.renderObject<RenderBox>(find.text('何卒'));
    final baseBaseline =
        tester.getRect(find.text('何卒')).top +
        (base.getDryBaseline(base.constraints, TextBaseline.alphabetic) ?? 0);
    expect(baseBaseline, closeTo(paragraphBaseline, 0.01));
  });

  testWidgets('ruby reserves the wider reading so neighbours do not overlap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              AgentRichText(
                text: '[RUBY=かんじ]漢字[/RUBY]',
                style: TextStyle(fontSize: 16),
              ),
              Text('次', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );

    final rubyFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_RubySpanWidget',
    );
    final rubyRect = tester.getRect(rubyFinder);
    final readingRect = tester.getRect(find.text('かんじ'));
    final nextRect = tester.getRect(find.text('次'));
    expect(rubyRect.width, greaterThanOrEqualTo(readingRect.width));
    expect(readingRect.left, greaterThanOrEqualTo(rubyRect.left));
    expect(readingRect.right, lessThanOrEqualTo(rubyRect.right));
    // The next inline run starts after the ruby's reserved reading width.
    expect(nextRect.left, greaterThanOrEqualTo(rubyRect.right - 0.01));
  });

  testWidgets('long underlined text can wrap between characters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            child: AgentRichText(
              text: '[UNDERLINE]这是一个很长的下划线句子应该能够换行[/UNDERLINE]',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );

    final underlineWidgets = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_UnderlineSpanWidget',
    );
    expect(underlineWidgets, findsWidgets);
    final tops = <double>{
      for (var index = 0; index < underlineWidgets.evaluate().length; index++)
        tester.getTopLeft(underlineWidgets.at(index)).dy,
    };
    // Distinct tops prove the paragraph wrapped inside the underlined run
    // instead of overflowing as one atomic inline widget.
    expect(tops.length, greaterThan(1));
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
