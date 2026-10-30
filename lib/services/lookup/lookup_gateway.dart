import '../../core/models/dict_info.dart';
import '../../core/models/lookup_match_mode.dart';
import '../../core/models/lookup_models.dart';
import '../../core/models/lookup_request.dart';

/// The narrow lookup surface shared by the UI and the Agent tool adapters.
///
/// `MdictService` implements this interface, so tests can use a lightweight
/// fake without starting the dictionary isolate.
abstract interface class LookupBackend {
  Future<LookupResult> lookup({
    required String query,
    required Iterable<String> rawCandidates,
    required List<DictionaryInfo> dictionaries,
    LookupMatchMode matchMode = LookupMatchMode.exact,
    int maxEntriesPerDictionary = 0,
    int suggestionLimit = 30,
  });
}

class LookupGatewayException implements Exception {
  const LookupGatewayException(this.message);

  final String message;

  @override
  String toString() => 'LookupGatewayException: $message';
}

/// Validates and normalizes a lookup request without UI dependencies.
class LookupGateway {
  const LookupGateway(this._backend);

  final LookupBackend _backend;

  Future<LookupResult> lookup(LookupRequest request) {
    final dictionaries = request.dictionaries
        .where((dictionary) => dictionary.enabled && dictionary.isAvailable)
        .toList(growable: false);
    if (dictionaries.isEmpty) {
      throw const LookupGatewayException('请先选择至少一本可用的 MDict 词典');
    }
    return _backend.lookup(
      query: request.query,
      rawCandidates: request.rawCandidates.isEmpty
          ? <String>[request.query]
          : request.rawCandidates,
      dictionaries: dictionaries,
      matchMode: request.matchMode,
      maxEntriesPerDictionary: request.maxEntriesPerDictionary,
      suggestionLimit: request.suggestionLimit,
    );
  }
}
