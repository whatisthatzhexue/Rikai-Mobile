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

  // Coverage output estimator inputs. These are public so contracts/tests can
  // point at one named constant instead of copying magic numbers.
  static const int coverageRootTagChars = 128;
  static const int coverageNotesChars = 500;
  static const int coverageRootAndNotesChars =
      coverageRootTagChars + coverageNotesChars;
  static const int coverageQueryChars = 100;
  static const int coverageRefsChars = 64;
  static const int coverageReasonChars = 500;
  static const int coverageTagChars = 120;
  static const int coverageDuplicateKeyChars = 300;

  /// CJK output can tokenize close to one UTF-16 code unit per token on some
  /// providers (notably Claude). 1.0 is a conservative lower bound for budget
  /// derivation, not a precise tokenizer estimate. English output gets a
  /// larger ceiling than it needs, which is harmless for a maximum.
  static const double coverageCharsPerToken = 1.0;

  /// Safety margin kept in tokens, independent of the character estimate.
  static const int coverageSafetyTokens = 1024;

  /// Output budget for the coverage review only. Analysis/repair budgets are
  /// independent. The formula is:
  ///   missing cap × (query + refs + reason + tag overhead)
  /// + duplicate cap × (dictionary/keys + reason + tag overhead)
  /// + root/notes overhead + safety margin.
  int get coverageReviewMaxTokens {
    final chars =
        coverageRootAndNotesChars +
        maxCoverageMissing *
            (coverageQueryChars +
                coverageRefsChars +
                coverageReasonChars +
                coverageTagChars) +
        maxCoverageDuplicateGroups *
            (coverageDuplicateKeyChars +
                coverageReasonChars +
                coverageTagChars);
    return (chars / coverageCharsPerToken).ceil() + coverageSafetyTokens;
  }
}
