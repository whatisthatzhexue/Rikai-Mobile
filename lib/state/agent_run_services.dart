import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/agent/agent_tool.dart';
import '../services/agent/adapters/dictionary_sample_port_adapter.dart';
import '../services/agent/adapters/lookup_port_adapter.dart';
import '../services/agent/adapters/ocr_port_adapter.dart';
import '../services/agent/adapters/tokenize_port_adapter.dart';
import '../services/agent/agent_orchestrator.dart';
import '../services/agent/familiarization/profile_repository.dart';
import '../services/agent/grammar_patterns.dart';
import '../services/agent/ports/agent_capability_exception.dart';
import '../services/agent/ports/dictionary_sample_port.dart';
import '../services/agent/ports/lookup_port.dart';
import '../services/agent/ports/ocr_port.dart';
import '../services/agent/ports/tokenize_port.dart';
import '../services/agent/providers/provider_factory.dart';
import '../services/mecab/mecab_service.dart';
import 'agent_providers.dart';
import 'providers.dart';

/// Ports and repositories for one Agent run. The loader is injectable so
/// lifecycle tests can replace OCR/tokenize/lookup/LLM without touching the
/// production services.
class AgentRunServices {
  const AgentRunServices({
    required this.ocrPort,
    required this.tokenizePort,
    required this.lookupPort,
    required this.samplePort,
    required this.grammar,
    required this.profileRepository,
    required this.unidicRepository,
    required this.llmFactory,
    required this.cancelOcr,
  });

  final OcrPort ocrPort;
  final TokenizePort tokenizePort;
  final LookupPort lookupPort;
  final DictionarySamplePort samplePort;
  final GrammarPatternCatalog grammar;
  final DictionaryProfileRepository profileRepository;
  final UnidicProfileRepository unidicRepository;
  final LlmFactory llmFactory;
  final Future<void> Function() cancelOcr;
}

typedef AgentRunServicesLoader =
    Future<AgentRunServices?> Function({
      required bool needsOcr,
      bool Function()? isCancelled,
    });

final agentRunServicesProvider = Provider<AgentRunServicesLoader>((ref) {
  return ({required needsOcr, isCancelled}) async {
    bool cancelled() => isCancelled?.call() == true;
    final ocrService = ref.read(ocrServiceProvider);
    final mdict = await ref.read(mdictServiceProvider.future);
    if (cancelled()) return null;
    final grammar = await ref.read(agentGrammarCatalogProvider.future);
    if (cancelled()) return null;

    TokenizePort tokenizePort;
    try {
      final mecab = await ref.read(mecabServiceProvider.future);
      tokenizePort = TokenizePortAdapter(mecab);
    } on MecabException catch (error) {
      // UniDic is optional; EvidenceBuilder marks structure as unavailable.
      tokenizePort = UnavailableTokenizePort(error.message);
    } catch (_) {
      tokenizePort = const UnavailableTokenizePort('UniDic 不可用');
    }
    if (cancelled()) return null;

    final store = ref.read(agentStoreProvider);
    final secrets = ref.read(secretStoreProvider);
    return AgentRunServices(
      ocrPort: OcrPortAdapter(
        service: ocrService,
        manifest: () async {
          if (!needsOcr) {
            throw const AgentCapabilityException(
              AgentToolErrorCode.modelMissing,
              '本次运行没有图片',
            );
          }
          return ref.read(ocrModelManifestProvider.future);
        },
      ),
      tokenizePort: tokenizePort,
      lookupPort: LookupPortAdapter(mdict),
      samplePort: DictionarySamplePortAdapter(mdict),
      grammar: grammar,
      profileRepository: store,
      unidicRepository: store,
      llmFactory: (config) =>
          createLlmProvider(config: config, secrets: secrets),
      cancelOcr: ocrService.cancel,
    );
  };
});
