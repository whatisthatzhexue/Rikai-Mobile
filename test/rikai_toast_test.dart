import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/core/ui/rikai_toast.dart';

void main() {
  testWidgets('a toast does not block controls underneath it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Stack(
              children: [
                Center(
                  child: FilledButton(
                    onPressed: () => RikaiToast.show(context, '已保存'),
                    child: const Text('显示'),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    child: FilledButton(
                      onPressed: () => taps++,
                      child: const Text('下方按钮'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示'));
    await tester.pump();
    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.text('下方按钮'));
    await tester.pump();
    expect(taps, 1);

    // Let the toast timer expire so the test binding has no pending timers.
    await tester.pump(const Duration(seconds: 3));
  });
}
