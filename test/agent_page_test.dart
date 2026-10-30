import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home opens the Agent page and shows the provider empty state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flutter.app_onboarding_completed': true,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => const []),
        ],
        child: RikaiApp(key: UniqueKey()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('词典助手'));
    await tester.tap(find.text('词典助手'));
    await tester.pumpAndSettle();

    expect(find.text('词典助手'), findsWidgets);
    expect(find.textContaining('本会话设置'), findsOneWidget);
    expect(find.text('去配置模型'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.tap(find.textContaining('本会话设置'));
    await tester.pumpAndSettle();
    expect(find.text('尚未配置模型'), findsOneWidget);
    expect(find.text('本次词典'), findsOneWidget);
  });
}
