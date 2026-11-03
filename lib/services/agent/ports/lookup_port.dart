import '../../../core/models/dict_info.dart';
import '../../../core/models/lookup_models.dart';
import '../../../core/models/lookup_request.dart';

abstract interface class LookupPort {
  Future<LookupResult> lookup(LookupRequest request);

  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  });
}

/// Optional extension for ports that can execute several independent lookups
/// in one worker round trip. Evidence builder batches queries and falls back
/// to [LookupPort.lookup] for fakes/integrations that do not implement this.
abstract interface class BatchLookupPort {
  Future<List<LookupResult>> lookupMany(List<LookupRequest> requests);
}
