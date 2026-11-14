import '../../../core/models/agent/agent_tool.dart';
import '../../../core/models/token.dart';
import '../../mecab/mecab_service.dart';
import '../ports/agent_capability_exception.dart';
import '../ports/tokenize_port.dart';
import 'agent_error_mapper.dart';

class TokenizePortAdapter implements TokenizePort {
  const TokenizePortAdapter(this._service);

  final MecabService _service;

  @override
  Future<List<Token>> analyze(String text) async {
    try {
      return await _service.analyze(text);
    } catch (error) {
      throw mapAgentError(error, fallbackMessage: '分词失败');
    }
  }
}

/// Used when UniDic is not configured or failed to open. Tokenization is
/// optional: the run continues with dictionary lookups/translation and marks
/// structural analysis as unavailable.
class UnavailableTokenizePort implements TokenizePort {
  const UnavailableTokenizePort(this.message);

  final String message;

  @override
  Future<List<Token>> analyze(String text) async {
    throw AgentCapabilityException(AgentToolErrorCode.unidicNotReady, message);
  }
}
