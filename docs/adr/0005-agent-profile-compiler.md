# ADR 0005: Agent profile compiler and single-query analysis

- Status: proposed; Phase 0 decision record. Phase 1a (F7 compound expansion),
  Phase 1b (profile compiler v2), Phase 2 (request pipeline) and Phase 3
  (conditional dictionary fan-out, default off) implemented 2026-11-06;
  Phase 4 not implemented.
- Date: 2026-11-04
- Update 2026-11-06: Phase 1a implemented. The F7 compound guard is
  token-based (default 6 overlapping tokens), not a 12-character cap;
  character counts do not transfer across writing systems. Phase 1b adds
  directional language pairs, intro and local coverage metrics to profiles;
  no automatic network prewarm was added. Phase 2 adds a local intent hint
  and content-free `AgentRunTelemetry`; it still uses one main analysis call.
  Phase 3 adds opt-in per-dictionary fan-out with bounded concurrency and local
  merge; default remains off until real provider/device acceptance.
- Related: ADR 0004 (accepted), `docs/agent_docs/agent-refactor-idea-plan.md`

## Context

`Agent-Refactor-Idea.txt` proposes a multilingual, dictionary-aware Agent
topology: per-word-list `explore_task`, per-tag `struct_agent`/`language_agent`,
per-dictionary `search_agent`/`summary_agent`, per-sentence `meaning_agent` for
user requests, and a `supervise_agent` that selects dictionaries. Its product
goals match Phase 6: mechanical lookup first, evidence post-filtering, strong
dictionary grounding, multilingual dictionary metadata, user-controlled
dictionaries, and an offline core.

The proposed topology does not match the shipped engineering boundary. It turns
deterministic work into LLM calls and creates four nested loops:

- dictionary × word list × tag for profile exploration;
- per-tag `struct_agent` format refinement;
- per-sentence `meaning_agent` for one user request;
- LLM-driven search-mode/query expansion inside a word lookup.

Under the review's stated assumptions (5 dictionaries, 3 word lists, 5 tags,
10 sentences), the proposal is estimated at roughly 180–235 model calls for a
cold start plus one request. The current fixed pipeline uses a few calls: one
main analysis, a conditional coverage review, conditional repairs, and an
optional rich-text pass. The proposal also conflicts with the accepted
boundary: model tool loops (ADR 0004, R-AGENT-01/02), model-selected
dictionaries (R-AGENT-04/09/11), and profile user confirmation (R-AGENT-10).

The product insight behind the proposal is still valuable: dictionary profiles
need directional language metadata and a short intro; a compound/fixed
collocation such as ところが may deserve its own lookup even when its pieces are
tokenized separately; word lists may be useful as optional coverage packs. The
decision below keeps those parts without adopting the multi-agent topology.

## Decision

1. **Reaffirm ADR 0004.** Keep the fixed pipeline, the no-tools boundary, the
   orchestrator-issued citations, and user-controlled dictionary selection. No
   model tool loops, no model-selected dictionaries, no model-driven search
   mode loop.

2. **Treat the dictionary profile as a compile-time artifact.** Build it from
   bounded, deterministic probes (diverse parts of speech, scripts and entry
   shapes), one small-model batch per 1–3 dictionaries, at most one
   format-correction call, local validation, and the existing user
   confirmation. Cache it by dictionary content/encoding plus schema/prompt
   version, not by the user's word-list selection.

3. **Keep the profile dictionary-scoped.** A profile describes the dictionary,
   not a particular enabled word list. Changing word-list selection does not
   invalidate a valid profile. Word lists, if retained, are coverage packs and
   do not drive format inference.

4. **Add directional language metadata and a short intro to the profile.**
   The profile should distinguish source and target languages (for example
   ja→zh versus zh→ja), not only a flat language list. Detect language pairs
   locally from script ratios and dictionary metadata; call a small model only
   when the local result is ambiguous. Exact field names and serialization are
   defined in the Phase 1 contracts/schema update, not in this ADR.

5. **Analyze a user request with one complex-model call.** Give the model the
   full source text, UniDic tokens/patterns, citations and confirmed profiles.
   Content/function word status is a local evidence flag, not two separate
   dictionary tasks. Keep the existing bracket-tag protocol and validators.

6. **Use the F7 coverage review as the only bounded expansion path.** The
   review may propose traceable MISSING queries, including a contiguous
   compound or fixed collocation whose pieces were tokenized separately. Phase 1
   adds the prompt guidance and a strict local guard; it does not add a
   per-word loop. Details are in the design delta §3.

7. **Route by task, not by agent count.** Small model: profile compilation,
   coverage review, format/language repair, rich-text formatting. Complex
   model: the main analysis. Rich-text remains post-result and off the critical
   path.

8. **Allow conditional fan-out only by dictionary.** If the number of
   dictionaries or the evidence exceeds the context budget, run one analysis
   per dictionary with bounded concurrency (2–3), merge locally, and re-run the
   validator. Never fan out by sentence or by word.

9. **Scope multilingual support explicitly.** Japanese source text is the
   supported path. Non-Japanese source requires a real `TokenizerPort`
   implementation; until then, degrade to bounded script-based lookup and do
   not claim token/grammar structure.

10. **Do not add an orchestration dependency.** Dart `Future.wait` and a
    bounded queue are sufficient. No LangChain/LangGraph-style runtime.

## F7 compound expansion (Phase 1, not implemented)

The F7 coverage review remains the only bounded expansion path. It may request
one contiguous compound or fixed collocation as a MISSING query (for example
`ところが` instead of `ところ` + `が`). The guard is token-based, not
character-based: exact source substring, no line break, at most 6 overlapping
source tokens (a configurable `AgentLimits` budget); without tokenization only
known token/pattern/entry terms are accepted. There is no hard-coded character
cap, so long single-token words and multiword phrases survive multilingual
support. Implementation, prompt text and tests are in the plan §3; no prompt,
validator or test change is part of Phase 0.

## Alternatives considered

- **Implement the idea literally.** Rejected: call amplification, per-sentence
  context loss, LLM-as-parser, and conflicts with R-AGENT-01/02/04/09/11.
- **Per-sentence `meaning_agent`.** Rejected: higher cost and worse cross-sentence
  reference resolution; the full source is already available to one analysis.
- **LLM-driven search mode/term loop.** Rejected: unbounded latency and a tool
  loop; local candidate expansion plus F7 already covers bounded expansion.
- **Two `summary_agent` calls per dictionary.** Rejected: structured profile
  results are locally mergeable.
- **21-word × 5-tag word lists as the profile driver.** Rejected: noun-biased,
  statistically noisy for coverage, and only five entries for format inference.
- **Model-generated word lists on the critical path.** Rejected: unnecessary
  call and quality variance; static or user-imported packs are cheaper.
- **Relax profile user confirmation.** Rejected for now: it would require an
  explicit R-AGENT-10 change; this ADR does not make that change.

## Consequences

- Profile generation remains bounded and cacheable: the first run pays one
  small-model call per dictionary (batched), later runs pay zero.
- User requests stay at one main analysis call plus conditional review/repair;
  cost and latency scale with evidence, not with sentence count.
- The idea's valid parts survive: directional language pairs, profile intro,
  per-dictionary failure isolation, and optional word-list coverage packs.
- The F7 compound capability is explicitly **not implemented** until Phase 1
  prompt/guard/tests land; documentation and UI do not present it as
  implemented before then.
- Rule changes are not made here. Any future relaxation of profile
  confirmation or dictionary selection needs its own rule/ADR decision.

## References

- [Agent 重构实施计划](../agent_docs/agent-refactor-idea-plan.md)
- [ADR 0004](0004-agent-capability-boundary.md)
- `docs/project-rules.md` R-AGENT-01/02/04/09/10/11/12/13/22
