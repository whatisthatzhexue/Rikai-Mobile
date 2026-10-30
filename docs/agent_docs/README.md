# Agent 文档（docs/agent_docs）

本目录保存 Phase 6「词典助手（Agent）」的评审、已知问题、修复状态与开发约束。
Agent 相关设计与契约仍以 `docs/phase6-agent-design.md`、
`docs/phase6-agent-contracts.md` 和 `docs/schemas/agent/` 为准；本目录记录的是
**当前实现与设计之间的差距**。

## 开发前必读

1. 本文件。
2. [phase6-pipeline-review.md](phase6-pipeline-review.md) —— 当前管线评审与
   已知问题（含 file:line 证据）。
3. [agent-lifecycle-and-edge-cases.md](agent-lifecycle-and-edge-cases.md) ——
   运行生命周期、离开/返回页面、取消、并发、进程死亡等意外情况规范。
4. [agent-maintainability-review.md](agent-maintainability-review.md) —— Agent
   代码可维护性评审（死抽象、god 文件、controller/测试、schema 债务）。
5. [non-agent-regression-review.md](non-agent-regression-review.md) —— Agent
   以外功能的回归检查（旧 integration test 文案、帮助页文案、构建风险）。
6. [../phase6-agent-design.md](../phase6-agent-design.md) —— 设计 v2。
7. [../phase6-agent-contracts.md](../phase6-agent-contracts.md) —— 工具/schema/
   状态机契约。
8. [../phase6-status.md](../phase6-status.md) —— 当前实现记录。
9. [../adr/0004-agent-capability-boundary.md](../adr/0004-agent-capability-boundary.md)
   —— 能力边界决策。

## 硬规则

- **开发或修改 Agent 前，先读 `docs/agent_docs/`，优先解决
  `phase6-pipeline-review.md` 中列出的高优先级问题。**
- 高优先级问题未关闭前，不要在 P6.6/P6.7 上继续叠加新功能；先把管线正确性
  （输入/校验/取消/失败路径）修好。
- 不要把未实现的能力写成已支持：模型工具调用、历史会话、真实 provider 验收、
  多 OCR 等当前状态以评审文档和 `docs/phase6-status.md` 为准。
- **运行状态必须放在应用级 controller，不得只存在 `AgentPage` State；用户离开
  Agent 页不得取消生成；返回时必须恢复最新阶段/流式文本/结果。** 具体规则见
  [agent-lifecycle-and-edge-cases.md](agent-lifecycle-and-edge-cases.md)。
- 图片只能经本机 OCR；不要把图片、路径、base64 或 provider 视觉能力引入 Agent。
- API Key 只放安全存储；不进 SharedPreferences、SQLite、日志、导出或仓库。
- 修复问题时同步更新本目录的状态表，并在完成一项后记录验证方式。

## 问题状态表

| ID | 问题 | 状态 |
|---|---|---|
| H1 | 工具调用层未接入，且 LLM Port 无法表达 tool_use/tool_result | fixed by removal：已确认固定流水线、模型无工具；删除 tools/、AgentTool* 死 DTO、LlmTool/Capabilities，契约保留为未来参考 |
| H2 | OpenAI-compatible/DeepSeek 生产路径缺少 JSON schema 回退 | partially fixed：analysis schema 已内联 prompt 并补 json_object 测试；familiarization prompt 仍未内联 schema（见 M16），需修正 README 的“已内联”说法 |
| H3 | 严格模式可空结果/零 citation 通过，epistemic 可绕过 | partially fixed：非空/source_id、词注强制 citation、literal/pattern 归一化、epistemic 徽标；translation 逐句 citation 仍可加强 |
| H4 | 取消是表面取消，并发 run 竞态 | mostly fixed：应用级 controller/run token/provider CancelToken/OCR cancel/evidence 检查；familiarization 取消链仍待补 |
| H5 | 多源输入只对 primary source 生成 quote，用户文本/指令混用 | partially fixed：有图时文本作为 instruction 不再进入 evidence；多 source 结果表达仍受限 |
| H6 | 失败路径：无修复/无 partial/无 retry/词典错误被吞/无 UniDic 中断 | mostly fixed：一次修复+本地抢救、provider 429/5xx 退避、词典 issue 透出、UniDic 降级；长文本段落选择/熟悉期取消仍待补 |
| H7 | 设置与密钥安全缺口 | partially fixed：模型输出日志 debug-only、Base URL 强制 HTTPS 校验、SSE 多行/错误对象处理；清除 Key/allowBackup 仍待补 |
| H8 | AgentStore 会话/运行/引用表未使用 | open；按 P6.7 处理 |

> 该表只记录评审结论；修复后请更新为 `fixed` / `partially fixed` 并附验证记录。
> 2026-10-30 设备验证：模拟器 x86_64 上图片 OCR → 分词 → MDict 查词 →
> DeepSeek 流式分析（阶段 + 已思考时长）→ 中文译文/逐句/原文/词典依据
> 已跑通；206 tests 与 debug APK 构建通过。仍不要据此开始 P6.6/P6.7。

## 回归与维护性评审

- **非 Agent 回归**：[non-agent-regression-review.md](non-agent-regression-review.md)
  —— 2 个 Android integration test 仍使用旧主页文案（「输入文本」「查词」），
  1 个帮助页文案指向旧「语料」入口；其余非 Agent 代码未发现确认的运行时回归，
  风险集中在构建/提交边界和 MDict worker 队列。详见该文档 R1–R9。
- **Agent 可维护性**：[agent-maintainability-review.md](agent-maintainability-review.md)
  —— 核心 Ports/Evidence/Citation/Validator 设计良好，但整体目前为中等可维护：
  约 900 行工具层生产未用、`AgentPage` 1,152 行、`DictionaryFamiliarizationService`
  752 行且流程重复、`AgentRunController` 不可注入/无测试、词典错误被吞、
  snapshot 丢错误码、schema/DTO 手工副本多。详见 M1–M28 与修复顺序。
- 这两份报告是**当前快照**；另一个 session 继续修改后，行号/状态需要复核。
  `flutter analyze` 当前为 No issues found；完整 `flutter test`/build 尚未运行。
