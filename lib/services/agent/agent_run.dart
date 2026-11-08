import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_json.dart';
import '../../core/models/agent/agent_limits.dart';
import '../../core/models/agent/agent_ocr.dart';
import '../../core/models/agent/agent_pitch.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/models/dict_info.dart';
import '../../core/utils/rich_text_tags.dart';
import 'agent_validator.dart';
import 'ports/llm_port.dart';
import 'familiarization/dictionary_familiarization_service.dart'
    show AgentProfileProposal, DictionaryProfileIssue, ProfileConfirmation;

enum AgentStage {
  prepare,
  ocr,
  familiarizing,
  awaitingProfile,
  tokenizing,
  evidence,
  coverage,
  reasoning,
  validating,
  formatting,
  done,
  error,
  cancelled,
}

class AgentImageInput {
  const AgentImageInput({
    required this.id,
    required this.localPath,
    this.mode = OcrMode.auto,
    this.variants = const <AgentOcrVariant>[],
    this.selectedVariantId,
  });

  final String id;
  final String localPath;
  final OcrMode mode;

  /// OCR variants already produced locally. When non-empty, the orchestrator
  /// reuses them instead of running OCR again; this is how P6.6 variant
  /// selection re-analyzes without repeating recognition.
  final List<AgentOcrVariant> variants;
  final String? selectedVariantId;
}

class AgentRunRequest {
  const AgentRunRequest({
    required this.sessionId,
    this.runId = '',
    required this.mode,
    required this.dictionaries,
    required this.provider,
    this.userText = '',
    this.context = '',
    this.images = const <AgentImageInput>[],
    this.allowFamiliarization = true,
    this.pendingProfileDictionaryIds = const <String>{},
    this.unidicPath = '',
    this.responseLanguage = AgentResponseLanguage.chinese,
  });

  final String sessionId;

  /// Internal run identity used by the app-level profile inbox.
  final String runId;
  final AgentMode mode;
  final List<DictionaryInfo> dictionaries;
  final AgentProviderConfig provider;
  final String userText;
  final String context;
  final List<AgentImageInput> images;
  final bool allowFamiliarization;

  /// Dictionary ids whose generated profile is already waiting in the app
  /// inbox. The current run uses noProfileInstruction and does not regenerate
  /// them; the next run reuses the confirmed profile.
  final Set<String> pendingProfileDictionaryIds;
  final String unidicPath;
  final AgentResponseLanguage responseLanguage;
}

/// Display-only rich-text output for one completed analysis.
///
/// This is separate from [AgentRunResult] so the core result can be returned
/// before optional formatting finishes; the controller applies these fields
/// when they arrive.
class AgentRichTextOutputs {
  const AgentRichTextOutputs({
    this.originalText,
    this.segmentTexts = const <String>[],
    this.segmentNotes = const <String>[],
    this.formattingCalls = 0,
  });

  final String? originalText;
  final List<String> segmentTexts;
  final List<String> segmentNotes;

  /// One for a batched formatting request, zero when the local fallback was
  /// used without contacting the provider.
  final int formattingCalls;
}

/// Per-run, content-free execution telemetry.
///
/// Provider usage is not exposed by every provider, so character counts are
/// recorded as the budget proxy; no prompt text, citation snippet, path or key
/// enters this object.
class AgentRunTelemetry {
  const AgentRunTelemetry({
    this.llmCalls = 0,
    this.analysisCalls = 0,
    this.coverageCalls = 0,
    this.repairCalls = 0,
    this.languageRepairCalls = 0,
    this.formattingCalls = 0,
    this.inputChars = 0,
    this.outputChars = 0,
    this.reasoningChars = 0,
    this.llmElapsedMs = 0,
    this.elapsedMs = 0,
    this.citationCount = 0,
    this.adoptedCitationCount = 0,
    this.targetsWithCitations = 0,
    this.targetCount = 0,
    this.httpAttempts = 0,
    this.analysisTtftMs = 0,
    this.analysisPrefillChars = 0,
  });

  final int llmCalls;
  final int analysisCalls;
  final int coverageCalls;
  final int repairCalls;
  final int languageRepairCalls;

  /// Rich-text display-formatting requests. These are included in [llmCalls]
  /// so it remains the total provider call count.
  final int formattingCalls;
  final int inputChars;
  final int outputChars;
  final int reasoningChars;
  final int llmElapsedMs;
  final int elapsedMs;
  final int citationCount;
  final int adoptedCitationCount;
  final int targetsWithCitations;
  final int targetCount;

  /// Actual provider HTTP attempts, including provider retries and stream
  /// reconnects. Unlike [llmCalls] (one per orchestrator request), this is the
  /// number of network round trips.
  final int httpAttempts;

  /// Main-analysis time to first text delta, including any reconnect attempts.
  final int analysisTtftMs;

  /// Actual prompt characters sent for main analysis, including continuation
  /// requests after a reconnect.
  final int analysisPrefillChars;

  AgentRunTelemetry copyWith({
    int? llmCalls,
    int? formattingCalls,
    int? inputChars,
    int? outputChars,
    int? llmElapsedMs,
  }) {
    return AgentRunTelemetry(
      llmCalls: llmCalls ?? this.llmCalls,
      analysisCalls: analysisCalls,
      coverageCalls: coverageCalls,
      repairCalls: repairCalls,
      languageRepairCalls: languageRepairCalls,
      formattingCalls: formattingCalls ?? this.formattingCalls,
      inputChars: inputChars ?? this.inputChars,
      outputChars: outputChars ?? this.outputChars,
      reasoningChars: reasoningChars,
      llmElapsedMs: llmElapsedMs ?? this.llmElapsedMs,
      elapsedMs: elapsedMs,
      citationCount: citationCount,
      adoptedCitationCount: adoptedCitationCount,
      targetsWithCitations: targetsWithCitations,
      targetCount: targetCount,
      httpAttempts: httpAttempts,
      analysisTtftMs: analysisTtftMs,
      analysisPrefillChars: analysisPrefillChars,
    );
  }

  /// Content-word targets that received at least one citation, divided by
  /// content-word targets. Particles, punctuation and grammar patterns are
  /// excluded.
  double get citationCoverage =>
      targetCount == 0 ? 0 : targetsWithCitations / targetCount;

  /// Format-repair calls divided by main analysis calls.
  double get repairRate => analysisCalls == 0 ? 0 : repairCalls / analysisCalls;

  Map<String, Object?> toJson() => <String, Object?>{
    'llm_calls': llmCalls,
    'analysis_calls': analysisCalls,
    'coverage_calls': coverageCalls,
    'repair_calls': repairCalls,
    'language_repair_calls': languageRepairCalls,
    'formatting_calls': formattingCalls,
    'input_chars': inputChars,
    'output_chars': outputChars,
    'reasoning_chars': reasoningChars,
    'llm_elapsed_ms': llmElapsedMs,
    'elapsed_ms': elapsedMs,
    'citation_count': citationCount,
    'adopted_citation_count': adoptedCitationCount,
    'targets_with_citations': targetsWithCitations,
    'target_count': targetCount,
    'http_attempts': httpAttempts,
    'analysis_ttft_ms': analysisTtftMs,
    'analysis_prefill_chars': analysisPrefillChars,
  };

  factory AgentRunTelemetry.fromJson(Map<String, Object?> json) {
    return AgentRunTelemetry(
      llmCalls: agentInt(json['llm_calls']),
      analysisCalls: agentInt(json['analysis_calls']),
      coverageCalls: agentInt(json['coverage_calls']),
      repairCalls: agentInt(json['repair_calls']),
      languageRepairCalls: agentInt(json['language_repair_calls']),
      formattingCalls: agentInt(json['formatting_calls']),
      inputChars: agentInt(json['input_chars']),
      outputChars: agentInt(json['output_chars']),
      reasoningChars: agentInt(json['reasoning_chars']),
      llmElapsedMs: agentInt(json['llm_elapsed_ms']),
      elapsedMs: agentInt(json['elapsed_ms']),
      citationCount: agentInt(json['citation_count']),
      adoptedCitationCount: agentInt(json['adopted_citation_count']),
      targetsWithCitations: agentInt(json['targets_with_citations']),
      targetCount: agentInt(json['target_count']),
      httpAttempts: agentInt(json['http_attempts']),
      analysisTtftMs: agentInt(json['analysis_ttft_ms']),
      analysisPrefillChars: agentInt(json['analysis_prefill_chars']),
    );
  }
}

class AgentRunResult {
  const AgentRunResult({
    required this.input,
    required this.evidence,
    required this.quotes,
    required this.analysis,
    required this.validation,
    required this.sources,
    required this.dictionaryProfiles,
    this.profileWarnings = const <String>[],
    this.unavailableProfiles = const <DictionaryProfileIssue>[],
    this.warnings = const <String>[],
    this.coverageFallbackUsed = false,
    this.ocrQuality = const <String, OcrQuality>{},
    this.pitchAccents = const <String, AgentPitchAccent>{},
    this.richOriginalText,
    this.richSegmentTexts = const <String>[],
    this.richSegmentNotes = const <String>[],
    this.telemetry = const AgentRunTelemetry(),
  });

  final AgentInputEnvelope input;
  final AgentEvidenceBundle evidence;
  final List<AgentQuoteRef> quotes;
  final AgentAnalysis analysis;
  final AgentValidationResult validation;
  final List<AgentSourceVersion> sources;
  final List<String> dictionaryProfiles;
  final List<String> profileWarnings;
  final List<DictionaryProfileIssue> unavailableProfiles;

  /// Non-fatal run warnings (language post-check, coverage review, etc.).
  final List<String> warnings;

  /// True when the one allowed coverage-review supplementary lookup ran.
  final bool coverageFallbackUsed;

  /// Local OCR quality for the selected variant of each image source, keyed by
  /// the opaque image id. Never serialized or sent to the provider.
  final Map<String, OcrQuality> ocrQuality;

  /// Local UniDic pitch data keyed by token id. Omitted from provider input;
  /// persisted only in the local history result codec.
  final Map<String, AgentPitchAccent> pitchAccents;

  /// Optional AI-formatted version of the whole “原文” section. It is accepted
  /// only when its stripped form reproduces the combined quote source exactly.
  /// This is intentionally section-level, not a field on each quote.
  final String? richOriginalText;

  /// AI-formatted versions of segment interpretations, aligned with
  /// [analysis.segments]. Empty entries mean “use the plain interpretation”.
  final List<String> richSegmentTexts;

  /// AI-formatted dictionary-fact explanations (word senses and grammar
  /// explanations), aligned with [analysis.segments]. Empty entries mean
  /// “render the plain note lines”.
  final List<String> richSegmentNotes;

  /// Content-free call/latency/citation stats for this run.
  final AgentRunTelemetry telemetry;

  List<AgentCitation> get citations => evidence.citations;

  /// Citations referenced by validated claims. When validation reports no used
  /// ids, all retrieved citations remain visible (the loose-mode fallback).
  List<AgentCitation> get adoptedCitations {
    final usedIds = validation.citationsUsed.toSet();
    if (usedIds.isEmpty) return citations;
    return citations
        .where((citation) => usedIds.contains(citation.id))
        .toList(growable: false);
  }

  /// Returns a copy with display-only formatting applied. Core analysis,
  /// validation, citations and warnings are unchanged.
  ///
  /// Sections the formatter rejected or returned empty keep the local RUBY
  /// baseline built with the result; a failed network pass must not downgrade
  /// a reading back to plain bracket text.
  AgentRunResult copyWithRichText(AgentRichTextOutputs rich) {
    final original = rich.originalText;
    return AgentRunResult(
      input: input,
      evidence: evidence,
      quotes: quotes,
      analysis: analysis,
      validation: validation,
      sources: sources,
      dictionaryProfiles: dictionaryProfiles,
      profileWarnings: profileWarnings,
      unavailableProfiles: unavailableProfiles,
      warnings: warnings,
      coverageFallbackUsed: coverageFallbackUsed,
      ocrQuality: ocrQuality,
      pitchAccents: pitchAccents,
      richOriginalText: original != null && original.isNotEmpty
          ? original
          : richOriginalText,
      richSegmentTexts: _mergeRichTextSections(
        richSegmentTexts,
        rich.segmentTexts,
      ),
      richSegmentNotes: _mergeRichTextSections(
        richSegmentNotes,
        rich.segmentNotes,
      ),
      telemetry: telemetry,
    );
  }

  /// Returns a copy with a refreshed content-free telemetry snapshot, used
  /// after an asynchronous display-formatting call completes.
  AgentRunResult copyWithTelemetry(AgentRunTelemetry telemetry) {
    return AgentRunResult(
      input: input,
      evidence: evidence,
      quotes: quotes,
      analysis: analysis,
      validation: validation,
      sources: sources,
      dictionaryProfiles: dictionaryProfiles,
      profileWarnings: profileWarnings,
      unavailableProfiles: unavailableProfiles,
      warnings: warnings,
      coverageFallbackUsed: coverageFallbackUsed,
      ocrQuality: ocrQuality,
      pitchAccents: pitchAccents,
      richOriginalText: richOriginalText,
      richSegmentTexts: richSegmentTexts,
      richSegmentNotes: richSegmentNotes,
      telemetry: telemetry,
    );
  }

  static List<String> _mergeRichTextSections(
    List<String> current,
    List<String> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final length = incoming.length > current.length
        ? incoming.length
        : current.length;
    return List<String>.unmodifiable(<String>[
      for (var index = 0; index < length; index++)
        if (index < incoming.length && incoming[index].isNotEmpty)
          incoming[index]
        else if (index < current.length)
          current[index]
        else
          '',
    ]);
  }

  static const String resultSchema = 'rikai.agent.run-result.v1';

  /// Local history codec. This is deliberately separate from the provider
  /// wire format: it persists already-validated structured data and never
  /// includes image paths, request bodies or API keys.
  Map<String, Object?> toJson() => <String, Object?>{
    'schema': resultSchema,
    'input': input.toJson(),
    'evidence': evidence.toJson(),
    'quotes': quotes.map((quote) => quote.toJson()).toList(),
    'analysis': analysis.toJson(),
    'validation': validation.toJson(),
    'sources': sources.map((source) => source.toJson()).toList(),
    'dictionary_profiles': dictionaryProfiles,
    'profile_warnings': profileWarnings,
    'unavailable_profiles': unavailableProfiles
        .map((issue) => issue.toJson())
        .toList(),
    'warnings': warnings,
    'coverage_fallback_used': coverageFallbackUsed,
    'ocr_quality': ocrQuality.map(
      (imageId, quality) => MapEntry(imageId, quality.toJson()),
    ),
    'pitch_accents': pitchAccents.map(
      (tokenId, accent) => MapEntry(tokenId, accent.toJson()),
    ),
    if (richOriginalText != null) 'rich_original_text': richOriginalText,
    'rich_segment_texts': richSegmentTexts,
    'rich_segment_notes': richSegmentNotes,
    'telemetry': telemetry.toJson(),
  };

  factory AgentRunResult.fromJson(Map<String, Object?> json) {
    final rawQuotes = json['quotes'];
    final rawSources = json['sources'];
    final rawUnavailable = json['unavailable_profiles'];
    return AgentRunResult(
      input: AgentInputEnvelope.fromJson(agentMap(json['input'])),
      evidence: AgentEvidenceBundle.fromJson(agentMap(json['evidence'])),
      quotes: rawQuotes is List
          ? rawQuotes
                .whereType<Map>()
                .map(
                  (value) => AgentQuoteRef.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentQuoteRef>[],
      analysis: AgentAnalysis.fromJson(agentMap(json['analysis'])),
      validation: AgentValidationResult.fromJson(agentMap(json['validation'])),
      sources: rawSources is List
          ? rawSources
                .whereType<Map>()
                .map(
                  (value) => AgentSourceVersion.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .toList(growable: false)
          : const <AgentSourceVersion>[],
      dictionaryProfiles: agentStringList(json['dictionary_profiles']),
      profileWarnings: agentStringList(json['profile_warnings']),
      unavailableProfiles: rawUnavailable is List
          ? rawUnavailable
                .whereType<Map>()
                .map((value) {
                  final map = value.map(
                    (key, item) => MapEntry(key.toString(), item),
                  );
                  return DictionaryProfileIssue(
                    dictionaryId: agentString(map['dictionary_id']),
                    title: agentString(map['title']),
                    reason: agentString(map['reason']),
                  );
                })
                .toList(growable: false)
          : const <DictionaryProfileIssue>[],
      warnings: agentStringList(json['warnings']),
      coverageFallbackUsed: agentBool(json['coverage_fallback_used']),
      ocrQuality: agentMap(json['ocr_quality']).map(
        (imageId, quality) =>
            MapEntry(imageId, OcrQuality.fromJson(agentMap(quality))),
      ),
      pitchAccents: agentMap(json['pitch_accents']).map(
        (tokenId, accent) =>
            MapEntry(tokenId, AgentPitchAccent.fromJson(agentMap(accent))),
      ),
      richOriginalText: json['rich_original_text'] is String
          ? json['rich_original_text'] as String
          : null,
      richSegmentTexts: agentStringList(json['rich_segment_texts']),
      richSegmentNotes: agentStringList(json['rich_segment_notes']),
      telemetry: AgentRunTelemetry.fromJson(agentMap(json['telemetry'])),
    );
  }
}

/// The combined source text for the detailed “原文” section. The formatter
/// works on this section as a whole rather than producing a field per quote.
String agentOriginalSource(List<AgentQuoteRef> quotes) {
  return quotes
      .map((quote) => quote.text)
      .where((text) => text.trim().isNotEmpty)
      .join('\n\n');
}

/// The raw assistant summary. The AI bubble renders this with `AgentRichText`
/// after local RUBY conversion; it never receives the model's display-only
/// BOLD/UNDERLINE pass. This raw value still keeps YOMI wrappers for
/// [agentSummaryDisplayText] and plain-text consumers.
String agentSummarySource(AgentAnalysis analysis) {
  if (analysis.noAnalysisReason.isNotEmpty) {
    return analysis.noAnalysisReason;
  }
  if (analysis.translation.isNotEmpty) {
    return analysis.translation.map((item) => item.text).join('\n');
  }
  if (analysis.segments.isNotEmpty) {
    return analysis.segments.first.interpretation;
  }
  return '';
}

/// The dictionary-fact explanation lines shown under a segment. These are the
/// word senses and grammar explanations, not the citation snippets.
String agentSegmentNotesSource(AgentSegment segment) {
  return <String>[
    for (final note in segment.wordNotes)
      '${note.surface}'
          '${_noteYomi(note)}'
          '：${note.sense}',
    for (final note in segment.grammarNotes) note.explanation,
  ].join('\n');
}

String _noteYomi(AgentWordNote note) {
  final reading = cleanReading(note.reading);
  if (reading.isEmpty || reading == note.surface) return '';
  return '[YOMI]$reading[/YOMI]';
}

/// Plain-text rendering of the summary for non-rich consumers. The AI bubble
/// now renders [agentSummarySource] with `AgentRichText` after local RUBY
/// conversion; this helper remains for copy/export-style plain text.
String agentSummaryDisplayText(AgentAnalysis analysis) =>
    richTextToPlain(agentSummarySource(analysis));

class AgentRunFailure implements Exception {
  const AgentRunFailure({
    required this.stage,
    required this.code,
    required this.message,
    this.cause,
    this.detail = '',
  });

  final AgentStage stage;
  final AgentToolErrorCode code;
  final String message;
  final Object? cause;

  /// Sanitized diagnostic text (for example the first model bytes). Never
  /// contains the API key; safe to show in a collapsible error detail.
  final String detail;

  @override
  String toString() =>
      'AgentRunFailure(${stage.name}/${code.wireName}): $message';
}

/// Run-scoped cancellation. Extends the provider-neutral signal so adapters can
/// cancel their in-flight HTTP request immediately.
class AgentCancellation extends LlmCancelToken {}

typedef AgentStageCallback = void Function(AgentStage stage, String message);

/// Receives display-only rich text after the core result has been delivered.
/// The controller applies it to the visible result without blocking `done`.
typedef AgentRichTextCallback = void Function(AgentRichTextOutputs outputs);

/// Notifies the UI when the display-only rich-text beautification pass starts
/// or finishes after the core result is already visible.
typedef AgentRichTextFormattingCallback = void Function(bool active);

/// Fires once the main analysis can be displayed, before optional
/// repair/language post-checks finish. The final [AgentRunResult] may replace
/// this value when those checks complete.
typedef AgentProvisionalResultCallback = void Function(AgentRunResult result);

/// Display-only translation preview from a complete `[TRANSLATION]` block.
/// It is not persisted and must not be treated as a validated final result.
typedef AgentTranslationPreviewCallback = void Function(String text);

/// Resolves every generated profile as a batch. The app-level inbox holds the
/// proposals until the user acts, so an absent page never implies a skip.
typedef AgentProfileReviewCallback =
    Future<List<ProfileConfirmation>> Function(
      String runId,
      List<AgentProfileProposal> proposals,
    );

enum AgentRunStatus {
  idle,
  preparing,
  ocr,
  familiarizing,
  awaitingProfile,
  tokenizing,
  reasoning,
  validating,
  done,
  cancelled,
  interrupted,
  error,
}

/// App-scoped state of the current Agent run. The page only renders this; the
/// run itself is owned by `AgentRunController`, so leaving the page or
/// rebuilding it never cancels or loses the run.
class AgentRunSnapshot {
  const AgentRunSnapshot({
    this.runId,
    this.sessionId,
    this.status = AgentRunStatus.idle,
    this.stageMessage = '',
    this.receivedChars = 0,
    this.progressStep = 0,
    this.evidenceCount = 0,
    this.citationCount = 0,
    this.maxEvidenceEntries = 0,
    this.pendingProfileCount = 0,
    this.richTextFormatting = false,
    this.result,
    this.provisionalResult,
    this.translationPreview,
    this.retainedResult,
    this.resultRetainedAfterFailure = false,
    this.resultReplaced = false,
    this.errorMessage,
    this.errorCode,
    this.retryable = false,
    this.errorDetail = '',
    this.sentText = '',
    this.sentImage = false,
    this.sentImagePaths = const <String>[],
    this.mode = AgentMode.strict,
    this.responseLanguage = AgentResponseLanguage.chinese,
    this.providerLabel = '',
    this.startedAt,
    this.thinkingStartedAt,
    this.finishedAt,
    this.updatedAt,
    this.slowRequestWarning = false,
  });

  static const AgentRunSnapshot idle = AgentRunSnapshot();

  final String? runId;
  final String? sessionId;
  final AgentRunStatus status;
  final String stageMessage;

  /// Characters received from the provider. The raw tagged stream is not
  /// rendered; the UI only shows this progress counter.
  final int receivedChars;

  /// 0=prepare/OCR, 1=lookup, 2=generation, 3=validation, 4=done.
  final int progressStep;
  final int evidenceCount;
  final int citationCount;
  final int maxEvidenceEntries;
  final int pendingProfileCount;

  /// True while the display-only rich-text beautification agent is still
  /// running after the main result is visible. The result is already usable;
  /// this flag only drives the dismissible “界面美化” banner.
  final bool richTextFormatting;

  int get evidenceLimit => maxEvidenceEntries > 0
      ? maxEvidenceEntries
      : AgentLimits.standard.maxEvidenceEntries;
  final AgentRunResult? result;

  /// A displayable result emitted before optional post-checks (format or
  /// language repair) finish. It is replaced by [result] when the run
  /// completes, and never sent back to the provider.
  final AgentRunResult? provisionalResult;

  /// Display-only translation from a complete `[TRANSLATION]` block in the
  /// current stream. Cleared when a provisional/final result arrives; never
  /// persisted or sent back to the provider.
  final String? translationPreview;

  /// Previous result kept visible while a regeneration runs. It is never sent
  /// to the provider again and is replaced only by a successful new run.
  final AgentRunResult? retainedResult;
  final bool resultRetainedAfterFailure;

  /// True when [result] replaced an already-displayed provisional result.
  /// Result blocks must not replay their entrance animation on that swap.
  final bool resultReplaced;
  final String? errorMessage;
  final AgentToolErrorCode? errorCode;
  final bool retryable;
  final String errorDetail;
  final String sentText;
  final bool sentImage;

  /// Local paths used only to render the sent image(s) in the user bubble.
  /// They are never sent to the provider, persisted, or logged.
  final List<String> sentImagePaths;
  final AgentMode mode;
  final AgentResponseLanguage responseLanguage;
  final String providerLabel;
  final DateTime? startedAt;

  /// When the main analysis model actually entered its generation stage.
  /// Null during prepare/OCR/lookup; the UI shows task elapsed time until
  /// this is set, then switches to honest thinking time.
  final DateTime? thinkingStartedAt;
  final DateTime? finishedAt;
  final DateTime? updatedAt;

  /// True after [AgentLimits.slowRequestWarningSeconds] of main-analysis
  /// thinking. It is an orange advisory only; the run continues.
  final bool slowRequestWarning;

  bool get isRunning => switch (status) {
    AgentRunStatus.preparing ||
    AgentRunStatus.ocr ||
    AgentRunStatus.familiarizing ||
    AgentRunStatus.awaitingProfile ||
    AgentRunStatus.tokenizing ||
    AgentRunStatus.reasoning ||
    AgentRunStatus.validating => true,
    _ => false,
  };

  bool get canCancel => isRunning;

  /// True while the current run may still use/display dictionary profiles.
  /// Deleting a profile stays locked for the active run; editing and explicit
  /// regeneration are allowed because they write a new profile revision.
  bool get profilesInUse => isRunning;

  bool get hasConversation =>
      sentText.isNotEmpty ||
      sentImage ||
      isRunning ||
      result != null ||
      provisionalResult != null ||
      (translationPreview?.isNotEmpty ?? false) ||
      errorMessage != null;

  AgentRunSnapshot copyWith({
    Object? runId = _unset,
    Object? sessionId = _unset,
    AgentRunStatus? status,
    String? stageMessage,
    int? receivedChars,
    int? progressStep,
    int? evidenceCount,
    int? citationCount,
    int? maxEvidenceEntries,
    int? pendingProfileCount,
    bool? richTextFormatting,
    Object? result = _unset,
    Object? provisionalResult = _unset,
    Object? translationPreview = _unset,
    Object? retainedResult = _unset,
    bool? resultRetainedAfterFailure,
    bool? resultReplaced,
    Object? errorMessage = _unset,
    Object? errorCode = _unset,
    bool? retryable,
    String? errorDetail,
    String? sentText,
    bool? sentImage,
    List<String>? sentImagePaths,
    AgentMode? mode,
    AgentResponseLanguage? responseLanguage,
    String? providerLabel,
    Object? startedAt = _unset,
    Object? thinkingStartedAt = _unset,
    Object? finishedAt = _unset,
    DateTime? updatedAt,
    bool? slowRequestWarning,
  }) {
    return AgentRunSnapshot(
      runId: identical(runId, _unset) ? this.runId : runId as String?,
      sessionId: identical(sessionId, _unset)
          ? this.sessionId
          : sessionId as String?,
      status: status ?? this.status,
      stageMessage: stageMessage ?? this.stageMessage,
      receivedChars: receivedChars ?? this.receivedChars,
      progressStep: progressStep ?? this.progressStep,
      evidenceCount: evidenceCount ?? this.evidenceCount,
      citationCount: citationCount ?? this.citationCount,
      maxEvidenceEntries: maxEvidenceEntries ?? this.maxEvidenceEntries,
      pendingProfileCount: pendingProfileCount ?? this.pendingProfileCount,
      richTextFormatting: richTextFormatting ?? this.richTextFormatting,
      result: identical(result, _unset)
          ? this.result
          : result as AgentRunResult?,
      provisionalResult: identical(provisionalResult, _unset)
          ? this.provisionalResult
          : provisionalResult as AgentRunResult?,
      translationPreview: identical(translationPreview, _unset)
          ? this.translationPreview
          : translationPreview as String?,
      retainedResult: identical(retainedResult, _unset)
          ? this.retainedResult
          : retainedResult as AgentRunResult?,
      resultRetainedAfterFailure:
          resultRetainedAfterFailure ?? this.resultRetainedAfterFailure,
      resultReplaced: resultReplaced ?? this.resultReplaced,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      errorCode: identical(errorCode, _unset)
          ? this.errorCode
          : errorCode as AgentToolErrorCode?,
      retryable: retryable ?? this.retryable,
      errorDetail: errorDetail ?? this.errorDetail,
      sentText: sentText ?? this.sentText,
      sentImage: sentImage ?? this.sentImage,
      sentImagePaths: sentImagePaths ?? this.sentImagePaths,
      mode: mode ?? this.mode,
      responseLanguage: responseLanguage ?? this.responseLanguage,
      providerLabel: providerLabel ?? this.providerLabel,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      thinkingStartedAt: identical(thinkingStartedAt, _unset)
          ? this.thinkingStartedAt
          : thinkingStartedAt as DateTime?,
      finishedAt: identical(finishedAt, _unset)
          ? this.finishedAt
          : finishedAt as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
      slowRequestWarning: slowRequestWarning ?? this.slowRequestWarning,
    );
  }
}

const Object _unset = Object();
