# Phase 6 status — dictionary assistant core

Date: 2026-10-30
Base: Phase 5 complete (`docs/phase5-status.md`)
Design: `docs/phase6-agent-design.md` v2
Contracts: `docs/phase6-agent-contracts.md` / `docs/schemas/agent/`

> **Status: P6.1–P6.5 core implemented; P6.6 (multi-OCR variants/repair) and
> P6.7 (annotation DSL/Markdown/ruby/pitch/release) are not implemented.**
> 2026-10-31 real-device feedback F1–F17 is documented but **not implemented**;
> follow `docs/agent_docs/device-feedback-2026-10-31.md` before extending the
> Agent. Automated tests use fake providers and never a real API key. On
> 2026-10-30 a user-configured DeepSeek provider was smoke-tested on the x86_64
> emulator (key never logged); arm64/real manga-page and real-dictionary
> `sample`/`suggest` acceptance still remain. The review backlog in
> `docs/agent_docs/phase6-pipeline-review.md` is authoritative for open gaps.

## Implemented

### P6.1 Capability layer

- `lib/core/models/agent/` DTOs: input envelope, evidence/citation, analysis,
  dictionary/UniDic profile, quote/source version, tool spec/result.
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
- Tool registry/adapters: `unidic.tokenize`, `mdict.lookup`, `mdict.suggest`
  (model-visible); `ocr.recognize`, `dictionary.sample`, `unidic.profile`
  (orchestrator-only). Minimal JSON-schema validator and per-run budget.
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
  the response-language setting (`follow` infers Japanese from kana, English
  from Latin-only input, otherwise Chinese). Raw streamed JSON, reasoning text
  and character counts are never rendered. Validated result items fade in one by
  one after validation; there is no streaming JSON partial display. Citations
  are numbered “依据1/依据2…” and consolidated once per segment instead of after
  every word note. The safe model-generated “summary” field is deferred (P3).
- **Schema success**: analysis/familiarization JSON Schema is included in the
  prompt for `json_object` providers; analysis requires non-empty
  `translation`/`segments` and a matching `source_id`.
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

### 2026-10-31 real-device feedback backlog (documented, not implemented)

The user reported 17 additional issues after a real-device P6.5 trial. The
authoritative plan, current-code evidence, wave ordering and acceptance
criteria are in
[`docs/agent_docs/device-feedback-2026-10-31.md`](agent_docs/device-feedback-2026-10-31.md).
Summary:

- **Wave 1 (quick/low-risk)**: short citation pills (F4), remove `qN` markers
  (F5), 3.5-row dictionary filters (F9), Chinese provider labels/presets (F10),
  current-dictionary-only entry links (F15), app-scoped OCR download progress
  (F16).
- **Wave 2 (Agent lifecycle/UI)**: Chinese-first default and no input-language
  heuristic (F1/F17), independent Agent dictionary preferences (F8), app-level
  dictionary-profile inbox that gates tokenizing (F2), elapsed time across page
  leave (F3), camera/gallery multi-image input (F11), full-screen sent-image
  viewer (F12), profile manager (F13), result action row/copy/edit/regenerate
  (F14).
- **Wave 3 (evidence)**: global `AgentLimits` and exact → prefix → suffix →
  incremental lookup (F6); one schema-constrained coverage review with at most
  one supplementary lookup pass (F7); output-language field validation and one
  repair (F1b).
- F2 must precede F7/F13/F14 profile work. F6 must precede F7. F17 must precede
  all Agent UI localization work. Do not start P6.6/P6.7 from this backlog.

Current behavior that differs from the target:

- `AgentPage.dispose()` detaches the profile handler and
  `AgentRunController` returns `skipOnce` when no handler is attached
  (`lib/state/agent_run_controller.dart:205-220`), so a profile generated while
  the user is away is not saved and tokenizing can start. This is F2.
- The default answer language is still `follow`, and `resolveAgentUiLanguage`
  still infers Japanese/English from the input
  (`lib/services/agent/agent_messages.dart:7-29`). This is F1/F17.
- Agent dictionary selection is still seeded from the lookup preference and is
  not independently persisted (`lib/features/agent/agent_page.dart:52-58`).
  This is F8.
- Evidence lookup is exact→prefix only and the `60` limit is hard-coded in
  several places (`lib/services/agent/evidence_builder.dart:23-25`,
  `lib/services/agent/agent_orchestrator.dart:45-47`). This is F6.

## Tests and build

```text
flutter analyze  -> No issues found
flutter test     -> 206 tests passed
flutter build apk --debug -> success
```

Device integration on the x86_64 emulator: MeCab/UniDic 4/4 passed;
MDict 5/6 passed (home label now reaches the search page, but the final search
assertion did not find `とうきょう【東京】`; this is the pre-existing non-Agent
search test, not an Agent path). No arm64/real-device Agent run was performed.

Device smoke: a real gallery image (`何卒宜しくお願い致します。\n東京で食べた。`)
completed on-device OCR → UniDic → MDict evidence → DeepSeek streaming analysis
→ Chinese translation/per-sentence notes/source quotes/dictionary-ordered
citations in the Agent page. The reasoning stream was large (~20k chars) and the
final JSON ~3k chars; DeepSeek `deepseek-flash` can take ~50s, which is why live
progress is required.

New test files include: `agent_models_test.dart`, `lookup_gateway_test.dart`,
`agent_tool_registry_test.dart`, `grammar_patterns_test.dart`,
`dictionary_probes_test.dart`, `provider_payload_test.dart`,
`openai_compatible_provider_test.dart`, `anthropic_provider_test.dart`,
`fake_provider_test.dart`, `profile_fingerprint_test.dart`,
`dictionary_familiarization_service_test.dart`,
`unidic_familiarization_service_test.dart`, `evidence_builder_test.dart`,
`agent_validator_test.dart`, `agent_orchestrator_test.dart`,
`agent_page_test.dart`, `agent_run_controller_test.dart`,
`agent_lifecycle_test.dart`, `agent_result_view_test.dart`,
`provider_http_test.dart`, `provider_retry_test.dart`,
`analysis_normalizer_test.dart`, `analysis_schema_contract_test.dart`.

## Not implemented / next

1. **2026-10-31 device feedback (F1–F17)**: execute the wave order in
   `docs/agent_docs/device-feedback-2026-10-31.md`. Wave 1 quick UI/non-Agent
   fixes; Wave 2 language/profile queue/multi-image/action row; Wave 3 lookup
   completeness + coverage review. **Do not start P6.6/P6.7 until these
   feedback items are closed or explicitly deferred.**
2. **P6.6 multi-OCR**: `ocr.consensus` variants, diff/hit-rate scoring,
   dictionary-assisted repair suggestions and the Agent OCR-version UI. The
   current Agent uses one OCR mode per image.
3. **P6.7**: annotation DSL, Markdown/ruby/pitch rendering, history/session UI
   (tables exist; no write/read UI yet), provider test-connection, release
   packaging/licence review.
4. Real device verification: provider network calls with a real key, MDict
   `sample`/`suggest` against the 463k-entry dictionary, Agent end-to-end on
   arm64, and secure-storage read/write/clear on device.
5. Agent conversation persistence: `AgentStore` schema is ready, but the
   controller keeps the current run only in memory; history/UI persistence and
   process-death recovery are pending.
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
