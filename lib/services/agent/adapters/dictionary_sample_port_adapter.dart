import '../../../core/models/dict_info.dart';
import '../../../core/models/dictionary_sample.dart';
import '../../mdict/mdict_worker.dart';
import '../familiarization/dictionary_probes.dart';
import '../ports/dictionary_sample_port.dart';
import 'agent_error_mapper.dart';

class DictionarySamplePortAdapter implements DictionarySamplePort {
  DictionarySamplePortAdapter(this._service, {DictionaryProbeSet? probes})
    : _probes = probes ?? DictionaryProbeSet.fallback;

  final MdictService _service;
  final DictionaryProbeSet _probes;

  @override
  Future<DictionarySample> sample(
    DictionaryInfo dictionary, {
    int maxEntries = 12,
  }) async {
    try {
      return await _service.sample(
        dictionary: dictionary,
        exactProbes: _probes.exact,
        prefixProbes: _probes.prefix,
        maxEntries: maxEntries,
      );
    } catch (error) {
      throw mapAgentError(error, fallbackMessage: '词典采样失败');
    }
  }
}
