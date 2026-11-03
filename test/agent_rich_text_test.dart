import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
                  '[RUBY=なにとぞ]何卒[/RUBY] [BOLD]标题[/BOLD] '
                  '[UNDERLINE]重点[/UNDERLINE]',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );

      expect(find.text('なにとぞ'), findsOneWidget);
      expect(find.text('何卒'), findsOneWidget);

      final spans = buildAgentRichTextSpans(
        '[RUBY=なにとぞ]何卒[/RUBY] [BOLD]标题[/BOLD] '
        '[UNDERLINE]重点[/UNDERLINE]',
        const TextStyle(fontSize: 16),
      );
      expect(spans.whereType<WidgetSpan>(), hasLength(1));
      final bold = spans.whereType<TextSpan>().firstWhere(
        (span) => span.text == '标题',
      );
      expect(bold.style?.fontWeight, FontWeight.w600);
      final underline = spans.whereType<TextSpan>().firstWhere(
        (span) => span.text == '重点',
      );
      expect(underline.style?.decoration, TextDecoration.underline);
    },
  );

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
