import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_models.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/providers.dart';
import 'entry_page.dart';

/// Runs a lookup across the enabled dictionaries.
Future<LookupResult> performLookup(
  WidgetRef ref,
  String query, {
  List<String>? rawCandidates,
  List<DictionaryInfo>? dictionaries,
}) async {
  final List<DictionaryInfo> source =
      dictionaries ?? ref.read(enabledDictionariesProvider);
  final selected = source
      .where((dictionary) => dictionary.enabled && dictionary.isAvailable)
      .toList(growable: false);
  if (selected.isEmpty) {
    throw const MdictException(MdictErrorCode.lookupFailed, '尚未添加可用的 MDict 词典');
  }
  final service = await ref.read(mdictServiceProvider.future);
  return service.lookup(
    query: query,
    rawCandidates: rawCandidates ?? [query],
    dictionaries: selected,
    maxEntriesPerDictionary: ref
        .read(appSettingsProvider)
        .maxEntriesPerDictionary,
  );
}

/// Looks up [word] (for example an `entry://` link) and pushes an entry page.
Future<void> lookupAndOpenEntry(
  BuildContext context,
  WidgetRef ref,
  String word,
) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Flexible(child: Text('正在查询…')),
            ],
          ),
        ),
      ),
    ),
  );

  LookupResult? result;
  Object? error;
  try {
    result = await performLookup(ref, word);
  } catch (caught) {
    error = caught;
  }

  if (navigator.mounted) navigator.pop(); // close the progress dialog
  if (!navigator.mounted) return;
  if (error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text('查询失败：${_shortError(error)}')),
    );
    return;
  }
  final hitGroups = result?.hitGroups ?? const [];
  if (hitGroups.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text('未找到「$word」')));
    return;
  }

  // A link follows the first exact result; the search UI offers “查看全部”
  // when a dictionary has several homographs.
  final firstGroup = hitGroups.first;
  navigator.push(
    MaterialPageRoute<void>(
      builder: (context) => EntryPage(
        word: word,
        groups: [
          DictionaryLookupGroup(
            dictionary: firstGroup.dictionary,
            entries: [firstGroup.entries.first],
          ),
        ],
        initialDictionaryId: firstGroup.dictionary.id,
      ),
    ),
  );
}

String _shortError(Object error) {
  if (error is MdictException) return error.message;
  return error.toString();
}
