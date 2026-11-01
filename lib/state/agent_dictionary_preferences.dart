import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/dict_info.dart';
import '../core/models/dictionary_selection.dart';
import 'providers.dart';

/// Agent-only dictionary selection. It is intentionally independent from
/// `lookupPreferencesProvider`: changing one never changes the other.
class AgentDictionaryPreferences {
  const AgentDictionaryPreferences({
    this.selectedIds,
    this.mode = DictionarySelectionMode.multi,
  });

  /// `null` means every currently enabled dictionary (the default). A concrete
  /// set is snapshotted on first edit so later-added dictionaries do not join
  /// silently.
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
}

final agentDictionaryPreferencesProvider =
    NotifierProvider<
      AgentDictionaryPreferencesNotifier,
      AgentDictionaryPreferences
    >(AgentDictionaryPreferencesNotifier.new);

class AgentDictionaryPreferencesNotifier
    extends Notifier<AgentDictionaryPreferences> {
  static const _selectedIdsKey = 'agent_dictionary_selected_ids';
  static const _modeKey = 'agent_dictionary_mode';

  late SharedPreferences _preferences;

  @override
  AgentDictionaryPreferences build() {
    _preferences = ref.watch(sharedPreferencesProvider);
    final stored = _preferences.getStringList(_selectedIdsKey);
    final mode = _preferences.getString(_modeKey) == 'single'
        ? DictionarySelectionMode.single
        : DictionarySelectionMode.multi;
    return AgentDictionaryPreferences(selectedIds: stored?.toSet(), mode: mode);
  }

  void toggle(String id, List<DictionaryInfo> enabled) {
    final current = state.selectedIds ?? _idsOf(enabled);
    final Set<String> next;
    if (state.mode == DictionarySelectionMode.single) {
      next = current.length == 1 && current.contains(id)
          ? <String>{}
          : <String>{id};
    } else {
      next = <String>{...current};
      if (!next.add(id)) next.remove(id);
    }
    _update(AgentDictionaryPreferences(selectedIds: next, mode: state.mode));
  }

  void selectAll() {
    _update(AgentDictionaryPreferences(selectedIds: null, mode: state.mode));
  }

  void setMode(DictionarySelectionMode mode) {
    _update(
      AgentDictionaryPreferences(selectedIds: state.selectedIds, mode: mode),
    );
  }

  void reset() {
    _preferences.remove(_selectedIdsKey);
    _preferences.remove(_modeKey);
    state = const AgentDictionaryPreferences();
  }

  static Set<String> _idsOf(List<DictionaryInfo> dictionaries) =>
      dictionaries.map((dictionary) => dictionary.id).toSet();

  void _update(AgentDictionaryPreferences next) {
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
