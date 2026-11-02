# P6.7 之后：任务级流式（Task-level Streaming）规划

> 状态：**规划中，尚未实现**。P6.7（annotation DSL、Markdown/ruby/pitch、会话历史
> 与发布打磨）完成并通过门禁后再启动；不要在当前 Wave 4 / P6.7 中提前改动
> Orchestrator 的流式协议。本文件是独立规划，不改变 `docs/project-rules.md` 的
> 隐私/Agent 边界，也不把未实现能力写成已支持。

## 1. 问题陈述

当前 Agent 是“整段生成、整段解析、整段校验、整段渲染”：

- 复杂模型的输出可能持续数十秒到数分钟；
- 网络中断时，Provider 侧不保留本次 Completion 的上下文；
- App 侧只保存最终结果，已生成但未通过最终校验的文本不会展示；
- 因此一次网络失败可能让用户等待很久后仍然一无所获。

任务级流式不是“把 JSON 边生成边塞给 UI”，而是把**已经闭合且通过局部校验的
标签块**尽早变成可见结果；未闭合、未校验或校验失败的块继续留在缓冲区。

## 2. 目标与非目标

### 目标

1. 译文优先：识别到闭合的 `[TRANSLATION]` 后尽早渲染，不必等待逐句解析。
2. 解析分段：以 `[SEGMENT]` 为单位切分模型输出，局部校验 citation、quote 和
   类型；通过后立即上屏。
3. 失败保留：网络中断或最终校验失败时，保留已经通过局部校验的内容，并明确
   标记“部分结果/非最终结果”。
4. 重试减负：缓存 OCR、UniDic、MDict 证据包，网络重试只重新请求 Provider。
5. 进度增强：等待期间展示分词高亮、已检索 citation 数、命中的词典名称。
6. 保持严格模式：任何未经校验的词典事实不得伪装成已验证事实。

### 非目标

- **不做断点续生成**：不尝试“刚才生成到一半，请接着写”。纯文本 Completion API
  无状态，续写容易重复、错位或引入未校验内容，性价比低。
- 不切换到 OpenAI Assistants/Threads 或其他服务端会话状态；不新增云端状态。
- 不把原始流式 JSON 或未闭合标签直接渲染给用户。
- 不把图片、图片路径、base64、API Key 或完整词典 HTML 放入流式缓存/事件。
- 不改变固定流水线、模型无工具、citation 由 Orchestrator 发放的边界。
- 不改变词典顺序、每会话词典选择或严格/宽松模式的语义。

## 3. 总体架构

```text
Provider SSE / text stream
        │
        ▼
StreamingAnalysisAssembler（新增，纯 Dart）
  ├─ 累积文本缓冲区
  ├─ 识别完整标签块（当前关注 TRANSLATION / SEGMENT / OPTION / UNRESOLVED）
  ├─ 块级标签完整性检查
  ├─ 块级解析 → 局部 AgentValidator
  └─ 产生 AgentStreamEvent
        │
        ▼
AgentRunController（应用级）
  ├─ 写入当前 run 的 partial result
  ├─ 处理 retry / cancel / evidence cache
  └─ 通知 UI
        │
        ▼
Agent UI
  ├─ 先渲染译文骨架
  ├─ 逐段追加已验证解析
  ├─ 失败块显示低置信/未验证（或隐藏，见 §5）
  └─ 最终完整结果到达后做一次对账，不重复插入
```

### 3.1 流式块协议

继续使用现有方括号标签协议，不新增 JSON：

```text
[TRANSLATION quote="q1"]译文[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]解释[/MEANING]
[WORD id="t1"]surface|reading|sense|source-1[/WORD]
[/SEGMENT]
```

- 只把**闭合块**送入解析；`[SEGMENT]` 未闭合时继续缓冲。
- `[TRANSLATION]` 是最高优先级块；闭合后先尝试局部校验并渲染。
- `[SEGMENT]` 内的 `[WORD]`/`[GRAMMAR]`/`[MEANING]` 必须随父块一起完整闭合后
  才校验，避免半段 citation 进入 UI。
- 文本标签无闭合时不允许“猜”结束位置；超时/取消时按失败处理。
- 覆盖率审查（`[COVERAGE]`）是独立的证据审查阶段，不进入任务级流式渲染；
  它仍是一次小模型结构化调用，完成后再进入分析流。

### 3.2 事件模型（建议）

```dart
sealed class AgentStreamEvent {}

class AgentTranslationReady extends AgentStreamEvent {
  final AgentTranslation translation;
  final AgentValidationResult validation;
}

class AgentSegmentReady extends AgentStreamEvent {
  final AgentSegment segment;
  final AgentValidationResult validation;
}

class AgentBlockRejected extends AgentStreamEvent {
  final String blockKind;
  final String reason;
  final String rawText; // 仅内存，不进入日志/导出
}

class AgentStreamCompleted extends AgentStreamEvent {
  final AgentAnalysis analysis;
  final AgentValidationResult validation;
}
```

事件只携带结构化结果和错误码；不携带 API Key、图片、文件路径或完整 HTTP body。

## 4. 局部解析与校验

### 4.1 复用现有组件

- 复用 `analysis_tag_parser.dart` 的字段解析规则和 `_cleanBody` 标记清理。
- 复用 `tag_block_integrity.dart` 的平衡/嵌套/重复标签检查。
- 复用 `AgentValidator` 的 citation/quote/严格模式规则，不另写一套宽松校验。
- 新增“块级校验入口”，把单块包装成最小 `AgentAnalysis` 后交给现有 validator；
  避免复制校验逻辑。

### 4.2 块级校验策略

| 块 | 校验 | 通过后 | 失败后 |
|---|---|---|---|
| `[TRANSLATION]` | quote id 存在；译文非空；citation 属于本次 run | 立即显示译文 | 不显示译文；记录原因，等待最终修复 |
| `[SEGMENT]` 词典事实 | citation 存在且属于本次 run；quote 匹配 | 立即显示逐句解析和依据 chip | 隐藏该段或标“未验证”，不冒充事实 |
| `[SEGMENT]` 结构分析 | token/pattern id 存在；UniDic 可用 | 显示结构分析及来源 | 隐藏结构结论 |
| `[OPTION]`/`[UNRESOLVED]` | citation/quote 校验 | 显示 | 隐藏或标“未验证” |
| `[SUPPLEMENT]` | 仅宽松模式显示 | 显示“模型补充” | 严格模式不显示 |

默认策略：

- **严格模式**：未通过局部校验的 claim 不展示为事实；可展示为“未验证”占位，
  并在最终结果中进入 `unresolved` 或错误提示。
- **宽松模式**：可展示但必须带“未验证/模型补充”标签，不能与词典事实混排。
- 任何块通过后仍要在最终完整结果到达时做一次对账；若最终校验推翻局部结论，
  以最终结果为准并更新 UI，不保留重复的旧块。

## 5. 失败、取消与重试

### 5.1 流中断

- 已通过局部校验的译文/段落保留在 `partialResult`；
- 当前未闭合块丢弃，不尝试补全；
- run 状态标记为 `partial`（或沿用 `error` + `partialResult` 标记，实施时在
  `AgentRunSnapshot`/契约中定稿）；
- UI 明确显示“结果未完成/网络中断”，不把部分结果标成最终结果。

### 5.2 取消

- 用户取消后立即停止流，不再发起新请求；
- 已通过局部校验的内容是否保留由用户可见语义决定：默认保留但标记“已取消”；
- 不把取消误报为 provider 失败。

### 5.3 重试与证据缓存

重试分为两种：

1. **网络重试**：Provider 请求失败、超时或流中断；如果输入、词典、UniDic、
   档案、模式均未变化，复用本次 run 的证据包，只重发 Provider 请求。
2. **重新分析**：用户修改输入、词典选择、模式、UniDic、档案或点击“重新生成”；
   证据缓存失效，重新执行 OCR/分词/查词。

建议缓存对象：

```text
AgentEvidenceCacheKey:
  sessionId + inputHash + dictionaryIds/order + unidicFingerprint
  + profileFingerprints + mode + limitsVersion

AgentEvidenceCacheValue:
  AgentInputEnvelope + AgentEvidenceBundle + source versions
```

- 缓存只存在内存，不写入磁盘/数据库/日志；
- 不缓存图片、路径、base64、API Key 或完整 HTML；
- 上限按 run 数/条目数/字节数设置，LRU 淘汰；
- 取消/进程死亡后缓存自然丢失，不做跨进程恢复；
- 缓存命中时仍要重新做最终 provider 校验，不能把旧结果直接当新结果。

## 6. UI 行为

### 6.1 骨架与顺序

```text
发送
  → 骨架：原文 + “正在生成译文…”
  → [TRANSLATION] 闭合：显示译文
  → 每个 [SEGMENT] 闭合并通过校验：追加逐句解析 + 依据 chip
  → 最终完整分析：对账、显示剩余部分、清除“生成中”
```

- 消息列表滚动位置仍由用户控制，不自动滚到底部（沿用当前规则）。
- 新块追加时避免整页重建；使用稳定的 segment id 作为 key。
- 最终结果到达时按 id 合并；已被最终结果替代的临时块不能重复显示。

### 6.2 失败块

- 失败块不直接显示原始模型文本；
- 显示“该段未通过依据校验”或黄色“低置信”占位，由用户决定是否展开；
- 不把失败块计入 citation 数量或“已检索”进度；
- 严格模式不得把失败块显示为词典事实。

### 6.3 进度增强

在现有阶段提示之外，增加低风险进度信息：

- 分词完成：显示“已分词 N 个词”或分词高亮预览（只读，不阻塞）；
- 查词中：显示“已检索 N / M 条依据”；
- 覆盖审查/补充查词：显示命中的词典名和新增依据数；
- 不显示完整证据正文、完整 HTML 或 provider 原始响应。

## 7. 契约与文档

- 标签协议保持不变；任务级流式只改变**消费方式**，不改变模型输出格式。
- `AgentStreamEvent`/partial result 需要新增到
  `docs/phase6-agent-contracts.md`，明确事件字段、错误码和最终对账规则。
- `AgentRunSnapshot` 需要增加 partial/stream 状态时，先更新
  `docs/agent_docs/agent-lifecycle-and-edge-cases.md`。
- `coverage` 审查不进入流式事件；它仍按现有阶段完成后才进入分析。
- 更新 `docs/design-tokens.md` 前先补流式骨架/低置信占位的 token。

## 8. 测试计划

### 8.1 解析器/组装器

- 标签被任意 chunk 边界切开（半开标签、半正文、半属性）仍能正确组装；
- 未闭合的 `[SEGMENT]` 不提前触发；
- 闭合后立刻产生事件；
- 未闭合/错序/重复标签产生 `AgentBlockRejected`；
- 流结束仍有未闭合块时按失败处理，不补全。

### 8.2 局部校验

- 合法 citation 的 segment 立即通过；
- 未知 citation/quote/pattern 的 segment 被拒绝；
- 严格模式下事实段无 citation 不显示为事实；
- 宽松模式补充必须带“模型补充”标签；
- 最终完整结果与 partial 块 id 冲突时以最终结果为准且不重复。

### 8.3 失败与重试

- 流中断保留已验证块，状态为 partial；
- 取消不发起新请求；
- evidence cache 命中时 OCR/分词/查词调用次数为 0；
- 输入/词典/模式变化后 cache miss；
- 缓存内容不包含图片/路径/Key/HTML（捕获对象断言）。

### 8.4 UI

- 译文先于 segments 显示；
- 失败块显示低置信/未验证，不显示模型原文；
- 用户滚动位置不被流式追加强制改变；
- 最终结果到达后无重复块/闪烁；
- 200% 字体和窄屏下不溢出。

## 9. 实施顺序（P6.7 之后）

1. **S1：StreamingAnalysisAssembler + 块级校验**（纯 Dart，先不接 UI）
   - 用现有标签协议和 validator 做单测；
   - 不改 Provider/Orchestrator 主流程。
2. **S2：Controller/UI 增量渲染**
   - `AgentStreamEvent` → snapshot → UI；
   - 先接译文和 segment，再接收 option/unresolved；
   - 最终对账与重复块清理。
3. **S3：证据缓存与网络重试**
   - 内存 LRU；只缓存 evidence/input/source versions；
   - 网络重试跳过本地证据步骤。
4. **S4：进度增强**
   - 分词/引用/词典名进度；
   - 不引入自动滚动。
5. **S5：失败恢复与设备验收**
   - 断流/取消/进程死亡/真实 provider/arm64；
   - 缓存命中与失效；
   - 大文本、多段、多词典性能。

## 10. 风险与对策

| 风险 | 对策 |
|---|---|
| 严格模式被局部流式“放松” | 未校验块不显示为事实；最终结果仍走完整 validator |
| 流式块与最终结果重复/冲突 | 以 segment/quote id 对账；最终结果覆盖 partial |
| 断流后用户误以为结果完整 | 明确 partial/未完成状态与错误提示 |
| 缓存导致旧证据复用 | key 包含输入、词典顺序、UniDic/档案指纹、模式、limits 版本 |
| 缓存隐私泄漏 | 只缓存内存中的结构化证据；禁止图片/路径/Key/HTML |
| 大段流式 UI 抖动 | 稳定 key、批量追加、限制重绘；不自动滚动 |
| Provider chunk 边界不稳定 | 组装器按完整标签块处理，不依赖 chunk 大小 |
| 断点续写造成重复/幻觉 | 明确非目标；只重试完整请求，不续写半截 |

## 11. 验收指标

- 译文首个可见时间明显早于完整分析完成时间（以设备/真实 provider 记录）；
- 100% 已显示的 citation 都属于本次 run 且通过 validator；
- 断流后已通过局部校验的内容可保留，且 UI 标记 partial；
- 网络重试不重复执行 OCR/分词/查词（缓存命中时调用次数为 0）；
- 最终结果与 partial 结果无重复 segment/citation；
- 所有自动化测试只用 fake provider；不把真实 API Key 写入测试或日志。

## 12. 与当前工作的关系

- 本规划不实现于当前 Wave 4 / P6.7；
- 当前先完成 P6.7 的 annotation/Markdown/历史与发布打磨；
- 任务级流式启动前，先完成 Wave 4 的设备/真实 provider/arm64 验收；
- 若 P6.7 后发现标签协议需要变更，应先更新
  `docs/phase6-agent-contracts.md` 和解析器测试，再进入 S1。
