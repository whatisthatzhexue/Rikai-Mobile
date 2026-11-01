import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_profiles_page.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dictionary = DictionaryInfo(
  id: 'dict-a',
  title: '测试词典',
  mdxPath: '/tmp/missing-dictionary.mdx',
);

const _stored = StoredDictionaryProfile(
  dictionaryId: 'dict-a',
  title: '测试词典',
  fingerprint: 'outdated',
  markdown: '这是一份词典档案。',
  status: DictionaryProfileStatus.confirmed,
  profile: DictionaryProfile(
    dictionaryId: 'dict-a',
    title: '测试词典',
    kind: '国語辞典',
    entryStructure: DictionaryEntryStructure(),
    searchBehavior: DictionarySearchBehavior(),
  ),
  modelId: 'small',
  promptVersion: 1,
  schemaVersion: 1,
);

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
    expect(find.text('测试词典'), findsOneWidget);
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
}
