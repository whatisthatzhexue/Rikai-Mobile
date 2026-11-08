import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_coverage.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_ocr.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/models/dict_info.dart';
import '../../core/utils/rich_text_tags.dart';
import '../../core/utils/script_language.dart';
import 'agent_coverage_parser.dart';
import 'agent_intent.dart';
import 'analysis_merge.dart';
import 'evidence_partition.dart';
import 'agent_language_validator.dart';
import 'agent_messages.dart';
import 'agent_prompts.dart';
import 'agent_run.dart';
import 'agent_task_route.dart';
import 'agent_validator.dart';
import 'analysis_normalizer.dart';
import 'analysis_salvager.dart';
import 'coverage_support.dart';
import 'analysis_tag_parser.dart';
import 'citation_registry.dart';
import 'evidence_builder.dart';
import 'evidence_cache.dart';
import 'familiarization/dictionary_familiarization_service.dart';
import 'familiarization/unidic_familiarization_service.dart';
import 'grammar_patterns.dart';
import 'ocr_consensus.dart';
import 'ports/agent_capability_exception.dart';
import 'ports/llm_port.dart';
import 'streaming_translation_assembler.dart';
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
    this.evidenceCache,
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
  final AgentEvidenceCache? evidenceCache;

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
    AgentTranslationPreviewCallback? onTranslationPreview,
    AgentCancellation? cancellation,
    AgentRichTextCallback? onRichTextReady,
    AgentRichTextFormattingCallback? onRichTextFormattingChanged,
    void Function(int accumulatedChars)? onTextDelta,
    void Function(int accumulatedChars)? onReasoningDelta,
    void Function(int citations)? onEvidenceProgress,
    void Function(Future<void> work)? onBackgroundProfiles,
  }) async {
    var stage = AgentStage.prepare;
    var runSucceeded = false;
    final uiLanguage = resolveAgentUiLanguage(request.responseLanguage);
    final runWatch = Stopwatch()..start();
    final telemetry = _RunTelemetryBuilder();
    var deferredProfileDictionaries = const <DictionaryInfo>[];
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
      final analysisModel = AgentTaskRoute.resolve(
        AgentTaskKind.analysis,
        request.provider,
      ).model;
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
          // Local confirmed profiles are used immediately. Missing profiles are
          // not generated on the critical path: the current run uses
          // noProfileInstruction and the proposals are generated after the
          // result, then confirmed/auto-accepted for the next run.
          final cached = await familiarizer.loadCached(
            request.dictionaries,
            pendingDictionaryIds: request.pendingProfileDictionaryIds,
          );
          for (final result in cached.results) {
            if (result.action == FamiliarizationAction.reuse &&
                result.markdown.isNotEmpty) {
              profiles.add(result.markdown);
            } else if (result.action == FamiliarizationAction.declined) {
              profiles.add(
                noProfileInstruction(
                  result.stored?.displayTitle ?? 'dictionary',
                  'user declined',
                ),
              );
            }
          }
          for (final dictionary in request.dictionaries) {
            if (request.pendingProfileDictionaryIds.contains(dictionary.id)) {
              profiles.add(
                noProfileInstruction(dictionary.title, 'pending confirmation'),
              );
            }
          }
          for (final dictionary in cached.missing) {
            profiles.add(
              noProfileInstruction(dictionary.title, 'profile not ready'),
            );
          }
          deferredProfileDictionaries = cached.missing;
        } on AgentCapabilityException catch (error) {
          // A profile is an aid, not a gate. Keep going with raw evidence and
          // show the failure to the user instead of blocking the whole run.
          profileWarnings.add(error.message);
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '[AgentFamiliarization] cache load failed '
              '(${error.runtimeType})',
            );
          }
          profileWarnings.add('词典档案读取失败');
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
      // Multi-image runs must expose quotes from every source. Building quotes
      // from the primary source only made SEGMENT/原文 cover the first image
      // while the other images were merely context.
      final quotes = <AgentQuoteRef>[];
      var quoteIndex = 0;
      for (final source in envelope.sources) {
        final text = source.isImage
            ? source.selectedVariant?.text ?? ''
            : source.text;
        if (text.trim().isEmpty) continue;
        final sourceQuotes = buildSourceQuotes(
          sourceId: source.id,
          text: text,
          origin: source.isImage
              ? source.selectedVariant?.origin ?? AgentQuoteOrigin.ocr
              : AgentQuoteOrigin.userText,
          startIndex: quoteIndex,
        );
        quotes.addAll(sourceQuotes);
        quoteIndex += sourceQuotes.length;
      }
      final translationAssembler = onTranslationPreview == null
          ? null
          : StreamingTranslationAssembler(
              quoteIds: quotes.map((quote) => quote.id).toSet(),
              onPreview: onTranslationPreview,
            );

      final llm = _llmFactory(request.provider);
      final requestedUser = request.images.isNotEmpty && userText.isNotEmpty
          ? userText
          : defaultImageUserRequest(request.responseLanguage);
      final smallModel = AgentTaskRoute.resolve(
        AgentTaskKind.coverage,
        request.provider,
      ).model;

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
      final cacheKey = evidenceCache == null
          ? null
          : agentEvidenceCacheKey(request, limits);
      final cachedEvidence = cacheKey == null
          ? null
          : evidenceCache!.get(cacheKey);
      var evidence =
          cachedEvidence ??
          await evidenceBuilder.build(
            sources: envelope.sources,
            dictionaries: request.dictionaries,
            quotes: quotes,
            maxSourceChars: maxSourceChars,
            isCancelled: () => cancellation?.isCancelled == true,
            onProgress: onEvidenceProgress,
          );
      if (cachedEvidence != null) {
        _citations.restore(cachedEvidence.citations);
        onEvidenceProgress?.call(cachedEvidence.citations.length);
      } else if (cacheKey != null && evidence.dictionaryIssues.isEmpty) {
        evidenceCache!.put(cacheKey, evidence);
      }
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
      } else if (envelope.sources.any((source) {
        final text = source.isImage
            ? source.selectedVariant?.text ?? ''
            : source.text;
        return isHanOnlyAmbiguous(text);
      })) {
        // Keep the safety notice before long profile Markdown, since the
        // prompt budget truncates profiles from the end.
        profiles.insert(0, hanOnlyAmbiguousInstruction());
      }

      final warnings = <String>[];
      void noteTruncation(AgentAnalysis? analysis) {
        if (analysis?.truncated != true) return;
        final warning = agentAnalysisTruncatedWarning(uiLanguage);
        if (!warnings.contains(warning)) warnings.add(warning);
      }

      var coverageFallbackUsed = false;
      if (_shouldRunCoverageReview(evidence)) {
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
          telemetry: telemetry,
        );
        evidence = coverage.evidence;
        coverageFallbackUsed = coverage.fallbackUsed;
        warnings.addAll(coverage.warnings);
        checkCancelled();
      } else if (limits.maxCoverageFallback > 0 && kDebugMode) {
        debugPrint(
          '[AgentCoverage] skipped '
          'citations=${evidence.citations.length} '
          'targets=${evidence.budget.uniqueTargets} '
          'cap=${evidence.budget.maxCitations}',
        );
      }
      _noteDictionariesWithoutEvidence(
        dictionaries: request.dictionaries,
        evidence: evidence,
        warnings: warnings,
        uiLanguage: uiLanguage,
      );

      notify(
        AgentStage.reasoning,
        agentStageMessage(AgentStage.reasoning, uiLanguage),
      );
      final intentHint = detectAgentIntent(requestedUser);
      if (_shouldFanOut(request, evidence)) {
        final fanOut = await _runDictionaryFanOut(
          llm: llm,
          model: analysisModel,
          request: request,
          envelope: envelope,
          evidence: evidence,
          quotes: quotes,
          profiles: profiles,
          userRequest: requestedUser,
          intentHint: intentHint,
          expectedSourceId: primary?.id,
          cancellation: cancellation,
          uiLanguage: uiLanguage,
          telemetry: telemetry,
          checkCancelled: checkCancelled,
        );
        if (fanOut != null) {
          var analysis = fanOut.analysis;
          var validation = validator.validate(
            analysis: analysis,
            evidence: evidence,
            quotes: quotes,
            mode: request.mode,
            expectedSourceId: primary?.id,
          );
          if (!validation.valid) {
            final salvaged = salvageAnalysis(
              analysis: analysis,
              evidence: evidence,
              quotes: quotes,
              mode: request.mode,
              expectedSourceId: primary?.id,
            );
            if (!salvaged.hasContent) {
              throw AgentRunFailure(
                stage: stage,
                code: AgentToolErrorCode.validationFailed,
                message: validation.errors.join('；'),
              );
            }
            analysis = salvaged.analysis;
            validation = validator.validate(
              analysis: analysis,
              evidence: evidence,
              quotes: quotes,
              mode: request.mode,
              expectedSourceId: primary?.id,
            );
            if (!validation.valid && _hasUsableAnalysis(analysis)) {
              validation = AgentValidationResult(
                valid: false,
                usable: true,
                errors: validation.errors,
                citationsUsed: validation.citationsUsed,
              );
            }
          }
          if (fanOut.partial) {
            warnings.add(agentFanOutPartialWarning(uiLanguage));
          }
          noteTruncation(analysis);
          final languageCheck = languageValidator.check(
            analysis,
            request.responseLanguage,
            allowedJapaneseTerms: _allowedJapaneseTerms(evidence, quotes),
          );
          if (languageCheck.isMismatch) {
            warnings.add(agentLanguageWarning(uiLanguage));
          }
          final fanOutStats = _contentCitationStats(evidence);
          var result = _buildResult(
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
            telemetry: telemetry.build(
              elapsedMs: runWatch.elapsedMilliseconds,
              citationCount: evidence.citations.length,
              adoptedCitationCount: validation.citationsUsed.length,
              targetsWithCitations: fanOutStats.cited,
              targetCount: fanOutStats.total,
            ),
          );
          result = await _formatResultRichText(
            result: result,
            llm: llm,
            model: smallModel,
            cancellation: cancellation,
            onRichTextReady: onRichTextReady,
            onRichTextFormattingChanged: onRichTextFormattingChanged,
            notify: notify,
            uiLanguage: uiLanguage,
            responseLanguage: request.responseLanguage,
            telemetry: telemetry,
          );
          checkCancelled();
          notify(
            AgentStage.done,
            agentStageMessage(AgentStage.done, uiLanguage),
          );
          _timing(
            'result_ready fan_out=true elapsed=${runWatch.elapsedMilliseconds}ms',
          );
          runSucceeded = true;
          return result;
        }
      }
      final analysisRequest = buildAnalysisRequest(
        model: analysisModel,
        mode: request.mode,
        responseLanguage: request.responseLanguage,
        input: envelope,
        evidence: evidence,
        quotes: quotes,
        dictionaryProfiles: profiles,
        userRequest: requestedUser,
        intentHint: intentHint,
        maxTokenEntries: limits.maxPromptTokenEntries,
        maxProfileCharsPerDictionary: limits.maxProfileCharsPerDictionary,
        maxProfileTotalChars: limits.maxProfileTotalChars,
      );
      var raw = await _collect(
        llm,
        analysisRequest,
        cancellation,
        onTextDelta: onTextDelta,
        onReasoningDelta: onReasoningDelta,
        onTelemetry: telemetry.record,
        label: 'analysis',
        translationAssembler: translationAssembler,
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
      if (kDebugMode && validation != null && !validation.valid) {
        debugPrint('[AgentValidation] errors=${validation.errors.join(' | ')}');
      }
      _timing(
        'evidence retrieved=${evidence.citations.length} '
        'adopted=${validation?.citationsUsed.length ?? 0} '
        'targets=${evidence.budget.uniqueTargets} '
        'truncated=${evidence.truncated}',
      );

      noteTruncation(analysis);

      // Local-first tolerance: if the model output is imperfect but salvage
      // can produce a displayable result (translation or at least one
      // interpretation), adopt it and skip the repair call. Contract errors
      // stay in `validation.errors` for telemetry; `usable` only suppresses
      // the generic UI warning.
      var cleanedUsable = false;
      if (analysis != null &&
          (formatErrors.isNotEmpty ||
              validation == null ||
              !validation.valid)) {
        final cleaned = salvageAnalysis(
          analysis: analysis,
          evidence: evidence,
          quotes: quotes,
          mode: request.mode,
          expectedSourceId: primary?.id,
        );
        if (_hasUsableAnalysis(cleaned.analysis)) {
          final cleanedValidation = validator.validate(
            analysis: cleaned.analysis,
            evidence: evidence,
            quotes: quotes,
            mode: request.mode,
            expectedSourceId: primary?.id,
          );
          final cleanedErrors = <String>{
            ...formatErrors,
            ...?validation?.errors,
            ...cleaned.notes,
            if (!cleanedValidation.valid) ...cleanedValidation.errors,
          }.toList(growable: false);
          if (kDebugMode) {
            debugPrint(
              '[AgentSalvage] usable errors=${cleanedErrors.join(' | ')}',
            );
          }
          analysis = cleaned.analysis;
          validation = AgentValidationResult(
            valid: false,
            usable: true,
            errors: cleanedErrors,
            citationsUsed: cleanedValidation.citationsUsed,
          );
          formatErrors = const <String>[];
          cleanedUsable = true;
        }
      }
      noteTruncation(analysis);

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
      if (!cleanedUsable &&
          (analysis == null ||
              formatErrors.isNotEmpty ||
              validation == null ||
              !validation.valid)) {
        checkCancelled();
        notify(AgentStage.validating, agentRepairingMessage(uiLanguage));
        try {
          final repairRaw = await _collect(
            llm,
            buildAnalysisRepairRequest(
              model: smallModel,
              mode: request.mode,
              responseLanguage: request.responseLanguage,
              rawOutput: raw,
              errors: repairErrors,
              availableIds: _availableIds(quotes, evidence),
            ),
            cancellation,
            onTelemetry: telemetry.record,
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
            if (kDebugMode && !validation.valid) {
              debugPrint(
                '[AgentValidation] after_repair='
                '${validation.errors.join(' | ')}',
              );
            }
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
      noteTruncation(analysis);
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

      final allowedTerms = _allowedJapaneseTerms(evidence, quotes);

      // F1b: check only human-readable fields. A single repair may translate
      // them; a failed or still-mismatched repair keeps the result and warns.
      if (analysis != null && validation != null && validation.displayable) {
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
                rawOutput: raw,
                mismatchedFields: languageCheck.mismatchedFields,
              ),
              cancellation,
              onTelemetry: telemetry.record,
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

      // A language-repair response is parsed through the same capped parser.
      noteTruncation(analysis);
      if (analysis == null || validation == null || !validation.displayable) {
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
          if (kDebugMode) {
            debugPrint('[AgentSalvage] errors=${errors.join(' | ')}');
          }
          if (languageValidator
              .check(
                salvaged.analysis,
                request.responseLanguage,
                allowedJapaneseTerms: allowedTerms,
              )
              .isMismatch) {
            warnings.add(agentLanguageWarning(uiLanguage));
          }
          checkCancelled();
          noteTruncation(salvaged.analysis);
          final salvageStats = _contentCitationStats(evidence);
          var result = _buildResult(
            envelope: envelope,
            evidence: evidence,
            quotes: quotes,
            analysis: salvaged.analysis,
            validation: AgentValidationResult(
              valid: false,
              usable: _hasUsableAnalysis(salvaged.analysis),
              errors: errors,
              citationsUsed: salvageValidation.citationsUsed,
            ),
            profiles: profiles,
            profileWarnings: profileWarnings,
            unavailableProfiles: unavailableProfiles,
            warnings: warnings,
            coverageFallbackUsed: coverageFallbackUsed,
            telemetry: telemetry.build(
              elapsedMs: runWatch.elapsedMilliseconds,
              citationCount: evidence.citations.length,
              adoptedCitationCount: salvageValidation.citationsUsed.length,
              targetsWithCitations: salvageStats.cited,
              targetCount: salvageStats.total,
            ),
          );
          // A validation failure must not disable display formatting. The
          // salvaged result is still user-visible, so run the same rich-text
          // pass here; otherwise every reading stays as plain parentheses and
          // no BOLD/UNDERLINE is rendered.
          result = await _formatResultRichText(
            result: result,
            llm: llm,
            model: smallModel,
            cancellation: cancellation,
            onRichTextReady: onRichTextReady,
            onRichTextFormattingChanged: onRichTextFormattingChanged,
            notify: notify,
            uiLanguage: uiLanguage,
            responseLanguage: request.responseLanguage,
            telemetry: telemetry,
          );
          _timing(
            'result_ready salvage=true elapsed=${runWatch.elapsedMilliseconds}ms',
          );
          runSucceeded = true;
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

      checkCancelled();
      final finalStats = _contentCitationStats(evidence);
      var result = _buildResult(
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
        telemetry: telemetry.build(
          elapsedMs: runWatch.elapsedMilliseconds,
          citationCount: evidence.citations.length,
          adoptedCitationCount: validation.citationsUsed.length,
          targetsWithCitations: finalStats.cited,
          targetCount: finalStats.total,
        ),
      );
      result = await _formatResultRichText(
        result: result,
        llm: llm,
        model: smallModel,
        cancellation: cancellation,
        onRichTextReady: onRichTextReady,
        onRichTextFormattingChanged: onRichTextFormattingChanged,
        notify: notify,
        uiLanguage: uiLanguage,
        responseLanguage: request.responseLanguage,
        telemetry: telemetry,
      );
      checkCancelled();
      notify(AgentStage.done, agentStageMessage(AgentStage.done, uiLanguage));
      _timing(
        'result_ready salvage=false elapsed=${runWatch.elapsedMilliseconds}ms',
      );
      runSucceeded = true;
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
    } finally {
      final deferred = deferredProfileDictionaries;
      final familiarizer = dictionaryFamiliarizer;
      if (runSucceeded &&
          deferred.isNotEmpty &&
          familiarizer != null &&
          cancellation?.isCancelled != true) {
        // Start only after the analysis path has finished so profile sampling
        // and the profile model call never compete with the user's answer.
        final work = _generateProfilesInBackground(
          familiarizer: familiarizer,
          dictionaries: deferred,
          request: request,
          onProfilesGenerated: onProfilesGenerated,
          onProfile: onProfile,
        );
        // The controller keeps the foreground service alive until this future
        // completes, so switching apps cannot suspend profile generation.
        onBackgroundProfiles?.call(work);
        unawaited(work);
      }
    }
  }

  Future<void> _generateProfilesInBackground({
    required DictionaryFamiliarizationService familiarizer,
    required List<DictionaryInfo> dictionaries,
    required AgentRunRequest request,
    required AgentProfileReviewCallback? onProfilesGenerated,
    required ProfileConfirmationCallback? onProfile,
  }) async {
    try {
      final generation = await familiarizer.generateMany(
        dictionaries,
        runId: request.runId,
      );
      final proposals = generation.proposals;
      if (proposals.isEmpty) return;
      if (onProfilesGenerated != null) {
        // The app inbox enqueues synchronously and then waits for decisions.
        // This future intentionally lives beyond the run.
        await onProfilesGenerated(request.runId, proposals);
        return;
      }
      if (onProfile == null) return;
      for (final proposal in proposals) {
        try {
          final decision = await onProfile(proposal.profile, proposal.markdown);
          await familiarizer.persistDecision(
            proposal,
            decision.action,
            decision.markdown,
            profile: decision.profile,
          );
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '[AgentFamiliarization] background decision failed '
              '(${error.runtimeType})',
            );
          }
        }
      }
    } catch (error) {
      // Profile generation is an aid; a background failure never affects the
      // already-delivered result.
      if (kDebugMode) {
        debugPrint(
          '[AgentFamiliarization] background generation failed '
          '(${error.runtimeType})',
        );
      }
    }
  }

  /// Applies display-only formatting to an already-built result.
  ///
  /// This is shared by the normal path and the salvage path. A validation
  /// failure must not disable formatting: salvaged results are still shown to
  /// the user, so their detailed original/segments/notes need the same RUBY,
  /// BOLD and UNDERLINE pass. With an async callback the result is returned
  /// immediately and the controller applies the tags when they arrive.
  Future<AgentRunResult> _formatResultRichText({
    required AgentRunResult result,
    required LlmPort llm,
    required String model,
    required AgentCancellation? cancellation,
    required AgentRichTextCallback? onRichTextReady,
    required AgentRichTextFormattingCallback? onRichTextFormattingChanged,
    required void Function(AgentStage stage, String message) notify,
    required AgentUiLanguage uiLanguage,
    required AgentResponseLanguage responseLanguage,
    required _RunTelemetryBuilder telemetry,
  }) async {
    if (!limits.enableRichTextPostProcess) return result;
    final originalSource = agentOriginalSource(result.quotes);
    final segmentSources = <String>[
      for (final segment in result.analysis.segments) segment.interpretation,
    ];
    final hasFormattingSources =
        originalSource.isNotEmpty ||
        segmentSources.any((text) => text.isNotEmpty);
    if (!hasFormattingSources) return result;

    Future<AgentRichTextOutputs?> format() => _formatRichText(
      llm: llm,
      model: model,
      responseLanguage: responseLanguage,
      originalSource: originalSource,
      segmentSources: segmentSources,
      cancellation: cancellation,
      telemetry: telemetry,
    );

    final richCallback = onRichTextReady;
    if (richCallback != null) {
      onRichTextFormattingChanged?.call(true);
      Future<void> applyLater() async {
        try {
          final outputs = await format();
          if (outputs != null && cancellation?.isCancelled != true) {
            richCallback(outputs);
          }
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '[AgentRichText] async formatting failed '
              '(${error.runtimeType}); keeping plain text',
            );
          }
        } finally {
          onRichTextFormattingChanged?.call(false);
        }
      }

      unawaited(applyLater());
      return result;
    }

    notify(
      AgentStage.formatting,
      agentStageMessage(AgentStage.formatting, uiLanguage),
    );
    onRichTextFormattingChanged?.call(true);
    try {
      final outputs = await format();
      if (outputs == null) return result;
      final updated = result.copyWithRichText(outputs);
      return updated.copyWithTelemetry(
        updated.telemetry.copyWith(
          llmCalls: updated.telemetry.llmCalls + outputs.formattingCalls,
          formattingCalls:
              updated.telemetry.formattingCalls + outputs.formattingCalls,
          formattingAcceptedSections:
              updated.telemetry.formattingAcceptedSections +
              outputs.acceptedSections,
          formattingRejectedSections:
              updated.telemetry.formattingRejectedSections +
              outputs.rejectedSections,
          formattingRepairedSections:
              updated.telemetry.formattingRepairedSections +
              outputs.repairedSections,
        ),
      );
    } finally {
      onRichTextFormattingChanged?.call(false);
    }
  }

  /// Formats the original section and all sentence interpretations in one
  /// batched request. Dictionary notes are intentionally excluded: their
  /// readings come from local `word[YOMI]reading[/YOMI]` /
  /// `reading【surface】` conversion, so they never consume a provider call.
  Future<AgentRichTextOutputs?> _formatRichText({
    required LlmPort llm,
    required String model,
    required AgentResponseLanguage responseLanguage,
    required String originalSource,
    required List<String> segmentSources,
    required AgentCancellation? cancellation,
    required _RunTelemetryBuilder telemetry,
  }) async {
    final sectionIds = <String>[];
    final sectionTexts = <String>[];
    if (originalSource.isNotEmpty) {
      sectionIds.add('original');
      sectionTexts.add(originalSource);
    }
    for (var index = 0; index < segmentSources.length; index++) {
      final source = segmentSources[index];
      if (source.isEmpty) continue;
      sectionIds.add('segment-$index');
      sectionTexts.add(source);
    }
    if (sectionTexts.isEmpty) return null;
    final results =
        await RichTextPostProcessor(
          llm: llm,
          model: model,
          responseLanguage: responseLanguage,
          onCall: telemetry.recordFormatting,
        ).processSections(
          sectionIds,
          sectionTexts,
          cancellation: cancellation,
          maxChars: limits.maxRichTextChars,
        );

    var cursor = 0;
    String? richOriginalText;
    if (originalSource.isNotEmpty) {
      final rich = results[cursor++];
      richOriginalText = rich.taggedText;
      _logRichText('original', originalSource, rich);
    }
    final outputs = <String>[];
    for (var index = 0; index < segmentSources.length; index++) {
      final source = segmentSources[index];
      if (source.isEmpty) {
        outputs.add('');
      } else {
        final rich = results[cursor++];
        outputs.add(rich.taggedText ?? '');
        _logRichText('segment', source, rich);
      }
    }
    final totalChars = sectionTexts.fold<int>(
      0,
      (sum, text) => sum + text.length,
    );
    final accepted = results.where((result) => result.accepted).length;
    return AgentRichTextOutputs(
      originalText: richOriginalText,
      segmentTexts: outputs,
      formattingCalls: totalChars <= limits.maxRichTextChars ? 1 : 0,
      acceptedSections: accepted,
      rejectedSections: results.length - accepted,
      repairedSections: results
          .where(
            (result) =>
                result.accepted && result.rejectionReason == 'tags_repaired',
          )
          .length,
    );
  }

  void _logRichText(
    String label,
    String source,
    RichTextPostProcessResult rich,
  ) {
    if (!kDebugMode) return;
    final tagged = rich.taggedText;
    final tagCount = tagged == null
        ? 0
        : RegExp(r'\[(?:RUBY|BOLD|UNDERLINE)\b').allMatches(tagged).length;
    final rubyCount = tagged == null
        ? 0
        : RegExp(r'\[RUBY=', caseSensitive: false).allMatches(tagged).length;
    final boldCount = tagged == null
        ? 0
        : RegExp(r'\[BOLD\]', caseSensitive: false).allMatches(tagged).length;
    final underlineCount = tagged == null
        ? 0
        : RegExp(
            r'\[UNDERLINE\]',
            caseSensitive: false,
          ).allMatches(tagged).length;
    // True when the final text is exactly what deterministic local conversion
    // would produce. That means the formatting model added no emphasis of its
    // own; `accepted/changed` alone would hide this.
    final localOnly = tagged != null && tagged == localReadingsToRuby(source);
    debugPrint(
      '[AgentRichText] $label '
      'accepted=${tagged != null} '
      'changed=${tagged != null && tagged != source} '
      'tags=$tagCount ruby=$rubyCount bold=$boldCount '
      'underline=$underlineCount local_only=$localOnly '
      'reason=${rich.rejectionReason} '
      'sourceChars=${source.length}',
    );
  }

  Set<String> _allowedJapaneseTerms(
    AgentEvidenceBundle evidence,
    List<AgentQuoteRef> quotes,
  ) {
    return <String>{
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
  }

  bool _shouldFanOut(AgentRunRequest request, AgentEvidenceBundle evidence) {
    if (!limits.enableDictionaryFanOut) return false;
    if (request.dictionaries.length > limits.dictionaryFanOutThreshold) {
      return true;
    }
    var chars = 0;
    for (final source in evidence.sources) {
      chars += source.text.length;
    }
    for (final citation in evidence.citations) {
      chars += citation.snippet.length;
    }
    return chars > limits.dictionaryFanOutEvidenceChars;
  }

  Future<_DictionaryFanOut?> _runDictionaryFanOut({
    required LlmPort llm,
    required String model,
    required AgentRunRequest request,
    required AgentInputEnvelope envelope,
    required AgentEvidenceBundle evidence,
    required List<AgentQuoteRef> quotes,
    required List<String> profiles,
    required String userRequest,
    required AgentIntentHint intentHint,
    required String? expectedSourceId,
    required AgentCancellation? cancellation,
    required AgentUiLanguage uiLanguage,
    required _RunTelemetryBuilder telemetry,
    required void Function() checkCancelled,
  }) async {
    final subsets = <_DictionarySubset>[];
    for (final dictionary in request.dictionaries) {
      final subsetEvidence = evidenceForDictionary(evidence, dictionary.id);
      if (subsetEvidence.citations.isEmpty) continue;
      final dictionaryRefs = envelope.dictionaries
          .where((item) => item.id == dictionary.id)
          .toList(growable: false);
      if (dictionaryRefs.isEmpty) continue;
      subsets.add(
        _DictionarySubset(
          dictionary: dictionary,
          evidence: subsetEvidence,
          input: AgentInputEnvelope(
            sessionId: envelope.sessionId,
            mode: envelope.mode,
            sources: envelope.sources,
            userText: envelope.userText,
            context: envelope.context,
            dictionaries: dictionaryRefs,
          ),
        ),
      );
    }
    if (subsets.length <= 1) return null;

    final results = List<AgentAnalysis?>.filled(subsets.length, null);
    final concurrency = limits.dictionaryFanOutConcurrency
        .clamp(1, subsets.length)
        .toInt();
    var next = 0;
    var partial = false;

    Future<void> worker() async {
      while (true) {
        checkCancelled();
        final index = next++;
        if (index >= subsets.length) return;
        final subset = subsets[index];
        try {
          final raw = await _collect(
            llm,
            buildAnalysisRequest(
              model: model,
              mode: request.mode,
              responseLanguage: request.responseLanguage,
              input: subset.input,
              evidence: subset.evidence,
              quotes: quotes,
              dictionaryProfiles: profiles,
              userRequest: userRequest,
              intentHint: intentHint,
              maxTokenEntries: limits.maxPromptTokenEntries,
              maxProfileCharsPerDictionary: limits.maxProfileCharsPerDictionary,
              maxProfileTotalChars: limits.maxProfileTotalChars,
            ),
            cancellation,
            onTelemetry: telemetry.record,
            label: 'analysis:${subset.dictionary.id}',
          );
          final parsed = _parseAndNormalize(
            raw,
            quotes,
            subset.evidence,
            expectedSourceId: expectedSourceId,
          );
          final analysis = parsed.analysis;
          if (analysis == null || !_hasAnalysisContent(analysis)) {
            partial = true;
            continue;
          }
          results[index] = analysis;
        } on AgentRunFailure catch (error) {
          if (cancellation?.isCancelled == true) rethrow;
          _timing(
            'fan_out_failed dictionary=${subset.dictionary.id} '
            'code=${error.code.wireName}',
          );
          partial = true;
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (var index = 0; index < concurrency; index++) worker(),
    ]);
    final analyses = <AgentAnalysis>[for (final analysis in results) ?analysis];
    if (analyses.isEmpty) return null;
    final merged = mergeDictionaryAnalyses(analyses, limits: limits);
    if (!_hasAnalysisContent(merged) && merged.noAnalysisReason.isEmpty) {
      return null;
    }
    _timing('fan_out merged=${analyses.length} partial=$partial');
    return _DictionaryFanOut(analysis: merged, partial: partial);
  }

  bool _hasAnalysisContent(AgentAnalysis analysis) {
    return analysis.translation.isNotEmpty ||
        analysis.segments.isNotEmpty ||
        analysis.interpretations.isNotEmpty ||
        analysis.unresolved.isNotEmpty ||
        analysis.modelSupplements.isNotEmpty;
  }

  /// Makes a selected-but-unused dictionary visible. Lookup failures already
  /// have their own dictionaryIssues warning; this only covers dictionaries
  /// that were queried successfully but produced no citation (no hit, or the
  /// global citation budget was exhausted before they were reached).
  void _noteDictionariesWithoutEvidence({
    required List<DictionaryInfo> dictionaries,
    required AgentEvidenceBundle evidence,
    required List<String> warnings,
    required AgentUiLanguage uiLanguage,
  }) {
    if (dictionaries.isEmpty) return;
    final cited = <String>{
      for (final citation in evidence.citations) citation.dictionaryId,
    };
    final failed = <String>{
      for (final issue in evidence.dictionaryIssues) issue.dictionaryId,
    };
    final missing = <String>[
      for (final dictionary in dictionaries)
        if (!cited.contains(dictionary.id) && !failed.contains(dictionary.id))
          dictionary.title,
    ];
    if (missing.isEmpty) return;
    final warning = agentDictionaryNoEvidence(uiLanguage, missing);
    if (!warnings.contains(warning)) warnings.add(warning);
  }

  /// Coverage review is useful when at least one lookup target has no hit, or
  /// when the evidence is already at the global cap and verified duplicates
  /// may free slots. If every target already produced a citation and there is
  /// headroom, the extra model round trip rarely changes the answer.
  bool _shouldRunCoverageReview(AgentEvidenceBundle evidence) {
    if (limits.maxCoverageFallback <= 0) return false;
    if (!limits.adaptiveCoverageReview) return true;
    // Only content words drive coverage. Punctuation, particles and other
    // function words used to make every run look under-covered even when all
    // readable words already had dictionary evidence.
    final stats = _contentCitationStats(evidence);
    if (stats.total <= 0) return false;
    final hitRate = stats.cited / stats.total;
    return hitRate < limits.coverageContentHitRateThreshold;
  }

  /// A locally cleaned result is displayable when it still has one complete
  /// user-facing product: a translation, at least one sentence interpretation,
  /// or a standalone NO_ANALYSIS reason. Invalid citations/quotes have already
  /// been removed by [salvageAnalysis], so this is the final usability gate.
  bool _hasUsableAnalysis(AgentAnalysis analysis) {
    if (analysis.noAnalysisReason.trim().isNotEmpty) return true;
    if (analysis.translation.any((item) => item.text.trim().isNotEmpty)) {
      return true;
    }
    return analysis.segments.any(
      (segment) => segment.interpretation.trim().isNotEmpty,
    );
  }

  /// Content-word citation coverage used by coverage review and telemetry.
  /// Counts token occurrences, not every lookup target: particles/punctuation
  /// and grammar-pattern targets are excluded.
  ({int total, int cited}) _contentCitationStats(AgentEvidenceBundle evidence) {
    var total = 0;
    var cited = 0;
    for (final source in evidence.sources) {
      for (final token in source.tokens) {
        if (!token.content) continue;
        total++;
        if (token.citationIds.isNotEmpty) cited++;
      }
    }
    return (total: total, cited: cited);
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
    required _RunTelemetryBuilder telemetry,
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
          maxSnippetChars: limits.coverageSnippetChars,
          maxTokenEntries: limits.maxPromptTokenEntries,
        ),
        cancellation,
        onTelemetry: telemetry.record,
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
            maxSnippetChars: limits.coverageSnippetChars,
            maxTokenEntries: limits.maxPromptTokenEntries,
          ),
          cancellation,
          onTelemetry: telemetry.record,
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
    // Coverage must stay inside this run's effective citation limit. Using the
    // global 60 here let a one-sentence run with a small short-text cap add up
    // to 54 supplementary entries.
    var remainingSlots =
        workingEvidence.budget.maxCitations - workingEvidence.citations.length;
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

    // A sense/usage/example gap is an explicit multi-sense signal, so allow a
    // second entry per dictionary for this targeted follow-up. Word/grammar/
    // reading gaps remain breadth-only.
    final wantsDepth = validated.missing.any(
      (item) =>
          item.kind == AgentCoverageKind.sense ||
          item.kind == AgentCoverageKind.usage ||
          item.kind == AgentCoverageKind.example,
    );
    final supplementary = await evidenceBuilder.lookupExtraQueries(
      queries: <String>[for (final item in validated.missing) item.query],
      dictionaries: request.dictionaries,
      maxNewCitations: remainingSlots,
      perDictionaryLimit: wantsDepth ? 2 : 1,
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
    String? richOriginalText,
    List<String> richSegmentTexts = const <String>[],
    List<String> richSegmentNotes = const <String>[],
    AgentRunTelemetry telemetry = const AgentRunTelemetry(),
  }) {
    // Pre-fill display fields with deterministic local RUBY. The optional
    // formatting model only adds BOLD/UNDERLINE later; it must not be the
    // reason a reading appears as plain `reading【surface】` in the first frame.
    final originalSource = agentOriginalSource(quotes);
    final localOriginalText = originalSource.isEmpty
        ? null
        : localReadingsToRuby(originalSource);
    final localSegmentTexts = <String>[
      for (final segment in analysis.segments)
        localReadingsToRuby(segment.interpretation),
    ];
    final localSegmentNotes = <String>[
      for (final segment in analysis.segments)
        localReadingsToRuby(agentSegmentNotesSource(segment)),
    ];
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
      pitchAccents: evidence.pitchAccents,
      richOriginalText: richOriginalText ?? localOriginalText,
      richSegmentTexts: List<String>.unmodifiable(
        richSegmentTexts.isEmpty ? localSegmentTexts : richSegmentTexts,
      ),
      richSegmentNotes: List<String>.unmodifiable(
        richSegmentNotes.isEmpty ? localSegmentNotes : richSegmentNotes,
      ),
      telemetry: telemetry,
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
    if (validation != null && validation.displayable && formatErrors.isEmpty) {
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
          usable: _hasUsableAnalysis(salvaged.analysis),
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

  /// Compact id list for the format repair prompt. It deliberately omits
  /// quote text, token fields and citation snippets: the repair may only reuse
  /// ids, never re-read the evidence. Token/pattern rows include their linked
  /// citation ids so the repair can fix an attribution error without receiving
  /// the full evidence bundle.
  List<String> _availableIds(
    List<AgentQuoteRef> quotes,
    AgentEvidenceBundle evidence,
  ) {
    final ids = <String>[
      for (final quote in quotes) 'quote ${quote.id}',
      for (final source in evidence.sources)
        for (final token in source.tokens)
          'token ${token.id} citations '
              '${token.citationIds.isEmpty ? '(none)' : token.citationIds.join(',')}',
      for (final pattern in evidence.patterns)
        'pattern ${pattern.id} citations '
            '${pattern.citationIds.isEmpty ? '(none)' : pattern.citationIds.join(',')}',
      for (final citation in evidence.citations) 'citation ${citation.id}',
    ];
    return ids;
  }

  ({AgentAnalysis? analysis, List<String> integrityErrors}) _parseAndNormalize(
    String raw,
    List<AgentQuoteRef> quotes,
    AgentEvidenceBundle evidence, {
    String? expectedSourceId,
  }) {
    final integrityErrors = analysisTagIntegrityErrors(raw);
    final parsed = parseTaggedAnalysis(
      raw,
      sourceId: expectedSourceId ?? '',
      limits: limits,
    );
    if (parsed == null) {
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
    void Function(int accumulatedChars)? onTextDelta,
    void Function(int accumulatedChars)? onReasoningDelta,
    void Function(
      LlmRequest request,
      String label,
      int outputChars,
      int reasoningChars,
      int elapsedMs,
      int httpAttempts,
      int firstTextMs,
      int prefillChars,
    )?
    onTelemetry,
    String label = 'request',
    StreamingTranslationAssembler? translationAssembler,
  }) async {
    final buffer = StringBuffer();
    final reasoning = StringBuffer();
    final watch = Stopwatch()..start();
    if (kDebugMode) {
      final promptChars = request.messages.fold<int>(
        0,
        (sum, message) => sum + message.text.length,
      );
      debugPrint(
        '[AgentPromptBudget] label=$label model=${request.model} '
        'messages=${request.messages.length} chars=$promptChars '
        'stream=${request.stream}',
      );
    }
    var firstEventAt = -1;
    var firstTextAt = -1;
    var httpAttempts = 0;
    var prefillChars = 0;
    final reconnectAttempts = limits.streamReconnectAttempts < 0
        ? 0
        : limits.streamReconnectAttempts;
    final maxAttempts = 1 + reconnectAttempts;
    final observedBase = request.copyWith(
      onHttpAttempt: (attempt, retry) => httpAttempts++,
    );

    // The tagged protocol is line-oriented. Drop an incomplete trailing line
    // before a continuation so the model re-emits it instead of duplicating
    // it after the resumed prefix.
    void trimToContinuationBoundary() {
      final text = buffer.toString();
      final newline = text.lastIndexOf('\n');
      if (newline < 0) {
        buffer.clear();
      } else if (newline + 1 < text.length) {
        final safe = text.substring(0, newline + 1);
        buffer.clear();
        buffer.write(safe);
      }
      translationAssembler?.reset(buffer.toString());
      onTextDelta?.call(buffer.length);
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        final delayMs = limits.streamReconnectDelayMs * attempt;
        if (delayMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
        if (cancellation?.isCancelled == true) {
          throw const AgentRunFailure(
            stage: AgentStage.reasoning,
            code: AgentToolErrorCode.toolCancelled,
            message: '已取消',
          );
        }
      }
      final attemptRequest = attempt == 0 || buffer.isEmpty
          ? observedBase
          : buildStreamContinuationRequest(observedBase, buffer.toString());
      final attemptChars = attemptRequest.messages.fold<int>(
        0,
        (sum, message) => sum + message.text.length,
      );
      var finished = false;
      final attemptStartChars = buffer.length;
      final attemptsBefore = httpAttempts;
      try {
        await for (final event in llm.stream(
          attemptRequest,
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
              if (firstTextAt < 0) firstTextAt = watch.elapsedMilliseconds;
              buffer.write(event.text);
              translationAssembler?.add(event.text);
              // Only the accumulated length is published. Converting the
              // whole buffer to a String on every delta is O(n²) for
              // reasoning models that emit thousands of tiny events, and the
              // UI never renders the raw tagged stream.
              onTextDelta?.call(buffer.length);
            case LlmEventType.reasoningDelta:
              reasoning.write(event.text);
              onReasoningDelta?.call(reasoning.length);
            case LlmEventType.error:
              throw AgentRunFailure(
                stage: AgentStage.reasoning,
                code: AgentToolErrorCode.providerUnavailable,
                message: '模型服务返回错误',
                detail: _debugHead(reasoning.toString()),
              );
            case LlmEventType.done:
              // `done` is terminal. Breaking here also cancels the provider's
              // SSE subscription, so a keep-alive socket cannot hide the
              // result.
              finished = true;
          }
          if (finished) break;
        }
      } on AgentRunFailure catch (error) {
        if (cancellation?.isCancelled == true) rethrow;
        if (!_isReconnectable(error)) rethrow;
        if (attempt == maxAttempts - 1) {
          // Reconnect is exhausted. A usable prefix is more valuable than a
          // failed run: let the normal parser/salvage decide whether it can
          // still show a partial result.
          if (buffer.isNotEmpty) break;
          rethrow;
        }
        trimToContinuationBoundary();
        if (kDebugMode) {
          debugPrint(
            '[AgentReconnect] label=$label attempt=$attempt '
            'code=${error.code.wireName} chars=${buffer.length}',
          );
        }
        continue;
      } on AgentCapabilityException catch (error) {
        if (cancellation?.isCancelled == true) {
          throw const AgentRunFailure(
            stage: AgentStage.reasoning,
            code: AgentToolErrorCode.toolCancelled,
            message: '已取消',
          );
        }
        if (!_isReconnectable(error)) rethrow;
        if (attempt == maxAttempts - 1) {
          if (buffer.isNotEmpty) break;
          rethrow;
        }
        trimToContinuationBoundary();
        if (kDebugMode) {
          debugPrint(
            '[AgentReconnect] label=$label attempt=$attempt '
            'code=${error.code.wireName} chars=${buffer.length}',
          );
        }
        continue;
      }
      // Fakes and adapters that do not report HTTP attempts still count as
      // one request per stream attempt. Real providers report each retry via
      // LlmRequest.onHttpAttempt.
      if (httpAttempts == attemptsBefore) httpAttempts++;
      final attemptHttp = httpAttempts - attemptsBefore;
      prefillChars += attemptChars * (attemptHttp > 0 ? attemptHttp : 1);
      if (kDebugMode) {
        debugPrint(
          '[AgentTiming] stream label=$label attempt=$attempt '
          'first_event=${firstEventAt}ms end=${watch.elapsedMilliseconds}ms '
          'chars=${buffer.length - attemptStartChars} '
          'total_chars=${buffer.length} reasoning=${reasoning.length} '
          'done=$finished cancelled=${cancellation?.isCancelled == true}',
        );
      }
      if (finished || buffer.isEmpty || attempt == maxAttempts - 1) break;
      // The provider closed the stream without a terminal event. Keep the
      // complete prefix and ask for the missing suffix once.
      trimToContinuationBoundary();
      if (kDebugMode) {
        debugPrint(
          '[AgentReconnect] label=$label attempt=$attempt '
          'stream ended without done; chars=${buffer.length}',
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
    translationAssembler?.flush();
    // Tail flush: the controller may have throttled the last delta. Emitting
    // the final accumulated length here guarantees the progress counter is
    // complete before validation starts.
    onTextDelta?.call(buffer.length);
    onReasoningDelta?.call(reasoning.length);
    onTelemetry?.call(
      request,
      label,
      buffer.length,
      reasoning.length,
      watch.elapsedMilliseconds,
      httpAttempts,
      firstTextAt,
      prefillChars,
    );
    return buffer.toString();
  }

  bool _isReconnectable(Object error) {
    final code = switch (error) {
      AgentRunFailure failure => failure.code,
      AgentCapabilityException failure => failure.code,
      _ => null,
    };
    return switch (code) {
      AgentToolErrorCode.providerUnavailable ||
      AgentToolErrorCode.providerRateLimited ||
      AgentToolErrorCode.toolTimeout => true,
      _ => false,
    };
  }
}

class _DictionarySubset {
  const _DictionarySubset({
    required this.dictionary,
    required this.evidence,
    required this.input,
  });

  final DictionaryInfo dictionary;
  final AgentEvidenceBundle evidence;
  final AgentInputEnvelope input;
}

class _DictionaryFanOut {
  const _DictionaryFanOut({required this.analysis, required this.partial});

  final AgentAnalysis analysis;
  final bool partial;
}

class _RunTelemetryBuilder {
  int llmCalls = 0;
  int analysisCalls = 0;
  int coverageCalls = 0;
  int repairCalls = 0;
  int languageRepairCalls = 0;
  int formattingCalls = 0;
  int inputChars = 0;
  int outputChars = 0;
  int reasoningChars = 0;
  int llmElapsedMs = 0;
  int httpAttempts = 0;
  int analysisTtftMs = 0;
  int analysisPrefillChars = 0;

  void record(
    LlmRequest request,
    String label,
    int outputChars,
    int reasoningChars,
    int elapsedMs,
    int httpAttempts,
    int firstTextMs,
    int prefillChars,
  ) {
    llmCalls++;
    this.httpAttempts += httpAttempts;
    inputChars += request.messages.fold<int>(
      0,
      (sum, message) => sum + message.text.length,
    );
    this.outputChars += outputChars;
    this.reasoningChars += reasoningChars;
    llmElapsedMs += elapsedMs;
    if (label == 'analysis' || label.startsWith('analysis:')) {
      analysisCalls++;
      analysisPrefillChars += prefillChars;
      if (firstTextMs >= 0 &&
          (analysisTtftMs == 0 || firstTextMs < analysisTtftMs)) {
        analysisTtftMs = firstTextMs;
      }
    }
    if (label == 'coverage' || label == 'coverage_repair') coverageCalls++;
    if (label == 'analysis_repair') repairCalls++;
    if (label == 'language_repair') languageRepairCalls++;
  }

  void recordFormatting(LlmRequest request, int outputChars, int elapsedMs) {
    llmCalls++;
    formattingCalls++;
    inputChars += request.messages.fold<int>(
      0,
      (sum, message) => sum + message.text.length,
    );
    this.outputChars += outputChars;
    llmElapsedMs += elapsedMs;
  }

  AgentRunTelemetry build({
    required int elapsedMs,
    required int citationCount,
    required int adoptedCitationCount,
    required int targetsWithCitations,
    required int targetCount,
  }) {
    final telemetry = AgentRunTelemetry(
      llmCalls: llmCalls,
      analysisCalls: analysisCalls,
      coverageCalls: coverageCalls,
      repairCalls: repairCalls,
      languageRepairCalls: languageRepairCalls,
      formattingCalls: formattingCalls,
      inputChars: inputChars,
      outputChars: outputChars,
      reasoningChars: reasoningChars,
      llmElapsedMs: llmElapsedMs,
      elapsedMs: elapsedMs,
      citationCount: citationCount,
      adoptedCitationCount: adoptedCitationCount,
      targetsWithCitations: targetsWithCitations,
      targetCount: targetCount,
      httpAttempts: httpAttempts,
      analysisTtftMs: analysisTtftMs,
      analysisPrefillChars: analysisPrefillChars,
    );
    if (kDebugMode) {
      debugPrint(
        '[AgentTelemetry] llm=${telemetry.llmCalls} http=${telemetry.httpAttempts} '
        'prefill=${telemetry.analysisPrefillChars} '
        'ttft=${telemetry.analysisTtftMs}ms '
        'elapsed=${telemetry.elapsedMs}ms '
        'citations=${telemetry.citationCount}/${telemetry.adoptedCitationCount} '
        'contentTargets=${telemetry.targetsWithCitations}/${telemetry.targetCount}',
      );
    }
    return telemetry;
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
