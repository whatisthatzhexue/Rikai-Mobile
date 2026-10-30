import 'package:flutter/foundation.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/agent/agent_tool.dart';
import 'agent_messages.dart';
import 'agent_run.dart';
import 'agent_validator.dart';
import 'analysis_normalizer.dart';
import 'analysis_parser.dart';
import 'analysis_prompts.dart';
import 'analysis_salvager.dart';
import 'citation_registry.dart';
import 'evidence_builder.dart';
import 'familiarization/dictionary_familiarization_service.dart';
import 'familiarization/familiarization_prompts.dart';
import 'familiarization/unidic_familiarization_service.dart';
import 'grammar_patterns.dart';
import 'ports/agent_capability_exception.dart';
import 'ports/llm_port.dart';
import 'ports/lookup_port.dart';
import 'ports/ocr_port.dart';
import 'ports/tokenize_port.dart';
import 'quote_builder.dart';

typedef LlmFactory = LlmPort Function(AgentProviderConfig config);

/// Fixed Stage -1..3 pipeline. The model never chooses OCR images, dictionary
/// selection or citations; it only reasons over the supplied evidence.
class AgentOrchestrator {
  AgentOrchestrator({
    required OcrPort ocrPort,
    required TokenizePort tokenizePort,
    required LookupPort lookupPort,
    required GrammarPatternCatalog grammar,
    required CitationRegistry citations,
    required LlmFactory llmFactory,
    this.dictionaryFamiliarizer,
    this.unidicFamiliarizer,
    this.validator = const AgentValidator(),
    this.maxTargets = 120,
    this.maxCitations = 60,
    this.maxSourceChars = 6000,
  }) : _ocrPort = ocrPort,
       _tokenizePort = tokenizePort,
       _lookupPort = lookupPort,
       _grammar = grammar,
       _citations = citations,
       _llmFactory = llmFactory;

  final OcrPort _ocrPort;
  final TokenizePort _tokenizePort;
  final LookupPort _lookupPort;
  final GrammarPatternCatalog _grammar;
  final CitationRegistry _citations;
  final LlmFactory _llmFactory;
  final DictionaryFamiliarizationService? dictionaryFamiliarizer;
  final UnidicFamiliarizationService? unidicFamiliarizer;
  final AgentValidator validator;
  final int maxTargets;
  final int maxCitations;
  final int maxSourceChars;

  Future<AgentRunResult> run(
    AgentRunRequest request, {
    ProfileConfirmationCallback? onProfile,
    AgentStageCallback? onStage,
    AgentCancellation? cancellation,
    void Function(String accumulated)? onTextDelta,
    void Function(String accumulated)? onReasoningDelta,
    void Function(int citations)? onEvidenceProgress,
  }) async {
    var stage = AgentStage.prepare;
    var uiLanguage = resolveAgentUiLanguage(
      request.responseLanguage,
      request.userText,
    );
    void notify(AgentStage next, String message) {
      stage = next;
      onStage?.call(next, message);
    }

    void checkCancelled() {
      if (cancellation?.isCancelled == true) {
        throw AgentRunFailure(
          stage: stage,
          code: AgentToolErrorCode.toolCancelled,
          message: '已取消',
        );
      }
    }

    try {
      notify(AgentStage.prepare, agentStageMessage(stage, uiLanguage));
      final userText = request.userText.trim();
      if (userText.isEmpty && request.images.isEmpty) {
        throw AgentRunFailure(
          stage: stage,
          code: AgentToolErrorCode.invalidArguments,
          message: '请输入文字或选择图片',
        );
      }
      if (request.dictionaries.isEmpty) {
        throw AgentRunFailure(
          stage: stage,
          code: AgentToolErrorCode.dictionaryNotReady,
          message: '请先选择至少一本可用词典',
        );
      }
      final analysisModel = request.provider.complexModel.trim().isEmpty
          ? request.provider.smallModel.trim()
          : request.provider.complexModel.trim();
      if (analysisModel.isEmpty) {
        throw AgentRunFailure(
          stage: stage,
          code: AgentToolErrorCode.notConfigured,
          message: '尚未配置模型',
        );
      }
      checkCancelled();

      notify(AgentStage.ocr, agentStageMessage(AgentStage.ocr, uiLanguage));
      final envelope = await _buildInput(request, cancellation: cancellation);
      if (request.responseLanguage == AgentResponseLanguage.follow) {
        final followText = envelope.sources
            .map(
              (source) => source.isImage
                  ? source.selectedVariant?.text ?? ''
                  : source.text,
            )
            .join(' ');
        uiLanguage = resolveAgentUiLanguage(
          AgentResponseLanguage.follow,
          followText,
        );
      }
      final totalChars = envelope.sources.fold<int>(
        0,
        (sum, source) =>
            sum +
            (source.isImage
                ? source.selectedVariant?.text.length ?? 0
                : source.text.length),
      );
      if (totalChars == 0) {
        throw AgentRunFailure(
          stage: stage,
          code: AgentToolErrorCode.invalidArguments,
          message: '没有识别到可用文字',
        );
      }
      if (totalChars > maxSourceChars) {
        throw AgentRunFailure(
          stage: stage,
          code: AgentToolErrorCode.invalidArguments,
          message: '文本过长，请选择要分析的段落',
        );
      }
      checkCancelled();

      final profiles = <String>[];
      final profileWarnings = <String>[];
      final unavailableProfiles = <DictionaryProfileIssue>[];
      final familiarizer = dictionaryFamiliarizer;
      if (request.allowFamiliarization && familiarizer != null) {
        notify(
          AgentStage.familiarizing,
          agentStageMessage(AgentStage.familiarizing, uiLanguage),
        );
        checkCancelled();
        try {
          final batch = await familiarizer.ensureMany(
            request.dictionaries,
            confirm: onProfile,
          );
          for (final result in batch.results) {
            if (result.markdown.isNotEmpty &&
                (result.action == FamiliarizationAction.reuse ||
                    result.action == FamiliarizationAction.created)) {
              profiles.add(result.markdown);
            }
          }
          profileWarnings.addAll(batch.warnings);
          unavailableProfiles.addAll(batch.issues);
        } on AgentCapabilityException catch (error) {
          // A profile is an aid, not a gate. Keep going with raw evidence and
          // show the failure to the user instead of blocking the whole run.
          profileWarnings.add(error.message);
        }
      }
      for (final issue in unavailableProfiles) {
        profiles.add(
          'NO PROFILE for ${issue.title} (${issue.reason}). '
          'Use generic lookup rules; do not assume this dictionary covers '
          'the requested word or grammar.',
        );
      }
      final unidicService = unidicFamiliarizer;
      if (unidicService != null && request.unidicPath.trim().isNotEmpty) {
        checkCancelled();
        try {
          final unidic = await unidicService.ensure(request.unidicPath);
          if (unidic != null) {
            profiles.add(
              'UniDic profile: ${unidic.featureLayout} fields\n'
              '${unidic.observations.join('\n')}',
            );
          }
        } on AgentCapabilityException catch (error) {
          if (error.code == AgentToolErrorCode.toolCancelled) rethrow;
          profileWarnings.add(error.message);
        }
      }
      checkCancelled();

      final primary = _primarySource(envelope);
      final quotes = primary == null
          ? const <AgentQuoteRef>[]
          : buildSourceQuotes(
              sourceId: primary.id,
              text: primary.isImage
                  ? primary.selectedVariant?.text ?? ''
                  : primary.text,
              origin: primary.isImage
                  ? AgentQuoteOrigin.ocr
                  : AgentQuoteOrigin.userText,
            );

      notify(
        AgentStage.tokenizing,
        agentStageMessage(AgentStage.tokenizing, uiLanguage),
      );
      checkCancelled();
      final evidence =
          await EvidenceBuilder(
            tokenizePort: _tokenizePort,
            lookupPort: _lookupPort,
            grammar: _grammar,
            citations: _citations,
            maxTargets: maxTargets,
            maxCitations: maxCitations,
          ).build(
            sources: envelope.sources,
            dictionaries: request.dictionaries,
            maxSourceChars: maxSourceChars,
            isCancelled: () => cancellation?.isCancelled == true,
            onProgress: onEvidenceProgress,
          );
      checkCancelled();
      for (final issue in evidence.dictionaryIssues) {
        profiles.add(
          'DICTIONARY UNAVAILABLE: ${issue.dictionaryTitle} '
          '(${issue.message}). Do not claim coverage from this dictionary; '
          'use the remaining evidence or mark the claim unresolved.',
        );
      }
      if (evidence.structureUnavailable) {
        profiles.add(
          'STRUCTURE UNAVAILABLE: UniDic is not configured or failed. Do not '
          'return structural_analysis segments, grammar_notes, word_notes or '
          'token ids. Translate the text and use dictionary citations or '
          'unresolved; never claim token/grammar analysis in this run.',
        );
      }

      notify(
        AgentStage.reasoning,
        agentStageMessage(AgentStage.reasoning, uiLanguage),
      );
      final llm = _llmFactory(request.provider);
      final requestedUser = request.images.isNotEmpty && userText.isNotEmpty
          ? userText
          : '解释这段日文并给出词典依据';
      final analysisRequest = buildAnalysisRequest(
        model: analysisModel,
        mode: request.mode,
        responseLanguage: request.responseLanguage,
        input: envelope,
        evidence: evidence,
        quotes: quotes,
        dictionaryProfiles: profiles,
        userRequest: requestedUser,
      );
      var raw = await _collect(
        llm,
        analysisRequest,
        cancellation,
        onTextDelta: onTextDelta,
        onReasoningDelta: onReasoningDelta,
      );
      notify(
        AgentStage.validating,
        agentStageMessage(AgentStage.validating, uiLanguage),
      );
      var analysis = _parseAndNormalize(raw, quotes, evidence);
      var validation = analysis == null
          ? null
          : validator.validate(
              analysis: analysis,
              evidence: evidence,
              quotes: quotes,
              mode: request.mode,
              expectedSourceId: primary?.id,
            );
      final repairErrors = <String>[
        if (analysis == null) '模型返回格式无效',
        if (validation != null && !validation.valid) ...validation.errors,
      ];

      // One bounded repair call. It reuses the same OCR/evidence/quotes; only
      // the model output is regenerated. A repair failure must not discard the
      // first analysis when it can still be salvaged.
      if (analysis == null || validation == null || !validation.valid) {
        checkCancelled();
        notify(AgentStage.reasoning, agentRepairingMessage(uiLanguage));
        try {
          final repairRaw = await _collect(
            llm,
            buildAnalysisRepairRequest(
              model: analysisModel,
              mode: request.mode,
              responseLanguage: request.responseLanguage,
              input: envelope,
              evidence: evidence,
              quotes: quotes,
              dictionaryProfiles: profiles,
              userRequest: requestedUser,
              rawOutput: raw,
              errors: repairErrors,
            ),
            cancellation,
          );
          final repaired = _parseAndNormalize(repairRaw, quotes, evidence);
          if (repaired != null) {
            raw = repairRaw;
            analysis = repaired;
            validation = validator.validate(
              analysis: repaired,
              evidence: evidence,
              quotes: quotes,
              mode: request.mode,
              expectedSourceId: primary?.id,
            );
          }
        } on AgentRunFailure {
          // A cancelled run must stop immediately; a provider/parse failure on
          // the repair attempt falls through to local salvage.
          if (cancellation?.isCancelled == true) rethrow;
          if (kDebugMode) {
            debugPrint('[AgentAnalysis] repair call failed; trying salvage');
          }
        }
      }

      checkCancelled();
      if (analysis == null || validation == null || !validation.valid) {
        final salvaged = analysis == null
            ? null
            : salvageAnalysis(
                analysis: analysis,
                evidence: evidence,
                quotes: quotes,
                mode: request.mode,
                expectedSourceId: primary?.id,
              );
        if (salvaged != null && salvaged.hasContent) {
          final salvageValidation = validator.validate(
            analysis: salvaged.analysis,
            evidence: evidence,
            quotes: quotes,
            mode: request.mode,
            expectedSourceId: primary?.id,
          );
          final errors = <String>{
            ...repairErrors,
            ...?validation?.errors,
            ...salvaged.notes,
            if (!salvageValidation.valid) ...salvageValidation.errors,
          }.toList(growable: false);
          return AgentRunResult(
            input: envelope,
            evidence: evidence,
            quotes: quotes,
            analysis: salvaged.analysis,
            validation: AgentValidationResult(
              valid: false,
              errors: errors,
              citationsUsed: salvageValidation.citationsUsed,
            ),
            sources: _sourceVersions(envelope),
            dictionaryProfiles: profiles,
            profileWarnings: profileWarnings,
            unavailableProfiles: unavailableProfiles,
          );
        }
        throw AgentRunFailure(
          stage: stage,
          code: AgentToolErrorCode.validationFailed,
          message: validation == null
              ? '模型返回格式无效'
              : validation.errors.join('；'),
          detail: _debugHead(raw),
        );
      }

      notify(AgentStage.done, agentStageMessage(AgentStage.done, uiLanguage));
      return AgentRunResult(
        input: envelope,
        evidence: evidence,
        quotes: quotes,
        analysis: analysis,
        validation: validation,
        sources: _sourceVersions(envelope),
        dictionaryProfiles: profiles,
        profileWarnings: profileWarnings,
        unavailableProfiles: unavailableProfiles,
      );
    } on AgentRunFailure {
      rethrow;
    } on AgentCapabilityException catch (error) {
      throw AgentRunFailure(
        stage: stage,
        code: error.code,
        message: error.message,
        cause: error,
      );
    } on Object catch (error) {
      throw AgentRunFailure(
        stage: stage,
        code: AgentToolErrorCode.internalError,
        message: 'Agent 运行失败',
        cause: error,
      );
    }
  }

  Future<AgentInputEnvelope> _buildInput(
    AgentRunRequest request, {
    AgentCancellation? cancellation,
  }) async {
    final sources = <AgentSourceInput>[];
    var index = 0;
    for (final image in request.images) {
      if (cancellation?.isCancelled == true) {
        throw AgentRunFailure(
          stage: AgentStage.ocr,
          code: AgentToolErrorCode.toolCancelled,
          message: '已取消',
        );
      }
      index++;
      final run = await _ocrPort.recognize(
        image: LocalOcrHandle(id: image.id, localPath: image.localPath),
        mode: image.mode,
      );
      final variant = AgentOcrVariant(
        id: 'var-$index',
        engine: run.engine,
        mode: run.mode,
        text: run.text,
        confidence: run.confidence,
        elapsedMs: run.elapsedMs,
      );
      sources.add(
        AgentSourceInput(
          id: 'src-$index',
          kind: AgentSourceKind.imageOcr,
          imageId: image.id,
          selectedVariantId: variant.id,
          variants: <AgentOcrVariant>[variant],
        ),
      );
    }
    final hasImages = request.images.isNotEmpty;
    // With an image, the text field is an instruction/context, not a second
    // source. Text-only input becomes the source text.
    if (!hasImages && request.userText.trim().isNotEmpty) {
      index++;
      sources.add(
        AgentSourceInput(
          id: 'src-$index',
          kind: AgentSourceKind.userText,
          text: request.userText.trim(),
        ),
      );
    }
    return AgentInputEnvelope(
      sessionId: request.sessionId,
      mode: request.mode,
      userText: hasImages ? request.userText.trim() : '',
      context: request.context.trim(),
      dictionaries: <AgentDictionaryRef>[
        for (final dictionary in request.dictionaries)
          AgentDictionaryRef(
            id: dictionary.id,
            title: dictionary.title,
            order: dictionary.order,
          ),
      ],
      sources: sources,
    );
  }

  AgentSourceInput? _primarySource(AgentInputEnvelope envelope) {
    for (final source in envelope.sources) {
      if (source.isImage) return source;
    }
    for (final source in envelope.sources) {
      if (!source.isImage && source.text.trim().isNotEmpty) return source;
    }
    return envelope.sources.isEmpty ? null : envelope.sources.first;
  }

  List<AgentSourceVersion> _sourceVersions(AgentInputEnvelope envelope) {
    final versions = <AgentSourceVersion>[];
    var index = 0;
    for (final source in envelope.sources) {
      index++;
      if (source.isImage) {
        final variant = source.selectedVariant;
        versions.add(
          AgentSourceVersion(
            id: 'sv-$index',
            sourceId: source.id,
            imageId: source.imageId,
            variantId: variant?.id,
            origin: AgentQuoteOrigin.ocr,
            text: variant?.text ?? '',
            engine: variant?.engine ?? '',
            mode: variant?.mode.name ?? '',
            confidence: variant?.confidence ?? 0,
          ),
        );
      } else {
        versions.add(
          AgentSourceVersion(
            id: 'sv-$index',
            sourceId: source.id,
            origin: AgentQuoteOrigin.userText,
            text: source.text,
          ),
        );
      }
    }
    return versions;
  }

  AgentAnalysis? _parseAndNormalize(
    String raw,
    List<AgentQuoteRef> quotes,
    AgentEvidenceBundle evidence,
  ) {
    try {
      final parsed = AgentAnalysis.fromJson(
        normalizeAnalysisJson(extractJsonObject(raw)),
      );
      if (parsed.translation.isEmpty || parsed.segments.isEmpty) {
        if (kDebugMode) {
          debugPrint('[AgentAnalysis] empty translation/segments');
        }
        return null;
      }
      return normalizeAnalysis(
        analysis: parsed,
        quotes: quotes,
        evidence: evidence,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AgentAnalysis] parse failed chars=${raw.length} '
          'head=${_debugHead(raw)} type=${error.runtimeType}',
        );
      }
      return null;
    }
  }

  Future<String> _collect(
    LlmPort llm,
    LlmRequest request,
    AgentCancellation? cancellation, {
    void Function(String accumulated)? onTextDelta,
    void Function(String accumulated)? onReasoningDelta,
  }) async {
    final buffer = StringBuffer();
    final reasoning = StringBuffer();
    await for (final event in llm.stream(request, cancellation: cancellation)) {
      if (cancellation?.isCancelled == true) {
        throw const AgentRunFailure(
          stage: AgentStage.reasoning,
          code: AgentToolErrorCode.toolCancelled,
          message: '已取消',
        );
      }
      switch (event.type) {
        case LlmEventType.textDelta:
          buffer.write(event.text);
          onTextDelta?.call(buffer.toString());
        case LlmEventType.reasoningDelta:
          reasoning.write(event.text);
          onReasoningDelta?.call(reasoning.toString());
        case LlmEventType.error:
          throw AgentRunFailure(
            stage: AgentStage.reasoning,
            code: AgentToolErrorCode.providerUnavailable,
            message: '模型服务返回错误',
            detail: _debugHead(reasoning.toString()),
          );
        case LlmEventType.done:
          break;
      }
    }
    if (buffer.isEmpty) {
      throw AgentRunFailure(
        stage: AgentStage.reasoning,
        code: AgentToolErrorCode.providerUnavailable,
        message: '模型没有返回文本',
        detail: _debugHead(reasoning.toString()),
      );
    }
    return buffer.toString();
  }
}

String _debugHead(String raw) {
  var text = raw
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[redacted]')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.length > 300) text = '${text.substring(0, 300)}…';
  return text;
}
