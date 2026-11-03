import 'package:flutter/foundation.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_coverage.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_ocr.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/agent/agent_tool.dart';
import 'agent_coverage_parser.dart';
import 'agent_language_validator.dart';
import 'agent_messages.dart';
import 'agent_prompts.dart';
import 'agent_run.dart';
import 'agent_validator.dart';
import 'analysis_normalizer.dart';
import 'analysis_salvager.dart';
import 'coverage_support.dart';
import 'analysis_tag_parser.dart';
import 'citation_registry.dart';
import 'evidence_builder.dart';
import 'familiarization/dictionary_familiarization_service.dart';
import 'familiarization/unidic_familiarization_service.dart';
import 'grammar_patterns.dart';
import 'ocr_consensus.dart';
import 'ports/agent_capability_exception.dart';
import 'ports/llm_port.dart';
import 'ports/lookup_port.dart';
import 'ports/ocr_port.dart';
import 'ports/tokenize_port.dart';
import 'quote_builder.dart';
import 'rich_text_post_processor.dart';

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

  static const int _maxOcrVariants = 4;

  int get maxTargets => limits.maxTargets;
  int get maxCitations => limits.maxEvidenceEntries;
  int get maxSourceChars => limits.maxSourceChars;

  Future<AgentRunResult> run(
    AgentRunRequest request, {
    ProfileConfirmationCallback? onProfile,
    AgentProfileReviewCallback? onProfilesGenerated,
    AgentStageCallback? onStage,
    AgentProvisionalResultCallback? onProvisionalResult,
    AgentCancellation? cancellation,
    void Function(String accumulated)? onTextDelta,
    void Function(String accumulated)? onReasoningDelta,
    void Function(int citations)? onEvidenceProgress,
  }) async {
    var stage = AgentStage.prepare;
    var uiLanguage = resolveAgentUiLanguage(request.responseLanguage);
    final runWatch = Stopwatch()..start();
    void notify(AgentStage next, String message) {
      stage = next;
      _timing('stage=${next.name} elapsed=${runWatch.elapsedMilliseconds}ms');
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
        profiles.add(noProfileInstruction(issue.title, issue.reason));
      }
      final unidicService = unidicFamiliarizer;
      if (unidicService != null && request.unidicPath.trim().isNotEmpty) {
        checkCancelled();
        try {
          final unidic = await unidicService.ensure(request.unidicPath);
          if (unidic != null) {
            profiles.add(
              unidicProfileInstruction(
                unidic.featureLayout,
                unidic.observations,
              ),
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
                  ? primary.selectedVariant?.origin ?? AgentQuoteOrigin.ocr
                  : AgentQuoteOrigin.userText,
            );

      final llm = _llmFactory(request.provider);
      final requestedUser = request.images.isNotEmpty && userText.isNotEmpty
          ? userText
          : defaultImageUserRequest();
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
          dictionaryUnavailableInstruction(
            issue.dictionaryTitle,
            issue.message,
          ),
        );
      }
      if (evidence.structureUnavailable) {
        profiles.add(structureUnavailableInstruction());
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
        label: 'analysis',
      );
      notify(
        AgentStage.validating,
        agentStageMessage(AgentStage.validating, uiLanguage),
      );
      final parseWatch = Stopwatch()..start();
      final parsed = _parseAndNormalize(
        raw,
        quotes,
        evidence,
        expectedSourceId: primary?.id,
      );
      var analysis = parsed.analysis;
      var formatErrors = parsed.integrityErrors;
      final validateWatch = Stopwatch()..start();
      var validation = analysis == null
          ? null
          : validator.validate(
              analysis: analysis,
              evidence: evidence,
              quotes: quotes,
              mode: request.mode,
              expectedSourceId: primary?.id,
            );
      _timing(
        'parse=${parseWatch.elapsedMilliseconds}ms '
        'validate=${validateWatch.elapsedMilliseconds}ms '
        'analysis=${analysis != null} valid=${validation?.valid}',
      );

      // Show the main analysis before any optional repair/language call. This
      // is what keeps a finished stream from sitting behind a silent second
      // model request; the final result replaces this preview when checks end.
      var provisional = _emitProvisionalResult(
        onProvisionalResult: onProvisionalResult,
        envelope: envelope,
        evidence: evidence,
        quotes: quotes,
        analysis: analysis,
        validation: validation,
        formatErrors: formatErrors,
        profiles: profiles,
        profileWarnings: profileWarnings,
        unavailableProfiles: unavailableProfiles,
        warnings: warnings,
        coverageFallbackUsed: coverageFallbackUsed,
        mode: request.mode,
        expectedSourceId: primary?.id,
        elapsedMs: runWatch.elapsedMilliseconds,
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
        notify(AgentStage.validating, agentRepairingMessage(uiLanguage));
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
            label: 'analysis_repair',
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

      // The first response may have been unparseable (nothing to preview) or
      // invalid (only a salvaged preview). If the repair now produced a valid
      // analysis, show it before the language/rich-text post-checks run.
      final repairedIsValid =
          analysis != null && validation?.valid == true && formatErrors.isEmpty;
      if (provisional == null || (provisional == false && repairedIsValid)) {
        final repairedProvisional = _emitProvisionalResult(
          onProvisionalResult: onProvisionalResult,
          envelope: envelope,
          evidence: evidence,
          quotes: quotes,
          analysis: analysis,
          validation: validation,
          formatErrors: formatErrors,
          profiles: profiles,
          profileWarnings: profileWarnings,
          unavailableProfiles: unavailableProfiles,
          warnings: warnings,
          coverageFallbackUsed: coverageFallbackUsed,
          mode: request.mode,
          expectedSourceId: primary?.id,
          elapsedMs: runWatch.elapsedMilliseconds,
        );
        if (repairedProvisional != null) provisional = repairedProvisional;
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
        final languageWatch = Stopwatch()..start();
        var languageCheck = languageValidator.check(
          analysis,
          request.responseLanguage,
          allowedJapaneseTerms: allowedTerms,
        );
        _timing(
          'language_check=${languageWatch.elapsedMilliseconds}ms '
          'mismatch=${languageCheck.isMismatch} '
          'fields=${languageCheck.mismatchedFields.length}',
        );
        if (languageCheck.isMismatch) {
          checkCancelled();
          notify(AgentStage.validating, agentRepairingMessage(uiLanguage));
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
              label: 'language_repair',
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
          final recheckWatch = Stopwatch()..start();
          languageCheck = languageValidator.check(
            analysis!,
            request.responseLanguage,
            allowedJapaneseTerms: allowedTerms,
          );
          _timing(
            'language_recheck=${recheckWatch.elapsedMilliseconds}ms '
            'mismatch=${languageCheck.isMismatch}',
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
          final result = _buildResult(
            envelope: envelope,
            evidence: evidence,
            quotes: quotes,
            analysis: salvaged.analysis,
            validation: AgentValidationResult(
              valid: false,
              errors: errors,
              citationsUsed: salvageValidation.citationsUsed,
            ),
            profiles: profiles,
            profileWarnings: profileWarnings,
            unavailableProfiles: unavailableProfiles,
            warnings: warnings,
            coverageFallbackUsed: coverageFallbackUsed,
          );
          _timing(
            'result_ready salvage=true elapsed=${runWatch.elapsedMilliseconds}ms',
          );
          return result;
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

      String? richSummary;
      if (limits.enableRichTextPostProcess) {
        final summarySource = agentSummarySource(analysis);
        if (summarySource.isNotEmpty) {
          notify(
            AgentStage.formatting,
            agentStageMessage(AgentStage.formatting, uiLanguage),
          );
          checkCancelled();
          final rich = await RichTextPostProcessor(
            llm: llm,
            model: smallModel,
          ).process(summarySource, cancellation: cancellation);
          if (kDebugMode && rich.taggedText == null) {
            debugPrint('[AgentRichText] rejected: ${rich.rejectionReason}');
          }
          richSummary = rich.taggedText;
          checkCancelled();
        }
      }

      notify(AgentStage.done, agentStageMessage(AgentStage.done, uiLanguage));
      final result = _buildResult(
        envelope: envelope,
        evidence: evidence,
        quotes: quotes,
        analysis: analysis,
        validation: validation,
        profiles: profiles,
        profileWarnings: profileWarnings,
        unavailableProfiles: unavailableProfiles,
        warnings: warnings,
        coverageFallbackUsed: coverageFallbackUsed,
        richSummary: richSummary,
      );
      _timing(
        'result_ready salvage=false elapsed=${runWatch.elapsedMilliseconds}ms',
      );
      return result;
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
          maxTokens: limits.coverageReviewMaxTokens,
        ),
        cancellation,
        label: 'coverage',
      );
    } on AgentRunFailure catch (error) {
      if (cancellation?.isCancelled == true) rethrow;
      if (kDebugMode) {
        debugPrint(
          '[AgentCoverage] request failed '
          '${error.code.wireName}: ${error.message}',
        );
      }
      return _CoverageOutcome(
        evidence: evidence,
        warnings: <String>[agentCoverageUnavailable(uiLanguage)],
      );
    }

    var parsed = parseCoverageReview(
      raw,
      expectedSourceId: primarySourceId ?? '',
      debugLog: _coverageDebug,
    );
    review = parsed.review;
    if (kDebugMode && parsed.normalizedText != raw) {
      debugPrint(
        '[AgentCoverage] normalized response before parse/repair '
        'chars=${raw.length} -> ${parsed.normalizedText.length}',
      );
    }
    if (review == null) {
      // One bounded format/tag-integrity repair; never loop. The repair sees
      // the normalized text so it cannot repeat an already fixed wrapper
      // error; normalization is idempotent.
      try {
        final repaired = await _collect(
          llm,
          buildCoverageRepairRequest(
            model: model,
            language: request.responseLanguage,
            input: envelope,
            evidence: evidence,
            userRequest: userRequest,
            rawOutput: parsed.normalizedText,
            errors: parsed.errors,
            maxTokens: limits.coverageReviewMaxTokens,
          ),
          cancellation,
          label: 'coverage_repair',
        );
        parsed = parseCoverageReview(
          repaired,
          expectedSourceId: primarySourceId ?? '',
          debugLog: _coverageDebug,
        );
        review = parsed.review;
      } on AgentRunFailure catch (error) {
        if (cancellation?.isCancelled == true) rethrow;
        if (kDebugMode) {
          debugPrint(
            '[AgentCoverage] repair failed '
            '${error.code.wireName}: ${error.message}',
          );
        }
      }
    }
    if (review == null) {
      if (kDebugMode) {
        debugPrint(
          '[AgentCoverage] parse failed chars=${raw.length} '
          'errors=${parsed.errors.join('；')} head=${_debugHead(raw)}',
        );
      }
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

  AgentRunResult _buildResult({
    required AgentInputEnvelope envelope,
    required AgentEvidenceBundle evidence,
    required List<AgentQuoteRef> quotes,
    required AgentAnalysis analysis,
    required AgentValidationResult validation,
    required List<String> profiles,
    required List<String> profileWarnings,
    required List<DictionaryProfileIssue> unavailableProfiles,
    required List<String> warnings,
    required bool coverageFallbackUsed,
    String? richSummary,
  }) {
    return AgentRunResult(
      input: envelope,
      evidence: evidence,
      quotes: quotes,
      analysis: analysis,
      validation: validation,
      sources: _sourceVersions(envelope),
      dictionaryProfiles: List<String>.unmodifiable(profiles),
      profileWarnings: List<String>.unmodifiable(profileWarnings),
      unavailableProfiles: List<DictionaryProfileIssue>.unmodifiable(
        unavailableProfiles,
      ),
      warnings: List<String>.unmodifiable(warnings),
      coverageFallbackUsed: coverageFallbackUsed,
      ocrQuality: _ocrQuality(envelope, evidence),
      richSummary: richSummary,
    );
  }

  /// Emits a displayable result as soon as the first analysis is parsed and
  /// locally validated. Optional post-checks (format repair, language repair)
  /// may take another full model round-trip; they must not hide an already
  /// complete answer behind a silent wait.
  /// Returns null when nothing could be displayed, true when a fully valid
  /// preview was emitted, and false when only a salvaged/invalid preview was
  /// emitted.
  bool? _emitProvisionalResult({
    required AgentProvisionalResultCallback? onProvisionalResult,
    required AgentInputEnvelope envelope,
    required AgentEvidenceBundle evidence,
    required List<AgentQuoteRef> quotes,
    required AgentAnalysis? analysis,
    required AgentValidationResult? validation,
    required List<String> formatErrors,
    required List<String> profiles,
    required List<String> profileWarnings,
    required List<DictionaryProfileIssue> unavailableProfiles,
    required List<String> warnings,
    required bool coverageFallbackUsed,
    required AgentMode mode,
    required String? expectedSourceId,
    required int elapsedMs,
  }) {
    if (onProvisionalResult == null || analysis == null) return null;
    if (validation != null && validation.valid && formatErrors.isEmpty) {
      onProvisionalResult(
        _buildResult(
          envelope: envelope,
          evidence: evidence,
          quotes: quotes,
          analysis: analysis,
          validation: validation,
          profiles: profiles,
          profileWarnings: profileWarnings,
          unavailableProfiles: unavailableProfiles,
          warnings: warnings,
          coverageFallbackUsed: coverageFallbackUsed,
        ),
      );
      _timing('provisional elapsed=${elapsedMs}ms valid=true salvage=false');
      return true;
    }
    final salvaged = salvageAnalysis(
      analysis: analysis,
      evidence: evidence,
      quotes: quotes,
      mode: mode,
      expectedSourceId: expectedSourceId,
    );
    if (!salvaged.hasContent) return null;
    final salvageValidation = validator.validate(
      analysis: salvaged.analysis,
      evidence: evidence,
      quotes: quotes,
      mode: mode,
      expectedSourceId: expectedSourceId,
    );
    final errors = <String>{
      ...formatErrors,
      ...?validation?.errors,
      ...salvaged.notes,
      if (!salvageValidation.valid) ...salvageValidation.errors,
    }.toList(growable: false);
    onProvisionalResult(
      _buildResult(
        envelope: envelope,
        evidence: evidence,
        quotes: quotes,
        analysis: salvaged.analysis,
        validation: AgentValidationResult(
          valid: false,
          errors: errors,
          citationsUsed: salvageValidation.citationsUsed,
        ),
        profiles: profiles,
        profileWarnings: profileWarnings,
        unavailableProfiles: unavailableProfiles,
        warnings: warnings,
        coverageFallbackUsed: coverageFallbackUsed,
      ),
    );
    _timing('provisional elapsed=${elapsedMs}ms valid=false salvage=true');
    return false;
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
      final prepared = image.variants;
      final AgentOcrVariant variant;
      final List<AgentOcrVariant> variants;
      if (prepared.isNotEmpty) {
        // P6.6: a selected variant is re-analyzed without repeating OCR.
        variants = _boundedVariants(prepared, image.selectedVariantId);
        variant = variants.firstWhere(
          (item) => item.id == image.selectedVariantId,
          orElse: () => variants.first,
        );
      } else {
        final run = await _ocrPort.recognize(
          image: LocalOcrHandle(id: image.id, localPath: image.localPath),
          mode: image.mode,
        );
        variant = AgentOcrVariant(
          id: 'var-$index',
          engine: run.engine,
          mode: run.mode,
          text: run.text,
          confidence: run.confidence,
          elapsedMs: run.elapsedMs,
        );
        variants = <AgentOcrVariant>[variant];
      }
      sources.add(
        AgentSourceInput(
          id: 'src-$index',
          kind: AgentSourceKind.imageOcr,
          imageId: image.id,
          selectedVariantId: variant.id,
          variants: variants,
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

  /// The input contract allows at most four variants per image. Keep the
  /// selected variant first so it cannot be dropped when a user has tried
  /// several repairs; dedupe by id without reordering the rest.
  List<AgentOcrVariant> _boundedVariants(
    List<AgentOcrVariant> prepared,
    String? selectedVariantId,
  ) {
    final seen = <String>{};
    final unique = <AgentOcrVariant>[];
    for (final variant in prepared) {
      if (seen.add(variant.id)) unique.add(variant);
    }
    if (unique.length <= _maxOcrVariants) return unique;
    final bounded = <AgentOcrVariant>[];
    for (final variant in unique) {
      if (variant.id == selectedVariantId) bounded.add(variant);
    }
    for (final variant in unique) {
      if (variant.id == selectedVariantId) continue;
      if (bounded.length >= _maxOcrVariants) break;
      bounded.add(variant);
    }
    return bounded;
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

  /// Local OCR quality for the selected image variants. It uses the final
  /// (possibly coverage-supplemented) evidence so the dictionary hit rate is
  /// the same one the answer used.
  Map<String, OcrQuality> _ocrQuality(
    AgentInputEnvelope envelope,
    AgentEvidenceBundle evidence,
  ) {
    final evidenceBySource = <String, AgentSourceEvidence>{
      for (final source in evidence.sources) source.id: source,
    };
    final quality = <String, OcrQuality>{};
    for (final source in envelope.sources) {
      if (!source.isImage) continue;
      final imageId = source.imageId;
      final variant = source.selectedVariant;
      if (imageId == null || variant == null) continue;
      final sourceEvidence = evidenceBySource[source.id];
      quality[imageId] = sourceEvidence == null
          ? OcrConsensus.assess(variant: variant)
          : OcrConsensus.assessWithEvidence(
              variant: variant,
              evidence: sourceEvidence,
            );
    }
    return quality;
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
            origin: variant?.origin ?? AgentQuoteOrigin.ocr,
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
    String label = 'request',
  }) async {
    final buffer = StringBuffer();
    final reasoning = StringBuffer();
    final watch = Stopwatch()..start();
    var firstEventAt = -1;
    var finished = false;
    try {
      await for (final event in llm.stream(
        request,
        cancellation: cancellation,
      )) {
        if (cancellation?.isCancelled == true) {
          throw const AgentRunFailure(
            stage: AgentStage.reasoning,
            code: AgentToolErrorCode.toolCancelled,
            message: '已取消',
          );
        }
        if (firstEventAt < 0) firstEventAt = watch.elapsedMilliseconds;
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
            // `done` is terminal. Breaking here also cancels the provider's
            // SSE subscription, so a keep-alive socket cannot hide the result.
            finished = true;
        }
        if (finished) break;
      }
    } finally {
      if (kDebugMode) {
        debugPrint(
          '[AgentTiming] stream label=$label '
          'first_event=${firstEventAt}ms end=${watch.elapsedMilliseconds}ms '
          'chars=${buffer.length} reasoning=${reasoning.length} '
          'done=$finished cancelled=${cancellation?.isCancelled == true}',
        );
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
    // Tail flush: the controller may have throttled the last delta. Emitting
    // the final accumulated value here guarantees the UI sees the complete
    // text before validation starts.
    onTextDelta?.call(buffer.toString());
    onReasoningDelta?.call(reasoning.toString());
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

void _coverageDebug(String message) {
  if (kDebugMode) debugPrint('[AgentCoverage] $message');
}

/// Bounded, content-free timing logs used to find post-stream latency.
/// Never log prompt text, citations, image paths or API keys here.
void _timing(String message) {
  if (kDebugMode) debugPrint('[AgentTiming] $message');
}

String _debugHead(String raw) {
  var text = raw
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[redacted]')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.length > 300) text = '${text.substring(0, 300)}…';
  return text;
}
