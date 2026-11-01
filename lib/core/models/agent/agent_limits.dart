/// Single source of truth for Agent pipeline budgets and UI-visible limits.
///
/// The same instance is read by the orchestrator, evidence builder, profile
/// inbox and UI counters so no surface hard-codes a limit such as `60`.
class AgentLimits {
  const AgentLimits({
    this.maxSourceChars = 6000,
    this.maxTargets = 120,
    this.maxEvidenceEntries = 60,
    this.maxEntriesPerDictionary = 3,
    this.maxSnippetChars = 400,
    this.maxImagesPerRun = 6,
    this.maxCoverageMissing = 20,
    this.maxCoverageDuplicateGroups = 10,
    this.maxCoverageFallback = 1,
  });

  static const AgentLimits standard = AgentLimits();

  final int maxSourceChars;
  final int maxTargets;
  final int maxEvidenceEntries;
  final int maxEntriesPerDictionary;
  final int maxSnippetChars;
  final int maxImagesPerRun;
  final int maxCoverageMissing;
  final int maxCoverageDuplicateGroups;
  final int maxCoverageFallback;
}
