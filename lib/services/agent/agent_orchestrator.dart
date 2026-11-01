import 'package:flutter/foundation.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_coverage.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/agent/agent_tool.dart';
import 'agent_language_validator.dart';
import 'agent_coverage_parser.dart';
import 'agent_messages.dart';
import 'agent_run.dart';
import 'agent_validator.dart';
import 'coverage_prompts.dart';
import 'coverage_support.dart';
import 'analysis_normalizer.dart';
import 'analysis_prompts.dart';
import 'analysis_salvager.dart';
import 'analysis_tag_parser.dart';
import 'citation_registry.dart';
import 'evidence_builder.dart';
import 'familiarization/dictionary_familiarization_service.dart';
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
    this.languageValidator = const AgentLanguageValidator(),
    this.limits = AgentLimits.standard,
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
  final AgentLanguageValidator languageValidator;
  final AgentLimits limits;

  int get maxTargets => limits.maxTargets;
  int get maxCitations => limits.maxEvidenceEntries;
  int get maxSourceChars => limits.maxSourceChars;

  Future<AgentRunResult> run(
    AgentRunRequest request, {
    ProfileConfirmationCallback? onProfile,
    AgentProfileReviewCallback? onProfilesGenerated,
    AgentStageCallback? onStage,
    AgentCancellation? cancellation,
    void Function(String accumulated)? onTextDelta,
    void Function(String accumulated)? onReasoningDelta,
    void Function(int citations)? onEvidenceProgress,
  }) async {
    var stage = AgentStage.prepare;
    var uiLanguage = resolveAgentUiLanguage(request.responseLanguage);
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
          final generation = await familiarizer.generateMany(
            request.dictionaries,
            runId: request.runId,
          );
          for (final result in generation.results) {
            if (result.markdown.isNotEmpty &&
                (result.action == FamiliarizationAction.reuse ||
                    result.action == FamiliarizationAction.created)) {
              profiles.add(result.markdown);
            }
          }
          profileWarnings.addAll(generation.warnings);
          unavailableProfiles.addAll(generation.issues);

          final proposals = generation.proposals;
          if (proposals.isNotEmpty && onProfilesGenerated != null) {
            notify(
              AgentStage.awaitingProfile,
              agentStageMessage(AgentStage.awaitingProfile, uiLanguage),
            );
            checkCancelled();
            final decisions = await onProfilesGenerated(
              request.runId,
              proposals,
            );
            for (var index = 0; index < proposals.length; index++) {
              final proposal = proposals[index];
              final decision = index < decisions.length
                  ? decisions[index]
                  : ProfileConfirmation(
                      action: ProfileConfirmationAction.skipOnce,
                      markdown: proposal.markdown,
                    );
              // The inbox persists the decision before releasing this future.
              // Only a saved profile is added to this run's prompt.
              if (decision.action == ProfileConfirmationAction.save) {
                final markdown = decision.markdown.trim().isEmpty
                    ? proposal.markdown
                    : decision.markdown.trim();
                if (markdown.isNotEmpty) profiles.add(markdown);
              }
            }
          } else if (proposals.isNotEmpty && onProfile != null) {
            // Direct callers/tests may resolve inline; the app controller uses
            // the app-level inbox callback above.
            for (final proposal in proposals) {
              final decision = await onProfile(
                proposal.profile,
                proposal.markdown,
              );
              final result = await familiarizer.persistDecision(
                proposal,
                decision.action,
                decision.markdown,
              );
              if (result.markdown.isNotEmpty &&
                  result.action == FamiliarizationAction.created) {
                profiles.add(result.markdown);
              }
            }
          }
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

      final llm = _llmFactory(request.provider);
      final requestedUser = request.images.isNotEmpty && userText.isNotEmpty
          ? userText
          : '解释这段日文并给出词典依据';
      final smallModel = request.provider.smallModel.trim().isEmpty
          ? analysisModel
          : request.provider.smallModel.trim();

      notify(
        AgentStage.tokenizing,
        agentStageMessage(AgentStage.tokenizing, uiLanguage),
      );
      checkCancelled();
      final evidenceBuilder = EvidenceBuilder(
        tokenizePort: _tokenizePort,
        lookupPort: _lookupPort,
        grammar: _grammar,
        citations: _citations,
        limits: limits,
      );
      var evidence = await evidenceBuilder.build(
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

      final warnings = <String>[];
      var coverageFallbackUsed = false;
      if (limits.maxCoverageFallback > 0) {
        notify(
          AgentStage.coverage,
          agentStageMessage(AgentStage.coverage, uiLanguage),
        );
        checkCancelled();
        final coverage = await _applyCoverageReview(
          llm: llm,
          model: smallModel,
          request: request,
          envelope: envelope,
          evidence: evidence,
          evidenceBuilder: evidenceBuilder,
          cancellation: cancellation,
          uiLanguage: uiLanguage,
          primarySourceId: primary?.id,
          userRequest: requestedUser,
          onProgress: onEvidenceProgress,
        );
        evidence = coverage.evidence;
        coverageFallbackUsed = coverage.fallbackUsed;
        warnings.addAll(coverage.warnings);
        checkCancelled();
      }

      notify(
        AgentStage.reasoning,
        agentStageMessage(AgentStage.reasoning, uiLanguage),
      );
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
      final parsed = _parseAndNormalize(
        raw,
        quotes,
        evidence,
        expectedSourceId: primary?.id,
      );
      var analysis = parsed.analysis;
      var formatErrors = parsed.integrityErrors;
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
        if (formatErrors.isNotEmpty) ...formatErrors,
        if (analysis == null) '模型返回格式无效',
        if (validation != null && !validation.valid) ...validation.errors,
      ];

      // One bounded repair call. It reuses the same OCR/evidence/quotes; only
      // the model output is regenerated. A repair failure must not discard the
      // first analysis when it can still be salvaged.
      if (analysis == null ||
          formatErrors.isNotEmpty ||
          validation == null ||
          !validation.valid) {
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
          final repaired = _parseAndNormalize(
            repairRaw,
            quotes,
            evidence,
            expectedSourceId: primary?.id,
          );
          if (repaired.analysis != null) {
            raw = repairRaw;
            analysis = repaired.analysis;
            formatErrors = repaired.integrityErrors;
            validation = validator.validate(
              analysis: analysis!,
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
      if (validation != null && formatErrors.isNotEmpty) {
        // Repairs may leave malformed blocks behind. Keep the parsable content
        // for salvage, but never report the tagged contract as fully satisfied.
        validation = AgentValidationResult(
          valid: false,
          errors: <String>[...formatErrors, ...validation.errors],
          citationsUsed: validation.citationsUsed,
        );
      }

      final allowedTerms = <String>{
        for (final source in evidence.sources)
          for (final token in source.tokens) ...<String>[
            token.surface,
            token.lemma,
            token.reading,
            ...token.lookupCandidates,
          ],
        for (final pattern in evidence.patterns) pattern.surface,
        for (final citation in evidence.citations) ...<String>[
          citation.headword,
          citation.entryKey,
          citation.matchedKey,
        ],
        for (final quote in quotes) quote.text,
      };

      // F1b: check only human-readable fields. A single repair may translate
      // them; a failed or still-mismatched repair keeps the result and warns.
      if (analysis != null && validation != null && validation.valid) {
        var languageCheck = languageValidator.check(
          analysis,
          request.responseLanguage,
          allowedJapaneseTerms: allowedTerms,
        );
        if (languageCheck.isMismatch) {
          checkCancelled();
          notify(AgentStage.reasoning, agentRepairingMessage(uiLanguage));
          try {
            final languageRaw = await _collect(
              llm,
              buildAnalysisLanguageRepairRequest(
                model: analysisModel,
                mode: request.mode,
                responseLanguage: request.responseLanguage,
                input: envelope,
                evidence: evidence,
                quotes: quotes,
                dictionaryProfiles: profiles,
                userRequest: requestedUser,
                rawOutput: raw,
                mismatchedFields: languageCheck.mismatchedFields,
              ),
              cancellation,
            );
            final repaired = _parseAndNormalize(
              languageRaw,
              quotes,
              evidence,
              expectedSourceId: primary?.id,
            );
            if (repaired.analysis != null && repaired.integrityErrors.isEmpty) {
              final repairedValidation = validator.validate(
                analysis: repaired.analysis!,
                evidence: evidence,
                quotes: quotes,
                mode: request.mode,
                expectedSourceId: primary?.id,
              );
              if (repairedValidation.valid) {
                raw = languageRaw;
                analysis = repaired.analysis;
                validation = repairedValidation;
                formatErrors = repaired.integrityErrors;
              }
            }
          } on AgentRunFailure {
            if (cancellation?.isCancelled == true) rethrow;
            // Keep the original result; the warning below records the failure.
          }
          languageCheck = languageValidator.check(
            analysis!,
            request.responseLanguage,
            allowedJapaneseTerms: allowedTerms,
          );
          if (languageCheck.isMismatch) {
            warnings.add(agentLanguageWarning(uiLanguage));
          }
        }
      }

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
          if (languageValidator
              .check(
                salvaged.analysis,
                request.responseLanguage,
                allowedJapaneseTerms: allowedTerms,
              )
              .isMismatch) {
            warnings.add(agentLanguageWarning(uiLanguage));
          }
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
            warnings: warnings,
            coverageFallbackUsed: coverageFallbackUsed,
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
        warnings: warnings,
        coverageFallbackUsed: coverageFallbackUsed,
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

  /// F7: one bounded coverage review after the initial evidence. It may run one
  /// supplementary lookup pass, and only deletes model-suggested duplicates
  /// after local verification.
  Future<_CoverageOutcome> _applyCoverageReview({
    required LlmPort llm,
    required String model,
    required AgentRunRequest request,
    required AgentInputEnvelope envelope,
    required AgentEvidenceBundle evidence,
    required EvidenceBuilder evidenceBuilder,
    required AgentCancellation? cancellation,
    required AgentUiLanguage uiLanguage,
    required String? primarySourceId,
    required String userRequest,
    required void Function(int citations)? onProgress,
  }) async {
    final warnings = <String>[];
    AgentCoverageReview? review;
    String raw;
    try {
      raw = await _collect(
        llm,
        buildCoverageRequest(
          model: model,
          language: request.responseLanguage,
          input: envelope,
          evidence: evidence,
          userRequest: userRequest,
        ),
        cancellation,
      );
    } on AgentRunFailure {
      if (cancellation?.isCancelled == true) rethrow;
      return _CoverageOutcome(
        evidence: evidence,
        warnings: <String>[agentCoverageUnavailable(uiLanguage)],
      );
    }

    var parsed = parseCoverageReview(
      raw,
      expectedSourceId: primarySourceId ?? '',
    );
    review = parsed.review;
    if (review == null) {
      // One bounded JSON-format repair; never loop.
      try {
        final repaired = await _collect(
          llm,
          buildCoverageRepairRequest(
            model: model,
            language: request.responseLanguage,
            input: envelope,
            evidence: evidence,
            userRequest: userRequest,
            rawOutput: raw,
            errors: parsed.errors,
          ),
          cancellation,
        );
        parsed = parseCoverageReview(
          repaired,
          expectedSourceId: primarySourceId ?? '',
        );
        review = parsed.review;
      } on AgentRunFailure {
        if (cancellation?.isCancelled == true) rethrow;
      }
    }
    if (review == null) {
      return _CoverageOutcome(
        evidence: evidence,
        warnings: <String>[agentCoverageUnavailable(uiLanguage)],
      );
    }
    if (review.verdict != AgentCoverageVerdict.missing) {
      return _CoverageOutcome(evidence: evidence, warnings: warnings);
    }

    final validated = validateCoverageReview(
      review: review,
      input: envelope,
      evidence: evidence,
      limits: limits,
    );
    if (validated.droppedMissing > 0) {
      warnings.add(agentCoverageUnverifiable(uiLanguage));
    }
    if (validated.missing.isEmpty && validated.duplicateGroups.isEmpty) {
      return _CoverageOutcome(evidence: evidence, warnings: warnings);
    }

    var workingEvidence = evidence;
    var fallbackUsed = false;
    var remainingSlots =
        limits.maxEvidenceEntries - workingEvidence.citations.length;
    if (remainingSlots < 0) remainingSlots = 0;
    var excludedKeys = const <String>{};

    if (remainingSlots == 0) {
      if (validated.missing.isEmpty) {
        return _CoverageOutcome(evidence: evidence, warnings: warnings);
      }
      final removeIds = verifyCoverageDuplicates(
        evidence: workingEvidence,
        groups: validated.duplicateGroups,
      );
      if (removeIds.isEmpty) {
        warnings.add(agentCoverageAtLimit(uiLanguage));
        return _CoverageOutcome(evidence: evidence, warnings: warnings);
      }
      excludedKeys = <String>{
        for (final citation in workingEvidence.citations)
          if (removeIds.contains(citation.id))
            '${citation.dictionaryId}\u0000${citation.entryKey}',
      };
      _citations.removeAll(removeIds);
      workingEvidence = pruneCoverageCitations(
        evidence: workingEvidence,
        removeIds: removeIds,
        limits: limits,
      );
      remainingSlots = removeIds.length;
      fallbackUsed = true;
    }

    if (validated.missing.isEmpty || remainingSlots <= 0) {
      return _CoverageOutcome(
        evidence: workingEvidence,
        fallbackUsed: fallbackUsed,
        warnings: warnings,
      );
    }

    final supplementary = await evidenceBuilder.lookupExtraQueries(
      queries: <String>[for (final item in validated.missing) item.query],
      dictionaries: request.dictionaries,
      maxNewCitations: remainingSlots,
      excludedKeys: excludedKeys,
      isCancelled: () => cancellation?.isCancelled == true,
      onProgress: onProgress,
      onDictionaryError: (dictionary, message) {
        final warning = agentDictionaryLookupFailed(
          uiLanguage,
          dictionary.title,
        );
        if (!warnings.contains(warning)) warnings.add(warning);
      },
    );
    fallbackUsed = true;
    final merged = mergeCoverageEvidence(
      evidence: workingEvidence,
      citationsByQuery: supplementary,
      missing: validated.missing,
      limits: limits,
    );
    if (merged.citations.length <= workingEvidence.citations.length) {
      warnings.add(agentCoverageNoNew(uiLanguage));
    }
    return _CoverageOutcome(
      evidence: merged,
      fallbackUsed: fallbackUsed,
      warnings: warnings,
    );
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

  ({AgentAnalysis? analysis, List<String> integrityErrors}) _parseAndNormalize(
    String raw,
    List<AgentQuoteRef> quotes,
    AgentEvidenceBundle evidence, {
    String? expectedSourceId,
  }) {
    final integrityErrors = analysisTagIntegrityErrors(raw);
    final parsed = parseTaggedAnalysis(raw, sourceId: expectedSourceId ?? '');
    if (parsed == null ||
        parsed.translation.isEmpty ||
        parsed.segments.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[AgentAnalysis] parse failed chars=${raw.length} '
          'head=${_debugHead(raw)}',
        );
      }
      return (analysis: null, integrityErrors: integrityErrors);
    }
    return (
      analysis: normalizeAnalysis(
        analysis: parsed,
        quotes: quotes,
        evidence: evidence,
      ),
      integrityErrors: integrityErrors,
    );
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

class _CoverageOutcome {
  const _CoverageOutcome({
    required this.evidence,
    required this.warnings,
    this.fallbackUsed = false,
  });

  final AgentEvidenceBundle evidence;
  final List<String> warnings;
  final bool fallbackUsed;
}

String _debugHead(String raw) {
  var text = raw
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[redacted]')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.length > 300) text = '${text.substring(0, 300)}…';
  return text;
}
