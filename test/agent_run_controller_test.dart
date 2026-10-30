import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_page.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/agent_run_controller.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _provider = AgentProviderConfig(
  id: 'p1',
  kind: AgentProviderKind.openAiCompatible,
  displayName: '测试模型',
  baseUrl: 'https://example.com',
  smallModel: 'small',
  complexModel: 'complex',
);

const _dictionary = DictionaryInfo(
  id: 'dict-1',
  title: '测试词典',
  mdxPath: '/tmp/dict.mdx',
);

class _RecordingRunController extends AgentRunController {
  bool startCalled = false;
  String sentText = '';
  List<AgentImageInput> sentImages = const <AgentImageInput>[];

  @override
  AgentRunSnapshot build() => AgentRunSnapshot.idle;

  @override
  Future<void> start({
    required String userText,
    required List<AgentImageInput> images,
    required List<DictionaryInfo> dictionaries,
    required AgentProviderConfig provider,
    required AgentMode mode,
    required String unidicPath,
    required AgentResponseLanguage responseLanguage,
    required AgentProfileLanguage profileLanguage,
  }) async {
    startCalled = true;
    sentText = userText;
    sentImages = images;
    state = AgentRunSnapshot(
      runId: 'run-test',
      sessionId: 'session-test',
      status: AgentRunStatus.reasoning,
      stageMessage: '生成结果',
      sentText: userText,
      sentImage: images.isNotEmpty,
      mode: mode,
      responseLanguage: AgentResponseLanguage.chinese,
      providerLabel: provider.displayName,
      progressStep: 2,
      evidenceCount: 5,
      citationCount: 2,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

void main() {
  testWidgets('sending clears the composer and shows thinking time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = _RecordingRunController();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => [_provider]),
          enabledDictionariesProvider.overrideWithValue([_dictionary]),
          agentRunControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '何卒宜しくお願い致します。');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();

    expect(controller.startCalled, isTrue);
    expect(controller.sentText, '何卒宜しくお願い致します。');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    expect(find.text('何卒宜しくお願い致します。'), findsOneWidget);
    expect(find.textContaining('已思考'), findsOneWidget);
    expect(find.textContaining('已接收'), findsNothing);
    expect(find.text('查词'), findsOneWidget);
    expect(find.textContaining('已检索 5 条'), findsOneWidget);
  });
}
