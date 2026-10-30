import '../../../core/models/dict_info.dart';
import '../../../core/models/dictionary_sample.dart';

abstract interface class DictionarySamplePort {
  Future<DictionarySample> sample(
    DictionaryInfo dictionary, {
    int maxEntries = 12,
  });
}
