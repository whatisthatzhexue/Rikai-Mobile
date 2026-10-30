import '../../../core/models/dict_info.dart';
import '../../../core/models/lookup_models.dart';
import '../../../core/models/lookup_request.dart';
import '../../lookup/lookup_gateway.dart';
import '../../mdict/mdict_worker.dart';
import '../ports/lookup_port.dart';
import 'agent_error_mapper.dart';

class LookupPortAdapter implements LookupPort {
  LookupPortAdapter(this._service) : _gateway = LookupGateway(_service);

  final MdictService _service;
  final LookupGateway _gateway;

  @override
  Future<LookupResult> lookup(LookupRequest request) async {
    try {
      return await _gateway.lookup(request);
    } catch (error) {
      throw mapAgentError(error, fallbackMessage: '词典查询失败');
    }
  }

  @override
  Future<List<String>> suggest({
    required String prefix,
    required List<DictionaryInfo> dictionaries,
    int limit = 10,
  }) async {
    try {
      return await _service.suggest(
        prefix: prefix,
        dictionaries: dictionaries,
        limit: limit,
      );
    } catch (error) {
      throw mapAgentError(error, fallbackMessage: '词典建议失败');
    }
  }
}
