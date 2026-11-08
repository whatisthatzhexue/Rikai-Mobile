# P7 — Agent 任务解耦、模型路由与并发/流式规划

> **2026-11-08 修正**：实施顺序与范围以
> [agent-runtime-roadmap-2026-11-08.md](agent-runtime-roadmap-2026-11-08.md)
> 为准。当前先做 **P7-lite**（任务路由表 + 任务级遥测 + 预算）；P7.1 翻译/语法
> 任务拆分、P7.3 多任务并发、P7.4 额外审查任务暂缓。保留主分析单次调用和
> 默认关闭的词典 fan-out；只有真实 provider 数据证明单次分析不可接受且支持
> prompt cache 时才重新评估拆分。
>
> 本文的“不做断点续生成”描述已过时：当前 `_collect` 已实现流式续传。
>
> 状态：**P7.0 已增量实现；P7.1–P7.4 未实现（按 roadmap 暂缓）**。
>
> 本规划不改变固定流水线、模型无工具、citation 由 orchestrator 发放、图片只在本机
> OCR 的既有边界。相关文档：
> - P6.7：annotation DSL、安全富文本/ruby/UniDic 声调、会话历史；
> - P6.8：[任务级流式规划](task-level-streaming-plan.md)（已收窄为 P6.8-lite）；
> - 契约：[phase6-agent-contracts.md](../phase6-agent-contracts.md)；
> - 安全规则：[project-rules.md](../project-rules.md) R-SEC/R-AGENT。

## 1. 背景

单体 Agent 在 Phase 6 初期保证了一致性：一次请求携带原文、OCR 文本、UniDic 证据、
MDict citation、词典档案和完整输出契约。但随着任务复杂化，单次 Prompt 越来越长：

- 指令、证据、格式规则、引用规则全部挤在一个上下文中，模型注意力容易涣散；
- 翻译、语法解析、富文本格式化使用同一旗舰模型，成本和延迟都被放大；
- 任何格式/语言问题都触发整段重新生成，无法只重跑受影响的任务；
- 长 reasoning 与格式化混在一起，用户等待时间长，且难以定位是哪一步慢。

P6.8 解决“已生成结果如何更早显示”；P7 解决“不要把所有工作塞进一次生成”。
两者互补：P7 提供可独立调度的任务，P6.8 提供按任务/按块上屏。

## 2. 目标

1. **任务解耦**：把主生成拆成至少三个可独立重试的产物：
   - 核心翻译（translation）；
   - 语法/结构解析（structure/grammar）；
   - 富文本后处理（rich-text formatting）。
2. **模型路由**：复杂理解/推理派给旗舰模型；格式化、审查、局部修复派给轻量模型或
   本地模型；路由由 orchestrator 决定，模型不能自行换模型。
3. **并发与流式**：独立任务通过 Dart `Future.wait` 并发调度；配合 P6.8 的
   task-level streaming，按任务完成速度增量上屏。
4. **单向数据流**：任务之间只通过 orchestrator 发放的结构化 artifact 通信；
   禁止模型与模型自由对话、辩论或多轮互评。
5. **失败可降级**：单个格式化/审查任务失败不应丢掉已完成的翻译/解析；核心任务
   失败必须有明确错误，不伪造结果。

## 3. 非目标

- 不恢复自由 ReAct / 多工具大循环；模型仍不能自行查词典、OCR 或选择词典。
- 不做多 Agent 自由辩论、投票、递归互评或“模型 A 修改模型 B”的开放循环。
- 不把图片、图片路径、base64、API Key、完整 MDict HTML 发给任何任务模型。
- 不做断点续生成；重试只重发完整任务请求（P6.8 非目标）。
- 不把未通过 validator 的 citation/quote/语言结果标成已验证。
- 不改变严格/宽松语义、词典顺序或每会话词典选择。
- P7 不替代 P6.7 的 annotation/Markdown/history 交付，也不替代 Wave 4 设备验收。

## 4. 任务拆分

### 4.1 核心翻译任务

输入：原文/OCR 文本、用户要求、输出语言、必要上下文。
输出：受标签协议约束的 `[TRANSLATION]`/`[OPTION]`/`[UNRESOLVED]` 等产物。
模型：旗舰模型（或用户指定的复杂模型）。
校验：quote id、输出语言、严格模式的 citation 规则由 orchestrator 继续执行。

### 4.2 语法/结构解析任务

输入：UniDic token/grammar evidence、原文、已确认词典档案（可选）。
输出：`[SEGMENT]`/`[WORD]`/`[GRAMMAR]` 结构。
模型：旗舰模型或高精度小模型；与翻译任务可并发，因为两者都只依赖证据包。
校验：token/pattern id、读音、epistemic 类型；不得把结构分析写成词典事实。

### 4.3 富文本后处理任务

输入：已完成、已校验的**纯文本详细结果**：整个“原文”section、每条逐句理解，以及
词典事实中的词义/语法解释（不含 citation snippet）。AI 气泡摘要不进入该任务，
保持纯文本。
输出：只在原文字符之间插入 `[RUBY=读音]base[/RUBY]`、`[BOLD]...[/BOLD]`、
`[UNDERLINE]...[/UNDERLINE]` 的文本。
模型：轻量模型或本地模型；直接阅读文本判断读音，不读取 UniDic 读音表。
硬约束（内部 Prompt 统一英文，实际文本见
`agent_prompts.dart` 的 `buildDetailedRubyPostProcessRequest`）：

> It is absolutely forbidden to modify, delete or add any character of the
> original text (including punctuation, spaces and line breaks). Only
> `[RUBY=xxx]`, `[BOLD]` and `[UNDERLINE]` may be inserted. The output must
> contain the complete original text. Leave every `[YOMI]...[/YOMI]` block
> exactly as supplied. The only exception is a bracket reading:
> `reading【surface】` (or the reversed `surface【reading】`) may be replaced by
> `[RUBY=reading]surface[/RUBY]`; the base characters must not change.
> Parentheses `（...）` are ordinary explanations.

结果生成模型在 `[MEANING]` 中把读音写成 `word[YOMI]reading[/YOMI]`（不带括号；
单词=读音时只写单词）；普通括号是解释性文字，不是读音。纯显示/导出读数使用
`reading【surface】`（例如 `すき【好き】`，反向 `surface【reading】` 也接受）。
格式化调用**不预注入 RUBY**：模型输入就是结果模型文本与 YOMI；本地
`localReadingsToRuby` 在 provisional/final/salvage 结果构建时始终执行，预览首帧
即 RUBY；provider/校验失败、模型保留 YOMI/`reading【surface】` 或 section 被拒绝时，同一本地转换
兜底，模型格式化只追加 BOLD/UNDERLINE。代码端必须剥离显示标签，并按
YOMI 规则（允许整块删除；保留块内容/位置不变）与原文逐字符比较；不完全一致就
丢弃该块格式化结果，保留本地 RUBY 基线。标签必须成对且正确嵌套：RUBY 可在
BOLD/UNDERLINE 内，BOLD/UNDERLINE 可以相互包裹，但不得进入 RUBY base 或嵌套
自身；RUBY 读音继承 BOLD、永不加下划线，并以 base 的 alphabetic baseline 对齐。
RUBY 是语言无关的发音标注，不限定书写系统，禁止标签/换行；RUBY 读音等于 base
时取消该 RUBY。读数转换是标签感知的：包住已有 `reading【surface】` 注记时
显示只保留一份读音，`[BOLD]reading[/BOLD]【surface】` 会把读数移入 BOLD 内成为
RUBY（读音继承粗体）；普通括号不转换；Markdown 导出输出 `reading【surface】`。
Prompt 不使用“uncertain 就返回原文”的模糊兜底，也不要求“必须产生变化”。
该任务没有修改原文的权限，因此不能用来修错、翻译或补内容。

### 4.4 可选审查任务

覆盖审查（F7）已经是一次独立小模型调用。P7 可把“引用/语言/格式审查”做成只读任务，
输出结构化 issue；它只能建议，不能直接改写产物，也不能触发无界重试。

## 5. 模型路由

```text
AgentModelRouter
  ├─ complex: 旗舰模型（翻译、结构推理、需要跨段理解的任务）
  ├─ small:   轻量模型（格式化、审查、局部修复）
  └─ local:   本地模型（可选；只处理文本，不接触图片/路径）
```

规则：

- 路由由 orchestrator 根据任务类型、输出预算、provider 能力和用户配置决定；
  模型不能请求换模型或换 provider。
- 轻量任务必须允许失败降级；不能把格式化失败升级为核心任务失败。
- 路由结果写入 task artifact 的 `model_id` 元数据，便于复现和成本统计。
- 同一任务的重试使用同一路由快照；用户修改 provider/model 后新 run 重新路由。
- 禁止把完整证据包重复发给格式化任务；格式化只接收最终纯文本。

## 6. 并发与流式

### 6.1 并发

- 翻译与语法解析共享证据包，可 `Future.wait` 并发；
- 富文本后处理依赖翻译/解析产物，必须后置，不能提前开始；
- 审查任务可在产物齐全后并发执行，但只能产生 issue；
- 并发数必须有界（按 provider/任务类型），不能把多词典、多 target、多任务
  做成无界并发；
- 每个任务独立超时、取消和错误码；取消一个任务不能留下悬挂 future。

### 6.2 与 P6.8 的配合

P6.8 的任务级流式提供块级事件；P7 的任务产物可作为新的流式单元：

```text
translation ready ─┐
structure ready  ─┼→ artifact merge → rich-text task → final result
coverage ready   ─┘
```

- 先显示翻译，再按任务追加结构/富文本；
- 富文本只替换已通过 diff 校验的显示文本，失败保留本地 RUBY 基线；
- 最终对账以 task id/segment id 合并，禁止重复块；
- 用户滚动位置不被强制改变。

## 7. 单向数据流与协议

- 任务之间不直接对话；所有输入/输出经过 orchestrator 的 artifact store。
- 每个 artifact 带：`task_id`、`run_id`、`kind`、`status`、`input_hash`、
  `model_id`、`prompt_version`、`schema/tag version`、`created_at`。
- 任务产物只能使用已注册的标签协议；未知标签/字段拒绝或降级。
- citation/quote/token/pattern id 由 orchestrator 发放并校验，任务模型不能自造。
- 禁止“模型 A 的自由文本作为模型 B 的系统指令”；跨任务只能传结构化字段。
- 审查/格式化任务的输出不得直接改变核心事实；必须通过本地 diff/validator。

## 8. 失败、降级与预算

| 任务 | 失败处理 |
|---|---|
| 翻译 | 明确错误；可重试一次；不把无依据内容伪装成事实 |
| 语法解析 | 降级为“结构不可用”，保留翻译/词典证据 |
| 富文本格式化 | 丢弃格式化，渲染纯文本；不提示为用户错误 |
| 审查 | warning；保留原产物，不让整次 run 失败 |
| 本地模型 | 不可用则回退 small/complex 或纯文本，不阻塞核心结果 |

预算必须按任务独立配置，且来自统一 policy；不能恢复全局 magic number。
富文本/审查的 max_tokens 至少覆盖“原文 + 标签开销”，但不得假设统一模型上限。

## 9. 隐私与安全

- 任务输入只包含文本：原文、OCR 文本、token/证据摘要、已确认档案、纯文本产物。
- 不发送图片、图片路径/文件名、base64、API Key、完整 HTML、MDD 资源。
- 富文本标签渲染使用 Flutter `TextSpan`/`WidgetSpan`，不执行 HTML/JS/Markdown
  中的脚本或任意链接。
- 日志只记录 task kind/model/status/elapsed/字符数/错误码；不记录正文、Key、完整
  请求体或路径。
- 用户清除 Key/session/档案后，所有任务仍保持离线核心可用。

## 10. 实施阶段

1. **P7.0（已增量实现，2026-11-03）**：详细解析的富文本后处理：
   `[RUBY]`/`[BOLD]`/`[UNDERLINE]`、严格 prompt、标签剥离 diff、失败保留本地
   RUBY 基线；AI 气泡摘要只做本地 RUBY，不进入模型格式化。
2. **P7.1**：把翻译和语法解析拆成独立任务/artifact；保留现有 validator 作为最终
   闸门。
3. **P7.2**：加入模型路由、任务级预算和 provider 能力检测；仍由用户配置 provider。
4. **P7.3**：`Future.wait` 并发 + P6.8 任务级流式渲染；任务产物按 id 对账。
5. **P7.4**：审查任务、失败降级矩阵、成本/延迟遥测、真实 provider/arm64 验收。

P7 启动前必须先完成 P6.7 与 Wave 4 设备验收；不得在未关闭的 F1–F17 问题上叠加
新的多任务协议。

## 11. 测试与验收

- 任务 artifact 的协议往返、未知字段/标签拒绝、版本/指纹失效。
- 翻译/语法任务并发时，citation 顺序、词典顺序和严格模式不被破坏。
- 富文本 diff：完全相同才采用；任何字符变化/未闭合标签/错误嵌套标签均回退纯文本。
- 模型路由：复杂任务只用配置的复杂模型；格式化/审查失败不回滚核心产物。
- 并发：一个有界调度器；单任务取消不遗留悬挂 future；超时/限流独立重试。
- P6.8 流式：译文先于完整结果；最终对账无重复/闪烁；失败保留已验证内容。
- 隐私：所有请求体断言无图片/路径/Key/HTML；日志脱敏。
- 设备：真实 provider、arm64、长文本、多词典、断网/限流/取消、进程死亡。

## 12. 风险与对策

| 风险 | 对策 |
|---|---|
| 多任务导致结果不一致 | orchestrator 单点合并；最终 validator 重新校验 |
| 自由多 Agent 变成不可控辩论 | 单向 DAG；禁止模型间对话/互评；只传结构化 artifact |
| 格式化模型改动原文 | 剥离标签逐字符 diff；失败保留本地 RUBY 基线（T-135） |
| 并发放大 provider 限流/成本 | 有界并发、任务预算、路由快照、429 退避 |
| 轻量模型格式失败阻塞核心 | 格式化/审查可降级；核心任务独立错误 |
| 任务产物重复上屏 | task/segment id 对账；最终结果覆盖 partial |
| 本地模型能力/许可不明 | 仅作为可选文本模型；不随包分发；用户配置 |
| 流式与隐私边界冲突 | 事件只带结构化文本/错误码；不缓存图片/路径/Key |

## 13. 与当前工作的关系

- P7.0 富文本后处理已落地；它只格式化详细解析的原文/逐句理解/词典事实解释，
  **不改变原文、不参与事实生成**。失败时保留本地 RUBY 基线，不影响核心结果；
  AI 气泡摘要和其他结果 prose 只做本地 RUBY，不进入模型格式化。
- P7.1–P7.4 尚未实现；当前 Wave 4/P6.7 完成前不启动。
- P6.8 任务级流式规划见
  [task-level-streaming-plan.md](task-level-streaming-plan.md)；P7 的任务 artifact
  应作为其流式单元，不另起一套协议。
- 若 P7 需要改变标签协议，先更新 `docs/phase6-agent-contracts.md`、解析器测试和
  `docs/project_tips.md`，再进入实现。
