# Agent-Refactor-Idea Phase 0 设计增量

- 状态：Phase 0 提案，2026-11-04；**未实现，不改变当前行为**。
- 关联：[ADR 0005](../adr/0005-agent-profile-compiler.md)、
  `docs/phase6-agent-design.md` §6.1/§6.3.1、
  `docs/phase6-agent-contracts.md` §5.1。
- 本文只记录目标架构、Phase 1 计划和验收标准；不复制规则正文、当前测试/
  设备/性能数据或契约字段表。字段名、序列化和错误码在 Phase 1 按
  contracts/schemas 流程定义。

## 1. 结论

保留 `Agent-Refactor-Idea.txt` 的产品目标，不采用它的多 Agent 拓扑：

- **保留**：机械查找先行、LLM 只做证据后过滤、词典档案缓存、语言对裁剪、
  实词/虚词本地分流、失败隔离、用户选典。
- **删除**：每句 `meaning_agent`、LLM 自主搜索循环、逐标签 `struct_agent`
  迭代、每 explore_task 的 `language_agent`、`search_agent`、每词典两次
  `summary_agent`、`supervise_agent` 选典。
- **替代**：档案编译器（一次编译、指纹缓存）+ 单次主分析 + F7 有界补查 +
  条件性按词典 fan-out。

一句话：**档案是编译产物，分析是单次查询，词表是可选覆盖包。**

## 2. 目标架构

```text
[词典导入/选中]
  └─ L0 本地：有界探针采样（12–24 条，覆盖词性/文字/条目形状）
      └─ L1 档案编译器（小模型，1 次/1–3 本词典）
          ├─ 本地脚本/语言对分类（高置信度不调用模型）
          ├─ 结构化档案：格式/方向性语言对/简介/强项/注意/覆盖指标
          ├─ 本地校验 + 至多 1 次格式修复 + 用户确认
          └─ 指纹缓存（词典级，不含词表选择）
[用户请求]
  └─ L2 本地证据装配：OCR → UniDic → 候选扩展 → 4 模式查词 → citation
      ├─ 本地意图提示（关键词/问号/输出语言），不单独调用
      └─ L3 一次主分析（复杂模型，流式）
          ├─ 条件：F7 覆盖审查（小模型，仅缺失 target）
          ├─ 条件：格式/语言修复（小模型，紧凑）
          └─ 条件：按词典 fan-out（仅 D>8 或超上下文，2–3 并发，本地合并）
  └─ L4 富文本后处理（小模型，批量、离核心路径）
```

## 3. Phase 1a：F7 复合词补查（先做，最小改动）

### 3.1 要解决的问题

`ところが` 在源文本中可能被分词为 `ところ` + `が`，两个 token 都缺少词典
证据；模型如果只按单 token 请求补查，可能错过整体词条。F7 已经允许
`[MISSING]` 请求有界补查，因此不需要给模型开工具循环，只需在覆盖审查里
显式允许“整体形式”查询，并在本地加硬约束。

### 3.2 Prompt（拟加入 `coverageSystemPrompt` 的 Rules 段）

英文原文，Phase 1 移入 `agent_prompts.dart`：

```text
- A source word may be split into pieces or be part of a fixed expression. If a
  contiguous compound or fixed collocation in the source is likely to have its
  own dictionary entry (for example ところが rather than ところ + が), request
  the whole form as one MISSING query. Do this only when the individual pieces
  are unresolved or the whole form is a known fixed expression; do not request
  every adjacent pair. The query must be an exact source substring, use only
  supplied refs, and stay within the normal limits; never request a whole
  sentence or a paraphrase.
```

不新增标签、不新增字段、不改 `[MISSING]` 语法；只是在现有 traceable 规则上
增加一条正向示例和反向限制。

### 3.3 本地硬约束（`validateCoverageReview`）

对 `kind == word` 的 MISSING 查询：

1. 如果查询已精确等于任一 token surface/lemma/reading/lookup candidate、
   pattern surface，或已有 citation 的 entryKey/headword/matchedKey，则视为
   已知术语，跳过下面的复合词长度/ token 限制（避免误杀长词条）。
2. 否则必须同时满足：
   - 是某个 source text 的精确连续子串（现有规则）；
   - Unicode code point 数 ≤ 12；
   - 不含空白或句读标点（`、。，．！？!?`）；允许 `・`、`〜` 等词内符号，
     但整体仍受长度/token 限制；
   - 在 source 中至少存在一个匹配位置，覆盖的 token 数 ≤ 4。
3. 不满足时丢弃该 MISSING，计入 `droppedMissing`，debug 日志记录
   `dropped MISSING[i] compound query=...`；沿用现有“有丢弃时提示可验证性
   警告”的行为，不新增 UI 文案。
4. `grammar`/`usage`/`context` 查询不套用 12 字符/4 token 限制；仍受现有
   100 字符全局上限、traceable 和 refs 校验约束。

**为什么是 12 字符/4 token**：`ところが` 是 4 字符、2 token；常见固定搭配
（`〜てしまう`、`〜ことがある`）也在 12 字符/4 token 内。整句通常远超这个
范围。12/4 是防滥用阈值，不是语言学结论；Phase 1 用真实样本回归后可调整，
但必须先改测试和文档。

### 3.4 测试

- `test/agent_coverage_test.dart`：
  - `ところが`（源文本子串，覆盖 2 个 token，4 字符）通过校验；
  - 超过 12 字符或覆盖 >4 token 的 `kind=word` 查询被丢弃，
    `droppedMissing` 增加；
  - 含空白/句读的查询被丢弃；
  - 精确匹配长词条/已有 citation key 时绕过复合词限制；
  - `grammar` 查询不受 12 字符限制。
- `test/agent_coverage_orchestrator_test.dart`：
  - fake coverage 返回 `[MISSING kind="word" query="ところが" refs="t1,t2"]`；
  - fake lookup 记录到一次 `ところが` 补查；
  - 合并后 citation 同时挂到 `t1`/`t2`；
  - 只发生一次覆盖审查 + 一次补查，不循环。
- 增加对 `coverageSystemPrompt` 的文本断言，确保复合词规则存在且未被
  后续编辑删除。
- 全量 `flutter analyze` / `flutter test`；不使用真实 API Key。

### 3.5 文档更新（Phase 1 实现后）

- `docs/phase6-agent-design.md` §6.3.1：补一句“F7 允许有界的复合词/固定搭配
  整体补查；本地限制 12 字符/4 token；不构成工具循环”。
- `docs/phase6-agent-contracts.md` §5.1：补 MISSING 校验规则和丢弃行为。
- `docs/project_tips.md`：只有出现真实失败模式时才新增 T-138，不预先写。
- 不在 Phase 0 修改现有设计/契约正文；本文件先作为提案。

## 4. Phase 1b：档案编译器 v2

1. 扩展现有档案 schema，新增方向性语言对、短简介、覆盖指标；字段名和
   JSON 键在 `docs/phase6-agent-contracts.md` / `docs/schemas/agent/` 定义。
2. 本地语言对分类：样本 headword/definition 的 Unicode 脚本比例 + 词典
   元数据；输出 confidence；低置信度才发 1 次小模型回退。
3. 探针保持 12–24 条，覆盖名词/动词/形容词/助词/片假名/汉字/英文/数字；
   继续使用 `assets/agent/dictionary_probes.json`。
4. 档案请求按 1–3 本/批合并（当前批上限偏保守，可提到 8k 或缩短 snippet）；
   保留一次“正文不变、仅补标签”的修复。
5. 档案在词典导入/选中时后台预热；分析时档案未就绪则用
   `noProfileInstruction` 继续，不阻塞主流程。
6. UI 显示方向性语言对和覆盖指标；用户确认流程不变（R-AGENT-10）。

**验收**：5 本词典冷启动 ≤6 次调用；第二次 0 次；语言对误判有回退；
切换词表不使档案失效。

## 5. Phase 2：请求管线收敛

1. 保留 `EvidenceBuilder` 的 4 模式预取和批量查词；不新增逐句 agent。
2. 增加本地意图提示（翻译/语法/解释、输出语言、是否多问），作为主 prompt
   的短段落；不单独发 intent 调用。
3. 主分析保持一次 `buildAnalysisRequest`；实词/虚词只在证据层用 `content`
   标记，不在任务层拆分。
4. 记录 calls/tokens/latency/citation coverage/repair rate；fake provider
   测试断言“5 词典 10 句只有 1 次主分析调用”。
5. 条件调用仍受 `AgentLimits` 约束；长文本继续 `maxSourceChars`/
   `maxTargets`/`maxCitations` 硬上限。

**验收**：一次请求核心调用 ≤4 次（主分析 + 至多 3 次条件调用）；
citation/quote/词典顺序不回归。

## 6. Phase 3：条件性 fan-out

- 仅当 `D > 8` 或 evidence 超过上下文预算时，按词典并行分析（2–3 并发）。
- 每个词典仍走同一标签协议；本地按词典顺序合并，再跑 validator。
- 单词典失败只降级该词典，其他结果保留。
- 默认关闭；真实 provider/arm64 验收后再考虑默认开启。

## 7. Phase 4：词表与多语言（延后，独立立项）

- 若产品需要词表：做成静态资产/用户导入的覆盖包，本地校验 21 项、标签
  映射、去重；不默认调用模型生成。
- 词表只用于覆盖指标，不参与格式推断，不进入档案指纹。
- 非日语源文本先实现 `TokenizerPort`，再谈 `WORD`/`GRAMMAR`；没有
  tokenizer 时明确降级，不伪装支持。

## 8. 不做什么

- 不恢复逐句 `meaning_agent` 或 LLM 自主搜索循环；
- 不让模型选词典、改词典顺序、改模式；
- 不把 21 词词表放进档案生成关键路径；
- 不为档案格式新增运行时 parser；
- 不引入 LangChain/LangGraph 或任何重型编排依赖；
- 不在 Phase 0 改 `docs/project-data.md` 的 Agent 数据行（R-DOC-11）。

## 9. 观测指标

| 指标 | 目标 |
|---|---|
| 每次 run 模型调用数 | 核心 ≤4（不含富文本） |
| 5 词典冷启动档案调用 | ≤6 |
| 档案缓存命中率 | 第二次 run 100% |
| p95 分析延迟 | <30s（真实 provider 验收） |
| citation 覆盖率 | 不低于当前基线 |
| F7 复合词查询通过率/丢弃率 | 持续跟踪，异常升高说明阈值或 prompt 退化 |
| 格式/语言修复触发率 | 持续跟踪，异常升高说明 prompt 退化 |

## 10. Phase 0 完成定义

- ADR 0005 和本设计增量已落盘；
- 明确 F7 复合词能力“未实现”，不写进 UI/状态文档；
- 不修改现有规则、契约正文或 `project-data.md`；
- Phase 1a 的 prompt/guard/test 清单可直接执行。
