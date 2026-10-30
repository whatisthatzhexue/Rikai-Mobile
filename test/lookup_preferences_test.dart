import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rikai_mobile/core/models/dict_info.dart';
import 'package:rikai_mobile/core/models/dictionary_selection.dart';
import 'package:rikai_mobile/state/lookup_preferences.dart';
import 'package:rikai_mobile/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dictionaries = [
  DictionaryInfo(id: 'a', title: 'A', mdxPath: '/a.mdx'),
  DictionaryInfo(id: 'b', title: 'B', mdxPath: '/b.mdx'),
];

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('an unset selection means every enabled dictionary', () async {
    final container = await _container();

    expect(container.read(lookupPreferencesProvider).selectedIds, isNull);
    expect(
      container
          .read(lookupPreferencesProvider)
          .selectedDictionaries(_dictionaries)
          .map((dictionary) => dictionary.id),
      ['a', 'b'],
    );
  });

  test('toggling and select-all persist for later pages', () async {
    final container = await _container();
    final notifier = container.read(lookupPreferencesProvider.notifier);

    // An unset selection starts with every dictionary selected, so the first
    // tap removes A; the second tap adds it back.
    notifier.toggle('a', _dictionaries);
    expect(container.read(lookupPreferencesProvider).selectedIds, {'b'});
    notifier.toggle('a', _dictionaries);
    expect(container.read(lookupPreferencesProvider).selectedIds, {'a', 'b'});

    notifier.selectAll();
    expect(container.read(lookupPreferencesProvider).selectedIds, isNull);

    notifier.setMode(DictionarySelectionMode.single);
    expect(
      container.read(lookupPreferencesProvider).mode,
      DictionarySelectionMode.single,
    );
  });
}
