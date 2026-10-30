import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/dict_info.dart';
import '../core/models/dictionary_selection.dart';
import 'providers.dart';

/// Global dictionary selection shared by the search page and the reader sheet.
///
/// [selectedIds] is null when every enabled dictionary is selected. That makes
/// newly added dictionaries participate automatically until the user narrows
/// the selection.
class LookupPreferences {
  const LookupPreferences({
    this.selectedIds,
    this.mode = DictionarySelectionMode.multi,
  });

  final Set<String>? selectedIds;
  final DictionarySelectionMode mode;

  bool isSelected(String id) {
    final ids = selectedIds;
    return ids == null || ids.contains(id);
  }

  List<DictionaryInfo> selectedDictionaries(List<DictionaryInfo> enabled) {
    final ids = selectedIds;
    if (ids == null) return enabled;
    return enabled
        .where((dictionary) => ids.contains(dictionary.id))
        .toList(growable: false);
  }

  String get signature {
    final ids = selectedIds;
    if (ids == null) return '*';
    final sorted = ids.toList()..sort();
    return sorted.join(',');
  }
}

final lookupPreferencesProvider =
    NotifierProvider<LookupPreferencesNotifier, LookupPreferences>(
      LookupPreferencesNotifier.new,
    );

class LookupPreferencesNotifier extends Notifier<LookupPreferences> {
  static const _selectedIdsKey = 'lookup_selected_dictionary_ids';
  static const _modeKey = 'lookup_selection_mode';

  late SharedPreferences _preferences;

  @override
  LookupPreferences build() {
    _preferences = ref.watch(sharedPreferencesProvider);
    final stored = _preferences.getStringList(_selectedIdsKey);
    final mode = _preferences.getString(_modeKey) == 'single'
        ? DictionarySelectionMode.single
        : DictionarySelectionMode.multi;
    return LookupPreferences(selectedIds: stored?.toSet(), mode: mode);
  }

  void toggle(String id, List<DictionaryInfo> enabled) {
    final current = state.selectedIds ?? _idsOf(enabled);
    final Set<String> next;
    if (state.mode == DictionarySelectionMode.single) {
      next = current.length == 1 && current.contains(id)
          ? <String>{}
          : <String>{id};
    } else {
      next = {...current};
      if (!next.add(id)) next.remove(id);
    }
    _update(LookupPreferences(selectedIds: next, mode: state.mode));
  }

  void selectAll() {
    // Null intentionally means "all enabled dictionaries", including ones
    // added later.
    _update(LookupPreferences(selectedIds: null, mode: state.mode));
  }

  void setMode(DictionarySelectionMode mode) {
    _update(LookupPreferences(selectedIds: state.selectedIds, mode: mode));
  }

  static Set<String> _idsOf(List<DictionaryInfo> dictionaries) {
    return dictionaries.map((dictionary) => dictionary.id).toSet();
  }

  void _update(LookupPreferences next) {
    state = next;
    final ids = next.selectedIds;
    if (ids == null) {
      _preferences.remove(_selectedIdsKey);
    } else {
      _preferences.setStringList(_selectedIdsKey, ids.toList());
    }
    _preferences.setString(_modeKey, next.mode.name);
  }
}
