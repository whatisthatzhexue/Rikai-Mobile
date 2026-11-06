/// Single source of truth for Agent pipeline budgets and UI-visible limits.
///
/// The same instance is read by the orchestrator, evidence builder, profile
/// inbox and UI counters so no surface hard-codes a limit such as `60`.
class AgentLimits {
  /// Default for [maxRichTextChars]. A static const (not the mutable
  /// `standard` instance field) is required for use as a default parameter.
  static const int defaultMaxRichTextChars = 20000;

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
    this.maxCoverageQueryChars = 100,
    this.maxCoverageCompoundTokens = 6,
    this.enableRichTextPostProcess = true,
    this.richTextConcurrency = 3,
    this.lookupBatchSize = 12,
    this.adaptiveCoverageReview = true,
    this.maxSegments = 40,
    this.maxSegmentsPerQuotePerType = 1,
    this.maxOptionsPerRun = 8,
    this.maxNotesPerSegment = 20,
    this.maxRichTextChars = defaultMaxRichTextChars,
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

  /// Global safety cap for one coverage MISSING query. Compound validation is
  /// token-based; this character cap only prevents pathological long strings.
  final int maxCoverageQueryChars;

  /// Maximum source-token span for a compound/fixed-collocation MISSING query
  /// that is not already a known token/pattern/entry term. The span is
  /// token-based so it transfers across writing systems; there is no
  /// language-specific character cap. When tokenization is unavailable, only
  /// known terms are accepted.
  final int maxCoverageCompoundTokens;

  /// Hard caps for the tagged analysis output. The parser applies them after
  /// parsing and marks the analysis truncated; the prompt states the same
  /// limits so a compliant model does not hit them.
  final int maxSegments;
  final int maxSegmentsPerQuotePerType;
  final int maxOptionsPerRun;
  final int maxNotesPerSegment;

  /// Maximum combined characters sent to one batched rich-text request.
  /// Above this the display formatter is skipped and the local RUBY baseline
  /// is used, so a long result cannot overflow the provider context.
  final int maxRichTextChars;

  /// Output budget for the main analysis request. Anthropic must send a value;
  /// an OpenAI-compatible provider only sends it when the user configured
  /// `maxOutputTokens`.
  static const int analysisMaxTokens = 12000;

  /// Optional rich-text formatting pass after a successful analysis. Tests
  /// that assert request sequences disable it explicitly.
  final bool enableRichTextPostProcess;

  /// Maximum number of concurrent rich-text formatting requests. Formatting
  /// sections are independent and run after `done`; a small bounded pool keeps
  /// them off the core result path without flooding the provider.
  final int richTextConcurrency;

  /// Maximum number of dictionary queries sent to the MDict worker in one IPC
  /// round trip. The worker still executes them sequentially; this only
  /// removes per-query isolate round trips.
  final int lookupBatchSize;

  /// When true, the coverage review is skipped if every lookup target already
  /// produced at least one citation and the evidence size is below the global
  /// cap. At the cap it still runs so verified duplicates can free slots.
  /// Set false in tests or integrations that need an unconditional review.
  final bool adaptiveCoverageReview;

  // Coverage output estimator inputs. These are public so contracts/tests can
  // point at one named constant instead of copying magic numbers.
  static const int coverageRootTagChars = 128;
  static const int coverageNotesChars = 500;
  static const int coverageRootAndNotesChars =
      coverageRootTagChars + coverageNotesChars;

  /// Default for [maxCoverageQueryChars]. The budget formula uses the
  /// instance value so a configured limit cannot under-estimate the request.
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
            (maxCoverageQueryChars +
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
