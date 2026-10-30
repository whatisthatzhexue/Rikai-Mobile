# Phase 6 词典助手管线评审

- 日期：2026-10-30
- 状态：评审完成；**H1/H8 未关闭，H2 已修复，H3–H7 部分修复**（2026-10-30
  管线加固，见文末 §7）。原始评审只读代码与文档，未修改业务代码、未运行设备测试。
- 评审范围：
  - 设计/契约：`docs/phase6-agent-design.md`、`docs/phase6-agent-contracts.md`、
    `docs/phase6-status.md`、`docs/adr/0004-agent-capability-boundary.md`、
    `docs/schemas/agent/`
  - 实现：`lib/services/agent/`、`lib/features/agent/`、
    `lib/state/agent_providers.dart`、`lib/services/storage/agent_store.dart`、
    `lib/services/security/secret_store.dart`
  - 测试：`test/agent_*`、`test/*provider*`、`test/evidence_builder_test.dart`
- 方法：逐文件阅读实现与契约，对照设计 v2 的流水线、工具可见性、citation/
  quote 规则、预算与隐私边界；记录“实现行为 vs 设计/契约”的差异，并用
  file:line 标注证据。

## 总结

P6.1–P6.5 的固定流水线已经能完成一条 happy path：文本/单图 → 本机 OCR →
UniDic 分词 → 逐词/语法 MDict 查词 → 一次 LLM 调用 → citation/quote 校验 →
结果渲染。但从管线角度看，仍存在 **8 类高优先级问题**，其中前 3 类会直接影响
P6.6 的可行性或真实 provider 的可用性：

1. 模型工具调用层没有接入，而且当前 LLM Port 也无法表达 tool_use/tool_result；
2. OpenAI-compatible/DeepSeek 生产路径没有 JSON schema 回退；
3. 严格模式可以接受空结果/零 citation，且模型可通过选择 `epistemic` 标签绕过
   严格校验；
4. 取消是表面取消，取消后快速重开会产生并发 run 竞态；
5. 多源输入只对 primary source 生成 quote；用户文本既当指令又当 evidence；
6. 失败路径缺少修复/partial result/provider 重试，词典错误被吞，无 UniDic
   直接中断；
7. 设置与密钥安全缺口（Base URL、清除 Key、capability、日志、payload guard）；
8. AgentStore 的会话/运行/引用表全部未使用，结果只存在页面 State。

建议：**在继续 P6.6/P6.7 之前先解决 H3–H6 的管线正确性，并先决策 H1 的工具
循环范围**；否则多 OCR/修复 UI 会建在不可取消、不可修复、不可表达多源输入的
管线上。

## 1. 当前管线实际行为

入口：`AgentPage._send`（`lib/features/agent/agent_page.dart:123-273`）构造
`AgentOrchestrator` 并调用 `run()`。

`AgentOrchestrator.run`（`lib/services/agent/agent_orchestrator.dart:62-290`）：

1. `prepare`：校验文本/图片、至少一本词典、provider 与模型名。
2. `ocr`：逐张图片调用 `OcrPortAdapter.recognize`（内部 ensureReady →
   recognize → composeOcrText），生成 `src-N` / `var-N`。
3. 总字符数检查：>6,000 直接报“请选择要分析的段落”。
4. `familiarizing`：对选中 MDict 做有界采样，小模型生成档案，`onProfile`
   回调展示确认 sheet；已确认/已拒绝的档案按指纹复用。UniDic 做确定性观察。
5. 只为 `_primarySource()` 生成 quotes（优先第一张图片）。
6. `tokenizing`：`EvidenceBuilder` 对**所有 source**（包括用户输入文本）分词、
   匹配语法模式、按“语法模式 → 内容词 → 功能词”去重预取，最多 120 个目标、
   60 个 citation；单目标先 exact，未命中再 prefix。
7. `reasoning`：构造**一次** `LlmRequest`，输入为 input envelope + evidence +
   quotes + 已确认档案；**请求里没有 `tools`**。`_collect` 只累积 textDelta，
   `toolCall` 事件被直接忽略。
8. `validating`：`AgentValidator` 检查 citation 存在性、quote/literal、严格模式
   的 claim 类型；失败即抛 `AgentRunFailure(VALIDATION_FAILED)`。
9. `done`：返回 `AgentRunResult`，只在 `AgentPage` 的 State 中渲染；不写
   `agent_runs`/`agent_messages`/`agent_citations` 等表。

模型可见工具 `unidic.tokenize` / `mdict.lookup` / `mdict.suggest` 和
`AgentToolRegistry` 只在测试中直接构造；`createDefaultAgentToolRegistry()`
无生产调用。`OcrWorkflow` 也未被 UI 或 Agent 使用。

## 2. 高优先级问题

### H1. “固定流水线 + 受限工具调用”实际只实现了固定流水线

证据：

- `docs/phase6-status.md:124-125` 已承认“bounded model tool calls ... not wired”。
- `lib/services/agent/analysis_prompts.dart:212-253` 构造 `LlmRequest` 时没有
  `tools`；`lib/services/agent/agent_orchestrator.dart:400-429` 的 `_collect`
  直接 `break` 掉 `LlmEventType.toolCall`。
- `lib/services/agent/tools/default_tools.dart:6-14` 的
  `createDefaultAgentToolRegistry` 无生产调用；`AgentToolRegistry`、
  `AgentToolBudget`、`AgentToolContext` 与六个工具都只在测试中使用。
- 更根本的是 `lib/services/agent/ports/llm_port.dart:25-37` 的 `LlmMessage`
  只有 `LlmTextPart`；没有 assistant `tool_use` / `tool_result` 的结构，
  `LlmRole.tool` 无法携带 `tool_call_id`。OpenAI/Anthropic adapter 也只序列化
  `{role, content: string}`，无法完成一次工具调用往返。
- `lib/services/agent/tools/mdict_tools.dart:71-78` 的 `mdict.lookup` 接受任意
  `query`，未实现契约要求的“查询必须能追溯到源文本/token/语法模式/suggest
  结果”；`mdict.suggest` 返回 `List<String>`，与契约的
  `{text, dictionary_id}` 不一致。
- `AgentToolSpec.maxCallsPerRun` 未被 `AgentToolRegistry` 执行；工具超时只返回
  `TOOL_TIMEOUT`，不会取消底层 future。

影响：P6.6 的“多 OCR/词典辅助修复”如果依赖模型补查，当前 LLM Port 无法承载；
即使只做 orchestrator-only 多 OCR，也需要先明确“是否保留工具调用”。当前
`AgentToolRegistry`/`CitationRegistry.issueFromLookup` 等属于死代码，容易让
后续开发者误以为工具链已经可用。

建议：先做产品决策。方案 A（推荐当前范围）：明确降级为“固定流水线、模型无
工具”，P6.6 多 OCR 由 orchestrator 调用 `ocr.recognize`，同步修正 contracts/
README/CLAUDE/ADR。方案 B：扩展 `LlmMessage` 为 `tool_use`/`tool_result`
消息模型，补 OpenAI/Anthropic 流式工具参数累积、预算、query 追溯与 citation
上限，再接入工具循环。

### H2. OpenAI-compatible / DeepSeek 生产路径缺少 JSON schema

证据：

- `lib/features/settings/agent_settings_page.dart:199-202` 把所有
  OpenAI-compatible provider 存成 `supportsJsonSchema: false`（只有 Anthropic
  为 true）。
- `lib/services/agent/providers/openai_compatible_provider.dart:180-194` 在
  `supportsJsonSchema=false` 时只发 `response_format: {type:'json_object'}`。
- `lib/services/agent/analysis_prompts.dart:14-48` 的 system prompt 只说
  “matching the requested schema”，从未把 schema 字段结构写进 prompt；
  `dictionaryProfileBatchResponseSchema()` 同样只经 `responseFormat` 传递。
- `test/openai_compatible_provider_test.dart:44-103` 用手工
  `supportsJsonSchema: true` 的 config 测 `json_schema` 分支；生产配置走的是
  `json_object` 分支，未被测试。

影响：DeepSeek 是首要 provider，但模型不知道 `translation/segments/
word_notes/epistemic/quote_id` 等字段结构，极易返回不可解析或不可校验的 JSON；
严格模式下会整次失败。

建议：当 `supportsJsonSchema=false` 时，把 analysis/familiarization 的 schema
（或等价字段说明+示例）内联进 user prompt；provider 设置中允许用户开启
`json_schema`（或按 kind 预置 DeepSeek capability）；补 `json_object` 分支的
请求体测试。

### H3. 严格模式可“空结果/零 citation 通过”，且 UI 不显示依据类别

证据：

- `lib/core/models/agent/agent_analysis.dart:286-346` 的 `fromJson` 对缺失
  `translation/segments` 直接给空列表；不校验 `schema`、不要求 `source_id`
  非空。
- `lib/services/agent/agent_validator.dart:66-79` 对 translation 只校验 label，
  citation 可选；`segments` 为空时整个循环不执行；`validate()` 返回
  `valid=true`。`sourceId` 完全未校验。
- `lib/services/agent/analysis_prompts.dart:51-179` 的运行时响应 schema 与
  `docs/schemas/agent/analysis.v1.schema.json` 不一致：运行时缺少 `schema`
  字段、`maxItems`/pattern/minLength 等约束。
- `lib/features/agent/agent_result_view.dart` 未渲染 `AgentSegment.epistemic`
  或 `confidence`；严格模式徽标旁边看不出“词典事实/结构分析/语境推断”的差别。
- `interpretations[].confidence` 未做 0–1 校验，UI 直接显示 `N%`。
- citation 只校验“ID 存在”，不校验语义归属：`wordNotes.surface/sense` 不与
  token 的 surface/lemma 比对，词注可以引用与它无关的词条 citation；结果视图
  仍把 citation chip 放在模型写的词义旁边，视觉上暗示该词条支持这段解释
  （`agent_validator.dart:49-64, 89-111`；`agent_result_view.dart:299-346`）。
- 严格模式的 citation 要求完全信任模型自报的 `epistemic`：把一段带词义的
  claim 标成 `translation` 就完全跳过 citation 检查
  （`agent_validator.dart:149-150`）；`structural_analysis` 只要有任意
  token/grammar note 即可，note 本身可以无 citation。模型可以靠改标签绕过
  严格模式。
- `AgentTranslation.label` 缺失时 `fromJson` 用默认值“模型译文”
  （`agent_analysis.dart:49`），validator 的 label 校验永远通过。
- `citationsUsed` 只校验存在性，不从 claim 重新汇总后做一致性校验；结果视图
  也不使用它。
- `unresolved` 以 quote 为单位豁免：同一 quote 下一条宽泛的 unresolved 可以让
  其他 confident context_inference 全部通过严格检查
  （`agent_validator.dart:44-47, 143-148`）。

影响：用户看到“严格模式”徽标，但结果可能是纯模型译文、无任何 citation；模型
把 `context_inference` 与 `dictionary_fact` 混排时用户无法分辨；模型写的词义
可能被错误地显示为“有词典依据”；模型可通过选择 `translation` 标签规避严格
模式。

建议：在 `AgentAnalysis.fromJson` 后增加严格 schema 校验（`schema`、
`source_id` 属于本 run、`translation` 或 `segments` 非空、数组上限）；严格模式
要求 translation 逐句带 citation 或标记未找到依据；结果视图增加 epistemic 徽标
与 confidence 范围校验；把运行时 schema 与 docs schema 对齐（至少补 `schema`）；
禁止模型用 `translation` 标签承载词典事实。

### H4. 取消是“表面取消”，并存在并发 run 竞态

证据：

- `lib/features/agent/agent_page.dart:275-282` 的 `_cancel` 立即把
  `_running=false`，但旧 run 的 `onStage`/成功/异常/`finally` 只检查 `mounted`
  （`agent_page.dart:216-272`），没有 run id/generation token；用户可在旧 run
  尚未结束时再次点击“开始分析”，旧 run 会覆盖新 run 的 stage/error/result。
- `_send` 无重入保护（`agent_page.dart:123-152`）。
- 取消只在阶段边界和每个 LLM event 检查（`agent_orchestrator.dart:74-82,
  399-412`）；`EvidenceBuilder.build` 不接受 cancellation，120 个目标 × exact+
  prefix 的两轮查询期间无法停止。
- provider 没有 `CancelToken`（`openai_compatible_provider.dart:42-61`、
  `anthropic_provider.dart:42-61`）；familiarization 是非流式，退出页面后仍会
  等到 120s 超时。
- `dispose` 只 cancel flag，不 cancel OCR；`_cancel` 的
  `unawaited(ocrService.cancel())` 也无错误处理。

影响：用户点“停止”后本地查词/网络请求仍在跑；快速重开会让界面进入错乱状态；
离开页面仍消耗 token。

建议：引入 `runId`/generation token，所有回调比对当前 run；`_send` 加
reentrancy guard；把 `AgentCancellation` 传入 `EvidenceBuilder` 每个 target 的
循环，并在 OCR/provider 层接 `CancelToken`/service cancel；`_running` 只在 run
future 真正结束后复位；`dispose` 调用完整取消链。

### H5. 多源输入只对 primary source 生成 quotes；用户文本与“指令”混用

证据：

- `AgentOrchestrator._primarySource`（`agent_orchestrator.dart:356-364`）永远
  优先返回第一张图片；`buildSourceQuotes` 只对 primary 生成 quote
  （`:186-197`）。
- 但 `EvidenceBuilder.build(sources: envelope.sources, ...)` 对**所有** source
  分词和查词（`evidence_builder.dart:49-121`）。
- `analysis.v1` schema 只有单个 `source_id`
  （`docs/schemas/agent/analysis.v1.schema.json:6-10`），多 source 无法在结果里
  表达。
- UI 允许同时输入文字和图片（`agent_page.dart:475-516`），但文字只作为 primary
  之外的 source；若图片 OCR 为空、文字非空，`totalChars` 通过而 quotes 为空，
  任何 segment 都会因 quote_id 无效而失败（或模型返回空 segments 而“成功”）。
- `AgentRunRequest.userText` 同时被当作“用户请求”和 `sources[]` 的 user_text
  source（`agent_orchestrator.dart:226, 329-338`）。用户输入“请解释这句话”会被
  UniDic 分词并查词，污染 evidence/预算。`responseLanguage.follow` 还会让
  “跟随输入语言”在纯日文段落场景下变成“用日语回答”，与中文用户的预期不符。
- 同一段 source text 在 prompt 里出现三次（input envelope、evidence source
  text、quotes），加上最多 60 条 citation、40 条 quote 和无上限的 profile
  Markdown，没有总 prompt/token 预算（`agent_orchestrator.dart:39-60,
  209-213`；`analysis_prompts.dart:181-210`）。
- `AgentRunRequest.context` 存在但 UI 无入口，始终为空。

影响：文字+图片、空 OCR 图片+文字、以及“指令文本”三种常见输入都会产生错误或
低质量证据；多图（P6.6）更无法表达。

建议：把 `instruction`/`context` 与 `sourceText` 拆开；`userText` 只作为
instruction，或至少不要把它加入 evidence sources；为每个 source 生成 quote
（quote ID 全局唯一并带 source_id），或明确限制单 source 并在 UI 说明。若保留
单 `source_id`，则 UI 只允许一个内容源。

### H6. 失败路径：无修复、无 partial、provider 无重试、词典错误被吞、无 UniDic 直接中断

证据：

- 校验失败直接抛 `AgentRunFailure(VALIDATION_FAILED)`
  （`agent_orchestrator.dart:246-259`），没有契约 §10 的“一次修复调用”，也没有
  design §6.5.7 的“部分结果 + 可见 validation_errors”。
- provider 只映射 429/5xx 错误码（`provider_http.dart:74-96`），没有“最多 2 次
  退避重试”（design §11）。
- `EvidenceBuilder._lookup` 捕获所有异常并返回空 groups
  （`evidence_builder.dart:241-264`），`group.error` 也未写入证据；单本词典失败
  最终表现为“没有 citation”，而不是“该词典查询失败”。
- `TokenizePortAdapter` 把 `MecabException` 映射为 `UNIDIC_NOT_READY`，但
  `AgentPage._send` 先 `await mecabServiceProvider.future`，未配置 UniDic 时
  在 orchestration 前就失败；`EvidenceBuilder` 也不支持“无 token 仍做 MDict
  查询”。与 design §6.3“分词失败不阻断纯翻译/仍可词典检索”不符。
- `totalChars > maxSourceChars` 直接报“请选择要分析的段落”，但 UI 没有段落
  选择器（`agent_orchestrator.dart:130-136`；`agent_page.dart:475-516`）。
- 熟悉期不是“纯辅助”：`ensureMany` 只捕获 `AgentCapabilityException`；SQLite
  读写失败或 `confirm` sheet 抛错会变成 `internalError`，整次分析中断
  （`agent_orchestrator.dart:143-172`）。UniDic 熟悉期在
  `allowFamiliarization` 之外无条件运行，失败也会中断（`:173-183`）；且它会
  自动写 `StoredUnidicProfile`，没有用户确认。
- 档案 Markdown 质量：`profileToMarkdown` 不包含 `entry_structure.notes` /
  `search_behavior.notes`，这两个模型字段永远进不了 prompt；Markdown 没有
  2,000 字符上限；档案 JSON 只校验 `dictionary_id`，空档案也能保存。
- 语法证据取错字符串：`_PatternTarget` 用 `GrammarPattern.surface` 而不是源
  文本中实际匹配的子串查词（`evidence_builder.dart:106-110`），活用形可能查
  不到。
- 预算分配：citation 满额后只 break 当前 group，后续 target 继续跑但不再发
  citation；语法模式排在所有 token 之前，可能耗尽 target 预算
  （`evidence_builder.dart:123-128, 159-162`）。

影响：一条常见的模型小错误会导致整次失败；词典故障与“没有词条”无法区分；
没有 UniDic 的用户完全无法使用 Agent；长文本用户没有可行路径。

建议：加入一次带 `validation_errors` 的修复请求；仍失败时返回通过校验的
partial result + warnings；provider 加 429/5xx 重试；EvidenceBuilder 记录每
词典错误并在结果中显示；把 UniDic 改为可选（无 token 时跳过结构证据，仍可
MDict 查询）；长文本提供段落选择或明确 UI 限制；熟悉期任何非致命失败只降级为
warning；UniDic 档案也走确认或明确标为确定性本地观察。

### H7. 设置与密钥安全缺口

证据：

- `agent_settings_page.dart:190-202` 不校验 Base URL（空值、非 HTTPS 均可保存）；
  `usesCleartextTraffic=false` 会让 http 在运行时失败，但保存时没有提示。
- 没有“清除 API Key”入口（只能删除整个 provider），没有 key 是否存在指示，
  没有测试连接（P6.7）。
- `supportsTools: true`、`supportsStreaming: true` 被硬编码
  （`agent_settings_page.dart:199-201`），与实际 provider 能力无关。
- `selectedAgentProviderProvider` 只在设置页写，AgentPage 不读
  （`agent_providers.dart:29-41`；`agent_page.dart:51, 86-92`）。
- `AgentStore` 的 DB version 1 没有 `onUpgrade`；`allowBackup` 未关闭；
  `providerErrorDetail`/`_debugHead` 可能把模型输出/服务器错误写进 logcat
  （`provider_http.dart:128-168`；`agent_orchestrator.dart:232-236`）。
- `assertNoImagePayload` 未阻止 `image` 键和 `.jpg/.png/.webp/.heic` 路径，且
  会把普通用户文本/词典摘要中的 `C:\`、`file://`、`base64,` 误判为违规并中止
  run（`provider_payload.dart:4-63`）。

影响：用户可能保存一个永远无法连接的 URL；无法单独撤销 Key；provider 能力
声明与实际不符；日志与备份边界弱于设置页的隐私承诺。

建议：保存前校验 https/URL（debug 允许 localhost 并提示），增加清除 Key/测试
连接，按 provider 配置 capability 或暂时删除 tools 开关；AgentPage 读取
selected provider；关闭 allowBackup 或排除 secure storage；降低日志中的模型
输出；把 payload guard 收窄到结构化图片字段/URI，避免误伤正文。

### H8. 会话/运行/引用没有持久化，AgentStore 一半是死表

证据：

- `AgentStore` 创建了 `agent_sessions`、`agent_runs`、`agent_messages`、
  `agent_tool_calls`、`agent_source_versions`、`agent_citations`、
  `annotation_rule_sets`（`agent_store.dart:28-166`），但只有 provider/
  dictionary_profiles/unidic_profiles 有读写方法（`:172-326`）。
- `AgentPage._result` 只存在 State（`agent_page.dart:57`），pop 即丢失；
  `sessionId` 是时间戳（`:200`），没有会话记录。
- `docs/phase6-status.md:122-123` 已承认 history 待做（P6.7），但 README/设计
  仍把 AgentStore 描述为已具备会话能力。

影响：没有历史、没有运行审计、无法恢复 citation 快照；“新会话”只是清空页面
状态，用户离开页面即丢失结果。

建议：要么在 P6.7 前补最小 run/session/citation 持久化（至少支持“最近结果”
恢复/历史列表），要么在文档中明确当前无历史并删除“AgentStore 已就绪”的表述；
DB 增加 onUpgrade。

## 3. 中低优先级问题

- **进度**：`AgentStage.evidence` 从未发出；整个查词阶段显示“分词”，用户可能
  以为卡死（`agent_orchestrator.dart:199-216`）。
- **结果 UX**：结果追加在表单底部，无自动滚动；显示全部 quotes（最多 40）与
  全部 citations（最多 60）；未解决项显示内部 `quoteId`；无“切换宽松模式”
  入口；无“词典中未找到依据”的专门状态；`translation.citationIds` 不渲染。
- **OCR 版本**：`AgentRunResult.sources` 有 engine/mode/confidence，但结果视图
  完全不显示（P6.6）。
- **模型路由**：分析始终用 complexModel（缺失时 small），UI 不显示当前路由，
  用户不能选择 small 分析（design §3/§10.2）。
- **会话词典**：单选模式不会收敛现有多选；“全选”在单选模式下也会选全部；
  “新会话”重置为全部 enabled 而非全局查词偏好；缺“恢复为查词选择”。
- **Familiarization**：样本在用户确认前已发送给 provider，且没有告知；用户选
  “不再询问”后永久生效且设置页没有重置入口；结果视图不提示 declined；
  `_retryProfile` 无 busy 状态，可双击并发。
- **设置**：provider list 加载/错误在 AgentPage 被当作“未配置”；设置保存/
  删除无 try/catch；错误无重试；协议切换不更新 Base URL 默认值；无 key 存在
  指示。
- **可访问性**：citation chip 28dp `GestureDetector` 无 Semantics/role；
  dictionary chip 32dp；阶段文本不是 live region。
- **证据完整性**：token evidence 只保留 `pos`，丢失 contract 要求的
  `pos1-4/c_type/c_form/goshu`；`quote_builder` 静默截断 40 条；`mdict.suggest`
  输出与契约不一致；`MdictLookupTool` 未实现 query 追溯与 citation 上限。
- **性能**：120 目标顺序 exact→prefix 查询无整体时间预算/并发；大词典 prefix
  扫描可能很慢；prompt 体积可达数万字符，无输入 token 预算。
- **其他**：`AgentStore._db()` 并发打开无锁；`saveProvider` replace 重置
  created_at；`AgentPage` provider 加载中 toast 误导；无多图/相机入口；
  `context` 无 UI。
- **Provider/SSE**：多行 `data:` 事件没有重组，`data:` 里的错误对象/
  `finish_reason` 长度截断被忽略（`provider_http.dart:11-24`；
  `openai_compatible_provider.dart:86-108`）；所有 provider `error` 事件都折叠成
  `PROVIDER_UNAVAILABLE`，`PROVIDER_REFUSED` 从未产生
  （`agent_orchestrator.dart:414-422`）。
- **死代码/未用资产**：`OcrWorkflow`、`createDefaultAgentToolRegistry`、
  `CitationRegistry.issueFromLookup`、`loadDictionaryProbes` 与
  `assets/agent/dictionary_probes.json`、`LlmTool/LlmRequest.tools/
  LlmCapabilities` 均无生产调用；`AgentStage.evidence/error/cancelled` 未发出；
  `AgentSourceVersion.blocksJson` 恒为 `'[]'`。
- **文本-only 也依赖 OCR manifest**：`AgentPage._send` 无条件
  `await ocrModelManifestProvider.future`，manifest 缺失时纯文字分析也无法运行
  （`agent_page.dart:156`）。
- **档案/工具细节**：`profileToMarkdown` 丢失 notes；档案 Markdown 无 2,000 字
  上限；`DictionaryProfile.copyWith` 只能改少数字段；`featureLayout` 在未观察
  到标准布局时仍回退 29；`AgentToolSpec.maxCallsPerRun` 未执行；tool 超时只
  返回错误码、不取消底层 future。

## 4. 文档与契约漂移

- **README**：开头 `README.md:7-9` 说 Phase 6 “planned / not part of the current
  build”；`README.md:175-177` 又说“current build contains no Agent/provider
  implementation”；与 `README.md:17-22, 97-129` 的 P6.1–P6.5 已实现矛盾。
- **CLAUDE.md**：`CLAUDE.md:45-48` 仍说主页“当前四个按钮、未实施前不得新增第五
  个”，而 `CLAUDE.md:78` 与 §5.11/§5.12 已按五个按钮描述；Phase 6 状态段落也
  已说五个。需要统一。
- **共享 OcrWorkflow**：README/ADR/CLAUDE 声称 UI 与 Agent 共用
  `OcrWorkflow`；实际 `lib/services/ocr/ocr_workflow.dart` 只有定义，无生产
  调用（`OcrPortAdapter` 自己做了 ensureReady→recognize→compose）。要么真正
  共用，要么删除该声明。
- **Contracts vs 运行时 schema**：
  - `docs/schemas/agent/analysis.v1.schema.json` 要求 `schema` 字段；
    `analysis_prompts.dart` 的运行时 schema 没有 `schema`。
  - 契约允许 `quote_text`（`phase6-agent-contracts.md:380-381`），
    `analysis.v1.schema.json` 的 `additionalProperties:false` 不允许。
  - 契约 `TokenEvidence` 有 `pos1-4/cType/cForm/goshu`，运行时/evidence schema
    只有 `pos`。
  - 错误码 `IMAGE_DECODE_FAILED` 出现在 `ocr.recognize` 错误列表，但不在
    `tool-result.v1.schema.json` 的 enum；`DICTIONARY_LOOKUP_FAILED`
    retryable 在示例与表格中相反。
  - 多 source 输入 vs 单个 `source_id`；`untrusted: true` 块不存在；
    6,000 字符预算 vs schema 20,000 上限；`OcrVariant` 的
    `fingerprint/selected/rotation mode` 未在 schema 中。
  - `test/fixtures/agent/` 不存在，契约却列了 fixture 路径。
- **状态文档**：`phase6-status.md` 把 tool loop、history、provider test
  connection 列为未实现，README/CLAUDE 的某些段落仍按已实现描述；`README`
  与 `docs/DEVELOPMENT_PLAN.md` 的 Phase 6 状态也不一致。

## 5. 建议的修复顺序（后续工作，不是本次范围）

### Phase A — 文档/契约校正（低风险，先做）

1. 统一 README/CLAUDE/DEVELOPMENT_PLAN/status 的 Phase 6 状态与五按钮描述。
2. 明确“P6.5 固定流水线无模型工具调用”；要么把 tool loop 标为 P6.6 待做并
   修正 ADR/contracts，要么在 Phase C 实现。
3. 删除/落实 `OcrWorkflow` 的“共享”声明；更新 schema 差异、错误码、fixtures。
4. 在 README/设置页写清发送给 provider 的内容（用户文本、OCR 文本、词典摘要、
   熟悉期样本），不只是“图片不上传”。

### Phase B — 管线正确性（建议优先于 P6.6）

1. 输入模型：拆分 instruction/context 与 source text；不要把 instruction 加入
   evidence sources；为每个 source 生成 quote 或限制单 source。
2. 严格校验：`AgentAnalysis` schema 校验（schema/source_id/非空/上限）；严格
   模式 translation 依据或“未找到依据”；epistemic/confidence 校验与 UI 徽标；
   `AgentValidator` 补 source_id、空结果、citation 归属规则。
3. 失败处理：一次修复请求；partial result + warnings；EvidenceBuilder 记录
   单词典错误；无 UniDic 时降级；长文本段落选择或明确限制。
4. 取消/重入：runId/generation token、reentrancy guard、EvidenceBuilder 取消、
   provider CancelToken、完整 dispose 取消链。
5. 进度：发出 `evidence` 阶段；对查词/熟悉期给更细的中文进度。

### Phase C — Provider/设置可靠性/安全

1. OpenAI-compatible 的 JSON schema 回退（prompt 内联 schema 或 capability
   开关）；补 `json_object` 分支测试。
2. provider 429/5xx 重试、超时/取消、错误码映射测试。
3. Base URL https 校验、清除 Key、测试连接、capability 配置；AgentPage 读取
   selected provider；关闭 allowBackup/排除 secure storage。
4. 收窄 `assertNoImagePayload`，避免误伤正文；补 `image` 键/.jpg 路径规则。

### Phase D — P6.6（在 B/C 之后）

1. 明确多 OCR 只由 orchestrator 调用 `ocr.recognize`（模型不可见）。
2. 若保留模型工具：扩展 LlmMessage 为 tool_use/tool_result、OpenAI/Anthropic
   流式参数累积、budget、query traceability、citation 上限；否则删掉工具层
   声明并只做本地 consensus/repair。
3. OCR variants/diff/hit-rate/repair suggestion UI；每 source 版本选择。

### Phase E — P6.7 + 持久化

1. `AgentStore` 的 run/session/message/citation 写入与历史 UI（或明确继续
   defer）；DB onUpgrade。
2. annotation DSL/Markdown/ruby/pitch、测试连接、发布验收。

## 6. 本次评审的验证

- 本次只读代码与文档，未修改 `lib/`、`test/` 或现有 Phase 6 设计/契约。
- 未运行 `flutter analyze`/`flutter test`/设备测试；本文结论以代码与文档引用
  为准，修复时须按第 5 节补充测试并在设备上验收。
- 关联文档：[README](README.md)、[设计 v2](../phase6-agent-design.md)、
  [契约](../phase6-agent-contracts.md)、[当前状态](../phase6-status.md)、
  [ADR 0004](../adr/0004-agent-capability-boundary.md)。

## 7. 2026-10-30 修复进展（设备验证）

以下为按本评审修复后的状态；详细实现记录见 `docs/phase6-status.md`。

- **H2 已修复**：analysis/familiarization 的完整 JSON schema 已内联进 prompt；
  OpenAI-compatible 仍走 `json_object`，但模型现在能看到字段结构。补了
  `json_object`/SSE 流式测试；deepseek-flash 实际跑通。
- **H3 部分修复**：解析后强制 `translation`/`segments` 非空、校验 `source_id`；
  严格模式下所有词注必须有 citation；新增 `AnalysisNormalizer`：`literal` 一律
  由 quote 回填、未知 `pattern_id` 丢弃；结果视图增加词典事实/结构分析/语境
  推断/模型译文徽标与置信度。translation 逐句 citation 仍待加强。
- **H4 部分修复**：AgentPage 增加 run generation 与 `_send` 重入保护；旧 run 的
  stage/text/result/error 不会覆盖新 run；EvidenceBuilder 每个 target 检查取消。
  provider CancelToken 与熟悉期取消仍待补。
- **H5 部分修复**：有图片时文本字段作为 instruction，不再加入 evidence sources；
  纯文本输入仍是 source。多 source 的 analysis schema/quote 仍只支持 primary。
- **H6 部分修复**：熟悉期改为按 token 预算分批，单词典失败产生
  `unavailable` + 原因 + “重试此词典”；档案失败只 warning 继续；prompt 明确
  “无档案词典按通用规则检索”。validation 修复请求、provider 429/5xx 重试、
  无 UniDic 降级仍待补。
- **H7 部分修复**：模型原文诊断日志加 `kDebugMode`；错误详情在 UI 可展开查看；
  Base URL 校验、清除 Key、allowBackup、payload guard 收窄仍待补。
- **H1 暂按方案 A**：当前 P6.5 明确为“固定流水线、模型无工具”；工具循环/
  task-tool 往返留到 P6.6 前决策，不再把 `AgentToolRegistry` 描述成已接入。
- **H8 仍 open**：会话/运行/引用持久化留到 P6.7；当前结果只在页面 State。

**验证**：模拟器 x86_64 上选择真实相册图片，端侧 OCR 得到
`何卒宜しくお願い致します。\n東京で食べた。`，MDict 查词生成 citation，DeepSeek
流式生成约 20k 字符 reasoning、约 3k 字符最终 JSON；UI 实时显示“模型思考中/
生成中”，最终展示中文译文、逐句理解、原文 quote 与按词典顺序的证据卡片。
`flutter analyze` 无问题，全量测试与 debug APK 构建通过；真实 arm64/真实漫画页
仍待验收。
