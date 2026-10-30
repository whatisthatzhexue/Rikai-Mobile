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
