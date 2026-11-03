import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_profiles_page.dart';
import 'package:rikai_mobile/services/agent/agent_run.dart';
import 'package:rikai_mobile/state/agent_profile_manager.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/agent_run_controller.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dictionary = DictionaryInfo(
  id: 'dict-a',
  title: '测试词典A',
  mdxPath: '/tmp/missing-dictionary-a.mdx',
);

const _dictionaryB = DictionaryInfo(
  id: 'dict-b',
  title: '测试词典B',
  mdxPath: '/tmp/missing-dictionary-b.mdx',
);

const _stored = StoredDictionaryProfile(
  dictionaryId: 'dict-a',
  title: '测试词典A',
  fingerprint: 'outdated',
  markdown: '这是一份词典档案。',
  status: DictionaryProfileStatus.confirmed,
  profile: DictionaryProfile(
    dictionaryId: 'dict-a',
    title: '测试词典A',
    kind: '国語辞典',
    entryStructure: DictionaryEntryStructure(),
    searchBehavior: DictionarySearchBehavior(),
  ),
  modelId: 'small',
  promptVersion: 1,
  schemaVersion: 1,
);

const _storedB = StoredDictionaryProfile(
  dictionaryId: 'dict-b',
  title: '测试词典B',
  fingerprint: 'outdated',
  markdown: '这是第二份词典档案。',
  status: DictionaryProfileStatus.confirmed,
  profile: DictionaryProfile(
    dictionaryId: 'dict-b',
    title: '测试词典B',
    kind: '国語辞典',
    entryStructure: DictionaryEntryStructure(),
    searchBehavior: DictionarySearchBehavior(),
  ),
  modelId: 'small',
  promptVersion: 1,
  schemaVersion: 1,
);

class _FixedRegenerationController extends AgentProfileRegenerationController {
  _FixedRegenerationController(this._initial);

  final AgentProfileRegenerationState _initial;

  @override
  AgentProfileRegenerationState build() => _initial;
}

class _FixedRunController extends AgentRunController {
  _FixedRunController(this._snapshot);

  final AgentRunSnapshot _snapshot;

  @override
  AgentRunSnapshot build() => _snapshot;
}

Future<void> _pumpProfilesPage(
  WidgetTester tester, {
  required List<DictionaryInfo> active,
  AgentRunSnapshot run = AgentRunSnapshot.idle,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        agentProfilesProvider.overrideWith(
          (ref) async => <StoredDictionaryProfile>[_stored, _storedB],
        ),
        enabledDictionariesProvider.overrideWithValue(<DictionaryInfo>[
          _dictionary,
          _dictionaryB,
        ]),
        agentProfileRegenerationProvider.overrideWith(
          () => _FixedRegenerationController(
            AgentProfileRegenerationState(activeDictionaries: active),
          ),
        ),
        agentRunControllerProvider.overrideWith(
          () => _FixedRunController(run),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AgentProfilesPage(),
      ),
    ),
  );
  // The active-regeneration progress bar animates forever, so settling is not
  // possible. Pump enough frames for the async profile list to arrive.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('profile manager lists stored profiles and enters multi-select', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProfilesProvider.overrideWith(
            (ref) async => <StoredDictionaryProfile>[_stored],
          ),
          enabledDictionariesProvider.overrideWithValue(<DictionaryInfo>[
            _dictionary,
          ]),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentProfilesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('词典档案'), findsOneWidget);
    expect(find.text('测试词典A'), findsOneWidget);
    expect(find.text('已信任'), findsOneWidget);

    final modeTooltip = tester.element(find.byTooltip('多选'));

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byTooltip('删除选中'), findsOneWidget);
    expect(find.byTooltip('重新生成选中'), findsOneWidget);

    // The selection action must not reuse the tapped mode toggle's element,
    // otherwise its ink/focus highlight is carried over to "select all".
    expect(tester.element(find.byTooltip('全选')), isNot(same(modeTooltip)));
    expect(
      find.byKey(const ValueKey('agent-profile-action-select-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-profile-action-selection-mode')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('全选'), findsNothing);
    expect(find.byTooltip('多选'), findsOneWidget);
  });

  testWidgets(
    'editing and deleting stay available during another regeneration',
    (tester) async {
      await _pumpProfilesPage(tester, active: <DictionaryInfo>[_dictionary]);

      expect(find.text('正在重新生成档案：测试词典A'), findsOneWidget);

      final refreshButtons = tester
          .widgetList<IconButton>(
            find.widgetWithIcon(IconButton, Icons.refresh),
          )
          .toList();
      expect(refreshButtons, hasLength(2));
      expect(refreshButtons[0].onPressed, isNull);
      expect(refreshButtons[1].onPressed, isNotNull);

      expect(
        tester
            .widgetList<IconButton>(
              find.widgetWithIcon(IconButton, Icons.edit_outlined),
            )
            .every((button) => button.onPressed != null),
        isTrue,
      );
      expect(
        tester
            .widgetList<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .every((button) => button.onPressed != null),
        isTrue,
      );
    },
  );

  testWidgets(
    'multi-select regeneration skips only dictionaries already generating',
    (tester) async {
      await _pumpProfilesPage(tester, active: <DictionaryInfo>[_dictionary]);

      await tester.tap(find.byTooltip('多选'));
      await tester.pump();
      await tester.tap(find.byTooltip('全选'));
      await tester.pump();

      final regenerateSelected = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(regenerateSelected.onPressed, isNotNull);
      final deleteSelected = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(deleteSelected.onPressed, isNotNull);
    },
  );

  testWidgets(
    'edit/regenerate stay available while profiles are in use; delete locks',
    (tester) async {
      await _pumpProfilesPage(
        tester,
        active: const <DictionaryInfo>[],
        run: const AgentRunSnapshot(status: AgentRunStatus.familiarizing),
      );

      expect(
        tester
            .widgetList<IconButton>(
              find.widgetWithIcon(IconButton, Icons.edit_outlined),
            )
            .every((button) => button.onPressed != null),
        isTrue,
      );
      expect(
        tester
            .widgetList<IconButton>(
              find.widgetWithIcon(IconButton, Icons.refresh),
            )
            .every((button) => button.onPressed != null),
        isTrue,
      );
      expect(
        tester
            .widgetList<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .every((button) => button.onPressed == null),
        isTrue,
      );

      await tester.tap(find.byTooltip('多选'));
      await tester.pump();
      await tester.tap(find.byTooltip('全选'));
      await tester.pump();
      final deleteSelected = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(deleteSelected.onPressed, isNull);
    },
  );

  testWidgets('delete unlocks after the main agent run completes', (
    tester,
  ) async {
    await _pumpProfilesPage(
      tester,
      active: const <DictionaryInfo>[],
      run: const AgentRunSnapshot(status: AgentRunStatus.done),
    );

    expect(
      tester
          .widgetList<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .every((button) => button.onPressed != null),
      isTrue,
    );
  });

  testWidgets(
    'multi-select regeneration is disabled when every selection is generating',
    (tester) async {
      await _pumpProfilesPage(
        tester,
        active: <DictionaryInfo>[_dictionary, _dictionaryB],
      );

      await tester.tap(find.byTooltip('多选'));
      await tester.pump();
      await tester.tap(find.byTooltip('全选'));
      await tester.pump();

      final regenerateSelected = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(regenerateSelected.onPressed, isNull);
      final deleteSelected = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(deleteSelected.onPressed, isNotNull);
    },
  );
}
