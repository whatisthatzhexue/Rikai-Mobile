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

## 硬规则

- **规范性 MUST/MUST NOT 规则统一以 `docs/project-rules.md` 为准；当前测试/设备/
  性能/环境/预算/固定文案统一以 `docs/project-data.md` 为准。** 本目录只保留
  Agent 专项评审、生命周期和历史 gap 证据，不复制规则正文/当前数值。
- 开发或修改 Agent 前，先读 `device-feedback-2026-10-31.md`（当前队列）；
  `phase6-pipeline-review.md` 是历史 gap 证据，不是当前任务清单。优先级/门禁见
  [`../project-rules.md`](../project-rules.md) R-AGENT-14/15。
- 图片/密钥/运行状态/未实现能力等具体规则见
  [`../project-rules.md`](../project-rules.md) R-SEC/R-AGENT；
  生命周期细节见 [agent-lifecycle-and-edge-cases.md](agent-lifecycle-and-edge-cases.md)。
- 修复问题时同步更新本目录的状态表，并在完成一项后记录验证方式。

## 问题状态表

| ID | 问题 | 状态 |
|---|---|---|
| H1 | 工具调用层未接入，且 LLM Port 无法表达 tool_use/tool_result | fixed by removal：已确认固定流水线、模型无工具；删除 tools/、AgentTool* 死 DTO、LlmTool/Capabilities，契约保留为未来参考 |
| H2 | OpenAI-compatible/DeepSeek 生产路径缺少 JSON schema 回退 | fixed：analysis/familiarization schema 已内联 prompt 并补 json_object 测试（M16） |
| H3 | 严格模式可空结果/零 citation 通过，epistemic 可绕过 | partially fixed：非空/source_id、词注强制 citation、literal/pattern 归一化、epistemic 徽标；translation 逐句 citation 仍可加强 |
| H4 | 取消是表面取消，并发 run 竞态 | mostly fixed：应用级 controller/run token/provider CancelToken/OCR cancel/evidence 检查；familiarization 取消链仍待补 |
| H5 | 多源输入只对 primary source 生成 quote，用户文本/指令混用 | partially fixed：有图时文本作为 instruction 不再进入 evidence；多 source 结果表达仍受限 |
| H6 | 失败路径：无修复/无 partial/无 retry/词典错误被吞/无 UniDic 中断 | mostly fixed：一次修复+本地抢救、provider 429/5xx 退避、词典 issue 透出、UniDic 降级；长文本段落选择/熟悉期取消仍待补 |
| H7 | 设置与密钥安全缺口 | partially fixed：模型输出日志 debug-only、Base URL 强制 HTTPS 校验、SSE 多行/错误对象处理；清除 Key/allowBackup 仍待补 |
| H8 | AgentStore 会话/运行/引用表未使用 | open；按 P6.7 处理 |

> 该表只记录评审结论；修复后请更新为 `fixed` / `partially fixed` 并附验证记录。
> 2026-10-30 设备验证：模拟器 x86_64 上图片 OCR → 分词 → MDict 查词 →
> DeepSeek 流式分析（阶段 + 已思考时长）→ 中文译文/逐句/原文/词典依据
> 已跑通；当前测试/构建/设备基线见
> [`docs/project-data.md`](../project-data.md) §2/§3/§5。仍不要据此开始 P6.6/P6.7。

### 2026-10-31 实机反馈（F1–F17）

- 完整方案、现状证据、时序与验收见
  [device-feedback-2026-10-31.md](device-feedback-2026-10-31.md)。
- 当前状态：**Wave 1 已实现**（F4/F5/F9/F10/F15/F16；代码/单元测试通过，
  设备视觉与跳转/下载验收留到 Wave 4）；Wave 2–4 未开始。F8 的“Agent 不影响
  查词”写隔离已满足，但独立持久化仍缺。
- 优先波次：Wave 1 低风险 UI/非 Agent；Wave 2 语言/档案队列/多图/操作行
  （F2 是分界）；Wave 3 检索完整度/覆盖审查；Wave 4 回归验收。
- F2 未完成前，不要实现 F7/F13/F14 的档案相关部分；不要把“页面 detach 后
  skip-once”当成合法确认。

## 回归与维护性评审

- **非 Agent 回归**：[non-agent-regression-review.md](non-agent-regression-review.md)
  —— 历史 R1–R9 结论保留；状态表显示 R1/R3 已修复、R2 文案已修但 MDict 搜索页
  最终断言仍失败；2026-10-31 新增 F15（词条内跳转范围）和 F16（OCR 下载状态）
  两个非 Agent 项，列入 device-feedback 的 Wave 1。详见该文档 §5–§6。
- **Agent 可维护性**：[agent-maintainability-review.md](agent-maintainability-review.md)
  —— 历史评审的 M1–M28 仍作为背景；状态表已更新：M1 死工具层已删除、M2
  `AgentPage` 已拆到 292 行、M3/M4/M5/M11 部分修复、M15/M16 已修复。新的 F1–F17
  反馈会重做档案队列、语言与检索策略，详见状态表和 device-feedback。
- 这些报告是**历史快照 + 状态表**；行号会随实现变化，继续修改后需复核。
  `flutter analyze` 最近记录为 No issues found；完整测试/构建以
  `docs/phase6-status.md` 的最新记录为准。
