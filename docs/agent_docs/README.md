# Agent 文档（docs/agent_docs）

本目录保存 Phase 6「词典助手（Agent）」的评审、已知问题、修复状态与开发约束。
Agent 相关设计与契约仍以 `docs/phase6-agent-design.md`、
`docs/phase6-agent-contracts.md` 和 `docs/schemas/agent/` 为准；本目录记录的是
**当前实现与设计之间的差距**。

## 开发前必读

1. 本文件。
2. [device-feedback-2026-10-31.md](device-feedback-2026-10-31.md) —— 2026-10-31
   实机反馈 17 项（F1–F17）的修正方案、依赖与执行波次；**当前优先工作队列**。
3. [../project-data.md](../project-data.md) —— 当前测试/设备/性能/环境/固定文案
   的单一事实源。
4. [../project-rules.md](../project-rules.md) —— 正面/反面 MUST/MUST NOT 规则的
   单一来源；Agent 相关规则见 R-AGENT。
5. [phase6-pipeline-review.md](phase6-pipeline-review.md) —— 当前管线评审与
   已知问题（含 file:line 证据）。
6. [agent-lifecycle-and-edge-cases.md](agent-lifecycle-and-edge-cases.md) ——
   运行生命周期、离开/返回页面、取消、并发、进程死亡等意外情况规范。
7. [agent-maintainability-review.md](agent-maintainability-review.md) —— Agent
   代码可维护性评审（死抽象、god 文件、controller/测试、schema 债务）。
8. [non-agent-regression-review.md](non-agent-regression-review.md) —— Agent
   以外功能的回归检查（旧 integration test 文案、帮助页文案、构建风险）。
9. [../phase6-agent-design.md](../phase6-agent-design.md) —— 设计 v2。
10. [../phase6-agent-contracts.md](../phase6-agent-contracts.md) —— 契约/schema/
    状态机。
11. [../phase6-status.md](../phase6-status.md) —— 当前实现记录。
12. [../adr/0004-agent-capability-boundary.md](../adr/0004-agent-capability-boundary.md)
    —— 能力边界决策。
13. [../project_tips.md](../project_tips.md) —— 项目误区/踩坑与已验证解决方式；
    遇到 Agent 管线、UI、构建或设备异常时先查 `T-###`。

## 硬规则

- **规范性 MUST/MUST NOT 规则统一以 `docs/project-rules.md` 为准；当前测试/设备/
  性能/环境/预算/固定文案统一以 `docs/project-data.md` 为准。** 本目录只保留
  Agent 专项评审、生命周期和历史 gap 证据，不复制规则正文/当前数值。
- 开发或修改 Agent 前，先读 `device-feedback-2026-10-31.md`（当前队列）；
  `phase6-pipeline-review.md` 是历史 gap 证据，不是当前任务清单。优先级/门禁见
  [`../project-rules.md`](../project-rules.md) R-AGENT-14/15。P6.6 多 OCR 核心
  已于 2026-11-02 按用户明确指示实现，但 Wave 4 真机/真实词典验收仍未完成；
  不要把它写成设备已验证。
- **Agent prompt 文本与请求构造统一维护在
  `lib/services/agent/agent_prompts.dart`**；不要在 orchestrator、parser、controller
  或 UI 中硬编码 prompt 字符串。`analysis_prompts.dart`、`coverage_prompts.dart`、
  `familiarization_prompts.dart` 仅为兼容 re-export，不是独立 prompt 源。
- **富文本后处理只用于详细解析**：仅“原文”section、逐句理解与词典事实解释
  （词义/语法，不含 citation snippet）使用 `[RUBY]`/`[BOLD]`/`[UNDERLINE]`；
  AI 气泡摘要和其他结果 prose（可能的理解/未解决/补充/引用行/词注 fallback）
  用本地 RUBY 渲染，不加载模型 BOLD/UNDERLINE。采用前必须剥离标签，
  并按 YOMI 规则（允许整块删除、保留块必须内容/位置不变）与原文逐字符严格比较；
  不一致就保留结果构建时的本地 RUBY 基线。标签必须正确
  嵌套：RUBY 可在 BOLD/UNDERLINE 内，BOLD/UNDERLINE 可相互包裹，但不得进入
  RUBY base 或嵌套自身。YOMI 内容比较忽略全/半角标点，RUBY 读音先清洗标点；
  RUBY 读音等于 base 时必须移除该 RUBY。读数转换是标签感知的：包住已有
  `reading【surface】` 时只保留一份读音，BOLD/UNDERLINE 在读数前关闭时把读数
  移入强调 span；普通括号 `（...）` 是解释性文字，不转换。可能的理解用
  `[OPTION]` 的结构化 label/confidence 显示“情况A”绿色胶囊 + “可能性N%”
  文本；所有情况引用同一组依据时 chip 只在最后一个情况下方显示一次，不同则
  逐情况保留。RUBY 以 base 的基线对齐，读音继承 BOLD 但永不加下划线。注音由 AI
  判断，不读取 UniDic 读音表。（R-AGENT-23、T-135）
- **P6.7 部分实现**：历史一条=一次 run、只读、不存图片/路径；声调只用 UniDic
  字段 24–26，只在词注/词典事实行；这两项已实现并有自动化测试。annotation DSL
  只接受安全 JSON AST，P6.7 先覆盖阅读器/照片集/语料；Markdown 只用于导出/
  受限档案预览；这两项仍待实现。详见 `../phase6-agent-design.md` §17.2、
  `../phase6-agent-contracts.md` §14、R-AGENT-24–27。Wave 4 由另一工作流继续。
- **内部系统 Prompt 指令统一英文**：用户/回答语言由 `AgentResponseLanguage` 控制；
  不要新增中文系统指令（校验错误文本可本地化）。闭合标签统一使用正斜杠 `[/TAG]`。
- 图片/密钥/运行状态/未实现能力等具体规则见
  [`../project-rules.md`](../project-rules.md) R-SEC/R-AGENT；
  生命周期细节见 [agent-lifecycle-and-edge-cases.md](agent-lifecycle-and-edge-cases.md)。
- 修复问题时更新对应权威文档的进展节（见下文“问题状态”），不要在本文件复制状态。

## 输出质检样本

[`../agent_output/`](../agent_output/) 保存 Agent 实际运行输出的 Markdown 质检样本，
命名规则为 `YYYY-MM-DD-HH-mm.txt`（本地时间，一次运行一个文件）。它用于人工检查
译文、逐句理解、可能的理解、未解决项和词典依据；不是模型原始响应或请求日志，
不得放入图片、路径、base64 或 API Key。发现展示问题时先定位管线/解析器原因，
不要把展示要求直接写进 prompt；目录说明见
[`../agent_output/README.md`](../agent_output/README.md)。

## 问题状态

本文件不维护状态副本；各项状态以下列为准：

- 当前工作队列、F1–F17 状态与 Wave 计划：
  [device-feedback-2026-10-31.md](device-feedback-2026-10-31.md) §1/§5。
- 管线评审 H1–H8 的结论、证据与修复进展：
  [phase6-pipeline-review.md](phase6-pipeline-review.md)。
- 可维护性 M1–M28：
  [agent-maintainability-review.md](agent-maintainability-review.md)。
- 非 Agent 回归 R1–R9 / F15–F16：
  [non-agent-regression-review.md](non-agent-regression-review.md)。
- 当前实现进度与测试/构建记录：[../phase6-status.md](../phase6-status.md)。
- 当前测试/设备/性能数字：[../project-data.md](../project-data.md)。
- P6.7 之后的任务级流式规划：
  [task-level-streaming-plan.md](task-level-streaming-plan.md)（规划中，未实现；
  不要当作当前任务）。
- P7 任务解耦/模型路由/并发流式规划：
  [p7-task-decomposition-plan.md](p7-task-decomposition-plan.md)（整体规划中；
  P7.0 富文本后处理已增量实现，其余未实现）。

## 回归与维护性评审

- **非 Agent 回归**：[non-agent-regression-review.md](non-agent-regression-review.md)
  —— 历史 R1–R9 结论与 F15/F16 登记；状态见该文档。
- **Agent 可维护性**：[agent-maintainability-review.md](agent-maintainability-review.md)
  —— 历史 M1–M28 背景；状态见该文档。
- 这些报告是**历史快照**；行号会随实现变化，继续修改后需复核。
