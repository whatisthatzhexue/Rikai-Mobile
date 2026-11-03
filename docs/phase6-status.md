# Phase 6 status — dictionary assistant core

Date: 2026-10-30
Base: Phase 5 complete (`docs/phase5-status.md`)
Design: `docs/phase6-agent-design.md` v2
Contracts: `docs/phase6-agent-contracts.md` / `docs/schemas/agent/`

> **Status: P6.1–P6.5 core and 2026-10-31 feedback Waves 1–3 are implemented;
> Wave 4 device acceptance is still pending. P6.6 multi-OCR core is implemented
> (2026-11-02) and its automated closeout completed on 2026-11-03; P6.6 device
> acceptance remains pending. P6.7 design/contracts were recorded on 2026-11-03
> (safe rich text/ruby/UniDic pitch, annotation DSL, one-run history/release);
> P6.7 implementation is not started and is gated by Wave 4.**

> Follow `docs/agent_docs/device-feedback-2026-10-31.md` for the remaining
> Wave 4 device checks. **Current test/device/build/environment numbers are
> centralized in `docs/project-data.md`; do not copy them here.** Normative
> MUST/MUST NOT rules live in `docs/project-rules.md`. Automated tests use fake
> providers and never a real API key. On
> 2026-10-30 a user-configured DeepSeek provider was smoke-tested on the x86_64
> emulator (key never logged); arm64/real manga-page and real-dictionary
> `sample`/`suggest` acceptance still remain. The review backlog in
> `docs/agent_docs/phase6-pipeline-review.md` is authoritative for open gaps.
>
> **2026-11-01 language decision (implemented in Wave 2–3)**: the default
> output/UI language is Chinese (`zh`); legacy `follow` maps to `zh`;
> `resolveAgentUiLanguage` takes only the explicit setting and never inspects
> source text. `AgentUiStrings` supplies Chinese/English/Japanese Agent-area
> copy. Wave 3 adds `AgentLanguageValidator` post-validation of human-readable
> fields plus one language repair with a visible warning when it still differs.

## Implemented

### P6.1 Capability layer

- `lib/core/models/agent/` DTOs: input envelope, evidence/citation, analysis,
  dictionary/UniDic profile, quote/source version, and `AgentToolErrorCode`
  (tool spec/result DTOs were removed with the 2026-10-31 tool-layer removal).
- `lib/core/models/lookup_request.dart`, `lib/core/models/dictionary_sample.dart`.
- `lib/services/agent/ports/`: OCR, tokenize, lookup, dictionary sample, LLM,
  secret, capability exception. Text-only LLM port has no image/file part.
- `lib/services/lookup/lookup_gateway.dart`: pure lookup validation/order used by
  UI lookup and the Agent. `performLookup` and `LookupSearchNotifier` now use it.
- `OcrWorkflow` was removed on 2026-10-31 (no production caller); the OCR port
  performs readiness/recognize/compose itself.
- `lib/services/mdict/mdict_worker.dart`: `sample` and `suggest` worker commands;
  `MdictService` implements `LookupBackend`; bounded samples produce plain-text
  snippets/features.
- **Tool registry/adapters were removed on 2026-10-31** with the fixed-pipeline/
  no-tools decision. `lib/services/agent/tools/` is absent; the contract keeps the
  tool table only as future reference. `AgentToolErrorCode` remains as the stable
  error vocabulary.
- `CitationRegistry` issues/keeps `source-N`, dedupes by dictionary + entry.
- Assets: `assets/agent/dictionary_probes.json`,
  `assets/agent/grammar_patterns_ja.json`; grammar longest-match catalog.

### P6.2 Provider/secret

- `flutter_secure_storage` 11.2.0; `FlutterSecureStorageSecretStore` and
  in-memory test store. Keys are namespaced; no SharedPreferences/SQLite key.
- `OpenAiCompatibleProvider` and `AnthropicProvider` (text-only, streaming and
  non-streaming), fake provider, provider factory.
- `assertNoImagePayload` rejects image/file keys and local/data URI values while
  allowing the opaque `image_id` handle.
- Provider request tests assert no image/path/key leakage; Anthropic test checks
  `x-api-key`, `anthropic-version: 2026-10-21`, top-level `system`, no temperature.

### P6.3 Familiarization

- Dictionary sample fingerprint (MDX stat + entry count/encoding + schema/prompt
  version) and UniDic fingerprint (runtime files + version + schema).
- `DictionaryFamiliarizationService`: bounded sample → small model JSON →
  user confirmation (`save/skip once/decline`) → SQLite profile; reuse and
  decline memory; mismatched dictionary id rejected.
- `UnidicFamiliarizationService`: deterministic token-layout observations, no
  fake UniDic entry lookup.
- `AgentStore` (`rikai_agent.db`) creates tables for providers, sessions, runs,
  messages, tool calls, source versions, citations, dictionary/UniDic profiles,
  annotation rule sets. Profile and provider CRUD implemented.

### P6.4 Orchestrator/evidence/validator

- `AgentOrchestrator` fixed stages: prepare → OCR → familiarizing → tokenize →
  evidence → reasoning → validate → done; cancellation, stage callback, source
  versions, budget, and stable `AgentRunFailure` codes.
- `EvidenceBuilder`: token/grammar targets, exact then prefix fallback, bounded
  unique targets/citations, per-token citation IDs, dictionary-order sorting.
- `QuoteBuilder`: sentence/clause UTF-16 quotes for original-text citation.
- `AgentValidator`: citation existence/ownership, quote/literal matching, strict
  dictionary-fact citations, structural token/pattern references, context
  inference unresolved rule, strict model-supplement rejection, reading check.
- Analysis prompt/schema and user prompt envelope (untrusted data labels).

### P6.5 Agent UI and settings

- Fifth home action `词典助手`; home labels now `拍照识别/查句子/查单词/
  历史记录/词典助手` (tests updated). Home body is a `SingleChildScrollView`
  so all five actions are built on small/landscape screens.
- `AgentPage` (292 lines after the split): only wiring; extracted
  `agent_session_panel.dart`, `agent_composer.dart`, `agent_message_list.dart`,
  `agent_message_widgets.dart`, `agent_evidence_panel.dart`, `agent_actions.dart`
  and `agent_progress_view.dart`. Run state lives in the app-scoped
  `AgentRunController`.
- User bubble renders sent image thumbnails (multiple images use Wrap) instead
  of a text-only “1 image” placeholder. Composer clears text + image after send.
- `AgentResultView`: original quotes, per-segment word/grammar notes,
  interpretation candidates, unresolved items, loose model supplements,
  dictionary-ordered evidence cards; citations are numbered “依据1/依据2…”
  once per segment, not repeated after every note.
- Citation tap re-runs an exact lookup in the cited dictionary and opens the
  existing `EntryPage`; missing entries show a toast.
- Familiarization confirmation sheet: editable Markdown, save/skip/decline.
- `AgentSettingsPage`: provider list/add/edit/delete, base URL, small/complex
  models, masked API key, secure storage, privacy copy. No real key is required
  for the empty-state/widget tests.
- `AgentTokens` semantic colors/sizes added to `app_tokens.dart`; no page-level
  hardcoded color/font-size values were introduced.

### Pipeline hardening after device test (2026-10-30)

- **SSE**: fixed Dio `Stream<Uint8List>` vs `utf8.decoder` runtime type mismatch;
  OpenAI-compatible streaming now parses text and DeepSeek `reasoning_content`.
  If a stream yields no text, the provider retries once non-streaming.
- **Visible generation**: Agent page shows the current stage, a four-step
  progress list (OCR → lookup → generate → validate), live retrieved-entry/
  citation counts, and a thinking-time label. Stage text and the timer follow
  the response-language setting. Legacy behavior (`follow` inferred Japanese
  from kana, English from Latin-only input, otherwise Chinese) is superseded by
  the 2026-11-01 decision: default `zh`, no input heuristic; implementation is
  pending. Raw streamed output, reasoning text
  and character counts are never rendered. Validated result items fade in one by
  one after validation; there is no streaming JSON partial display. Citations
  are numbered “依据1/依据2…” and consolidated once per segment instead of after
  every word note. The safe model-generated “summary” field is deferred (P3).
- **Tag format success**: analysis/familiarization use bracket-tag plain text,
  not JSON. Analysis requires non-empty `translation`/`segments`; tag-block
  integrity (balance/nesting/single-instance fields) is checked before repair.
  No `response_format`/`json_schema`/`output_config` is sent.
- **Normalization**: `literal` is filled from the selected quote; grammar notes
  with unknown `pattern_id` are dropped; result view shows epistemic/confidence
  badges.
- **Fewer requests / failure isolation**: familiarity profiles are split by a
  4K token estimate; missing/failed dictionaries produce `unavailable` issues
  with a per-dictionary retry, and the Agent continues with generic lookup.
- **Language split**: profile language (default 中文) and answer language are
  separate settings; profile language is stored/in the fingerprint, and changing
  it asks before invalidating existing profiles.
- **Input split**: with an image, the text field is an instruction/context and is
  not added to evidence sources; text-only input remains the source.
- **Cancellation/reentrancy**: `AgentRunController` is app-scoped. The page only
  subscribes to its snapshot; `dispose()` no longer cancels a run, repeated sends
  are ignored while a run is active, and old callbacks are discarded by the run
  cancellation token. Provider `CancelToken` and familiarization cancellation
  remain pending.
- **Composer lifecycle**: after sending, both the text field and the image
  attachment are cleared; the user bubble is the source of truth. Retry and
  “new session” use the controller's request snapshot rather than the empty
  composer.
- **UniDic optional**: a missing/broken UniDic no longer fails the run. The
  evidence bundle carries `structure_unavailable`, the prompt forbids token/
  grammar claims, the validator rejects structural claims, and the result view
  shows “结构分析不可用”.
- **Validation repair/salvage**: a parse/validation failure triggers one repair
  call with the original output + errors + the same evidence/quotes (no OCR or
  lookup rerun). If repair still fails, invalid citations/unknown tokens/patterns
  are removed, strict unsupported claims become `unresolved`, and the partial
  result is shown with a warning instead of an empty error card. A strict-mode
  error still offers “宽松重试”.
- **Strict mode**: word notes always require citations in strict mode; unknown
  source/citation and empty results are rejected; debug-only raw-output logs.

### 2026-10-31 real-device feedback backlog (Waves 1–2 implemented)

The user reported 17 additional issues after a real-device P6.5 trial. The
authoritative plan, current-code evidence, wave ordering and acceptance
criteria are in
[`docs/agent_docs/device-feedback-2026-10-31.md`](agent_docs/device-feedback-2026-10-31.md).
Summary:

- **Wave 1 (quick/low-risk)**: short citation pills (F4), remove `qN` markers
  (F5), 3.5-row dictionary filters (F9), Chinese provider labels/presets (F10),
  current-dictionary-only entry links (F15), app-scoped OCR download progress
  (F16).
- **Wave 2 (implemented, Agent lifecycle/UI)**: Chinese-first default and no
  input-language heuristic (F1a/F17), independent Agent dictionary preferences
  (F8), app-level dictionary-profile inbox that gates tokenizing (F2), elapsed
  time across page leave (F3), camera/gallery multi-image input (F11),
  full-screen sent-image viewer (F12), profile manager (F13), result action
  row/copy/edit/regenerate (F14). F1b is implemented in Wave 3.
- **Wave 3 (implemented)**: `AgentLanguageValidator` + one language repair
  (F1b); global `AgentLimits` and exact → prefix → suffix → incremental lookup,
  continuing past a zero-new mode, with normal progression ending at the global
  cap (cancellation aborts; per-target/per-dictionary caps skip queries, not
  modes) and N/M progress (F6); one `[COVERAGE]` tag review, source-id fill,
  tag-integrity checks, traceability filtering, locally verified duplicate
  pruning, flow A/B and at most one supplementary lookup (F7). All Agent prompt
  text is centralized in `agent_prompts.dart`; old prompt files are compatibility
  re-exports.
- F2 must precede F7/F13/F14 profile work. F6 must precede F7. F17 must precede
  all Agent UI localization work. The backlog itself does not authorize P6.6/
  P6.7; P6.6 was started separately on 2026-11-02 by explicit user instruction,
  while Wave 4 device acceptance remains pending.

Wave 1 implementation (2026-10-31):

- `DictionaryFilterBar` now reserves 3.5 rows; `AppSizes.dictionaryFilterVisibleRows`
  is the shared token.
- Provider settings use Chinese labels and `AgentProviderPreset` (`DeepSeek`,
  `Claude（Anthropic）`, other OpenAI-compatible); DeepSeek/Claude fill their
  default base URLs without overwriting a user-edited address.
- `entry://` links build an exact `LookupRequest` limited to the current entry
  tab's dictionary; global lookup selection/mode is not used.
- OCR model downloads moved to app-scoped `ocrModelDownloadControllerProvider`;
  the model page subscribes and re-enters with the current progress/cancel state.
- Citation chips use the compact 24dp pill and `Wrap`; evidence rows no longer
  use the long `依据N · 查看` string. Unresolved items no longer show `（q1）`.
- Wave 1 verification: `flutter analyze` clean; current test/build results in
  `docs/project-data.md` §2/§5. Device visual/navigation/download acceptance
  remains for Wave 4.

Wave 2 implementation (2026-11-01):

- **F1a/F17 language**: `AgentResponseLanguage` no longer has `follow`; stored
  `follow` maps to `zh`. `resolveAgentUiLanguage(setting)` takes no source
  text. New `AgentUiStrings` (zh/en/ja) supplies Agent page, session panel,
  composer, message/result copy, profile sheet/manager, and Agent settings
  labels. The analysis prompt contract now states that all human-readable
  fields use the configured language and Japanese appears only in quotes,
  word forms, readings and dictionary examples.
- **F8 selection**: `AgentDictionaryPreferences` uses separate
  `agent_dictionary_selected_ids` / `agent_dictionary_mode` keys. The Agent
  page never reads or writes `lookupPreferencesProvider`.
- **F2 profile inbox**: `DictionaryFamiliarizationService.generateMany()`
  returns all proposals without asking consent; `persistDecision()` writes only
  after an explicit decision. `AgentProfileInboxController` is app-scoped and
  `AgentRunController` waits in `AgentRunStatus.awaitingProfile`. Page detach
  cannot call `skipOnce`; closing the sheet keeps the item pending. Decisions
  are persisted by the inbox so run-generated and manager-generated proposals
  share one path.
- **F3 elapsed time**: `startedAt` remains in the app-scoped snapshot;
  `awaitingProfile` counts as running. A wall-clock elapsed test covers a
  10-second absence; run/profile tests assert no extra provider request before
  the user decides.
- **F11/F12 images**: composer supports a camera/gallery bottom sheet,
  multi-select, append, per-image removal and `AgentLimits.maxImagesPerRun`
  (6). Sent thumbnails open the existing `PhotoViewerPage`.
- **F13 profile manager**: `/agent-profiles` lists stored profiles with
  trusted/declined/pending/stale/ unavailable states, Markdown edit, single and
  batch regenerate, and multi-select delete. Regeneration uses the shared
  inbox, not a page-local familiarizer.
- **F14 result actions**: result bubble has regenerate then copy (Markdown via
  `buildAgentResultMarkdown`, no raw JSON/reasoning/paths). Long-press on a
  user message offers copy/edit. `regenerate()` replays the request from the
  familiarization stage, keeps the previous result visible until success, and
  restores it with a notice on failure.
- Wave 2 review follow-up (2026-11-01): profile-language changes apply without a
  dialog; `AgentProfileInboxHost` is shared by the Agent page, profile manager
  and Agent settings and uses a claim guard so a proposal never opens twice.
  Regeneration moved to app-scoped `AgentProfileRegenerationController` (no
  duplicate token spend after leaving/re-entering; title-bar text and
  indeterminate progress). Independent dictionaries may regenerate in parallel;
  only the same dictionary is refused while its request is active, and its
  edit/delete actions stay available. The title lists every active dictionary
  and updates as new requests are added or finish. “不再询问” now saves and
  enables `agent_profiles_auto_accept` (default off; new checkbox in Agent
  settings). Any save made while an Agent page or subpage is mounted (manual or
  auto-accept) shows the shared host toast once per batch. The “详细解析 ·
  依据 N 条” header now counts only adopted citations, matching the filtered
  evidence section and Markdown export. Retry-dictionary shows a spinner; Agent
  no longer auto-scrolls; the profile-manager mode toggle stays in place and the
  composer image notice is centered.
- Model output format: analysis and dictionary profiles use bracket-tag plain
  text (`analysis_tag_parser.dart`, `dictionary_profile_tag_parser.dart`).
  Leaked type/probability markers are stripped; types/confidence are derived
  locally. `tag_block_integrity.dart` checks unclosed/misordered/mis-nested
  blocks and duplicate single-instance tags before one “text unchanged, tags
  only” repair. Legacy JSON output fallback, runtime response schemas and the
  `response_format`/`json_schema` capability flag were removed; DTO JSON remains
  only for local storage.
- Wave 2 verification: `flutter analyze` clean; current test/build results in
  `docs/project-data.md` §2/§5. Device visual/provider/arm64 acceptance remains
  for Wave 4.

Wave 3 implementation (2026-11-01, F1b/F6/F7):

- **F1b**: `AgentLanguageValidator` checks translation, segment interpretation,
  word sense, grammar explanation, option meaning, unresolved reason and model
  supplement; source quotes, word forms, readings and citation snippets are not
  checked. Allowed source terms/readings/quoted material are stripped before a
  conservative script-ratio judgment. On mismatch the orchestrator sends one
  `LANGUAGE CORRECTION TASK` request that keeps tags/ids/citations/quotes and
  only translates human-readable prose; a structurally valid repaired result is
  used. A failed or still-mismatched repair keeps the result and adds a
  localized `warnings` entry rendered in the result view.
- **F6**: `AgentLimits` (`lib/core/models/agent/agent_limits.dart`) is the single
  budget source and is injectable through `agentLimitsProvider`. Evidence lookup
  runs mode-by-mode: all targets exact, then prefix, suffix, incremental. A mode
  with zero new unique citations does **not** stop later modes; normal mode
  progression ends at the global cap, while cancellation aborts and per-target/
  per-dictionary caps skip a target/dictionary without stopping the mode loop;
  duplicate `(dictionaryId, entryKey)` entries are linked, not reissued. When
  UniDic fails/returns no tokens, bounded raw-surface targets keep MDict lookups
  alive: chunks are split by newline/whitespace/punctuation, whole chunks ≤12 chars and
  2–6 char windows are added, candidates go through `lookupCandidatesFor`, and
  raw targets share the same modes and caps. Progress uses `已检索 N / M` from
  the run's limit snapshot.
- **F7**: After initial evidence, one `[COVERAGE]` tag review (small model, one
  tag-format repair). The parser fills `source_id` locally and checks the single
  COVERAGE root, MISSING/DUPLICATE/NOTES parentage, NOTES uniqueness and tag
  closure before accepting a review. Queries are kept only when traceable to
  source text, token surface/lemma/reading/candidates, pattern surface or an
  existing citation key; source refs must exist. Flow A supplements below the cap
  with the same F6 mode order. Flow B verifies model-suggested same-dictionary
  duplicate groups locally by snippet overlap, keeps the denser entry, prunes the
  rest from the bundle/registry, then supplements. At most one review and one
  fallback per run; failure, untraceable queries, no verified duplicates or no new
  evidence produce localized warnings and keep the original evidence.
  `AgentStage.coverage` maps to the lookup progress step; `coverageFallbackUsed`
  is recorded in the result. The `coverage.v1` JSON DTO/serialization remains
  internal; no persistence call is currently wired.
- All Agent prompt text/request builders live in
  `lib/services/agent/agent_prompts.dart`; other Agent files must not embed prompt
  literals.
- Wave 3 verification: `flutter analyze` clean; `flutter test` see
  `docs/project-data.md` §2.1; `flutter build apk --debug` succeeded after the
  prompt/coverage/raw-surface migration. Real provider/arm64/large-dictionary
  smoke remains Wave 4.

P6.6 implementation (2026-11-02, multi-OCR core):

- `AgentOcrVariant` now carries local `origin` (OCR or dictionary repair) and
  prepared variants can be passed through `AgentImageInput`; re-analysis reuses
  the selected OCR text and does not run recognition again. Source/quote
  provenance records `dictionary_repair` locally without serializing paths or
  origins to the provider.
- `OcrConsensus` (`lib/services/agent/ocr_consensus.dart`) computes local
  quality (confidence, script-neutral meaningful characters, duplicate-noise
  ratio, bounded dictionary hit rate), bounded character diff (prefix/suffix +
  LCS for small middles), deterministic variant ranking, and bounded
  dictionary-backed repair suggestions. No kana ratio/matching is used, so the
  signal remains usable for non-Japanese dictionaries. No provider call, image
  upload or automatic text replacement is involved.
- `AgentOcrVariantsController` (`lib/state/agent_ocr_variants.dart`) is
  app-scoped. After the user asks for a comparison it runs unique
  `(engine, mode)` combinations (`paddle_v5/horizontal`, `manga_ocr/vertical`,
  `paddle_v5/vertical`, then `auto`), never dedupes by text (text equality is not
  a duplicate signal), reports a stable error code on failure, and supports
  stop/clear.
- `AgentOcrVariantsPanel` shows variant chips (engine/mode/confidence), quality
  metrics, low-quality warning, difference preview with highlighted changed
  spans, dictionary candidates, and an explicit “re-analyze with this variant”
  action. Applying a candidate creates a `dictionary_repair` variant and starts
  a new run; it never edits the previous result in place.
- `AgentRunResult.ocrQuality` exposes the selected variant's local quality for
  the UI; it is never sent to the provider.
- Automated coverage: quality/diff/ranking/repair unit tests, controller
  generation/dedupe/error/clear tests, prepared-variant orchestrator test, and
  panel widget tests. Real-device visual/OCR quality and real dictionary
  suggestion quality remain Wave 4/P6.6 device acceptance.

P6.6 automated closeout (2026-11-03):

- The P6.6 implementation is frozen for automated verification: `flutter
  analyze` is clean, the suite has 350 declarations (366 executed cases) in 77
  files, and the debug APK builds. The current test baseline is recorded in
  `docs/project-data.md` §2.1.
- No new P6.6 feature is added in this closeout. The remaining P6.6 work is
  device acceptance (real manga pages, forced MangaOCR, the real 463k-entry
  dictionary, 200% font, re-analysis latency) and the gaps listed below.
- Known functional gaps kept for P6.7: the comparison panel is mounted only
  when a displayable result exists, so a run that fails before producing one
  has no multi-OCR entry; per-variant citations are still rebuilt only after
  the user commits a variant; only the selected variant is written to
  `AgentSourceVersion`, and all-variant persistence belongs to the P6.7
  history work.

2026-11-02 stability/feedback fixes:

- **Provider HTTP 400 hardening**: before any request the adapter validates a
  non-empty model, drops whitespace-only messages, requires at least one
  non-system message, merges consecutive Anthropic roles, sanitizes unpaired
  UTF-16 surrogates/control characters, and requires a positive `maxTokens`.
  It deliberately does **not** impose a universal output ceiling: model limits
  differ (deepseek-flash is far above 8,192). Providers have an optional
  `maxOutputTokens` (persisted in `capabilities_json` as `max_output_tokens`;
  0 = unset): OpenAI-compatible omits `max_tokens` when unset and sends it when
  set; Anthropic always sends `max_tokens`, preferring the provider value over
  the request builder's 12,000. HTTP 400 responses are classified from the real
  error body (context length, unsupported output parameter, reasoning/tool
  parameter mismatch, generic invalid parameter) and debug logs record only
  request shape, not prompt text or keys.
- **Reasoning-only stream**: if SSE produced `reasoning_content` but no text,
  the provider now raises `PROVIDER_EMPTY_OUTPUT` immediately instead of
  repeating the same expensive request non-streaming. `finish_reason` is logged
  with the SSE counters. Only a completely empty stream (no reasoning, no text)
  falls back. Stream progress publishes at most every 250 ms because reasoning
  models can emit >10k tiny deltas and the UI shows elapsed time, not characters.
- **P6.6 UI feedback**: the card title is “文字识别结果”; each image is shown as
  a tappable thumbnail using the same full-screen viewer as user messages;
  quality shows “置信度” and “词典命中” capsules with plain percentage values.
  Kana ratio/matching was removed from OCR quality and ranking, and character
  classification is script-neutral for future non-Japanese dictionaries.
- **Per-image comparison state**: `loadingImageIds` / per-image error codes
  replace the single global loading flag; comparing image 1 no longer shows a
  spinner on image 2 and no longer blocks image 2's comparison. Native OCR calls
  are serialized through an internal queue; UI state remains independent.
- **Missing alternative variants**: text-equality dedupe was removed (auto and
  horizontal often return identical text but are still distinct options), OCR
  readiness is awaited before checking vertical availability, and `auto` is
  offered as an alternative when the baseline used horizontal/vertical. The empty
  copy is now “没有可用的其他文字识别结果”.
- **Coverage review stability**: compact coverage input (selected text,
  token/pattern ids, cleaned citation snippets plus retained token/pattern
  offsets and citation `entry_key`/`matched_key`/`headword`), per-item tolerant
  parsing (one malformed MISSING/DUPLICATE no longer discards the review),
  normalization of empty/self-closing sufficient blocks, and debug diagnostics
  for request/parse failures. Every automatic correction (unknown kind, source-N
  remap, priority clamp, truncation) is logged with item index and before/after
  values. Repair requests reuse the normalized text, and normalization is
  idempotent. Its output budget is derived independently by
  `AgentLimits.coverageReviewMaxTokens` from the MISSING/duplicate caps, reason
  length, tag overhead and a safety margin; the estimator uses
  `AgentLimits.coverageCharsPerToken = 1.0` (conservative for CJK) and all
  overhead values live in named `AgentLimits.coverage*` constants. It does not
  follow the analysis request or a global provider ceiling. Genuine request
  failures still keep evidence and show the warning.
- **UniDic path clearing**: empty input (or the explicit “清除” button) clears the
  saved path and invalidates the MeCab service; non-empty invalid paths are still
  rejected and never saved.
- **P6.6 model x orientation matrix**: `OcrPort.recognize` now accepts an optional
  engine constraint. The native OCR plugin forces `paddle_v5` or `manga_ocr` when
  requested (default null keeps the existing best-of behavior) and rejects
  MangaOCR horizontal requests. The Agent generates up to four unique
  `(engine, mode)` variants: `paddle_v5/horizontal`, `manga_ocr/vertical`,
  `paddle_v5/vertical`, then `auto`, so horizontal and vertical no longer show
  near-identical PaddleOCR results under different labels. Maximum four variants
  per source is enforced in the controller and re-analysis.
- **P6.6 UI feedback**: variant chips are left-aligned and wrap by row; each chip
  has a fixed 28dp height and reserves the recommendation icon slot, so selection
  never changes its size. Diff highlights use the dedicated warm
  `AgentTokens.diffHighlightSurface`/`diffHighlightText` pair instead of the
  citation blue, and unchanged text is muted. Agent thumbnails decode at display
  resolution via `cacheWidth`/`cacheHeight` to avoid a full-photo decode when a
  lazily built card enters the viewport.
- **Expanded evidence scroll jank**: `AgentResultView` now splits its expanded
  detail into small blocks and appends them across frames
  (`_ProgressiveResultBody`, 4 initial + 3 per frame); each dictionary
  `_EvidenceGroup` uses the same chunker for its citation rows. Only the first
  `AgentFadeIn.maxAnimatedItems` blocks run the staggered fade, so expanding a
  dictionary evidence card no longer builds the whole result tree and starts
  dozens of animations in one frame. The inline `ExpansionTile` UX is unchanged.
- **Dictionary repair selection**: repair candidates now use the same chip design
  as OCR variants. Unselected candidates stay grey; selecting another candidate
  for the same word replaces the previous one; different words can each keep one
  selection. The “re-analyze with this variant” action stays a bottom-right blue
  `FilledButton.tonal` in both the dictionary-repair section and the OCR-variant
  diff section; it is enabled only when at least one candidate is selected and
  grey/disabled otherwise. Applying selections uses `OcrConsensus.applyRepairs`,
  which replaces spans from the end backwards so multiple words can be applied
  in one new `dictionary_repair` variant without invalidating earlier UTF-16
  offsets.
- **Interpretation percentages**: the tag parser assigns OPTION blocks relative
  weights (0.5 without citations, 0.7 with citations), not model probabilities.
  `normalizeAnalysis` and `salvageAnalysis` now normalize multiple OPTION blocks
  to integer percentages summing to 100 (two 0.7 options become 50%/50%; three
  become 34%/33%/33%). A single OPTION keeps its heuristic value. The prompt
  still forbids model-emitted confidence values; no prompt rule was added for
  this display invariant.
- **Agent output corpus**: `docs/agent_output/` now stores Markdown output
  samples named `YYYY-MM-DD-HH-mm.txt` for manual quality inspection; see
  [`agent_output/README.md`](agent_output/README.md). These files are not
  provider logs and contain no image paths or keys.

P7.0 rich-text post-processing (2026-11-03, incremental):

- After a validated analysis, small-model formatting passes insert
  `[RUBY=reading]base[/RUBY]`, `[BOLD]...[/BOLD]` and
  `[UNDERLINE]...[/UNDERLINE]` into the **detailed** result: the whole “原文”
  section and each segment interpretation. The AI bubble summary remains plain
  text and is not formatted. The prompt uses the fixed strict constraint: no
  character may be changed/deleted/added, except a whole YOMI block may be
  deleted when replaced by equivalent RUBY. It has no vague “return the whole
  original text if uncertain” escape; only a specific uncertain word may be
  left unchanged. AI reads the text itself; UniDic readings are not supplied.
- The analysis prompt asks the result-generation model to wrap reading
  annotations in `[YOMI]...[/YOMI]` inside `[MEANING]` only, e.g.
  `base[YOMI]（reading）[/YOMI]`. Repair/language-repair prompts preserve
  YOMI blocks exactly. `[TRANSLATION]` stays plain.
- `rich_text_tags.dart` strips every known tag and checks balanced, correctly
  nested tags and safe pronunciation annotations without assuming a script.
  RUBY may be nested inside BOLD/UNDERLINE (and BOLD/UNDERLINE may wrap each
  other); style tags may not appear inside a RUBY base. YOMI contents are
  compared after removing full-/half-width punctuation. It also verifies
  retained YOMI blocks are unchanged and in the same base position;
  whole-block deletion is allowed. Model RUBY readings are cleaned of full-/
  half-width punctuation before being stored; an empty or base-equal reading
  removes the RUBY pair. When the formatter wraps an existing
  `surface（reading）`, the duplicate parentheses are collapsed for display and
  Markdown export (`richTextToPlain` still emits one `base（reading）`). The
  processor accepts the result only when the tag-stripped, YOMI-normalized text
  equals the original **character for character** (no trim or Unicode
  normalization). Any change, malformed tag, empty output or provider failure
  discards the formatted block and renders it plain; the run itself is not
  failed and no user-facing error is shown.
- `AgentRunResult.richOriginalText` carries the whole original section;
  `AgentRunResult.richSegmentTexts` is aligned with `analysis.segments`;
  `AgentRunResult.richSegmentNotes` carries the AI-formatted dictionary-fact
  word senses/grammar explanations (not citation snippets). Retained YOMI
  wrappers are stripped and show as `base（reading）`. `AgentRichText` renders
  ruby/bold/underline in the detailed original, segment interpretation and
  dictionary-fact notes only. Ruby uses the body text color and aligns the
  annotated base to the line's alphabetic baseline (the reading sits above and
  never pushes the base down). A reading inside BOLD inherits the bold weight;
  a reading is never underlined, even inside UNDERLINE. Duplicate
  `surface（reading）` annotations produced by wrapping an existing note are
  collapsed to one reading. UNDERLINE is body-colored with 2x thickness. The
  Markdown export uses `richTextToPlain` (RUBY becomes `base（reading）`;
  BOLD/UNDERLINE/YOMI tags are removed) so copied text contains no tags.
- `AgentLimits.enableRichTextPostProcess` (default true) is disabled in tests
  that assert provider request sequences; a `formatting` stage is reported.
- Internal system Prompt instructions are English-only; validation error text
  may remain localized. The user/answer language is still controlled by
  `AgentResponseLanguage`.
- Tests: `rich_text_post_processor_test.dart`, `agent_rich_text_test.dart`,
  `analysis_tag_parser_test.dart`, `agent_language_validator_test.dart`, and
  rich-text cases in `agent_orchestrator_test.dart`.
- P7.1–P7.4 (task split/model routing/concurrency/streaming) are **not**
  implemented; the plan is in
  [`agent_docs/p7-task-decomposition-plan.md`](agent_docs/p7-task-decomposition-plan.md).

Current known gaps:

- Wave 4 device acceptance is not done: real provider/API key, arm64 Agent
  end-to-end, real large-dictionary suffix/incremental smoke, and secure-storage
  device I/O remain unverified. Automated Wave 3 tests do not prove those.
- The coverage review uses the small model and tag text parsed locally; real
  provider tag reliability and latency still need device measurement.
- P7.0 rich-text formatting is applied only to the assistant summary; the
  detailed structured result and Markdown export remain plain. Real-provider
  formatting acceptance, ruby layout at 200% font and small screens still need
  device/visual verification.
- Test coverage gaps: there is no dedicated raw-surface-target cap test (current
  cap tests use token targets), and no dedicated duplicate-`[NOTES]` integrity
  test. The implementation has both paths but the tests do not yet pin them.
- `coverage.v1` still has JSON serialization methods, but no persistence call is
  wired; do not describe it as an active storage format.
- P6.6 device acceptance is pending: horizontal/vertical variant quality on
  real manga pages, dictionary candidate usefulness against the real 463k-entry
  dictionary, contrast/overflow at 200% font, and re-analysis latency.
- P6.6 variant comparison is mounted only when a displayable result exists
  (`agent_message_list.dart`); an OCR/analysis failure before that point has no
  multi-OCR comparison or repair entry yet. Keep this as a documented P6.6/P6.7
  follow-up rather than claiming every failure path is covered.
- Native OCR calls are serialized through a queue; two image comparisons show
  independent loading/error state and can both be started, but the second waits
  for the first engine call to finish.
- Provider 400 handling now reports the actual error-body category, but it does
  not automatically repair context-length or model-specific parameter problems;
  the user still needs to shorten input or adjust the model/provider.
- Provider settings now include an optional `maxOutputTokens` as the last input
  field (Agent settings dialog, blank = default) and recommend leaving it blank
  for OpenAI-compatible services. OpenAI-compatible omits `max_tokens` when
  blank; Anthropic uses it when set, otherwise the request builder's value
  (12,000 for analysis). This is an explicit per-service choice, not a universal
  ceiling.
- Long reasoning-model latency is a model-choice issue, not a removable request
  parameter. The app has no reasoning-effort/thinking-off setting; selecting a
  non-reasoning complex model (for example deepseek-chat/flash) is the current
  way to shorten analysis time. Automated tests cannot prove real provider
  latency.
- P6.6 does not yet show per-variant citations before the user commits to a
  re-analysis; citations are rebuilt after the selected variant is analyzed.
  All variants are in the input envelope, but only the selected variant is
  recorded in `AgentSourceVersion` (the SQLite source-version store is not yet
  wired to persist every variant).
- Process-death recovery of the in-memory profile inbox remains P6.7; the queue
  survives page navigation but not process death.
- P6.7 之后的任务级流式规划：
  [`task-level-streaming-plan.md`](agent_docs/task-level-streaming-plan.md)
  （规划中，未实现）。

Agent output quality samples are stored under `docs/agent_output/` as
`YYYY-MM-DD-HH-mm.txt` Markdown copies (one run per file). They are manual
inspection fixtures, not provider logs; see that directory's README.

### 2026-11-03 Post-stream result latency

The provider stream ending (`finish_reason=stop`) is not the same as the UI
having a result. Three sequential costs used to sit between them:

1. The OpenAI-compatible/Anthropic adapters kept reading the SSE body until the
   socket closed. A proxy or keep-alive connection could therefore add seconds
   after the logical end. They now stop at `finish_reason`, `[DONE]`, or
   `message_stop`, and `_collect` treats `LlmEventType.done` as terminal and
   cancels the subscription.
2. The first parsed/validated analysis was held until the optional validation
   repair, language repair, and (previously) P7.0 rich-text post-processing calls
   finished. `AgentOrchestrator` now emits an `onProvisionalResult` callback
   immediately after the first parse/validation (salvage is used when that first
   analysis is invalid); repair stages stay in `AgentStage.validating` instead of
   returning to `reasoning`. `AgentRunSnapshot.provisionalResult` renders the
   summary with “结果已出，正在复核…”, and the final result replaces it on
   completion. The app controller now passes `onRichTextReady`, so display-only
   formatting starts after the core result and is applied when it arrives.
3. The progress counter now receives only the accumulated character count.
   `_collect` no longer converts the growing buffer to a String on every delta,
   and stage transitions publish the final count; the UI's elapsed label uses a
   local timer, so no 4 Hz whole-page state updates are needed.

No run-result SQLite write sits on this path; profile decisions are the only
persistence and happen before their futures are released. Debug builds log
`[AgentTiming]` for provider headers/first event/finish/stream close, each
`_collect` label, stage transitions, parse/validate/language timing, provisional
emission, controller state changes, and the first result frame. Logs contain
durations and counts only — never prompt text, citations, paths, or keys.
`test/agent_orchestrator_test.dart`, `test/openai_compatible_provider_test.dart`,
`test/provider_http_test.dart`, and `test/agent_wave2_ui_test.dart` cover the
provisional-before-repair, held-socket, `[DONE]`, and provisional-bubble cases.

**2026-11-03 performance pass 2**: rich-text sections use a bounded worker pool
(`AgentLimits.richTextConcurrency`) and per-run text dedupe with a length-derived
output budget; the app controller applies formatting after `done`. The analysis
prompt uses a compact projection (selected OCR variant once, no
`lookup_candidates`/`tool_call_id`/internal budget, evidence does not repeat the
source text). `_collect` publishes accumulated lengths instead of full strings.
Evidence lookups are batched per mode through `BatchLookupPort`/`lookupMany`
(`AgentLimits.lookupBatchSize`), and coverage review is adaptive
(`AgentLimits.adaptiveCoverageReview`). New tests:
`test/evidence_builder_batch_test.dart`, compact-prompt/async-rich-text cases in
`test/agent_orchestrator_test.dart`, and the post-done rich-text controller case
in `test/agent_lifecycle_test.dart`.

## Tests and build

```text
flutter analyze  -> No issues found (see docs/project-data.md §2.1)
flutter test     -> see docs/project-data.md §2.1
flutter build apk --debug -> see docs/project-data.md §5
```

Device integration: current suite counts/results are in
`docs/project-data.md` §3. Known issue: MDict's final search assertion does not
find `とうきょう【東京】`; this is the pre-existing non-Agent search test, not
an Agent path. No arm64/real-device Agent run was performed.

Device smoke: a real gallery image (`何卒宜しくお願い致します。\n東京で食べた。`)
completed on-device OCR → UniDic → MDict evidence → DeepSeek streaming analysis
→ Chinese translation/per-sentence notes/source quotes/dictionary-ordered
citations in the Agent page. The reasoning stream was large (~20k chars) and the
final JSON ~3k chars; DeepSeek `deepseek-flash` can take ~50s, which is why live
progress is required.

New test files include: `agent_models_test.dart`, `lookup_gateway_test.dart`,
`grammar_patterns_test.dart`,
`dictionary_probes_test.dart`, `provider_payload_test.dart`,
`openai_compatible_provider_test.dart`, `anthropic_provider_test.dart`,
`fake_provider_test.dart`, `profile_fingerprint_test.dart`,
`dictionary_familiarization_service_test.dart`,
`unidic_familiarization_service_test.dart`, `evidence_builder_test.dart`,
`agent_validator_test.dart`, `agent_orchestrator_test.dart`,
`agent_page_test.dart`, `agent_run_controller_test.dart`,
`agent_lifecycle_test.dart`, `agent_result_view_test.dart`,
`provider_http_test.dart`, `provider_retry_test.dart`,
`analysis_normalizer_test.dart`, `tag_block_integrity_test.dart`,
`agent_settings_page_test.dart`, `lookup_actions_test.dart`,
`ocr_model_download_controller_test.dart`.
Wave 2 adds `agent_language_test.dart`, `agent_dictionary_preferences_test.dart`,
`agent_profile_inbox_test.dart`, `agent_profile_regeneration_test.dart` and
`agent_wave2_ui_test.dart`, plus new queue/gate/regenerate/multi-image cases in
`agent_lifecycle_test.dart` and `agent_page_test.dart`.
Wave 3 adds `agent_language_validator_test.dart`, `agent_coverage_test.dart`
and `agent_coverage_orchestrator_test.dart`, plus lookup-mode/cap cases in
`evidence_builder_test.dart` and language/coverage cases in
`agent_orchestrator_test.dart`.
P6.6 adds `ocr_consensus_test.dart`, `agent_ocr_variants_test.dart` and
`agent_ocr_variants_ui_test.dart`, plus a prepared-variant case in
`agent_orchestrator_test.dart`.
P7.0 adds `rich_text_post_processor_test.dart`, `agent_rich_text_test.dart`, and
rich-text accept/fallback cases in `agent_orchestrator_test.dart`.

## P6.7 design decisions (2026-11-03, design-only)

- **Gate**: per `CLAUDE.md`, F1–F17 / Wave 4 device acceptance is still open, so
  no user-visible P6.7 feature was implemented. This step only updates design,
  contracts, schemas and tokens; it adds no P6.7 `lib/`, `test/` or build
  changes.
- **History**: independent `/agent-history` (not the home corpus history); one
  entry = one run/analysis, read-only; no images/thumbnails/paths in AgentStore;
  manual delete/clear only; startup marks unfinished runs `interrupted`; every
  OCR variant is persisted as text; pending profile inbox survives restart;
  citations re-open by exact key and fall back to the saved snippet.
- **Pitch**: only UniDic accent fields 24–26. Real 2025.12 output was probed on
  the x86_64 emulator and verified (`aType`: 橋=2, 箸=1, 端=0, 東京=0, 日本=3,
  食べる=2, 花=2, 雨=1, 飴=0, 今日=1). The temporary probe test was removed after
  use. The high/low line appears only in word notes/dictionary-fact rows;
  missing/invalid data renders plain text; no AI-inferred pitch.
- **DSL**: safe JSON AST + built-in rule sets + preview/version/rollback; reader,
  photo and corpus first; Agent results later; no free-form editor in P6.7.
- **Markdown**: bracket-tag wire format remains; Markdown only for copy/export
  and restricted profile preview; no general Markdown renderer.
- **P6.6 carryovers**: failed-run multi-OCR entry and per-variant citation
  preview are now part of the P6.7 design; implementation follows Wave 4.
- **Docs/schemas**: `docs/phase6-agent-design.md` §17.2,
  `docs/phase6-agent-contracts.md` §14, `docs/design-tokens.md` P6.7 rows,
  `docs/project-rules.md` R-AGENT-24–27, and new schemas under
  `docs/schemas/agent/` (`history-entry.v1`, `history-result.v1`, `pitch.v1`,
  `annotation-rules.v1`). JSON syntax was validated; current test/build numbers
  are unchanged and no new tests were run in this design-only step.

## Not implemented / next

1. **2026-10-31 device feedback (F1–F17)**: Waves 1–3 are implemented and
   verified by unit/widget tests; Wave 4 device acceptance remains
   (real provider, arm64, large-dictionary suffix/incremental smoke). The
   2026-11-02 user instruction to continue development was used to start P6.6;
   this does not turn the pending Wave 4 device checks into verified results.
2. **P6.6 multi-OCR**: core implemented 2026-11-02 (quality/diff/ranking,
   dictionary-assisted candidates, user-confirmed variant re-analysis and UI).
   Remaining: real-device visual/OCR/dictionary acceptance. The failed-run
   multi-OCR entry and per-variant citation preview are now included in the P6.7
   design (§17.2.7); persistence of every variant is part of P6.7 history work.
3. **P6.7**: design recorded 2026-11-03 (history one run/read-only/text-only,
   safe rich text/ruby/UniDic pitch, annotation DSL with built-in rules and
   preview/rollback, Markdown export/restricted preview, provider
   test-connection, release packaging/licence review). Implementation has not
   started and is gated by Wave 4.
4. Real device verification: provider network calls with a real key, MDict
   `sample`/`suggest` against the 463k-entry dictionary, Agent end-to-end on
   arm64, and secure-storage read/write/clear on device.
5. Agent conversation persistence: `AgentStore` schema is ready, but the
   controller keeps the current run only in memory; history/UI persistence and
   process-death recovery are pending. The P6.7 design (one run per history
   entry, read-only detail, no image paths, startup `interrupted`) is recorded
   in §17.2.2 and contract §14.1; no implementation yet.
6. Tool calling: removed by decision (2026-10-31). The pipeline is fixed and the
   model has no tools; the contracts keep the tool table only as a future
   reference. Reintroducing tool calls requires a new ADR plus tool_use/
   tool_result message support.
7. Provider reliability: OpenAI/Anthropic now use a provider-neutral cancel
   token, retry 429/5xx/timeouts up to 3 attempts, parse multi-line SSE data and
   stream error objects. Remaining: familiarization cancellation and exposing a
   structured retryable error detail for every provider failure.
8. No commit/reset was performed by this session; the tree also contains an
   external save-point commit (`c79d03f`) that predates the latest edits.
9. **Conversational Agent UI v2**: `docs/design-tokens.md` defines the
   message-first Agent layout (about 80% message area, ≥70% on small screens,
   16/4 bubbles, fixed composer, streaming/stop, folded evidence, error cards,
   grouped settings). The current P6.5 page has the conversation layout
   (bubbles/folded evidence/fixed composer), an app-scoped run controller,
   thinking-time progress, and the core v2 tokens in `app_tokens.dart`. History,
   full accessibility/200% verification, provider cancellation and complete v2
   acceptance are still pending. Do not describe the remaining items as
   implemented.
