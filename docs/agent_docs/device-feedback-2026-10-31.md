# Agent 实机反馈修正计划（2026-10-31）

- 状态：**Wave 1 已实现（F4/F5/F9/F10/F15/F16）；Wave 2–4 未开始；
  未开始 P6.6/P6.7。**
- 来源：用户实机使用 P6.5 后提出的 17 项反馈（本文件按原编号 F1–F17 记录）。
- 基线：P6.5 固定流水线、应用级 `AgentRunController`；Wave 1 后
  `flutter analyze` 无问题、213 tests 通过、debug APK 构建成功。真实
  arm64/漫画页验收仍未完成；本文件不改变已有验证记录。
- Wave 1 验证：`flutter test` 213 passed；`flutter build apk --debug` 成功。
  F4/F5/F9/F10 有 widget/unit 覆盖；F15 有请求范围 unit 测试；F16 有
  controller 进度/取消测试。设备手工验收仍待 Wave 4。
- 约束：不 commit/reset；不覆盖已有评审结论；图片仍只在本机 OCR；API Key 仍只
  在安全存储；F15/F16 是用户明确要求的非 Agent 修复，不能借机改动查词/OCR
  的核心行为。

关联文档：

- [生命周期规范](agent-lifecycle-and-edge-cases.md)
- [管线评审](phase6-pipeline-review.md)（H1–H8）
- [可维护性评审](agent-maintainability-review.md)（M1–M28）
- [非 Agent 回归](non-agent-regression-review.md)（R1–R9）
- [设计 v2](../phase6-agent-design.md)、[契约](../phase6-agent-contracts.md)、
  [当前状态](../phase6-status.md)

## 0. 结论与执行顺序

17 项中真正卡住后续工作的是 **F1/F17（默认中文与 UI 文案语言）**、
**F2（词典档案确认队列）**、**F6/F7（检索完整度）**。其余大多可独立完成。

推荐顺序：

```text
Wave 0  本文档 + 规范同步（已完成）
Wave 1  低风险、可并行的 UI/非 Agent 修正
        F9 → F10 → F15 → F16 → F4 → F5
Wave 2  Agent 状态、语言与档案生命周期（串行，先做此波再做检索重构）
        F8 → F1a/F17 → F2 → F3 → F11 → F12 → F13 → F14
Wave 3  检索完整度与语言结果校验
        F1b → F6 → F7
Wave 4  回归、设备验收、状态表更新
```

排序理由：

1. **F8 先于 F2**：先把 Agent 词典选择迁到独立持久化，避免确认队列改造时再次
   碰同一份页面状态。
2. **F1a/F17 先于 F2**：档案队列的“等待确认”“已跳过”“待处理 N 个”等文案必须
   走统一语言表；先做语言基础，不再到处补中文硬编码。
3. **F2 是分界线**：在应用级档案队列落地前，不做 F7（覆盖审查）、F13（档案管理）
   或 F14 的重新生成，否则会把“页面回调即跳过”的临时行为固化进新功能。
4. **F3 在 F2 后补测试**：确认等待期间也要计入 run 的 wall-clock 时间。
5. **F11/F12 先于 F14**：先有多图选择与查看，再做结果操作行/编辑重发，避免编辑
   用户气泡时又改一次图片数据结构。
6. **F13 先于 F14**：F14 的循环图标要“从熟悉词典步骤重跑”，复用 F13 的档案
   服务/管理接口，而不是再造一套页面内重试。
7. **F6 先于 F7**：F7 的补充检索必须建立在“exact→prefix→suffix→incremental、
   全局上限、遇到无新增即停止”的确定性检索器上；否则覆盖审查会放大无界查询。
8. **F1b 放在 Wave 3 开头**：语言后校验/一次修复与 F6/F7 都改 orchestrator，但
   它不依赖覆盖审查；先做可先降低“设置中文却输出日文”的体感问题。

## 1. 状态总表

| ID | 反馈摘要 | 当前状态 | 处理波次 | 依赖 |
|---|---|---|---|---|
| F1 | 默认输入/输出中文；设置语言后结果仍不总是目标语言 | open；默认 `follow`，无结果语言校验 | 2（默认/文案）+3（校验） | F17 |
| F2 | 离开 Agent 页后档案不保存/队列未堆积，查词提前开始 | open；页面 detach 后按 `skipOnce` 继续 | 2 | F1a、F8 |
| F3 | 离开页面期间也要计算思考时间 | 待验证；`startedAt` 已在应用级 snapshot，页面标签为 wall-clock，缺回归测试 | 2 | F2 |
| F4 | 依据气泡改为短胶囊并自动换行 | fixed（unit/widget；设备视觉待验） | 1 | — |
| F5 | 结果中的 `（q1）` 等标记太抽象 | fixed（unit/widget） | 1 | — |
| F6 | 查词不能只完全/前方匹配；达到全局上限或搜不到更多才停 | open；当前每目标 exact 后 prefix，`60` 硬编码 | 3 | F6 前先定义 `AgentLimits` |
| F7 | 查词结束后补做覆盖审查，最多回退一次查词 | open；无覆盖审查 schema/阶段 | 3 | F2、F6 |
| F8 | Agent 词典选择必须独立保存，不影响查词选择 | partial；写隔离已满足，但仍从查词偏好初始化且无独立持久化 | 2 | — |
| F9 | 词典选择第 4 行露出半行（预留 3.5 行） | fixed（shared widget + widget test；设备视觉待验） | 1 | — |
| F10 | Provider 表单中文化、DeepSeek/Claude 自动填 Base URL | fixed（widget/unit test；设备保存待验） | 1 | — |
| F11 | 上传照片按钮先选相机/相册，支持多选、依次追加 | open；仅相册单选 | 2 | F12 可复用 |
| F12 | 发送后的图片可点开，全屏缩放同照片集 | open；用户气泡缩略图不可点 | 2 | F11 |
| F13 | 标题栏管理全部词典档案：删除/修改/重新生成/多选 | open；无档案管理 UI，历史按钮仍占位 | 2 | F2 |
| F14 | AI 结果底部循环/复制；用户气泡长按复制/修改 | open；无操作行、无结果 Markdown、无编辑重发 | 2 | F2、F13 |
| F15 | 词条内跳转只查当前词条所在词典，完全匹配后取首个 | fixed（unit；设备词条跳转待验） | 1 | —（非 Agent） |
| F16 | OCR 模型后台下载，返回模型页仍显示进度 | fixed（controller unit；设备下载页待验） | 1 | —（非 Agent） |
| F17 | Agent 本地 UI 文案跟随输出语言，禁用输入启发式 | open；`resolveAgentUiLanguage` 按假名/拉丁推断 | 2 | F1a |

## 2. 共同基础设施（先定义，避免每项各造一套）

### 2.1 `AgentLimits` 单一来源

F6 明确要求不能硬编码 `60`。新增一个可注入的 policy（建议放
`lib/core/models/agent/agent_limits.dart` 或 `lib/services/agent/agent_limits.dart`）：

```text
maxSourceChars             6000
maxTargets                 120
maxEvidenceEntries         60   // 全局检索/引用上限；UI 只读它
maxEntriesPerDictionary    3
maxSnippetChars            400
maxImagesPerRun            6    // F11 多图上限，可调
maxCoverageMissing         20   // F7 schema 允许的缺失项
maxCoverageDuplicateGroups 10   // F7 去重组上限
maxCoverageFallback        1    // F7 每个用户请求最多回退一次
```

- `AgentOrchestrator`、`EvidenceBuilder`、`AgentEvidenceBudget`、结果页计数和
  `AgentRunSnapshot` 全部引用同一对象/字段；代码里不再散落 `60`。
- `AgentLimits` 也是请求级快照的一部分；run 中修改设置不影响当前 run。
- 现有 `maxTargets/maxCitations/maxSourceChars` 构造参数可以保留给测试，但生产
  默认值必须来自 policy。

### 2.2 应用级档案队列与独立选择

- `AgentProfileProposal`/`AgentProfileInboxController`：应用级，不依赖页面
  `BuildContext`，保存“已生成、待用户处理”的档案。
- `AgentDictionaryPreferencesNotifier`：Agent 自己的 `selectedIds + mode`，
  独立持久化，不读/不写 `lookupPreferencesProvider`。
- `AgentUiStrings`：Agent 功能区的本地文案表，按 `AgentUiLanguage` 取字符串；
  **语言只由显式设置决定**，不再读输入文本。

### 2.3 语言结果后校验

- 新增 `AgentLanguageValidator`：检查模型输出中的人类可读字段（译文、逐句解释、
  词注释义、语法说明、未解决原因、模型补充），不检查原文 quote、词形、读音、
  citation 摘要。
- 通过 Unicode 脚本比例/假名检测判定字段是否明显偏离目标语言；判定为偏离时
  走一次**语言修复调用**（复用现有 repair 管线：同一证据/quote，保留 citation、
  quote_id、结构；不重跑 OCR/查词），仍偏离则保留结果并显示警告，不丢弃已付费
  输出。模型 API 无法“强制”语言，文档不能承诺 100%。

## 3. 逐项方案

### F1｜默认中文，并提高输出语言稳定性

现状：

- `AppSettings.agentResponseLanguage` 默认 `'follow'`
  （`lib/services/storage/settings_store.dart:20-21`）。
- `AgentRunRequest.responseLanguage` 默认 `follow`
  （`lib/services/agent/agent_run.dart:52`）。
- `AgentResponseLanguage.follow` 的 UI 选项存在
  （`lib/features/settings/agent_settings_page.dart:90-106`）。
- prompt 只有 `AgentResponseLanguage.instruction` 的软约束
  （`lib/core/models/agent/agent_profile.dart:50-57`），没有结果语言校验。

方案：

1. 默认值改为 `zh`；`SettingsStore.load()` 对缺失值使用 `zh`。已有
   `follow` 建议一次性迁移为 `zh`，从 Agent 设置移除“跟随输入”；如需保留枚举，
   仅用于读取旧配置，解析时直接映射到中文。
2. system prompt 增加明确的“输出语言契约”：所有人类可读字段用目标语言；日语仅
   出现在原文引用、词形/读音/词典例句中；不得把日语原文当作用户解释。
3. `AgentLanguageValidator` 做字段级后校验；失败时一次语言修复，仍失败则显示
   “部分内容未按设置语言输出”警告并保留结果；不要静默删改或整次失败。
4. 目标语言是 `zh` 时，输入框占位、按钮、阶段文字、错误摘要也全部中文；用户把
   语言改成 English/日本語时，Agent 本地文案按 F17 同步切换。

验收：

- 日本语输入 + 默认设置：Agent 页面文案、译文、逐句解释、词注均为中文；只有
  原文/词形/读音保留日文。
- 设置 English：页面阶段文字与结果人类可读字段为英文；日本语输入不触发日文 UI。
- 语言修复失败仍能看到结果和明确警告，不出现“生成完却空白”。

### F2｜词典档案按应用级队列逐个确认，查词阶段等待全部处理

现状（确认问题）：

- `AgentPage.dispose()` 只 detach profile handler
  （`lib/features/agent/agent_page.dart:62-65`）。
- `AgentRunController` 在 handler 为空或抛错时返回 `skipOnce`
  （`lib/state/agent_run_controller.dart:205-220`）。因此用户离开页面后，生成
  其实可能继续（controller 是应用级），但档案不会保存，run 也不会停在
  待确认状态。
- `DictionaryFamiliarizationService.ensureMany()` 在生成后立即调用页面注入的
  `confirm`（`lib/services/agent/familiarization/dictionary_familiarization_service.dart:351-389`），
  无法形成“生成完先堆积、回来再处理”的队列。
- `AgentRunStatus` 没有 `awaitingProfile`，状态机与实现不一致
  （`lib/services/agent/agent_run.dart:122-134`）。

方案：**生成与确认两阶段分离，禁止页面 detach 即 skip。**

1. 新增应用级 `AgentProfileInboxController`：
   - `AgentProfileProposal { id, runId, dictionaryId, title, fingerprint, draft,
     markdown, status, createdAt }`；
   - 状态：`pending / save / skipOnce / decline`；
   - 提供 `pendingProfiles`、`allResolved(runId)`、`resolve(id, action, markdown)`。
2. 熟悉期服务拆成：
   - `generateMissing(dictionaries, ...)`：只做采样 + LLM + 解析，返回 proposals；
     不调用 UI，不写档案；
   - `persistDecision(proposal, action)`：只有用户在队列中确认后才写
     `dictionary_profiles`；`skipOnce` 不写，`decline` 写 declined。
3. controller 在生成完成后把 proposals 入队，状态进入 `awaitingProfile`：
   - 只要还有 `pending`，不进入 tokenizing；
   - 页面回到前台时按队列顺序显示 sheet；顶部显示“待处理档案 N 个”；
   - 用户离开页面、旋转、打开设置时，队列和生成都继续；不自动 skip；
   - 用户 dismiss sheet 只会把该项留在 pending，绝不推进；
   - 提供显式的“本次全部跳过”操作时需要二次确认，属于用户处理，不是自动跳过。
4. 采样失败/模型没有返回该词典：生成 `unavailable` issue，记录 warning；这类
   没有可确认的档案，不阻塞后续，但结果显示“档案不可用”。
5. 队列当前放应用内存；进程被杀后的恢复归 P6.7 持久化，不能在本项里假装已支持。
6. 如果用户永远不回来，run 可停在 `awaitingProfile`；这是“必须先处理”的预期，
   不是页面挂死。UI 显示等待态和取消入口。

验收：

- 发送后立即返回主页；档案生成继续；返回时显示待处理档案，查词尚未开始。
- 一次选中 3 本词典，3 个 proposal 逐个弹出；处理完最后一个才进入查词。
- 离开页面后重新进入，未处理项仍在；不会出现“已跳过但没保存”。
- 单本采样失败只显示 warning，不阻塞其他档案/查词。

### F3｜离开 Agent 页面期间继续计算思考时间

现状：

- `AgentRunSnapshot.startedAt` 在 `start()` 时写入
  （`lib/state/agent_run_controller.dart:114-130`），页面重建不会重置。
- `AgentElapsedLabel` 用 `DateTime.now() - startedAt`，并在有 `finishedAt` 时停止
  （`lib/features/agent/agent_message_widgets.dart:330-391`）。从代码看，离开再返回
  会包含离开期间的 wall-clock；但缺少回归测试，且 F2 的等待确认状态尚未定义。

方案：

- 保留应用级 `startedAt/finishedAt`；禁止页面 `initState` 重新计时。
- 统一 `elapsed = finishedAt ?? now - startedAt`，并在 F2 的
  `awaitingProfile` 状态仍继续增长（用户明确要求离开期间也计算；等待确认是否
  计入由本项按“计入”实现，未来若要排除需另立产品决策）。
- 增加“离开页面 10 秒再返回”的测试：时间包含离开区间，且没有第二次 provider
  请求。
- 若 UI 需要区分“正在生成”和“等待用户确认”，可额外显示阶段文字，但不重置时钟。

### F4｜依据气泡改为短胶囊，自动换行

现状：

- `_CitationChip` 高度 28、12sp、横向 padding 8、`Wrap`（`lib/features/agent/agent_result_view.dart:539-575`）；
- 证据行另有 `依据N · 查看` 长文本（`:509-515`），视觉上仍是长条。

方案：

- 采用词典筛选条同样的“短胶囊 + Wrap”语言，但**颜色保持当前 Agent 颜色**
  （`AgentTokens.citationSurface/citationText`，不改成词典筛选的深蓝选中态）。
- 建议 token：视觉高度 24–28（取 24）、水平内边距 8、字号 12、文本 `依据N`、
  `Wrap(spacing: 4, runSpacing: 4)`；视觉高度小，但用 `InkResponse`/`Semantics`
  提供 ≥40dp 触控热区，不能牺牲可点击性。
- 证据卡不再显示 `依据N · 查看` 长串；保留短 chip，点击 chip 查看；词条标题与
  短 chip 分两行或同一行的紧凑布局，避免整行被文本占满。
- 所有引用位置（逐句、多解释、证据组）统一使用同一个 chip 组件。
- 自动换行遵循组件宽度，不强制列布局；行内按 `依据1 → 依据2 → …` 顺序。

验收：

- 在窄屏/200% 字体下 chip 不溢出、不横向滚动；一行放不下自动换行；颜色与当前
  浅蓝底蓝字一致。

### F5｜移除 `（q1）` 等内部标记

现状：

- `AgentResultView` 的“未解决”直接拼 `unresolved.quoteId`
  （`lib/features/agent/agent_result_view.dart:168-181`），用户看到 `（q1）`。

方案：

- **选择“直接删除标记”**：`quote_id` 只作为内部结构，不进入用户可见文本；
  `unresolved` 只显示原因，原文已经在上方“原文”块中列出。
- 如果确实需要指向具体句子，用“第 1 处原文”这类由 quote 顺序生成的自然语言，
  不显示 `qN`/`seg-N`/`tN` 等内部 ID。
- prompt/schema 明确禁止在人类可读字段中写入内部 ID；UI 只对 `unresolved` 做
  防御性裁剪（去掉末尾 `（qN）`），不误删正文。
- 测试断言结果页不出现 `（q1）`/`qN`，同时 quote 原文仍可见。

### F6｜查词完整度：全局上限 + 四种匹配模式递进

现状：

- `EvidenceBuilder` 每目标先 exact，未命中再 prefix
  （`lib/services/agent/evidence_builder.dart:171-184`）；
- `maxCitations=60` 在 orchestrator/evidence/budget 多处硬编码
  （`agent_orchestrator.dart:45-47`、`evidence_builder.dart:23-25`、
  `agent_evidence.dart:231-232`）；
- `LookupMatchMode` 已支持 `incremental/exact/prefix/suffix`，但没有被 Agent 的
  递进策略使用。

方案：

1. 使用 `AgentLimits.maxEvidenceEntries`（默认 60）作为唯一上限；不在业务代码
   写 `60`。
2. 新增 `EvidenceLookupPlan`/`LookupCompletenessPolicy`：
   - 先对所有 target 跑 exact；
   - 若未达上限，依次跑 prefix → suffix → incremental；
   - 每个模式只处理尚未达到每词每典上限的 target，按词典顺序查询；
   - 每模式统计“新增的唯一 citation 数”；若某模式新增为 0，说明无法从该模式
     获得更多内容，停止后续模式；
   - citation 数达到上限立即停止；重复 `(dictionaryId, entryKey)` 不计数、不发新
     citation。
3. 进度显示“已检索 N 条 / 上限 M 条”，N/M 来自 policy；UI 不写死 60。
4. 性能保护：suffix/incremental 依赖 worker 的 key 扫描缓存；每目标/每模式有
   取消检查；大词典扫描期间仍可停止；不要把 120 个 target 的四轮查询做成无界
   并发。
5. 测试：exact 达上限时不跑后续模式；prefix 有新增继续；suffix/incremental
   顺序正确；某模式无新增即停止；全局上限变量被引用。

### F7｜查词后做一次覆盖审查，最多回退查词一次

现状：

- 当前证据构建完直接进入 reasoning；没有“缺少哪些资料”的审查，也没有回退
  查词阶段（`agent_orchestrator.dart:233-273`）。

方案：新增 **一次性覆盖审查**，放在初始证据之后、最终 analysis 之前。

#### F7.1 轻量 schema（新建议，不直接复用较重的 analysis schema）

```json
{
  "schema": "rikai.agent.coverage.v1",
  "source_id": "src-1",
  "verdict": "missing",
  "missing": [
    {
      "kind": "word|grammar|sense|usage|reading|example|context",
      "query": "何卒",
      "source_refs": ["t12", "p3"],
      "reason": "缺少该词在正式请求语境下的释义",
      "priority": 1
    }
  ],
  "duplicate_groups": [
    {
      "dictionary_id": "dict_a",
      "keep_entry_key": "何卒",
      "remove_entry_keys": ["何卒（副）"],
      "reason": "词条相同且释义大部分重合"
    }
  ],
  "notes": ""
}
```

- `missing` 最多 `AgentLimits.maxCoverageMissing` 项；`duplicate_groups` 最多
  `maxCoverageDuplicateGroups` 组。
- `query` 必须可追溯到源文本子串、token 的 lemma/lookupCandidates、已匹配语法
  模式或已有 suggest 结果；否则 orchestrator 丢弃，不能把模型当任意词典浏览器。
- 输入只含文本源、token/语法摘要、去 HTML/去路径/截断的词典摘要，不含图片、路径、
  完整 HTML、MDD、base64。
- 复用现有 JSON 解析/一次修复/校验管线；覆盖审查失败只产生 warning，不让整次
  run 失败。

#### F7.2 流程

```text
initial evidence (F6 modes)
  → coverage review (small model, schema)
  → if missing and count < limit:
        flow A: supplementary lookup (exact → prefix → suffix → incremental)
  → else if count == limit:
        verify duplicate groups locally
        remove low-density duplicate citations to free N slots
        flow A with N slots
  → final analysis (reasoning/validation)
```

- **流程 A（未达上限）**：按 `missing` 中可追溯的 query 直接补充检索；仍按 F6
  的模式顺序，直到达到上限或某模式无新增；已有 citation 不重复。
- **流程 B（已达上限）**：先由本地确定性校验确认“同一词典 + 同一词条/词条键 +
  摘要大部分重合”；删除信息密度较低的重复条目，空出的槽位再用流程 A 补充。
  不能仅凭模型说“重复”就删除，不能跨词典误删。
- 若没有可验证的重复项，跳过流程 B，显示“检索已达上限，无法再补充”，不做
  无限回退。
- 每个用户请求最多一次覆盖审查 + 一次回退查词；用 `coverageFallbackUsed` 标记，
  绝不循环。
- 新增 `AgentStage.coverage`（或 evidence 子阶段）和“补充资料中”进度；结果中
  记录覆盖审查 warning/fallbackUsed。
- 新 citation 仍由 `CitationRegistry` 发放，保持词典顺序；删除重复 citation 后
  要重建最终 bundle/citationsUsed，不能让模型看到已删除来源。

验收：

- 第一次检索未满 60：覆盖审查给出缺失词，补充后条目数增加；只回退一次。
- 第一次已满 60：有重复时删除低密度条目并补充；无重复时明确结束，不循环。
- 缺失 query 不可追溯时被丢弃，不产生任意词条访问。
- 覆盖审查 schema 失败/超时：保留原证据继续分析，显示 warning。

### F8｜Agent 词典选择独立保存，禁止与查词共用结果

现状：

- `AgentPage.initState` 从 `lookupPreferencesProvider` 取初始选择
  （`lib/features/agent/agent_page.dart:52-58`）；
- 页面只改本地 `_selectedIds`，不写查词全局偏好
  （`:86-103`），所以“Agent 影响查词”目前没有发生；但 Agent 自身没有独立
  持久化，重启/重新进入会再次被查词偏好覆盖。

方案：

- 新增 `AgentDictionaryPreferences` 与 `agentDictionaryPreferencesProvider`，
  独立 key（例如 `agent_dictionary_selected_ids`、`agent_dictionary_mode`），
  默认“全部 enabled 词典”。
- `AgentPage`/`AgentSessionPanel` 只读写这个 provider；不再读
  `lookupPreferencesProvider`。
- 查词页/阅读弹层继续使用 `lookupPreferencesProvider`；互不监听、互不写入。
- 如未来需要“从查词选择导入”，做成显式按钮，不做自动同步。
- run 开始时仍快照所选词典列表（已有行为），保证会话隔离。

验收：

- 改 Agent 选择后，查词页选择不变；改查词选择后，Agent 选择不变。
- 重启应用后 Agent 选择恢复；新建 Agent 会话仍使用 Agent 自己的选择。
- 单/多选模式也独立持久化。

### F9｜词典选择第 4 行露出一半（3.5 行）

现状：

- `DictionaryFilterBar.maxVisibleRows = 3`，最大高度按 3 行计算
  （`lib/features/lookup/dictionary_filter_bar.dart:24,41-45`）。

方案：

- 在共享 widget 中把可见高度改为 **3.5 行**：
  `3.5 * AppSizes.dictionaryFilterRow + 3 * AppSpacing.xxs`（具体 gap 数以
  `Wrap.runSpacing` 为准）；第 4 行至少露出一半气泡，避免用户误以为不存在。
- 新增 token（如 `dictionaryFilterVisibleRows = 3.5`），不要在各页面写
  `32 * 3.5` 魔法数。
- 搜索页、阅读查词弹层、Agent 会话面板都使用同一个 `DictionaryFilterBar`，
  因此一次修改覆盖所有词典选择界面；如果某页有局部高度覆盖，一并移除。
- 内部仍可纵向滚动；滚动条/内容不得推挤结果区。

验收：

- 词典多到第 4 行时，第 4 行可见至少半个 chip；可滚动选择；三个界面表现一致。

### F10｜Provider 表单中文化、预设自动填 Base URL

现状：

- 设置页大量英文：`模型 Provider`、`添加 Provider`、`Base URL`、`Small model`、
  `Complex model`、`OpenAI-compatible / DeepSeek`
  （`lib/features/settings/agent_settings_page.dart:108-113,403-467`）。
- 只有 Anthropic 默认填 Base URL；OpenAI-compatible/DeepSeek 初始为空
  （`:357-365`）。

方案：

- 用户可见文案改为：
  - `模型服务`（不显示 Provider）
  - `服务商`
  - `接口地址`（Base URL）
  - `快速模型`（说明：用于词典档案/覆盖检查）
  - `高精度模型`（说明：用于最终解析）
  - `API Key` 可保留，或改为“接口密钥（API Key）”
- 服务商选项：
  - `DeepSeek` → 内部 kind `openAiCompatible`，默认接口地址
    `https://api.deepseek.com/`；
  - `Claude（Anthropic）` → 默认 `https://api.anthropic.com/`；
  - `其他 OpenAI 兼容服务` → 默认空，用户手填。
- 切换预设时，仅当接口地址为空或仍等于上一预设默认值才自动填写；用户已手改的
  地址不能被静默覆盖（可提示“已保留你的自定义地址”）。
- 模型名不强制预填，但可在字段下方给推荐示例；不把 provider 能力/Key 写到 UI
  以外的新位置。
- 保留现有 HTTPS/主机校验；错误文案中文化。

验收：

- 新用户选 DeepSeek 后接口地址自动为 `https://api.deepseek.com/`；选 Claude
  自动为 Anthropic 地址；选手动服务为空。
- 编辑已有自定义地址时，切换预设不会覆盖。
- 表单不再出现 `Provider/Base URL/small-model/complex-model` 英文标签。

### F11｜照片按钮：相机/相册底部菜单，多选并依次追加

现状：

- Agent 只有 `_imagePath` 单值（`lib/features/agent/agent_page.dart:42,105-113`），
  `_pickImage` 只用相册单选。
- composer 只渲染一张缩略图（`lib/features/agent/agent_composer.dart:32-67`）。

方案：

- 页面状态改为 `List<AgentImageInput>`（或带本地 id 的 `_PickedImage`），按选择
  顺序追加，不覆盖已有图片。
- 点击上传按钮弹出底部 `showModalBottomSheet`：
  - `拍照`：`ImagePicker.pickImage(source: camera)`，一次一张；
  - `从相册选择`：`ImagePicker.pickMultiImage()`，多选后按返回顺序追加。
- composer 显示 `Wrap` 缩略图（64dp），每张有移除按钮；超过
  `AgentLimits.maxImagesPerRun` 时提示并拒绝新增。
- `_send` 不再检查单路径；把列表传给 controller（controller 已支持多图并按
  `img-1...` 归一化，见 `agent_run_controller.dart:56-63`）。
- 图片仍只在本机 OCR；不把路径/文件名发给 provider；用户气泡显示全部图片。
- 图片选择抽象成可注入的 picker（便于测试），不要把 `ImagePicker` 硬编码在
  widget 内；测试覆盖追加/移除/取消/上限。

验收：

- 相册可一次选多张；接着再拍一张会追加，不替换；发送后用户气泡显示全部图片。
- 取消选择不改变已选图片；移除单张不影响其他图片。

### F12｜发送后的图片可点开全屏缩放

现状：

- 用户气泡缩略图只是 `Image.file`，没有点击处理
  （`lib/features/agent/agent_message_widgets.dart:88-114`）。
- 照片集已有 `PhotoViewerPage`（黑底、`InteractiveViewer`、关闭按钮，
  `lib/features/capture/photo_viewer_page.dart`）。

方案：

- 给用户气泡的每张缩略图包 `InkWell`/`GestureDetector` + `Semantics`；点击
  `Navigator.push(RikaiPageRoute(...))` 打开现有 `PhotoViewerPage(imagePath: path)`。
- 复用照片集同样的黑底/双指缩放/平移/关闭；不新建第二套 viewer。
- 多图逐张可点；图片缺失时保留破图占位和可读错误，不崩溃。
- 图片路径仍仅用于本机显示；不写入 provider/日志/SQLite。

验收：

- 发送 2 张图片后，点击任意一张进入全屏，可缩放/平移/关闭，返回对话位置不丢。
- 自动化测试若受 `Image.file` 解码影响，至少覆盖 onTap/navigation 回调；真实
  设备手工验收。

### F13｜标题栏管理所有词典档案（删除/修改/重新生成/多选）

现状：

- Agent AppBar 的历史按钮仍只提示 P6.7（`lib/features/agent/agent_page.dart:223-226`），
  没有档案管理页面/路由。
- `AgentStore` 已有 profile load/save/delete，但没有列表、批量删除、Markdown
  更新的公开方法（`lib/services/storage/agent_store.dart:172-228`）。

方案：

- 新增 `/agent-profiles`（“词典档案”）页面，Agent AppBar 增加独立入口（不要
  占用/伪装成历史按钮；历史仍在 P6.7）。
- 列表参考语料页的紧凑卡片，但把原图片区替换为**一行粗体词典标题**（16sp/600，
  同 MDict 管理界面的标题样式）；显示状态（已信任/已拒绝/待确认/已失效）、
  更新时间、词典是否仍可用。
- 操作：点击卡片进入 Markdown 编辑 sheet（复用熟悉期 sheet）；每项提供
  “修改 / 重新生成 / 删除”；多选模式支持全选、删除选中、批量重新生成。
- 数据层补 `listDictionaryProfiles()`、`deleteDictionaryProfiles(ids)`、
  `updateProfileMarkdown(id, markdown)`；修改保留原 fingerprint，重新生成使用
  `force: true` 并重新走用户确认（不能静默保存）。
- 重新生成需要已配置模型服务；无 provider 时给出中文提示；生成过程用 F2 的
  app 级档案服务/队列，不在页面里重新 new familiarizer。
- run 进行中允许查看，但禁用修改/删除/重新生成，避免改变正在使用的档案；run
  结束再操作。
- 多选删除/批量重新生成都要二次确认；删除只删应用私有 SQLite，不碰用户
  UniDic/MDict 目录。

验收：

- 标题栏可进入档案列表；能看到所有已存/已拒绝档案；单条修改后下次 run 使用
  新 Markdown；删除后下次重新熟悉；多选批量操作可用。
- 没有 provider 时“重新生成”有明确说明，不崩溃。

### F14｜结果操作行与用户气泡复制/修改

现状：

- AI 气泡没有底部操作行（当前 summary 后直接结束，
  `lib/features/agent/agent_message_widgets.dart:290-322`）。
- 没有结果 Markdown 导出、复制、重新生成、用户消息编辑。

方案：

- 在 AI 结果气泡最下方增加操作行，图标顺序固定：
  1. 循环图标：`重新生成结果`；
  2. 复制图标：复制完整结果为 Markdown。
  20dp 图标、40dp 触控、带 `Semantics`/tooltip；仅在完成（或可重试错误）时显示。
- 新增 `AgentResultMarkdownBuilder`：从结构化 `AgentRunResult` 生成 Markdown
  （原文、译文、逐句、词注、语法、多解释、未解决、按词典顺序的证据/依据编号），
  不包含隐藏 reasoning、原始 JSON、API Key、图片路径。复制后 toast 提示。
- 循环图标调用 `AgentRunController.regenerate()`：
  - 使用发送时的输入快照（文本/图片/词典/provider/模式/语言）；
  - 从**熟悉词典步骤**重新启动，已确认且指纹有效的档案复用，缺失/失效档案
    重新进入 F2 队列；如用户要强制重做全部档案，使用 F13 档案管理页的
    “重新生成”，结果操作行的循环不静默作废已确认档案；
  - 在新 run 完成前保留旧结果（至少本地可见），失败时不丢旧结果；
  - 新 runId，旧回调不能覆盖新结果。
- 长按用户气泡弹出底部菜单：`复制`（复制用户原文）和 `修改`。
  - 修改把文本填回 composer 并聚焦（图片保留，除非用户移除）；
  - 用户再次发送后从修改处重新开始，后续旧消息不再参与（当前只有单轮时清空
    旧结果；P6.7 有历史时截断该消息之后的消息）；
  - 不清空用户在编辑后新输入的草稿，除非发送成功。
- 结果操作行与用户气泡菜单都使用 F17 的语言表。

验收：

- 结果底部循环/复制顺序正确；复制内容是 Markdown 且无 raw JSON/reasoning。
- 长按用户气泡可复制/修改；修改发送后从该点重新开始，旧结果不覆盖新结果。
- 重新生成从熟悉词典步骤开始，且待确认档案按 F2 队列处理。

### F15｜词条内链接只查当前词条所在词典（非 Agent 修复）

现状：

- `EntryPage._openEntryLink` 只传 `word`（`lib/features/lookup/entry_page.dart:136-139`）；
- `lookupAndOpenEntry` 使用 `enabledDictionariesProvider` 和全局
  `appSettings.lookupMatchMode`（`lib/features/lookup/lookup_actions.dart:15-32,94-106`）。

方案：

- 扩展 `lookupAndOpenEntry` 参数：`required List<DictionaryInfo> dictionaries`、
  `LookupMatchMode matchMode = LookupMatchMode.exact`；词条内链接传当前 tab 的
  `DictionaryLookupGroup.dictionary`，并显式使用 `exact`。
- `EntryPage` 每个 tab 的 `onEntryLink` 闭包带上该 tab 的 group；不要用用户全局
  词典选择，也不要把全局匹配模式带进来。
- 完全匹配没有结果时提示“当前词典中未找到「X」”，不回退到其他词典/前缀模式
  （除非未来产品另行决定）；搜索页/阅读弹层继续使用各自全局偏好，不受影响。
- 测试：两个词典都收录目标词时，只查当前 tab 的词典；全局设置变化不影响链接。

### F16｜OCR 模型下载提升为应用级控制器（非 Agent 修复）

现状：

- `ModelPage` 用页面 State 保存 `_downloadCancel/_downloadProgress/_busySetId`
  （`lib/features/settings/model_page.dart:29-33,127-200`）。
- 离开页面后下载继续（`.part` 保留），但页面销毁后进度状态丢失；重新进入时
  只从磁盘状态显示，不知道正在下载及百分比（用户反馈）。

方案：

- 新增应用级 `ocrModelDownloadControllerProvider`（Riverpod Notifier）：
  - 状态按模型集：`idle/downloading/completed/failed/cancelled`；
  - 保存进度、错误、起止时间、当前文件名、取消令牌；
  - 提供 `start(set)`、`cancel(setId)`、`dismiss(setId)`；同一模型集不重复启动；
  - 控制器负责调用现有 `OcrModelManager.downloadSet` 和 mirror 设置；下载完成
    后通知模型状态刷新。
- `ModelPage` 不再持有下载 CancelToken/进度；每次进入订阅 controller，直接显示
  进行中的任务、百分比、取消按钮和完成/失败状态；离开页面不取消。
- 退出页面时的“同时停止下载”提示改为调用 controller.cancel；仅取消不删除
  `.part` 文件，保留续传。
- 注意：这是应用内页面切换的修复，不承诺进程被杀后继续；进程死亡仍只能靠
  `.part` 重新开始。
- 测试：controller 进度/取消/完成状态；widget 离开再进入仍显示下载中；下载
  完成刷新模型状态；非 Agent 代码只改下载状态所有权，不改模型下载内容/校验。

### F17｜本地 UI 文案跟随输出语言，禁用输入启发式

现状：

- `resolveAgentUiLanguage(setting, sourceText)` 在 `follow` 下按假名/拉丁推断，
  会把“输入日语、想翻成中文”的用户误判为日文 UI
  （`lib/services/agent/agent_messages.dart:7-29`）。
- Agent 页面/结果页仍有大量硬编码中文（如“严格模式”“查看诊断”“原文”“逐句理解”）。

方案：

- `AgentUiLanguage` 只由显式 `AgentResponseLanguage` 决定：
  - `zh → chinese`，`en → english`，`ja → japanese`；
  - 旧 `follow` → 中文（或从设置移除，见 F1）；**绝不读取输入文本**。
- 新增 `AgentUiStrings` 集中管理 Agent 功能区文案：AppBar、会话设置、词典选择、
  composer、阶段/进度/思考时间、错误卡、结果区标题、citation/证据、熟悉期 sheet、
  Agent 设置页按钮/说明。默认中文，en/ja 提供对应表。
- 控制器/orchestrator 的错误只传稳定 code/摘要；页面用语言表映射为用户文案，
  诊断细节仍折叠显示，不能把中文异常直接当 UI 文案。
- 范围限定为 Agent 功能区；主页/查词等应用外壳仍按应用语言，不在本项扩大为
  全局国际化。
- 测试：日语输入 + 中文设置时 Agent 阶段/按钮全中文；英文设置时同类文案英文；
  `resolveAgentUiLanguage` 不再接收 sourceText。

## 4. 数据结构与阶段增补（实施时同步契约）

```text
AgentRunStatus:
  ... awaitingProfile (F2), coverage (F7 可选) ...

AgentRunSnapshot 新字段:
  pendingProfileCount        // F2 文案/状态
  coverageFallbackUsed       // F7 防止二次回退
  coverageWarnings           // F7 非致命提示
  retainedResult?            // F14 重新生成期间保留旧结果

AgentLimits                  // 唯一上限来源，见 §2.1
AgentProfileProposal         // F2 队列项
AgentDictionaryPreferences   // F8 独立选择
AgentLanguageValidator       // F1 结果语言检查
AgentCoverageReview          // F7 覆盖审查结果
```

- `AgentStage.coverage`/`awaitingProfile` 必须进入状态映射、进度步骤和语言表。
- 不新增工具调用；F7 的缺失检查是 orchestrator 的一次结构化 LLM 调用，模型不能
  自行查词典。
- 不把图片、路径、base64、完整 HTML 发给 provider；F7 输入也只含清洗摘要。

## 5. 实施时序（按波次执行）

### Wave 0：文档与规范（本次）

- 新增本文档；同步生命周期、设计、契约、状态、设计 token、README/CLAUDE 的状态
  和链接。
- 不修改代码、不运行需要设备/API Key 的测试。

### Wave 1：低风险 UI/非 Agent 修正（已实现）

1. **F9** 3.5 行筛选条（共享 widget；先做，影响所有词典选择）。
2. **F10** Provider 中文化与预设 Base URL。
3. **F15** 词条内链接当前词典 + exact（非 Agent；最后跑查词回归）。
4. **F16** 应用级 OCR 下载控制器（非 Agent；不改下载校验）。
5. **F4** citation 短胶囊。
6. **F5** 去除 qN 标记。

验证：`flutter analyze` 无问题；完整 `flutter test` 213 passed；
`flutter build apk --debug` 成功。设备手工验收留到 Wave 4。

每项完成后 `flutter analyze`；本波结束跑 `flutter test`。

### Wave 2：Agent 状态、语言、生命周期（串行）

1. **F8** Agent 独立词典选择 provider（不读查词偏好）。
2. **F1a/F17** 默认中文、移除 follow 输入推断、Agent 文案表。
3. **F2** 应用级档案队列 + `awaitingProfile` gate + 页面返回恢复。
4. **F3** 离开/返回思考时间回归测试。
5. **F11** 相机/相册底部菜单 + 多图追加。
6. **F12** 图片全屏查看（复用 `PhotoViewerPage`）。
7. **F13** 词典档案管理页（列表/修改/删除/重新生成/多选）。
8. **F14** 结果操作行、Markdown 复制、用户气泡复制/修改、从熟悉步骤重新生成。

说明：F2 完成前不得推进 F7/F13/F14 的档案相关部分；F13 先于 F14 的循环重生成。

### Wave 3：检索完整度与结果语言

1. **F1b** 输出语言字段校验 + 一次语言修复（复用 repair；失败保留结果）。
2. **F6** `AgentLimits` + exact→prefix→suffix→incremental 递进。
3. **F7** `agent.coverage.v1` 覆盖审查 + 流程 A/B + 最多一次回退。
4. 补性能/取消/词典顺序测试；大词典 suffix/incremental 设备冒烟。

### Wave 4：回归与验收

- `flutter analyze`、完整 `flutter test`、`flutter build apk --debug`。
- x86_64 集成回归：MeCab/UniDic、MDict 查词/词条内链接、OCR 模型下载页。
- 手工设备场景：多图发送/点开、档案队列离页返回、思考时间、中文/英文文案、
  citation 换行、覆盖审查回退一次。
- 更新 `phase6-status.md` 和本文状态表；仍未验证的 arm64/真实 provider/secure
  storage 不能写成已通过。

## 6. 验收清单（按反馈逐项）

- [ ] F1 默认中文；日语输入不改变中文 UI/结果语言；设置英文时结果和 Agent 文案
      为英文；语言修复失败有可见警告。
- [ ] F2 离页期间生成继续；返回按队列处理；全部处理前不进入查词；不自动跳过。
- [ ] F3 离页 10 秒返回，思考时间包含离页区间；无第二次 provider 请求。
- [x] F4 依据为短胶囊、自动换行、颜色不变；触控目标仍需设备视觉/可点性验收。
- [x] F5 结果中无 `（q1）` 等内部标记，原文 quote 仍显示。
- [ ] F6 四种模式按 exact/prefix/suffix/incremental 递进；达全局上限或无新增
      即停止；上限来自 `AgentLimits`。
- [ ] F7 查词后有一次覆盖审查；未满/已满分别走流程 A/B；最多回退一次；重复条目
      删除前有本地重合校验。
- [ ] F8 Agent/查词词典选择双向隔离且各自持久化。
- [x] F9 所有词典筛选条第 4 行露出半行（共享 widget 测试）。
- [x] F10 表单无 Provider/Base URL/small/complex 英文；DeepSeek/Claude 自动填地址；
      自定义地址不被覆盖（preset 逻辑/表单测试）。
- [ ] F11 相机/相册底部菜单；多选/连续追加；上限可配。
- [ ] F12 用户气泡图片可点开全屏缩放。
- [ ] F13 标题栏档案管理；修改/删除/重新生成/多选/确认。
- [ ] F14 结果操作行循环→复制；Markdown 无 raw JSON/reasoning；用户气泡可复制/
      修改并从修改处重发。
- [x] F15 词条内链接只用当前词典 + exact + 首个结果；请求范围已有 unit 测试，
      设备词条跳转待验。
- [x] F16 下载状态提升为应用级 controller；进度/取消有 unit 测试，返回模型页
      仍显示进度待设备验收；取消仍保留 `.part`（原有下载测试）。
- [ ] F17 Agent 本地文案由显式输出语言决定，输入启发式已删除。

## 7. 风险与边界

1. **LLM 语言无法 100% 强制**：只能 prompt + 字段检测 + 一次修复 + 可见警告；
   不承诺绝对。若 provider 持续不遵守，用户可换模型/服务商。
2. **F6 的 suffix/incremental 成本**：大词典扫描必须复用 worker 缓存、设置上限、
   可取消；不能对 120 个目标无限循环。
3. **F7 可能引入噪声**：缺失 query 必须可追溯，重复删除必须本地验证；模型只能
   提议，citation/词典顺序仍由 orchestrator 掌握。
4. **F2 等待可能很久**：用户不回来时 run 停在待确认是预期行为；取消/重试仍可用。
   进程死亡后的队列恢复归 P6.7，当前不能声称已支持。
5. **F13 不是 P6.7 历史 UI**：只管理词典档案，不实现对话会话历史；不要顺手把
   P6.6/P6.7 标成已完成。
6. **F15/F16 是非 Agent 范围**：按用户明确要求修改，但不得改变查词选择全局偏好、
   MDict 查词语义、模型下载校验与 `.part` 续传。
7. **本次只改文档**：未运行完整测试/构建；实施时每个 Wave 必须重新跑 analyze/
   test/build，并按 `docs/dev-setup.md` 做设备集成测试。
