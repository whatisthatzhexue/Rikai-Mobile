import 'agent_run.dart';
import 'agent_ui_strings.dart';

export 'agent_ui_strings.dart' show AgentUiLanguage, resolveAgentUiLanguage;

String agentStageMessage(AgentStage stage, AgentUiLanguage language) =>
    AgentUiStrings.of(language).stageMessage(stage);

String agentRepairingMessage(AgentUiLanguage language) =>
    AgentUiStrings.of(language).repairing;

String agentLanguageWarning(AgentUiLanguage language) =>
    AgentUiStrings.of(language).languageWarning;

String agentFanOutPartialWarning(AgentUiLanguage language) =>
    AgentUiStrings.of(language).fanOutPartial;

String agentAnalysisTruncatedWarning(AgentUiLanguage language) =>
    AgentUiStrings.of(language).analysisTruncated;

String agentCoverageUnavailable(AgentUiLanguage language) =>
    AgentUiStrings.of(language).coverageUnavailable;

String agentCoverageUnverifiable(AgentUiLanguage language) =>
    AgentUiStrings.of(language).coverageUnverifiable;

String agentCoverageAtLimit(AgentUiLanguage language) =>
    AgentUiStrings.of(language).coverageAtLimit;

String agentCoverageNoNew(AgentUiLanguage language) =>
    AgentUiStrings.of(language).coverageNoNew;

String agentDictionaryLookupFailed(AgentUiLanguage language, String name) =>
    AgentUiStrings.of(language).dictionaryLookupFailed(name);

String agentDictionaryNoEvidence(
  AgentUiLanguage language,
  List<String> names,
) => AgentUiStrings.of(language).dictionaryNoEvidence(names);

String agentInputRequiredMessage(AgentUiLanguage language) =>
    AgentUiStrings.of(language).inputRequired;

String agentDictionaryRequiredMessage(AgentUiLanguage language) =>
    AgentUiStrings.of(language).dictionaryRequired;

String agentModelRequiredMessage(AgentUiLanguage language) =>
    AgentUiStrings.of(language).modelRequired;

List<String> agentProgressStepLabels(AgentUiLanguage language) =>
    AgentUiStrings.of(language).progressStepLabels;

String agentEvidenceProgressLabel(
  int evidenceCount,
  int citationCount,
  int maxEvidenceEntries,
  AgentUiLanguage language,
) => AgentUiStrings.of(
  language,
).evidenceProgressLabel(evidenceCount, citationCount, maxEvidenceEntries);

String agentThinkingFallback(AgentUiLanguage language) =>
    AgentUiStrings.of(language).thinkingFallback;

String agentElapsedLabel(int seconds, AgentUiLanguage language) =>
    AgentUiStrings.of(language).elapsedLabel(seconds);

String agentTaskElapsedLabel(int seconds, AgentUiLanguage language) =>
    AgentUiStrings.of(language).taskElapsedLabel(seconds);

String agentTaskDurationLabel(int seconds, AgentUiLanguage language) =>
    AgentUiStrings.of(language).taskDurationLabel(seconds);

String agentSlowRequestWarning(AgentUiLanguage language) =>
    AgentUiStrings.of(language).slowRequestWarning;
