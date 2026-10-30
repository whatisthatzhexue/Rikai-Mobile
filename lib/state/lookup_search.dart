import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/dict_info.dart';
import '../core/models/lookup_match_mode.dart';
import '../core/models/lookup_models.dart';
import '../services/mdict/mdict_worker.dart';
import 'lookup_preferences.dart';
import 'providers.dart';

/// Search text survives page navigation for the app's lifetime.
final lookupQueryControllerProvider = Provider<TextEditingController>((ref) {
  final controller = TextEditingController();
  ref.onDispose(controller.dispose);
  return controller;
});

class LookupSearchState {
  const LookupSearchState({
    this.result,
    this.error,
    this.busy = false,
    this.lastQuery = '',
    this.selectionSignature = '',
    this.matchMode = LookupMatchMode.exact,
  });

  final LookupResult? result;
  final Object? error;
  final bool busy;
  final String lastQuery;

  /// Dictionary selection used for [result]. The search page compares this
  /// with the global filter so a selection changed from the reader sheet is
  /// reflected when the page is reopened.
  final String selectionSignature;

  /// Matching mode used for [result]; changing the global mode must refresh it.
  final LookupMatchMode matchMode;

  LookupSearchState searching(String query, LookupMatchMode mode) {
    return LookupSearchState(
      result: result,
      error: null,
      busy: true,
      lastQuery: query,
      selectionSignature: selectionSignature,
      matchMode: mode,
    );
  }

  LookupSearchState completed(LookupResult result, String signature) {
    return LookupSearchState(
      result: result,
      error: null,
      busy: false,
      lastQuery: lastQuery,
      selectionSignature: signature,
      matchMode: matchMode,
    );
  }

  LookupSearchState failed(Object error, String signature) {
    return LookupSearchState(
      result: result,
      error: error,
      busy: false,
      lastQuery: lastQuery,
      selectionSignature: signature,
      matchMode: matchMode,
    );
  }
}

final lookupSearchProvider =
    NotifierProvider<LookupSearchNotifier, LookupSearchState>(
      LookupSearchNotifier.new,
    );

class LookupSearchNotifier extends Notifier<LookupSearchState> {
  int _generation = 0;

  @override
  LookupSearchState build() {
    return const LookupSearchState();
  }

  Future<void> search(
    String rawQuery, {
    List<DictionaryInfo>? dictionaries,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    final settings = ref.read(appSettingsProvider);
    final List<DictionaryInfo> enabled =
        dictionaries ?? ref.read(enabledDictionariesProvider);
    final selected = ref
        .read(lookupPreferencesProvider)
        .selectedDictionaries(enabled);
    final signature = selected.map((dictionary) => dictionary.id).toList()
      ..sort();

    if (selected.isEmpty) {
      state = LookupSearchState(
        result: state.result,
        error: const MdictException(
          MdictErrorCode.lookupFailed,
          '请先选择至少一本可用的 MDict 词典',
        ),
        busy: false,
        lastQuery: query,
        selectionSignature: signature.join(','),
        matchMode: settings.lookupMatchMode,
      );
      return;
    }

    final generation = ++_generation;
    state = state.searching(query, settings.lookupMatchMode);
    try {
      final service = await ref.read(mdictServiceProvider.future);
      final result = await service.lookup(
        query: query,
        rawCandidates: [query],
        dictionaries: selected,
        matchMode: settings.lookupMatchMode,
        maxEntriesPerDictionary: settings.maxEntriesPerDictionary,
      );
      if (generation != _generation) return;
      state = state.completed(result, signature.join(','));
    } catch (error) {
      if (generation != _generation) return;
      state = state.failed(error, signature.join(','));
    }
  }
}
