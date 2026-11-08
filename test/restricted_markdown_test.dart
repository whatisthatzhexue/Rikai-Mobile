import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/core/ui/restricted_markdown.dart';

void main() {
  testWidgets('renders whitelisted Markdown and leaves unsafe syntax literal', (
    tester,
  ) async {
    const source =
        '# 标题\n\n'
        '**粗体** 和 *斜体*，还有 `code`。\n'
        '- 列表项\n'
        '<script>alert(1)</script>\n'
        '[链接](http://example.com)\n'
        '![图片](file:///tmp/a.png)';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: RestrictedMarkdown(text: source)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    expect(rich, contains('标题'));
    expect(rich, contains('粗体'));
    expect(rich, contains('斜体'));
    expect(rich, contains('列表项'));
    expect(rich, contains('<script>alert(1)</script>'));
    expect(rich, contains('[链接](http://example.com)'));
    expect(rich, contains('![图片](file:///tmp/a.png)'));
  });

  testWidgets('unknown Markdown is displayed as plain text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: RestrictedMarkdown(text: '> quote\n| table |\n```\ncode'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    expect(rich, contains('> quote'));
    expect(rich, contains('| table |'));
    expect(rich, contains('```'));
  });
}
