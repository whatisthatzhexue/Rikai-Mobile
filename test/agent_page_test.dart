import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/app.dart';
import 'package:rikai_mobile/core/models/agent/agent_input.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/agent/agent_provider.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_page.dart';
import 'package:rikai_mobile/services/agent/agent_image_picker.dart';
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
    AgentRunResult? retainResult,
  }) async {
    sentImages = images;
    state = AgentRunSnapshot(
      status: AgentRunStatus.reasoning,
      sentText: userText,
      sentImage: images.isNotEmpty,
      startedAt: DateTime.now(),
    );
  }
}

class _ModeSnapshotRunController extends AgentRunController {
  @override
  AgentRunSnapshot build() => const AgentRunSnapshot(
    runId: 'run-mode',
    status: AgentRunStatus.done,
    sentText: '何卒',
    mode: AgentMode.loose,
  );
}

class _BeautifyRunController extends AgentRunController {
  @override
  AgentRunSnapshot build() => const AgentRunSnapshot(
    runId: 'run-beautify',
    status: AgentRunStatus.done,
    sentText: '何卒',
    richTextFormatting: true,
  );

  void finishFormatting() {
    state = state.copyWith(richTextFormatting: false);
  }
}

class _FakeImagePicker implements AgentImagePicker {
  @override
  Future<List<String>> pickFromCamera() async => <String>['/tmp/camera.jpg'];

  @override
  Future<List<String>> pickFromGallery() async => <String>[
    '/tmp/a.jpg',
    '/tmp/b.jpg',
  ];
}

void main() {
  testWidgets(
    'beautifying banner is dismissible and follows the formatting state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = _BeautifyRunController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            agentProvidersProvider.overrideWith((ref) async => [_provider]),
            enabledDictionariesProvider.overrideWithValue([_dictionary]),
            agentRunControllerProvider.overrideWith(() => controller),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const AgentPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('界面美化正在进行中…'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('界面美化正在进行中…'), findsNothing);
    },
  );

  testWidgets('beautifying banner closes automatically when formatting ends', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = _BeautifyRunController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => [_provider]),
          enabledDictionariesProvider.overrideWithValue([_dictionary]),
          agentRunControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const AgentPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('界面美化正在进行中…'), findsOneWidget);

    controller.finishFormatting();
    await tester.pumpAndSettle();
    expect(find.text('界面美化正在进行中…'), findsNothing);
  });

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

  testWidgets(
    'gallery picker appends multiple images and sends them together',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'flutter.app_onboarding_completed': true,
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            agentProvidersProvider.overrideWith((ref) async => [_provider]),
            enabledDictionariesProvider.overrideWithValue([_dictionary]),
            agentRunControllerProvider.overrideWith(
              _RecordingRunController.new,
            ),
            agentImagePickerProvider.overrideWithValue(_FakeImagePicker()),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const AgentPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从相册选择'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('agent-composer-image-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-composer-image-1')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), '请解释');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();

      // The recording controller is app-scoped; read it from the page's
      // ProviderScope container.
      final element = tester.element(find.byType(AgentPage));
      final ref = ProviderScope.containerOf(element);
      final recording =
          ref.read(agentRunControllerProvider.notifier)
              as _RecordingRunController;
      expect(recording.sentImages, hasLength(2));
      expect(recording.sentImages.first.localPath, '/tmp/a.jpg');
    },
  );

  testWidgets('reopening the page keeps the current session mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProvidersProvider.overrideWith((ref) async => [_provider]),
          enabledDictionariesProvider.overrideWithValue([_dictionary]),
          agentRunControllerProvider.overrideWith(
            _ModeSnapshotRunController.new,
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const AgentPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('宽松'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('严格'), findsOneWidget);
  });

  testWidgets('selected provider survives a page rebuild', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const second = AgentProviderConfig(
      id: 'p2',
      kind: AgentProviderKind.openAiCompatible,
      displayName: '第二模型',
      baseUrl: 'https://example.com',
      smallModel: 'small',
      complexModel: 'complex',
    );
    Widget build() => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        agentProvidersProvider.overrideWith((ref) async => [_provider, second]),
        enabledDictionariesProvider.overrideWithValue([_dictionary]),
        agentRunControllerProvider.overrideWith(_RecordingRunController.new),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const AgentPage()),
    );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('本会话设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二模型').last);
    await tester.pumpAndSettle();

    // Recreate the page and the provider tree; the selection is persisted in
    // SharedPreferences rather than kept in the page's local state.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.textContaining('第二模型'), findsWidgets);
  });
}
