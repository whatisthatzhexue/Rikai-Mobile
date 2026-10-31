# Agent 代码可维护性评审

- 日期：2026-10-30
- 状态：**快照评审，问题未修复**。另一个 session 正在修改 Agent 代码；行号/文件
  规模以当前工作区快照为准，合并后需复核。
- 范围：`lib/features/agent/`、`lib/services/agent/`、`lib/state/agent_run_controller.dart`、
  `lib/core/models/agent/`、`lib/services/storage/agent_store.dart`、
  `lib/state/agent_providers.dart` 及 Agent 测试。
- 方法：只读代码/测试/调用链；未改代码；`flutter analyze` 当前干净；未运行完整
  `flutter test`/build，避免与另一个 session 冲突。

## 结论

**核心服务层（Ports、Evidence、Citation、Validator、隐私 guard）设计良好，但整体
还不算“高度可维护”，目前属于中等。** 最大拖累不是算法，而是：

1. 约 900 行工具层完全未被生产使用；
2. `AgentPage` 1,152 行 god widget；
3. `DictionaryFamiliarizationService` 752 行且 `ensure`/`ensureMany` 两套流程；
4. 应用级 `AgentRunController` 不可注入、无 controller 测试；
5. 词典错误被吞、snapshot 丢错误码、cancelled 状态不可见；
6. DTO/schema 手工副本多，改一个字段要动很多层。

## 一、值得保留的设计

- Ports/adapters 边界清晰：`OcrPort`、`TokenizePort`、`LookupPort`、
  `DictionarySamplePort`、`LlmPort`、`SecretPort` 都是薄接口；orchestrator
  不依赖 Flutter/Widget。
- citation 只由 `CitationRegistry` 发放；`EvidenceBuilder` 做目标/预算；
  `AgentValidator` 校验 quote/literal、citation 存在性、epistemic、confidence。
- 图片/路径隐私 guard `assertNoImagePayload` 在 provider 发送前递归检查；
  orchestrator 测试断言 `/sdcard`/文件名不进入 prompt。
- `AgentRunController`（应用级，408 行）+ 不可变 `AgentRunSnapshot` 是正确方向；
  页面只订阅，`dispose` 只 detach；旧 run 回调由 token 身份检查丢弃。
- 熟悉期有用户确认、指纹缓存、批量上限；profile 不写用户词典目录。
- 不可变 wire DTO、`wireName` 枚举、`agent_json.dart` 解析助手；fake ports/
  provider 易读；provider 流式/非流式/SSE 测试较扎实；新增
  `analysis_normalizer.dart` 并带测试。

## 二、高优先级可维护性问题

### M1. 工具层完全未被生产使用（高）

- `lib/services/agent/tools/**`、`AgentToolRegistry`、`AgentToolBudget`、
  六个工具、`AgentSchemaValidator` 约 900 行，只有
  `test/agent_tool_registry_test.dart` 直接 new；`createDefaultAgentToolRegistry()`
  无 `lib/` 调用。
- `AgentOrchestrator` 明确忽略 `LlmEventType.toolCall`；
  `buildAnalysisRequest()` 不填 `tools`；`LlmMessage` 只有 `LlmTextPart`，无法
  表达 assistant `tool_use`/`tool_result`；但设置页给所有 provider 写
  `supportsTools: true`。
- 同类死抽象：`OcrWorkflow`（无生产调用）、`CitationRegistry.issueFromLookup`
  （无调用）、`loadDictionaryProbes`（只用 fallback）、`LlmCapabilities`
  （provider 实现但 orchestrator 不读）。

**建议**：先做决策。若当前产品是“固定流水线、模型无工具”，删除 tools/、
`AgentTool*` DTO、`LlmTool`/`LlmCapabilities` 和死测试，更新 contracts/README；
若要保留工具循环，必须一并实现 tool part DTO、OpenAI/Anthropic 流式参数累积、
预算/取消/query 追溯。不要保留两套抽象。

### M2. `AgentPage` 是 1,152 行 god widget（高）

- 文件同时包含：输入/图片选择、会话词典、provider/模式、发送/停止/重试/新会话、
  滚动、熟悉期重试（页面内重新组装 `DictionaryFamiliarizationService`）、
  citation 打开（直接 `MdictService.lookup` 并构造 `EntryPage`）、7 个私有 widget。
- `_retryProfile` 与 `AgentRunController._openServices` 重复组装适配器；
  `_confirmProfile` 与页面内联 sheet 逻辑重复。

**建议**：拆 `agent_session_panel.dart`、`agent_composer.dart`、
`agent_message_bubble.dart`、`agent_evidence_panel.dart`；把 profile retry 和
citation open 移到 controller/use-case，页面只负责渲染与路由。

### M3. 熟悉期服务 752 行，`ensure`/`ensureMany` 两套流程（高）

- `dictionary_familiarization_service.dart` 的 `ensure()` 与 `ensureMany()` 各自
  实现指纹/复用/decline/采样/确认/保存；`_saveConfirmed`/`_saveDeclined` 只被
  `ensureMany` 使用；Markdown 渲染和三套语言标签也在同一文件。
- 建议让 `ensure()` 委托 `ensureMany([dict])`；拆出 `profile_repository` 适配、
  `dictionary_profile_markdown.dart`、`dictionary_profile_parser.dart`。

### M4. 生命周期 controller 不可注入、无测试（高）

- `AgentRunController._openServices` 直接读 `ocrServiceProvider`、
  `mecabServiceProvider`、`mdictServiceProvider`、`agentStoreProvider`、
  `secretStoreProvider`，内部 new `OcrPortAdapter`/`TokenizePortAdapter`/
  `LookupPortAdapter`/orchestrator；`FakeProvider`/fake ports 无法注入。
- 没有 `test/agent_run_controller_test.dart`；离开页面→继续→返回、取消、
  快速重开、immediate error、profile handler detach、streaming progress 都未测。
- `AgentPage` 在 `initState` 缓存 `_runController` notifier 实例；若 provider
  被 invalidate，页面持有旧 notifier。
- `detachProfileHandler` 用 `identical` 比较 tear-off；不保证相同，建议存单例或
  显式置空。

**建议**：注入 `AgentRunServicesFactory`/`AgentOrchestratorFactory`；页面在调用点
`ref.read(...notifier)` 或 watch；补 controller 测试。

### M5. 词典错误被吞、错误码丢失（高）

- `EvidenceBuilder._lookup` 捕获所有异常返回空 `LookupResult`
  （`evidence_builder.dart:264-287`）；`group.error` 也未写入证据。词典服务故障与
  “查无此词”不可区分，strict 模式最终显示误导性的“没有 citation”。
- `AgentRunSnapshot` 只有 `errorMessage/errorDetail`，没有
  `AgentToolErrorCode`/retryable；`AgentRunController` 捕获 `AgentRunFailure`
  时丢弃 `code`。
- 校验错误把内部 token/citation/pattern ID 直接拼进用户消息。

**建议**：EvidenceBuilder 记录每词典错误并在结果/警告中显示；snapshot 加
`errorCode`/`retryable`；校验错误分“用户摘要 + 结构化 details”。

## 三、中优先级：状态/生命周期/交互

| ID | 问题 | 证据/影响 | 建议 |
|---|---|---|---|
| M6 | 立即校验失败会清空输入且不可重试 | `AgentRunController._setImmediateError` 的 snapshot 不含 `sentText/sentImage`；`AgentPage._send` 在 `start` 后立即清空 composer；空模型名/空词典等错误会丢输入、`_lastInputs` 未设置 | 错误 snapshot 带上 sentText/sentImage；确认 run 被接受后再清空输入 |
| M7 | cancelled 状态不可见 | 页面只在 `run.isRunning || result != null || errorMessage != null` 时渲染 assistant bubble；cancel 后三者都不满足，只显示 user bubble | 渲染 `cancelled`：保留 partial（若有）+“已停止 · 重试” |
| M8 | `evidence/error/cancelled` 阶段与 `interrupted` 未发出 | `AgentStage.evidence` 只用于映射；`AgentRunStatus.interrupted` 从未设置 | 发出 evidence 阶段；interrupted 在持久化/进程恢复时设置 |
| M9 | retry 使用旧词典/provider 快照 | `_lastInputs` 原样重放；词典被删除/禁用或 provider 改名后仍用旧配置 | 重试时按当前 repository 重新解析词典/ provider |
| M10 | 文本-only 仍依赖 OCR manifest | `_openServices` 无条件 `await ocrModelManifestProvider.future` | 只有 `images.isNotEmpty` 时才打开 OCR |
| M11 | 取消链未闭环 | provider 无 `CancelToken`；familiarization 非流式且无 token；`cancel()` 只 flip flag + `ocrService.cancel()` unawaited | provider CancelToken、familiarization 取消、OCR 错误处理 |
| M12 | `selectedAgentProviderProvider` 只写不读 | settings 写入；AgentPage 用自己的 `_selectedProviderId` 并默认 first | 读 app-level 选择或删除 dead notifier |
| M13 | `receivedChars` 语义是 max 而非累计 | `_publishProgress` 取 `max(textChars, reasoningChars)` | 求和或改名 `progressChars` 并文档化 |
| M14 | 文本-only 的 OCR manifest / OCR cancel 资源浪费 | 同 M10/M11 | 懒加载 OCR |

## 四、中优先级：JSON/schema/命名

| ID | 问题 | 证据/影响 | 建议 |
|---|---|---|---|
| M15 | 运行时 schema 与 docs schema 手工副本 | `analysisResponseSchema()` 缺 `schema`/maxItems 等；`docs/schemas/agent/analysis.v1.schema.json` 是另一份 | 单一来源（生成 Dart map 或 contract test 对比 required/limits） |
| M16 | 熟悉期没有 schema fallback | `familiarization_prompts.dart` 不内联 `dictionaryProfileResponseSchema`；settings 对非 Anthropic 仍 `supportsJsonSchema=false`；README H2 声称 familiarization 已内联，但当前代码没有 | 把 analysis 的 schema-in-prompt 机制复用到 familiarization；修正 README |
| M17 | 宽松 JSON 默认掩盖模型错误 | `AgentTranslation.fromJson` 缺 label 默认“模型译文”，validator 的 label 检查永远通过；未知 epistemic 默认 `contextInference`；未知 provider kind 默认 OpenAI-compatible；未知 source kind 默认 imageOcr | 缺 required 字段/未知 enum 直接 validationFailed；移除 label 默认 |
| M18 | DTO 列表解析样板 19 次 | `raw is List ? raw.whereType<Map>().map(...)` 在多个 DTO 重复 | `agentObjectList<T>()` 助手；未来可 codegen |
| M19 | `AgentStage` 与 `AgentRunStatus` 平行 enum | 两套枚举 + switch 映射；`evidence` 映射到 `tokenizing`，`error/cancelled` 未用 | 一套 lifecycle enum，或直接由 stage 生成 snapshot status |
| M20 | 预算/上限常量散落 | 6000/120/60/6/12000/16000/2000/90s 分散在构造函数 | `AgentLimits`/policy 对象 |
| M21 | “provider” 重载 | `AgentProviderConfig` 与 Riverpod provider 同名概念 | 改名 `AgentLlmConfig` / `agentLlmConfigsProvider` 或文档约定 |
| M22 | 死字段/死常量 | `AgentSourceVersion.blocksJson` 恒 `'[]'`；`AgentModelSupplement.label` 被忽略；`AgentToolSpec.maxCallsPerRun` 未执行；`AgentRunResult.sources` 未渲染 | 实现或删除 |
| M23 | 日志/脱敏三份实现 | `_debugHead`、`providerErrorDetail`、`_providerErrorMessage`；部分 `debugPrint` 未 gate `kDebugMode` | 统一 `AgentRedactor`/`AgentLogger`，release 静默 |
| M24 | provider error 事件全部折叠 | `_collect` 把 `LlmEventType.error` 都映射 `providerUnavailable`；`providerRefused` 从未产生 | `LlmEvent` 带 code/type，在一处映射 |

## 五、中优先级：持久化/扩展性

- **M25 `AgentStore` 死表/无迁移**：创建 `agent_sessions`/`runs`/`messages`/
  `tool_calls`/`source_versions`/`citations`/`annotation_rule_sets`，但无读写方法；
  只有 version 1/onCreate，无 onUpgrade。P6.7 历史前先加 migration 和
  `AgentRunResult`/`AgentRunSnapshot` 的 `toJson`。
- **M26 P6.6 多 OCR 只完成一半**：controller/orchestrator 接受多图，但页面只有
  一个 `_imagePath`；quotes 只对 `_primarySource` 生成；结果视图只渲染一个 quote
  list。加多 OCR 前先做 per-source quote builder 和 source/variant selector。
- **M27 tool loop 不是小扩展**：`LlmMessage` 无 tool part，provider 不累积
  tool-call 参数，orchestrator 丢弃 toolCall，registry 无取消/结果通道；若
  P6.6 要模型补查，需要完整重构，不是接一个 registry 调用。
- **M28 分层/依赖方向**：`AgentRunSnapshot` 在 `lib/services/agent/agent_run.dart`
  却属于 UI state；`lib/core/models/dictionary_sample.dart` import
  `agent/agent_json.dart`（core→agent）；settings 依赖 Agent 枚举。建议把
  snapshot 移到 `lib/state/`，把共享 JSON helper 移到 core。

## 六、测试现状

- 已有：orchestrator happy path/图片路径不泄漏/strict 失败；validator 规则；
  evidence 去重/排序/截断；provider 流式/非流式/SSE/错误映射；familiarization
  确认/复用/decline/batch；models round-trip；analysis normalizer。
- 缺失：`AgentRunController` 全部生命周期测试；cancelled 渲染；immediate error；
  retry 配置刷新；text-only 不依赖 OCR；dictionary lookup 抛错；maxSourceChars；
  `evidence` stage；loose-mode orchestration；多源 quotes；进程死亡恢复。
- 建议以 `openai_compatible_provider_test.dart` 的 fake-server 模式为模板，
  给 controller 注入 fake ports 写完整生命周期测试。

## 七、建议修复顺序

1. **先决策工具层**：删除死工具层并更新文档，或完整实现 tool loop。不要继续
   保留 `supportsTools: true` 的假象。
2. 拆 `AgentPage`（目标 <300 行）和 `DictionaryFamiliarizationService`；
   移出 `_retryProfile`/`_openCitation`。
3. 给 `AgentRunController` 注入 service/orchestrator factory，补生命周期测试。
4. 修 M5（词典错误/错误码）与 M6–M7（immediate error/cancelled）。
5. 收口 schema/DTO（M15–M18）与预算常量（M20）。
6. 补 AgentStore migration/toJson（M25），再谈 P6.6/P6.7。

## 八、验证状态

- `flutter analyze` 当前 `No issues found`（快照）。
- 未运行完整 `flutter test`/`flutter build apk --debug`；另一个 session 正在
  工作，完成后必须补跑。
- 本报告只读，未改代码/测试；行号/文件规模会随另一 session 的修改变化。

关联：[管线评审](phase6-pipeline-review.md)、[生命周期规范](agent-lifecycle-and-edge-cases.md)、
[非 Agent 回归检查](non-agent-regression-review.md)。

## 九、状态更新（2026-10-31）

| ID | 状态 | 说明 |
|---|---|---|
| M1 | fixed | 已确认固定流水线、模型无工具；删除 `lib/services/agent/tools/`、`AgentToolSpec/Result`、`LlmTool/Capabilities/tools` 与 `OcrWorkflow`；契约/README/ADR 已标注保留为未来参考 |
| M2 | fixed | `AgentPage` 已降至 292 行；拆出 session/composer/message/evidence/actions/progress/fade-in 文件 |
| M3 | partially fixed | `ensure()` 已委托 `ensureMany`，markdown 拆到 `dictionary_profile_markdown.dart`；service 仍约 455 行，batch 请求/保存可继续拆 |
| M4 | partially fixed | 新增可注入 `agentRunServicesProvider`；`agent_lifecycle_test.dart` 覆盖 start→done/cancel/immediate error；页面离开→返回 widget 测试仍未补 |
| M5 | mostly fixed | snapshot 有 `errorCode/retryable`；EvidenceBuilder 记录 `dictionaryIssues` 并在结果 UI 提示；校验失败改为“修复→抢救→错误” |
| M6 | fixed | immediate error 保留 sentText/sentImage；页面仅在 run 被接受后清空输入栏 |
| M7 | fixed | cancelled 状态会渲染 AI 气泡与“重试” |
| M10 | fixed | text-only run 不再等待 OCR manifest |
| M11 | partially fixed | provider 已有 `LlmCancelToken`/Dio CancelToken、429/5xx 退避、多行 SSE；familiarization 取消链仍 open |
| M13 | no-op for UI | UI 不再显示字数，只显示思考时长；`receivedChars` 仅 controller 内部使用 |
| M15 | fixed | runtime analysis schema 增加 `schema`，新增 contract test 对比 docs required/properties |
| M16 | fixed | familiarization system prompt 内联单个/批量 profile schema |

> 本表只更新状态，不覆盖上文评审结论。

## 十、2026-10-31 实机反馈

17 项实机反馈的方案、依赖与波次见
[device-feedback-2026-10-31.md](device-feedback-2026-10-31.md)。与本评审直接相关的
后续项：

- F2（应用级档案队列/gate）会重做熟悉期生成/确认边界，关联 M3/M11；
- F13（词典档案管理）需要 `AgentStore` 的 profile 列表/更新/批量删除方法，关联
  M25，但不等于 P6.7 会话历史；
- F14（复制/编辑/重新生成）会新增结果 Markdown 构建和 controller 恢复旧结果，
  关联 M6/M7；
- F6/F7 会拆出检索策略与覆盖审查，关联 M5/M20、H6。

在上述反馈未完成前，仍不要开始 P6.6/P6.7。
