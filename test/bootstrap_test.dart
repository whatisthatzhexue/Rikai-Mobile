import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/bootstrap.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('splash shows the icon and the current loading phase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const SplashPage(status: '正在加载分词功能…'),
      ),
    );
    await tester.pump();

    expect(find.text('正在加载分词功能…'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('splash reports a startup error with retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SplashPage(status: '正在加载主界面…', error: 'boom', onRetry: () {}),
      ),
    );

    expect(find.text('启动失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('bootstrap transitions from splash to home', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const BootstrapApp());
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('使用前须知'), findsOneWidget);
  });
}
