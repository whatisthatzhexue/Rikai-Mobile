import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexicandy/core/models/agent/agent_profile.dart';
import 'package:lexicandy/core/models/dict_info.dart';
import 'package:lexicandy/core/theme/app_tokens.dart';
import 'package:lexicandy/features/agent/agent_profiles_page.dart';
import 'package:lexicandy/services/agent/agent_run.dart';
import 'package:lexicandy/services/agent/familiarization/profile_repository.dart';
import 'package:lexicandy/state/agent_profile_manager.dart';
import 'package:lexicandy/state/agent_providers.dart';
import 'package:lexicandy/state/agent_run_controller.dart';
import 'package:lexicandy/state/providers.dart';
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
    languagePairs: <DictionaryLanguagePair>[
      DictionaryLanguagePair(source: 'ja', target: 'ja', confidence: 0.8),
    ],
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

const _storedTruncated = StoredDictionaryProfile(
  dictionaryId: 'dict-a',
  title: '测试词典A',
  fingerprint: 'outdated',
  markdown: '这是一份样本不完整的词典档案。',
  status: DictionaryProfileStatus.confirmed,
  profile: DictionaryProfile(
    dictionaryId: 'dict-a',
    title: '测试词典A',
    kind: '国語辞典',
    coverage: DictionaryCoverage(
      sampleEntries: 20,
      sampleTruncated: true,
      unsampledProbeCount: 3,
    ),
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

class _MutableProfileRepository implements DictionaryProfileRepository {
  _MutableProfileRepository(Iterable<StoredDictionaryProfile> profiles) {
    for (final profile in profiles) {
      _values[profile.dictionaryId] = profile;
    }
  }

  final Map<String, StoredDictionaryProfile> _values =
      <String, StoredDictionaryProfile>{};

  Future<List<StoredDictionaryProfile>> list() async =>
      _values.values.toList(growable: false);

  @override
  Future<StoredDictionaryProfile?> load(String dictionaryId) async =>
      _values[dictionaryId];

  @override
  Future<void> save(StoredDictionaryProfile profile) async {
    _values[profile.dictionaryId] = profile;
  }

  @override
  Future<void> delete(String dictionaryId) async {
    _values.remove(dictionaryId);
  }
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
        agentRunControllerProvider.overrideWith(() => _FixedRunController(run)),
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
    expect(find.textContaining('ja→ja'), findsOneWidget);

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
      // A disabled red delete button looked enabled. The locked state is now
      // a grey lock icon with an explanatory tooltip.
      expect(
        tester
            .widgetList<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_outline),
            )
            .every((button) => button.onPressed == null),
        isTrue,
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.lock_outline),
        findsNWidgets(2),
      );

      await tester.tap(find.byTooltip('多选'));
      await tester.pump();
      await tester.tap(find.byTooltip('全选'));
      await tester.pump();
      final deleteSelected = tester.widget<IconButton>(
        find.byKey(
          const ValueKey<String>('agent-profile-action-delete-selected'),
        ),
      );
      expect(deleteSelected.onPressed, isNull);
      expect(deleteSelected.icon, isA<Icon>());
      expect((deleteSelected.icon as Icon).icon, Icons.lock_outline);
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

  testWidgets('profile card warns when the dictionary sample was truncated', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProfilesProvider.overrideWith(
            (ref) async => <StoredDictionaryProfile>[_storedTruncated],
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

    expect(find.textContaining('3 项检查未覆盖'), findsOneWidget);
  });

  testWidgets('editing a stale profile clears its stale label immediately', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final repository = _MutableProfileRepository(<StoredDictionaryProfile>[
      _stored,
      _storedB,
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          agentProfilesProvider.overrideWith((ref) async => repository.list()),
          agentProfileRepositoryProvider.overrideWithValue(repository),
          dictionaryProfileFingerprintProvider.overrideWithValue(
            (
              dictionary, {
              required promptVersion,
              required schemaVersion,
              required language,
            }) async => 'current-fingerprint',
          ),
          enabledDictionariesProvider.overrideWithValue(<DictionaryInfo>[
            _dictionary,
            _dictionaryB,
          ]),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentProfilesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('测试词典A'), findsOneWidget);
    expect(find.text('已失效'), findsNWidgets(2));

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.edit_outlined).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await repository.load('dict-a');
    expect(saved, isNotNull);
    expect(saved!.fingerprint, isNot('outdated'));
    // A is now valid; B was not edited and remains stale.
    expect(find.text('已失效'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'stale label disappears before the refreshed profile list arrives',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final repository = _MutableProfileRepository(<StoredDictionaryProfile>[
        _stored,
        _storedB,
      ]);
      final refresh = Completer<void>();
      var loads = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            agentProfilesProvider.overrideWith((ref) async {
              loads++;
              if (loads == 1) return repository.list();
              // Keep the previous list visible while the real SQLite reload
              // would be in flight.
              await refresh.future;
              return repository.list();
            }),
            agentProfileRepositoryProvider.overrideWithValue(repository),
            dictionaryProfileFingerprintProvider.overrideWithValue(
              (
                dictionary, {
                required promptVersion,
                required schemaVersion,
                required language,
              }) async => 'current-fingerprint',
            ),
            enabledDictionariesProvider.overrideWithValue(<DictionaryInfo>[
              _dictionary,
              _dictionaryB,
            ]),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const AgentProfilesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已失效'), findsNWidgets(2));

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.edit_outlined).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // The new revision is persisted, but the provider refresh is still
      // deliberately blocked. A's stale badge must be gone immediately; B was
      // not edited and remains stale.
      expect(loads, greaterThanOrEqualTo(2));
      expect(find.text('已失效'), findsOneWidget);

      refresh.complete();
      await tester.pumpAndSettle();
      expect(find.text('已失效'), findsOneWidget);
      // Let the save toast timer expire before the widget tree is disposed.
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
