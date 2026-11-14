import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/utils/rich_text_tags.dart';
import 'package:lexicandy/features/agent/agent_rich_text.dart';

void main() {
  test('trims known okurigana from the ruby range', () {
    final segments = minimalRubySegments('悩んでも', 'なやんでも');
    expect(segments, hasLength(2));
    expect(segments[0], (base: '悩', reading: 'なや'));
    expect(segments[1].reading, isNull);
    expect(segments[1].base, 'んでも');
  });

  test('handles prefix kana and internal kana anchors', () {
    expect(minimalRubySegments('お茶', 'おちゃ'), <MinimalRubySegment>[
      (base: 'お', reading: null),
      (base: '茶', reading: 'ちゃ'),
    ]);
    expect(minimalRubySegments('申し込み', 'もうしこみ'), <MinimalRubySegment>[
      (base: '申', reading: 'もう'),
      (base: 'し', reading: null),
      (base: '込', reading: 'こ'),
      (base: 'み', reading: null),
    ]);
  });

  test('keeps whole-word ruby when no kana alignment exists', () {
    expect(minimalRubySegments('何卒', 'なにとぞ'), <MinimalRubySegment>[
      (base: '何卒', reading: 'なにとぞ'),
    ]);
  });

  testWidgets('renders only the unknown kanji with a reading', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentRichText(
            text: '[RUBY=なやんでも]悩んでも[/RUBY]',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    expect(find.text('悩'), findsOneWidget);
    expect(find.text('なや'), findsOneWidget);
    expect(find.text('悩んでも'), findsNothing);

    final spans = buildAgentRichTextSpans(
      '[RUBY=なやんでも]悩んでも[/RUBY]',
      const TextStyle(fontSize: 16),
    );
    expect(spans.whereType<WidgetSpan>(), hasLength(1));
    final plain = spans
        .whereType<TextSpan>()
        .map((span) => span.text ?? '')
        .join();
    expect(plain, 'んでも');
  });

  testWidgets('renders internal kana anchors as plain text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentRichText(
            text: '[RUBY=もうしこみ]申し込み[/RUBY]',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );

    expect(find.text('申'), findsOneWidget);
    expect(find.text('もう'), findsOneWidget);
    expect(find.text('込'), findsOneWidget);
    expect(find.text('こ'), findsOneWidget);
    final spans = buildAgentRichTextSpans(
      '[RUBY=もうしこみ]申し込み[/RUBY]',
      const TextStyle(fontSize: 16),
    );
    expect(spans.whereType<WidgetSpan>(), hasLength(2));
    final plain = spans
        .whereType<TextSpan>()
        .map((span) => span.text ?? '')
        .join();
    expect(plain, 'しみ');
  });
}
