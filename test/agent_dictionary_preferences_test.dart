import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/dictionary_selection.dart';
import 'package:rikai_mobile/state/agent_dictionary_preferences.dart';
import 'package:rikai_mobile/state/lookup_preferences.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dictionaries = <DictionaryInfo>[
  DictionaryInfo(id: 'a', title: 'A', mdxPath: '/a.mdx'),
  DictionaryInfo(id: 'b', title: 'B', mdxPath: '/b.mdx'),
];

void main() {
  test(
    'Agent selection is independent from lookup selection and persists',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();

      ProviderContainer makeContainer() => ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );

      var container = makeContainer();
      final lookup = container.read(lookupPreferencesProvider.notifier);
      lookup.toggle('a', _dictionaries);
      expect(
        container
            .read(lookupPreferencesProvider)
            .selectedDictionaries(_dictionaries)
            .map((dictionary) => dictionary.id),
        <String>['b'],
      );

      // The Agent preference starts at "all enabled" rather than inheriting the
      // lookup preference.
      expect(
        container
            .read(agentDictionaryPreferencesProvider)
            .selectedDictionaries(_dictionaries)
            .map((dictionary) => dictionary.id),
        <String>['a', 'b'],
      );

      final agent = container.read(agentDictionaryPreferencesProvider.notifier);
      agent.setMode(DictionarySelectionMode.single);
      agent.toggle('a', _dictionaries);
      expect(
        container
            .read(agentDictionaryPreferencesProvider)
            .selectedDictionaries(_dictionaries)
            .map((dictionary) => dictionary.id),
        <String>['a'],
      );
      expect(
        container
            .read(lookupPreferencesProvider)
            .selectedDictionaries(_dictionaries)
            .map((dictionary) => dictionary.id),
        <String>['b'],
      );
      container.dispose();

      // New container = app restart. Both selections survive independently.
      container = makeContainer();
      addTearDown(container.dispose);
      expect(
        container
            .read(agentDictionaryPreferencesProvider)
            .selectedDictionaries(_dictionaries)
            .map((dictionary) => dictionary.id),
        <String>['a'],
      );
      expect(
        container.read(agentDictionaryPreferencesProvider).mode,
        DictionarySelectionMode.single,
      );
      expect(
        container
            .read(lookupPreferencesProvider)
            .selectedDictionaries(_dictionaries)
            .map((dictionary) => dictionary.id),
        <String>['b'],
      );
    },
  );
}
