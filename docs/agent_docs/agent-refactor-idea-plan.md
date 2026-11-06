# Agent 重构实施计划（Agent-Refactor-Idea）

- 状态：Phase 1a（F7 复合词补查）、Phase 1b（档案编译器 v2）与 Phase 2
  （请求管线收敛）已实现（2026-11-06）；Phase 3–4 未实现。
- 文档角色：
  - 原始提案：`Agent-Refactor-Idea.txt`（项目根目录；产品逻辑锚点，不是当前规则）。
  - 决策：[ADR 0005](../adr/0005-agent-profile-compiler.md)（why/what；被拒方案）。
  - 实施计划：本文（how/when；Phase 1a–4、F7 细节、验收）。
  - 索引：[README.md](README.md)；交接摘要：`CLAUDE.md`。
- 本文不复制规则正文、当前测试/设备/性能数据或契约字段表；字段名、序列化和
  错误码在 Phase 1 按 contracts/schemas 流程定义。

## 1. 范围

本文只覆盖实施；决策理由和被拒方案见 ADR 0005，不在这里重复。

- **保留**：机械查找先行、LLM 只做证据后过滤、词典档案缓存、语言对裁剪、
  实词/虚词本地分流、失败隔离、用户选典。
- **不采用**：每句 `meaning_agent`、LLM 自主搜索循环、逐标签 `struct_agent`
  迭代、每 explore_task 的 `language_agent`、`search_agent`、每词典两次
  `summary_agent`、`supervise_agent` 选典。
- **目标**：档案编译器（一次编译、指纹缓存）+ 单次主分析 + F7 有界补查 +
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

## 3. Phase 1a：F7 复合词补查（已实现，2026-11-06）

### 3.1 要解决的问题

`ところが` 在源文本中可能被分词为 `ところ` + `が`，两个 token 都缺少词典
证据；模型如果只按单 token 请求补查，可能错过整体词条。F7 已经允许
`[MISSING]` 请求有界补查，因此不需要给模型开工具循环，只需在覆盖审查里
显式允许“整体形式”查询，并在本地加硬约束。

### 3.2 Prompt（已加入 `coverageSystemPrompt` 的 Rules 段）

英文原文，已移入 `agent_prompts.dart`：

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
   已知术语，跳过下面的 token 跨度限制（避免误杀长词条）。
2. 否则必须同时满足：
   - 是某个 source text 的精确连续子串（现有规则）；
   - 不含换行；
   - **若该 source 有 tokens**：在 source 的匹配位置中，至少有一处覆盖的
     token 数 ≤ 6。6 是 `AgentLimits` 的可配置预算，不是硬编码字符数；
   - **若 tokenization 不可用或该 source 无 tokens**：只接受精确已知术语
     （token/pattern/citation key），任意子串丢弃；不做字符数兜底。
3. 不满足时丢弃该 MISSING，计入 `droppedMissing`；沿用现有“有丢弃时提示
   可验证性警告”的行为，不新增 UI 文案。
4. `grammar`/`usage`/`context` 查询不套用 6-token 限制；仍受现有 100 字符
   全局上限、traceable 和 refs 校验约束。

**为什么用 token 跨度而不是 12 字符**：字符数依赖书写系统和分词器，无法跨语言
复用：

- `ところが` 是 2 个 token；
- 长德语复合词是 1 个 token（字符数可能超过 12，但仍是单词）；
- 英文 `take care of` 是 3 个 token；
- 10 词句子是 10+ 个 token。

6 是防整句的初始阈值，不是语言学结论；它放在 `AgentLimits`，多语言接入后可按
tokenizer 调整，不需要改校验迁移逻辑。Phase 1 用真实样本回归后可调整，但必须
先改测试和文档。没有 tokenizer 时不做字符数猜测，直接退化为“只接受已知术语”，
避免多语言后期出现语言相关 magic number。

### 3.4 测试

- `test/agent_coverage_test.dart`：
  - `ところが`（源文本子串，覆盖 2 个 token）通过校验；
  - 覆盖 ≤6 个 token 的短语通过；覆盖 7+ 个 token 的查询被丢弃，
    `droppedMissing` 增加；
  - 长单 token（例如 20 字符片假名词）通过，证明不按字符数误杀；
  - 含空格的 3-token 英文短语通过；
  - 含换行的查询被丢弃；
  - tokenization 不可用或 source 无 tokens 时，任意子串被丢弃，精确已知
    术语通过；
  - 精确匹配长词条/已有 citation key 时绕过 token 限制；
  - `grammar` 查询不受 6-token 限制。
- `test/agent_coverage_orchestrator_test.dart`：
  - fake coverage 返回 `[MISSING kind="word" query="ところが" refs="t1,t2"]`；
  - fake lookup 记录到一次 `ところが` 补查；
  - 合并后 citation 同时挂到 `t1`/`t2`；
  - 只发生一次覆盖审查 + 一次补查，不循环。
- 增加对 `coverageSystemPrompt` 的文本断言，确保复合词规则存在且未被
  后续编辑删除。
- 全量 `flutter analyze` / `flutter test`；不使用真实 API Key。

### 3.5 文档更新（已执行，2026-11-06）

- `docs/phase6-agent-design.md` §6.3.1：已补“F7 允许有界的复合词/固定搭配
  整体补查；本地限制为可配置的 token 跨度（默认 6）；不构成工具循环”。
- `docs/phase6-agent-contracts.md` §5.1：已补 MISSING 校验规则和丢弃行为。
- `docs/project-data.md` §8.1：已新增 `maxCoverageQueryChars`/
  `maxCoverageCompoundTokens` 与 profile prompt 版本行；§2 测试基线已按
  Phase 1b 结果更新（当前值以该文件为准）。
- `docs/project_tips.md`：只有出现真实失败模式时才新增 T-138，不预先写。
- 本次实现已同步更新 `docs/phase6-status.md`、ADR 0005 和 `README.md` 状态。

## 4. Phase 1b：档案编译器 v2（已实现，2026-11-06）

1. 扩展现有 profile v1 schema（可选字段）：短简介 `intro`、方向性
   `language_pairs`、本地 `coverage`；JSON 键见
   `docs/schemas/agent/dictionary-profile.v1.schema.json`。profile prompt 版本
   升到 2，旧档案通过指纹失效并重新生成；schema 标识仍为 v1（向后兼容）。
2. 本地语言对分类：标题脚本提示（日中/中日/和英/英和/三语标题等）+
   headword/definition 的 Unicode 脚本比例；输出 confidence。模型
   `[LANGUAGES]` 只作同一档案请求内的低置信度回退，**不额外发语言调用**。
3. 探针扩到 16 条精确探针 + 11 条前缀探针，覆盖名词/动词/形容词/语法词/
   片假名/汉字/英文/数字；每词典样本上限 20 条，继续使用
   `assets/agent/dictionary_probes.json`。
4. 档案请求按 1–3 本/批合并（`maxBatchTokens=20000`）；保留一次“正文不变、
   仅补标签”的修复。`intro`/`language_pairs`/`coverage` 不改变用户确认流程。
5. **预热范围**：没有新增“词典选中即自动联网”的后台预热（避免违反
   R-PROD-03 的主动发送边界）。档案仍在 Agent run 开始或档案管理页显式生成；
   生成失败/待确认时保留 `noProfileInstruction` 降级，不谎称已有档案。
6. UI：Markdown 显示 `intro`、方向性语言对和覆盖指标；档案卡片 subtitle 显示
   `ja→zh` 等方向对；用户确认流程不变（R-AGENT-10）。

**验收**：5 本词典冷启动 ≤6 次调用（3 本/批）；第二次 0 次；语言对误判有
模型 `[LANGUAGES]` 回退；无自动联网；切换词表不使档案失效。测试见
`dictionary_sample_analysis_test.dart`、`dictionary_familiarization_service_test.dart`、
`dictionary_profile_tag_parser_test.dart`、`agent_models_test.dart`、
`agent_profiles_page_test.dart`。

## 5. Phase 2：请求管线收敛（已实现，2026-11-06）

1. 保留 `EvidenceBuilder` 的 4 模式预取和批量查词；不新增逐句 agent。
2. 新增 `agent_intent.dart`：本地关键词检测翻译/语法/解释/读音/校对和多问题，
   作为主 prompt 的短 `Local request hint` 段落；不单独发 intent 调用，用户
   请求仍是权威。
3. 主分析保持一次 `buildAnalysisRequest`；实词/虚词只在证据层用 `content`
   标记，不在任务层拆分。
4. 新增 `AgentRunTelemetry`：记录 `llmCalls`/`analysisCalls`/`coverageCalls`/
   `repairCalls`/`languageRepairCalls`/输入输出字符/推理字符/LLM 与总耗时/
   citation 数与 target 覆盖；不记录正文、路径或 Key。结果 JSON/history 可回放。
   覆盖合并/删重时重新计算 `targetsWithCitations`，避免 telemetry 和后续
   coverage 判断使用旧值。
5. 条件调用仍受 `AgentLimits` 约束；长文本继续 `maxSourceChars`/
   `maxTargets`/`maxCitations` 硬上限。
6. fake provider 测试断言：5 词典、10 句、无覆盖审查时只有 1 次主分析调用，
   并校验 telemetry 计数。

**验收**：一次请求核心调用 ≤4 次（主分析 + 至多 3 次条件调用）；
citation/quote/词典顺序不回归；telemetry 不含正文/路径/Key。

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

## 10. Phase 0 / 1a / 1b / 2 完成定义

- ADR 0005 和本实施计划已落盘；
- Phase 1a 的 prompt、token 跨度校验和测试已实现；F7 复合词能力已在 design/
  contracts/status 中记录为已实现；
- Phase 1b 的 intro、方向性语言对、覆盖指标、探针/批量调整、Markdown/卡片
  显示和测试已实现；未新增自动后台联网预热；
- Phase 2 的本地意图提示、单次主分析断言、`AgentRunTelemetry` 和覆盖计数
  重算已实现；
- 未修改现有规则正文；`project-data.md` 的预算/测试基线更新需用户同意；
- Phase 3–4 仍为未实现，不能写成已支持。
