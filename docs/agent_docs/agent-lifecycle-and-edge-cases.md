# Agent 运行生命周期与意外情况处理

- 状态：**开发规范（要求）**。应用级 `AgentRunController`、provider CancelToken、
  OCR/Evidence 取消、四步进度和编号依据已落地；进程死亡持久化、familiarization
  取消和“离开页面→返回”的 widget 测试仍待补。未完成前不要把剩余能力写成已实现。
- 适用范围：`lib/features/agent/`、`lib/state/`、`lib/services/agent/` 及后续
  P6.6/P6.7 的 Agent UI。
- 关联：[管线评审](phase6-pipeline-review.md) 的 H4（取消/并发）与 H8（持久化）、
  [设计 v2](../phase6-agent-design.md)、[UI 规范](../design-tokens.md) 的
  “Phase 6 Agent 对话式界面 v2”。

> **典型场景**：用户发送图片/文本后按返回键去主页、设置或历史页；Agent 的
> OCR/分词/查词/生成必须继续，不能被页面 `dispose` 取消。用户再次进入词典助手
> 时，页面重新订阅应用级 controller，显示最新阶段、已思考时长/证据数量或最终
> 结果；不得重新发一次 provider 请求，也不得显示空白新会话。

## 1. 核心要求（先读这一节）

1. **运行状态属于应用，不属于页面。** 一次 Agent 运行（run）由应用级
   controller/notifier/store 持有；`AgentPage` 只是订阅者和渲染器，不能把
   `result/running/stage/cancellation` 放在页面 `State` 里作为唯一来源。
2. **用户离开词典助手页面时，运行必须继续。** 返回主页、打开设置/历史/模型页、
   切换 Tab、旋转屏幕、页面被重建，都不得取消正在进行的 OCR、分词、查词、
   熟悉期或 LLM 请求（除非用户明确点“停止”）。
3. **用户回到助手界面时，必须看到最新进展。** 包括当前阶段（本机 OCR/熟悉词典/
   分词/查词/生成/校验）、已流式生成的部分文本（如有）、证据/citation 数量、
   错误或完成状态；不得重新发一次请求，也不得显示空白新会话。
4. **“思考进展”不是隐藏推理链。** UI 展示阶段文字、已用思考时间和证据/citation
   计数即可。生成过程中显示**已思考时长**（每秒刷新），不要显示已接收字数、
   原始流式 JSON、模型隐藏 chain-of-thought、原始 provider 请求体或 API Key。
   已生成的内部文本只用于诊断/恢复，不作为用户可见进度。
5. **取消只有用户显式操作才发生。** “停止”按钮可以取消；`dispose`、路由 pop、
   打开设置、应用切后台都不得等价于取消。
6. **同一 session 同时最多一个 run。** 重复点“开始分析”、旧 run 未结束时新开
   run、旧回调覆盖新结果，都必须被 runId/generation token 阻止。
7. **应用生命周期内有效，不等于进程死后还能继续。** Android 可能杀进程/限制
   后台网络；应用内页面切换必须继续，切后台尽力继续，进程死亡后只能显示
   “已中断/重试”，不得承诺自动续跑。
8. **失败不吞内容。** 已生成的文本、证据和部分结果必须保留；错误以消息内卡片
   或状态条呈现，不整屏清空、不弹阻塞式全局对话框。
9. **就地恢复，不重复扣费。** 返回页面只重新订阅当前 run；不得因为重建页面
   重新调用 provider，也不得重置 citation/进度。
10. **配置在 run 开始时快照。** 会话词典、严格/宽松、provider/model、语言在
    run 开始时确定；run 中修改设置只影响下一次 run，不改变当前 run 的词典顺序
    或模型。

## 2. 术语

- **应用生命周期**：Flutter 进程/引擎存活期间，包括任意路由、页面重建、应用
  切后台（受系统后台限制）。不包含强制停止、进程被杀、系统重启后的自动续跑。
- **页面生命周期**：`AgentPage` 的 mount/unmount、`initState`/`dispose`。
  页面生命周期不能决定 run 生命周期。
- **思考/生成进展**：当前 stage、stage message、已用思考时长、证据/citation
  数量、可取消状态。不是模型隐藏推理过程，也不展示原始流式 JSON 或字数。
- **界面进展语言**：阶段文字与“已思考 N 秒”跟随“回答语言”设置；`follow` 时
  按输入推断（含假名→日文，纯拉丁→英文，其余→中文）。模型隐藏推理的语言只能
  通过 prompt 引导，无法由 API 强制。
- **阶段进度**：固定四步 OCR → 查词 → 生成 → 校验；显示当前/已完成步骤、
  已检索词典条目数与 citation 数。不显示字数或原始流式 JSON。
- **部分结果**：只展示本地校验/抢救后仍成立、且有 citation/evidence 支撑的
  条目；校验完成后再逐条淡入。当前 schema 是整体 JSON，不做流式 JSON 解析。
- **依据编号**：citation chip 使用全局编号「依据1」「依据2」…，同一段落的
  依据合并到卡片底部一行，按 Wrap 紧凑排列，不在每条词注后重复占行；证据组
  也显示同一编号，便于和正文对应。
- **生成摘要（P3，暂不做）**：若未来恢复，必须由模型在 schema 中输出独立的
  `summary` 字段，不能截取/泄露 reasoning；在 P0/P1/P2 反馈前不实现。
- **快照（AgentRunSnapshot）**：当前 run 的最小可渲染状态；页面返回时只读它。

## 3. 标准运行状态模型

建议实现为应用级 `AgentRunController`（Riverpod `Notifier`/`AsyncNotifier` 或
等价的 app-scoped store），至少暴露：

```text
AgentRunSnapshot {
  runId, sessionId,
  status: idle | preparing | ocr | familiarizing | tokenizing | evidence |
          reasoning | validating | done | cancelled | interrupted | error,
  stageMessage,                // 跟随回答语言的阶段说明
  startedAt,                   // run 开始时间；UI 据此显示“已思考 N 秒”
  internalChars,               // 仅供诊断/恢复，不得作为进度展示
  evidenceCount, citationCount,
  partialResult,               // 已通过校验/可渲染的结构化结果（可选）
  errorCode, errorMessage,
  updatedAt,
  canCancel
}
```

规则：

- `runId` 每次 start 重新生成；所有异步回调（stage、stream、OCR、familiarization、
  lookup）必须携带 runId，controller 丢弃非当前 run 的事件。
- 生成中的可见进度是 `startedAt` 推导的**已思考时长**，由页面每秒刷新；页面
  重建/返回时从 snapshot 的 `startedAt` 继续计时，不得从 0 重新开始。
- `internalChars`（若实现）只在 controller 内部记录，用于诊断/失败详情；UI
  **不得显示字数**，也不得显示原始流式 JSON。
- `partialResult` 只在安全时写入；校验失败/中断时保留可展示的部分，不整块清除。
- `stageMessage` 跟随回答语言设置（`follow` 按输入推断），不显示原生异常、路径、Key。
- controller 负责创建 `AgentOrchestrator`/ports；页面不得自己构造 orchestrator。
- controller 的 `cancel()` 只应由用户“停止”调用；页面 `dispose()` 只取消订阅，
  不调用 `cancel()`。

## 4. 场景矩阵（必须逐项处理）

| 场景 | 期望行为 | 禁止行为 |
|---|---|---|
| 用户从 Agent 页返回主页/其他页 | run 继续；controller 保留 snapshot；返回时显示最新进展 | 在 `dispose` 里 cancel；清空 result/stage |
| 用户打开设置/历史/模型页 | run 继续；返回后仍能看到阶段/已思考时长 | 重新开始 run；显示空会话 |
| 用户打开熟悉期 sheet 后离开 | 决定为“本次跳过”或保留 sheet 待返回；run 不取消、不永久挂起 | 让 run 无限等待一个已不存在的页面 |
| 应用切后台 | 进程存活时尽力继续；回前台刷新 snapshot | 主动取消；承诺后台一定完成 |
| 应用回前台 | 显示当前 run 的最新状态；若已被系统中断则显示 interrupted | 自动从头重跑；重复请求 |
| 进程被杀/重启 | 从持久化快照显示“已中断/重试”；不自动续跑 | 声称 run 还在继续；静默丢弃 |
| 屏幕旋转/页面重建 | 从 controller 恢复；不重复请求 | 重新初始化 run |
| 低内存/系统回收页面 | snapshot 不丢；返回可恢复 | 把状态存在页面 State 导致丢失 |
| 用户点“停止” | 取消 provider/OCR/本地查词；保留可展示内容；status=cancelled | 只把 UI 标志设为 false，后台继续 |
| 用户重复点“开始分析” | 忽略或提示先停止；同一 session 不并行 | 两个 provider 请求/两个 run 交错 |
| 网络断开/超时 | 错误卡 + 保留 partial + 重试；可显示离线状态条 | 整屏清空；阻塞弹窗 |
| provider 401/429/5xx | 稳定错误码 + 中文原因 + 重试/检查 Key | 丢内容；显示 Key/请求体 |
| OCR 模型缺失/图片解码失败 | 明确错误 + 模型设置入口；无文本时不调用 LLM | 通用“运行失败”；继续发空请求 |
| UniDic 未配置 | 按设计降级：仍可查词/翻译，标“结构分析不可用” | 整次 run 直接失败 |
| 单本词典失败/不可用 | 标记该词典失败，其他词典继续；结果显示提示 | 静默吞掉；让 strict 变成“无依据” |
| 空 OCR/空文本 | 明确“没有识别到可用文字”+重试/换图 | 发空 prompt；崩溃 |
| 文本超过预算 | 段落选择或明确限制；不静默截断 | 截断后继续分析 |
| 严格校验失败 | 错误卡 + 保留已生成内容 + 重试/切宽松 | 清空结果；只写“出错了” |
| 图片选择取消/权限拒绝 | 保持 idle；不产生 run | 弹错误对话框；自动重试 |
| run 中修改 provider/model/语言 | 当前 run 不受影响；下一次 run 使用新配置 | 中途换模型/换词典顺序 |
| run 中删除词典 | 当前 run 使用开始时的快照；失败时给出可读错误 | 原地修改正在使用的列表 |
| run 中切换严格/宽松 | 当前 run 不变；下一次生效 | 中途改变校验规则 |
| 新会话时仍有 run | 禁用或二次确认停止；不并行 | 直接清空页面并启动第二个 run |
| 返回时 run 已完成 | 显示结果/操作行；不重复请求 | 显示“新会话”空白 |
| 返回时 run 仍在流式 | 显示阶段 + 已思考时长 + 停止按钮 | 只显示“正在输入…”占位 |
| 返回时 run 已取消 | 显示 cancelled + 保留 partial + 重试 | 伪装完成 |
| 返回时 run 已失败 | 显示错误卡 + 保留 partial | 丢失已生成内容 |

## 5. 返回助手界面的渲染规则

`AgentPage` 的 `initState`/`build` 必须从应用级 controller 读取当前 snapshot：

1. **没有 run**：显示正常空态/输入区。
2. **run 进行中**：按消息流渲染用户消息、AI 气泡（阶段文字 + 每秒刷新的
   “已思考 N 秒”，两者跟随回答语言）、四步进度（OCR → 查词 → 生成 → 校验）、
   已检索条目/citation 计数、停止按钮；输入区按生成中状态处理。不显示字数/
   原始 JSON，也不展示未校验的部分结果。
3. **run 已完成**：显示结果、证据折叠、操作行（复制/重试/引用）。
4. **run 已取消**：保留 partial，显示“已停止 · 重试”。
5. **run 已中断/失败**：保留 partial，显示错误卡或“生成中断 · 重试”。
6. **熟悉期 sheet 待确认**：返回时重新展示 sheet（或按“本次跳过”继续），不得让
   run 永久停在 `awaitingProfile`。
7. **正在 `push` 设置页**：Agent 页仍在栈中时继续订阅；从设置返回时无需重新
   start。
8. **发送后输入栏清空**：用户点发送并成功创建 run 后，输入框文本和已选图片
   必须**同时清空**；不得只清图片或只清文本。已发送内容只由用户消息气泡表示，
   输入栏不得残留待发送状态。
9. **用户气泡显示图片本身**：发送图片后，用户气泡必须直接展示本地缩略图
    （多张图用 Wrap 排列），而不是“图片 1 张（仅本机 OCR）”占位；下方可保留
   “仅本机 OCR，不会上传”说明。图片路径只用于本机渲染，不得进入 provider
   请求、SQLite、日志或导出。
10. **重试复用请求快照**：发送时保存文本/图片/词典/模式/provider/语言的快照；
   “重试”从该快照重新创建 run，不读取（已被清空的）输入栏，也不得清空用户在
   发送后新输入的草稿。

页面不得在 `initState` 自动 `start()`（除非用户刚点了发送），也不得在返回时
清空 controller。

## 6. 取消、重试与并发

### 6.1 停止

- “停止”必须让 controller 调用取消链：provider `CancelToken`、OCR
  `OcrService.cancel()`、EvidenceBuilder 每个 target 的取消检查、熟悉期/查词
  的 generation token。
- 取消后 status=`cancelled`，保留 partial 和已发放 citation；不得让旧 run 的
  `onStage`/成功/异常回调覆盖新状态。
- `dispose`/路由 pop 不调用停止；只有用户显式操作。

### 6.2 重试

- 重试创建新 runId，从失败阶段或当前输入重新开始；不复用旧 stream/cancellation。
- 重试期间保留旧结果/partial，直到新结果可替换；UI 明确显示“重试中”。
- 重试不得重复扣费：若失败发生在 provider 之前（OCR/分词/词典），不要调用
  provider；若 provider 已返回，按产品策略决定是否复用缓存。

### 6.3 并发

- 同一 session 只允许一个 active run；开始新 run 时：
  - 若旧 run 仍在运行：禁用发送，或弹出“停止当前分析并重新开始？”确认；
  - 旧 run 的 runId 与新 run 不同，所有旧回调被丢弃；
  - 不允许多个 controller 同时写同一 session 的 snapshot。
- 快速双击发送、快速切换页面、快速点停止/开始，都必须幂等。

## 7. 持久化、进程死亡与后台限制

- **应用内页面切换（必须）**：controller 活在应用级 provider/store 中；页面销毁
  不影响 run。
- **应用切后台（尽力）**：Flutter 进程存活时继续；Android 可能暂停/限制网络或
  杀进程，不能承诺“后台一定完成”。
- **进程死亡/重启（P6.7 可选）**：将 run snapshot（不含 Key/完整请求体）写入
  `AgentStore`；启动时若发现未完成 run，标记 `interrupted`，提供“重试”；不要
  自动续跑、不要假装完成。
- **持久化内容**：runId、sessionId、status、stageMessage、partial 文本/结构化
  结果、证据/citation 摘要、错误码、时间。不要持久化 API Key、完整 provider
  body、原始图片字节。
- **历史**：历史会话打开时只恢复 snapshot；citation 失效时显示已保存摘要，不
  打开任意词条（见设计 §8.2）。

## 8. 当前实现进度与剩余差距（必须知道）

应用级 `AgentRunController` 已落地（`lib/state/agent_run_controller.dart:35`），
`AgentPage` 通过 `agentRunControllerProvider` 订阅 snapshot（`agent_page.dart:54,
357`）；`dispose()` 只 `detachProfileHandler` 和释放输入/滚动控制器，不再取消
run（`agent_page.dart:63-68`）。因此“离开页面继续生成、返回恢复最新进展”的
主体结构已经具备，**不要再按旧版页面 State 实现回退**。

仍需补齐：

- **进程死亡/重启持久化**：`AgentRunSnapshot` 是应用内存态；`AgentStore` 的
  sessions/runs/messages/citations 表仍未写入（H8），进程被杀后无法恢复。
- **provider 取消链**：OpenAI/Anthropic 已接 `LlmCancelToken` → Dio
  `CancelToken`，点“停止”会取消网络请求；familiarization 取消仍待补。
- **后台限制**：controller 在应用进程存活时继续；切后台/系统杀进程不能承诺
  完成，需在 UI 标 interrupted/重试。
- **生成进度**：`AgentRunSnapshot` 保存 `startedAt`/`progressStep`/
  `evidenceCount`/`citationCount`；页面显示四步进度、检索计数和“已思考 N 秒”。
  校验后的合法条目逐条淡入；不保存/展示原始流式 JSON，也不显示字数。失败/
  取消时保留已校验的结构化结果（若有），绝不展示 raw JSON 或隐藏 reasoning。
- **测试**：已有 controller 的 start→done、cancel、immediate error 测试，以及
  发送清空/思考时长 widget 测试；离开页面→继续→返回的 widget 测试和进程死亡
  模拟仍缺。
- **页面职责**：`AgentPage` 已降至 292 行，会话设置/composer/消息/证据/动作/
  进度拆到独立文件；页面只做 wiring。
- **取消边界**：provider/OCR/EvidenceBuilder 已接入；familiarization 的
  非流式调用仍可能等到 provider 超时。

因此：本文仍是目标规范；**生命周期主体已实现，剩余持久化/取消/测试项待补**。
详见 [phase6-pipeline-review.md](phase6-pipeline-review.md) 的 H4/H8。

## 9. 实现清单（改造时逐项勾选）

- [x] 新增应用级 `AgentRunController`（Riverpod provider），持有
      `AgentRunSnapshot`、当前 `AgentCancellation`。
- [x] `start()` 创建 runId、快照会话词典/provider/model/模式/语言，创建
      orchestrator 和 ports；页面不再自己构造。
- [x] `cancel()` 只在用户点“停止”时调用，取消 provider/OCR/evidence；
      familiarization 取消仍未闭环。
- [x] 页面只 `ref.watch` snapshot；`dispose()` 只取消订阅，不 cancel run。
- [x] 所有异步回调带 run token；controller 丢弃旧 run 事件。
- [x] `startedAt` 持续保留；页面重建/返回后“已思考时长”继续累加；不显示字数或
      原始流式 JSON。
- [x] 阶段事件包含 stage message；四步进度（OCR/查词/生成/校验）可见；查词
      过程中实时显示已检索条目/citation 数量。
- [x] 校验完成的合法条目逐条淡入；不做流式 JSON 解析，不展示未校验尾部。
- [ ] 生成摘要（P3）暂不做；未来只允许独立 `summary` 字段，禁止截取 reasoning。
- [x] 重复发送/新会话/重试有幂等保护；同一 session 最多一个 active run。
- [x] 熟悉期 confirm 回调在 controller 层排队；页面离开时按 skip-once 返回，
      不让 run 永久挂起（返回后不会自动重开 sheet）。
- [x] 发送成功后同时清空输入栏文本和图片附件；重试从发送快照重放，不清空新草稿。
- [x] run 开始时快照词典/模式/模型/语言；run 中设置变更不影响当前 run。
- [ ] 失败/取消/中断保留 partial；错误卡可重试；不弹阻塞全局对话框。
- [ ] （P6.7）将 snapshot 写入 AgentStore；进程重启标记 interrupted；不自动
      续跑。
- [x] 隐私：snapshot/日志不含 API Key/完整请求体；snapshot 可含仅用于本机气泡
      渲染的图片路径，但不得进入 provider、SQLite、日志或导出；图片只在本机 OCR。

## 10. 测试清单（必须覆盖）

- [x] controller 的 start→done、cancel、immediate error 已有测试；fake
      provider 只按预期请求。
- [ ] 离开 Agent 页 → 运行继续 → 返回后看到最新 stage/partial；widget 测试
      仍缺（unit 级 controller 已不受页面影响）。
- [ ] `dispose` 页面不触发 cancel；只有点“停止”才 cancel（代码已满足，widget
      断言仍缺）。
- [ ] 打开设置页/历史页再返回，run 不重启、不重复请求、结果不丢。
- [ ] 流式中返回：阶段文字、“已思考 N 秒”、四步进度和停止按钮可见；检索阶段
      能看到条目计数增长；不出现空白新会话，也不显示字数或原始流式 JSON。
- [ ] 完成后返回：结果/证据折叠/操作行可见；不重新分析。
- [ ] 错误后返回：错误卡 + partial 保留；重试使用新 runId。
- [ ] 取消后返回：显示已停止 + partial + 重试；旧回调不覆盖。
- [ ] 快速双击发送/开始：只有一个 run/一个 provider 请求。
- [x] 发送文字后：输入框为空、用户气泡仍显示原文、AI 气泡显示“已思考 N 秒”；
      发送图片路径的清空与重试复用仍需补设备测试。
- [ ] 旧 run 未结束时新 run：旧结果不覆盖新结果；旧 stage 不覆盖新 stage。
- [ ] 旋转/重建页面：snapshot 保留，不重复请求。
- [ ] 熟悉期 sheet 打开时离开/返回：不永久挂起；skip-once 或重新展示。
- [ ] 进程死亡模拟（重建 provider/store）：显示 interrupted + 重试，不自动续跑。
- [ ] 应用切后台/回前台：回前台显示最新 snapshot；不自动重跑。
- [ ] 网络断开/provider 429/超时：错误卡 + partial + 重试；不整屏清空。
- [ ] 无 UniDic/无 OCR 模型/单词典失败/空 OCR/超长文本：可读错误 + 下一步操作。
- [ ] 语义/无障碍：阶段文本、停止按钮、错误卡可被读屏识别。

## 11. 验收标准

以下场景必须能手工复现：

1. 用户发送图片/文本后，立即返回主页；等待 10 秒再回到词典助手，仍能看到
   最新阶段和“已思考 N 秒”，且没有第二次 provider 请求。
2. 用户在流式生成中打开设置页，修改模型后返回；当前 run 继续使用旧模型完成，
   下一次 run 使用新模型。
3. 用户在流式中点“停止”；后台请求不应再写入 UI，页面保留阶段/耗时并可重试
   （provider 网络取消已接入；familiarization 取消仍待补）。
4. 用户快速返回/重进三次；只有一个 run、一个请求、一个结果，无旧结果覆盖。
5. 旋转屏幕/系统回收页面后返回；阶段、思考时长和最终结果不丢。
6. 进程被杀后重开；显示“已中断”而非“已完成”，提供重试（P6.7 持久化待补）。

> 当前 P6.5 页面不满足以上验收；改造完成前，本文是**目标规范**，不是现状描述。
