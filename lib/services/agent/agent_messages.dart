import 'agent_run.dart';
import 'agent_ui_strings.dart';

export 'agent_ui_strings.dart' show AgentUiLanguage, resolveAgentUiLanguage;

String agentStageMessage(AgentStage stage, AgentUiLanguage language) =>
    AgentUiStrings.of(language).stageMessage(stage);

String agentRepairingMessage(AgentUiLanguage language) =>
    AgentUiStrings.of(language).repairing;

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
  AgentUiLanguage language,
) => AgentUiStrings.of(
  language,
).evidenceProgressLabel(evidenceCount, citationCount);

String agentThinkingFallback(AgentUiLanguage language) =>
    AgentUiStrings.of(language).thinkingFallback;

String agentElapsedLabel(int seconds, AgentUiLanguage language) =>
    AgentUiStrings.of(language).elapsedLabel(seconds);
