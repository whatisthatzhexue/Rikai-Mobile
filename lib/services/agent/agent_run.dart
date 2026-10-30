import 'package:rikai_ocr/rikai_ocr.dart';

import '../../core/models/agent/agent_analysis.dart';
import '../../core/models/agent/agent_evidence.dart';
import '../../core/models/agent/agent_input.dart';
import '../../core/models/agent/agent_profile.dart';
import '../../core/models/agent/agent_provider.dart';
import '../../core/models/agent/agent_quote.dart';
import '../../core/models/agent/agent_tool.dart';
import '../../core/models/dict_info.dart';
import 'agent_validator.dart';
import 'ports/llm_port.dart';
import 'familiarization/dictionary_familiarization_service.dart'
    show DictionaryProfileIssue;

enum AgentStage {
  prepare,
  ocr,
  familiarizing,
  tokenizing,
  evidence,
  reasoning,
  validating,
  done,
  error,
  cancelled,
}

class AgentImageInput {
  const AgentImageInput({
    required this.id,
    required this.localPath,
    this.mode = OcrMode.auto,
  });

  final String id;
  final String localPath;
  final OcrMode mode;
}

class AgentRunRequest {
  const AgentRunRequest({
    required this.sessionId,
    required this.mode,
    required this.dictionaries,
    required this.provider,
    this.userText = '',
    this.context = '',
    this.images = const <AgentImageInput>[],
    this.allowFamiliarization = true,
    this.unidicPath = '',
    this.responseLanguage = AgentResponseLanguage.follow,
  });

  final String sessionId;
  final AgentMode mode;
  final List<DictionaryInfo> dictionaries;
  final AgentProviderConfig provider;
  final String userText;
  final String context;
  final List<AgentImageInput> images;
  final bool allowFamiliarization;
  final String unidicPath;
  final AgentResponseLanguage responseLanguage;
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

  List<AgentCitation> get citations => evidence.citations;
}

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

enum AgentRunStatus {
  idle,
  preparing,
  ocr,
  familiarizing,
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
    this.result,
    this.errorMessage,
    this.errorCode,
    this.retryable = false,
    this.errorDetail = '',
    this.sentText = '',
    this.sentImage = false,
    this.sentImagePaths = const <String>[],
    this.mode = AgentMode.strict,
    this.responseLanguage = AgentResponseLanguage.follow,
    this.providerLabel = '',
    this.startedAt,
    this.finishedAt,
    this.updatedAt,
  });

  static const AgentRunSnapshot idle = AgentRunSnapshot();

  final String? runId;
  final String? sessionId;
  final AgentRunStatus status;
  final String stageMessage;

  /// Characters received from the provider. The raw stream is JSON and is not
  /// rendered; the UI only shows this progress counter.
  final int receivedChars;

  /// 0=prepare/OCR, 1=lookup, 2=generation, 3=validation, 4=done.
  final int progressStep;
  final int evidenceCount;
  final int citationCount;
  final AgentRunResult? result;
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
  final DateTime? finishedAt;
  final DateTime? updatedAt;

  bool get isRunning => switch (status) {
    AgentRunStatus.preparing ||
    AgentRunStatus.ocr ||
    AgentRunStatus.familiarizing ||
    AgentRunStatus.tokenizing ||
    AgentRunStatus.reasoning ||
    AgentRunStatus.validating => true,
    _ => false,
  };

  bool get canCancel => isRunning;

  bool get hasConversation =>
      sentText.isNotEmpty ||
      sentImage ||
      isRunning ||
      result != null ||
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
    Object? result = _unset,
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
    Object? finishedAt = _unset,
    DateTime? updatedAt,
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
      result: identical(result, _unset)
          ? this.result
          : result as AgentRunResult?,
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
      finishedAt: identical(finishedAt, _unset)
          ? this.finishedAt
          : finishedAt as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _unset = Object();
