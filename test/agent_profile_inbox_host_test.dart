import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/agent/agent_profile.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/theme/app_tokens.dart';
import 'package:rikai_mobile/features/agent/agent_profile_inbox_host.dart';
import 'package:rikai_mobile/services/agent/agent_ui_strings.dart';
import 'package:rikai_mobile/services/agent/familiarization/dictionary_familiarization_service.dart';
import 'package:rikai_mobile/services/agent/familiarization/profile_repository.dart';
import 'package:rikai_mobile/state/agent_profile_inbox.dart';
import 'package:rikai_mobile/state/agent_providers.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dictionary = DictionaryInfo(
  id: 'dict-a',
  title: '测试词典',
  mdxPath: '/a.mdx',
);

const _profile = DictionaryProfile(
  dictionaryId: 'dict-a',
  title: '测试词典',
  kind: '国語辞典',
  entryStructure: DictionaryEntryStructure(),
  searchBehavior: DictionarySearchBehavior(),
);

void main() {
  testWidgets(
    'never-ask saves the profile, enables auto-accept and shows a toast',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final repository = InMemoryDictionaryProfileRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            agentProfileRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AgentProfileInboxHost(
              strings: AgentUiStrings.of(AgentUiLanguage.chinese),
              child: const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AgentProfileInboxHost)),
      );
      container
          .read(agentProfileInboxProvider.notifier)
          .enqueue(<AgentProfileProposal>[
            AgentProfileProposal(
              id: 'p1',
              dictionary: _dictionary,
              fingerprint: 'fp',
              profile: _profile,
              markdown: 'draft profile',
              runId: 'run-1',
            ),
          ]);
      await tester.pumpAndSettle();

      expect(find.text('不再询问'), findsOneWidget);
      await tester.tap(find.text('不再询问'));
      await tester.pumpAndSettle();

      final saved = await repository.load('dict-a');
      expect(saved?.status, DictionaryProfileStatus.confirmed);
      expect(
        container.read(appSettingsProvider).agentProfilesAutoAccept,
        isTrue,
      );
      expect(container.read(agentProfileInboxProvider).pending, isEmpty);
      expect(find.textContaining('测试词典'), findsWidgets);
      expect(find.textContaining('词典档案已生成'), findsOneWidget);

      // Let the toast timer expire before the test ends.
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
