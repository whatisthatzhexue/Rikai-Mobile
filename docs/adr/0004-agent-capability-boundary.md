# ADR 0004: Agent capability ports and deterministic citation pipeline

- Status: proposed (Phase 6 design only; not implemented)
- Date: 2026-10-30

## Context

Phase 6 adds an optional dictionary assistant that calls a user-configured text
LLM. The existing app already has clean, UI-free services for OCR
(`OcrService`), tokenization (`MecabService`), and dictionary lookup
(`MdictService`), but the lookup flow also contains UI-coupled duplication
(`performLookup`, `LookupSearchNotifier.search`). A free-form agent loop would
let the model decide which words to look up, in which dictionary order, and
which evidence to cite. That conflicts with the product requirements:

- every factual answer must be traceable to a real dictionary entry;
- the user's dictionary order is authoritative;
- images must never leave the device;
- strict mode must not fabricate when evidence is missing;
- per-session dictionary selection must not mutate the global lookup filter.

## Decision

1. Introduce narrow Dart **ports** around existing services:
   `OcrPort`, `TokenizePort`, `LookupPort`, `DictionarySamplePort`, `LlmPort`,
   `SecretPort`. Ports are typed, UI-free, and explicitly parameterized; they do
   not read Riverpod state.
2. Expose a smaller **tool** surface to the model through JSON Schema:
   `unidic.tokenize`, `mdict.lookup`, `mdict.suggest`. OCR, dictionary sampling,
   and UniDic profiling are `orchestratorOnly` and invisible to the model.
3. Run a **fixed pipeline** rather than a free ReAct loop:
   OCR → dictionary familiarization → tokenize → evidence gather → model
   reasoning → validation. The model may request a bounded number of extra
   lookups, but the orchestrator prefetches every token/grammar target in user
   dictionary order.
4. Issue **citations only from the orchestrator** (`CitationRegistry`) and
   validate citation IDs, source quotes, dictionary order, and strict-mode
   claim classes before rendering. The model never receives image paths, raw
   HTML, MDD resources, or API keys.
5. Keep UI and Agent on the same capability implementation: extract a pure
   `LookupGateway` from the existing UI lookup paths and an `OcrWorkflow` that
   bundles readiness, recognition, and text composition.

## Alternatives considered

- **Free ReAct loop with all tools visible.** Rejected: dictionary order,
  citation completeness, cost, latency, and testability are harder to
  guarantee; the product workflow is fixed.
- **No tools at all; one giant prompt containing all dictionary text.**
  Rejected: context bloat, privacy/copyright risk, and no way to prove which
  entry supported a claim.
- **Let the model call OCR with a local image path.** Rejected: the path could
  leak into the provider request; OCR remains a local orchestrator step.
- **Store API keys in SharedPreferences for simplicity.** Rejected by the
  privacy boundary; keys belong in Android Keystore-backed secure storage.
- **Reuse `EntryRenderer` to build LLM evidence.** Rejected: it writes MDD
  resources and emits `file://` URLs for a WebView; evidence needs plain-text
  snippets only.

## Consequences

- Existing offline flows remain unchanged; the ports are adapters, not a
  rewrite.
- Agent behavior is deterministic and testable with fake ports/providers.
- The model has less freedom but cannot reorder dictionaries or invent sources.
- A new `MdictService.sample`/`suggest` surface and a pure `LookupGateway` are
  required before the Agent UI can be built.
- Phase 6 stays gated by Phase 4.5/Phase 5 acceptance; this ADR does not
  authorize implementation.
