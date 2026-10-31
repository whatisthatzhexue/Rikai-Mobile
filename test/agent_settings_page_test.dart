import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/settings/agent_settings_page.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('provider form uses Chinese labels and fills DeepSeek address', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('模型服务'), findsOneWidget);
    await tester.tap(find.text('添加模型服务'));
    await tester.pumpAndSettle();

    expect(find.text('服务商'), findsOneWidget);
    expect(find.text('接口地址'), findsOneWidget);
    expect(find.text('快速模型'), findsOneWidget);
    expect(find.text('高精度模型'), findsOneWidget);
    expect(find.text('快速模型用于词典档案和资料检查。'), findsOneWidget);
    expect(find.text('高精度模型用于最终解析。'), findsOneWidget);
    expect(find.textContaining('API 的访问地址'), findsNothing);
    expect(find.textContaining('留空时回退'), findsNothing);
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('Small model'), findsNothing);
    expect(find.text('Complex model'), findsNothing);

    final baseUrl = tester.widget<TextField>(
      find.byKey(const ValueKey('agent-provider-base-url')),
    );
    expect(baseUrl.controller?.text, 'https://api.deepseek.com/');

    await tester.enterText(
      find.byKey(const ValueKey('agent-provider-base-url')),
      'https://example.com/v1',
    );
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude（Anthropic）').last);
    await tester.pumpAndSettle();
    expect(baseUrl.controller?.text, 'https://example.com/v1');
  });

  testWidgets(
    'provider row shows address and model summaries on separate lines',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      const provider = AgentProviderConfig(
        id: 'p1',
        kind: AgentProviderKind.openAiCompatible,
        displayName: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/',
        smallModel: 'deepseek-chat',
        complexModel: 'deepseek-reasoner',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            agentProvidersProvider.overrideWith((ref) async => [provider]),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AgentSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('接口地址：https://api.deepseek.com/'), findsOneWidget);
      expect(find.text('复杂模型：deepseek-reasoner'), findsOneWidget);
      expect(find.text('简单模型：deepseek-chat'), findsOneWidget);
    },
  );
}
