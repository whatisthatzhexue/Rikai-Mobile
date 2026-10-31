import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/dict_info.dart';
import '../../core/models/lookup_match_mode.dart';
import '../../core/models/lookup_models.dart';
import '../../core/models/lookup_request.dart';
import '../../core/theme/page_route.dart';
import '../../core/ui/rikai_toast.dart';
import '../../services/lookup/lookup_gateway.dart';
import '../../services/mdict/mdict_worker.dart';
import '../../state/providers.dart';
import 'entry_page.dart';

/// Runs a lookup across the enabled dictionaries.
Future<LookupResult> performLookup(
  WidgetRef ref,
  String query, {
  List<String>? rawCandidates,
  List<DictionaryInfo>? dictionaries,
  LookupMatchMode? matchMode,
  LookupRequest? request,
}) async {
  final service = await ref.read(mdictServiceProvider.future);
  final settings = ref.read(appSettingsProvider);
  final effectiveRequest =
      request ??
      LookupRequest(
        query: query,
        rawCandidates: rawCandidates ?? <String>[query],
        dictionaries: dictionaries ?? ref.read(enabledDictionariesProvider),
        matchMode: matchMode ?? settings.lookupMatchMode,
        maxEntriesPerDictionary: settings.maxEntriesPerDictionary,
      );
  try {
    return await LookupGateway(service).lookup(effectiveRequest);
  } on LookupGatewayException catch (error) {
    throw MdictException(MdictErrorCode.lookupFailed, error.message);
  }
}

/// An `entry://` link stays inside the dictionary currently being read.
/// It never falls back to the global dictionary selection or match mode.
LookupRequest entryLinkLookupRequest({
  required String word,
  required DictionaryInfo dictionary,
}) {
  return LookupRequest(
    query: word,
    rawCandidates: <String>[word],
    dictionaries: <DictionaryInfo>[dictionary],
    matchMode: LookupMatchMode.exact,
    maxEntriesPerDictionary: 1,
  );
}

/// Looks up [word] (for example an `entry://` link) and pushes an entry page.
Future<void> lookupAndOpenEntry(
  BuildContext context,
  WidgetRef ref,
  String word, {
  LookupRequest? request,
}) async {
  final navigator = Navigator.of(context);

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
    result = await performLookup(ref, word, request: request);
  } catch (caught) {
    error = caught;
  }

  if (navigator.mounted) navigator.pop(); // close the progress dialog
  if (!navigator.mounted) return;
  if (error != null) {
    RikaiToast.show(navigator.context, '查询失败：${_shortError(error)}');
    return;
  }
  final hitGroups = result?.hitGroups ?? const [];
  if (hitGroups.isEmpty) {
    RikaiToast.show(navigator.context, '未找到「$word」');
    return;
  }

  // A link follows the first exact result; the search UI offers “查看全部”
  // when a dictionary has several homographs.
  final firstGroup = hitGroups.first;
  navigator.push(
    RikaiPageRoute<void>(
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
