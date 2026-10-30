import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/lookup/dictionary_filter_bar.dart';

void main() {
  testWidgets('unselected mode labels are white on the blue AppBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('查词'),
            actions: [
              DictionarySelectionModeToggle(
                mode: DictionarySelectionMode.multi,
                onDark: true,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(of: find.text('单选'), matching: find.byType(RichText)),
    );
    expect(richText.text.style?.color, AppColors.onHeader);
  });
}
