# Phase 6 — 词典助手接口契约 v1

> **2026-10-31 实现决策**：当前为固定流水线、模型无工具。工具表（`ToolSpec`/
> `ToolResult`、`unidic.tokenize`、`mdict.lookup`、`mdict.suggest`、预算/可见性）
> 仅作为未来契约保留；`lib/services/agent/tools/` 已删除，模型请求不携带 tools。
>
> **2026-11-01 输出格式变更（已实现）**：分析和词典档案生成不再要求模型输出
> JSON。运行时使用方括号标签的纯文本块，代码用正则解析；模型不输出 confidence、
> 概率或 `context_inference`/`dictionary_fact` 等内部标记。旧 JSON 响应格式、
> 运行时 JSON schema、`response_format`/`json_schema` 能力标志和旧 JSON 输出
> 回退均已移除；分析/档案 DTO 仍可序列化为本地 JSON 供存储使用。覆盖审查也已
> 迁移到 `[COVERAGE]` 标签协议。所有 Agent prompt 统一维护在
> `lib/services/agent/agent_prompts.dart`，其他文件不得硬编码 prompt；旧的
> `analysis_prompts.dart`/`coverage_prompts.dart`/`familiarization_prompts.dart`
> 仅保留兼容 re-export，不是独立 prompt 源。解析器额外
> 校验标签块完整性（未闭合、错序、越界嵌套、重复单例标签）；格式或完整性失败时
> 只有一次“保持正文不变、仅补标签”的格式纠错调用。
>
> **2026-11-01 语言决策（Wave 2–3 已实现）**：默认输出/UI 语言为中文（`zh`）；
> 旧 `follow` 映射为 `zh`；禁止按输入假名/拉丁字符推断。§5.2 的默认/文案契约
> 与 F1b 结果字段语言后校验/一次修复均已落地。
>
> 规范性 MUST/MUST NOT 规则见 `docs/project-rules.md`；当前预算/上限和固定文案
> 见 `docs/project-data.md`。本文件只保留 Agent 字段、错误码、状态机和未来
> tool 契约，不重复规则正文或当前实现数值。

- 状态：**P6.1–P6.5 核心、Wave 1–3 与 P6.6 多 OCR 核心（含失败态入口与逐版本
  依据预览）已实现，P6.6 自动化收尾于 2026-11-03 完成；P6.7-1 历史/持久化与
  P6.7-2 UniDic 声调已于 2026-11-03 实现；P6.7 DSL/发布契约仍为设计；P6.6
  真机验收与 Wave 4 设备验收仍未完成**；
  与 `docs/phase6-agent-design.md` v2 配套。实现状态见 `docs/phase6-status.md`。
  **2026-10-31 实机反馈的 F1–F17 修正计划见
  `docs/agent_docs/device-feedback-2026-10-31.md`；Wave 1–3 已实现（应用级档案
  队列/语言默认与文案、F1b 语言后校验、F6 检索递进、F7 覆盖审查）；Wave 4
  设备验收仍未完成，不能把真实 provider/arm64/大词典冒烟写成已支持。**
- 目的：把 Agent 的工具、输入/输出、错误码、状态机和校验规则固定下来，避免实现时
  各自发明字段。机器可读 schema 在 `docs/schemas/agent/`。
- 版本规则：所有 schema 带 `schema` 常量（如 `rikai.agent.input.v1`）；破坏性字段
  变更升 v2。工具带 `version`（如 `1.0.0`）；prompt 带 `prompt_version`。词典档案
  同时记录 `profile_schema_version` 和 `prompt_version`，变化时失效重探。

## 1. 公共工具契约

### 1.1 ToolSpec / ToolResult

```dart
class ToolSpec {
  final String name;          // 'unidic.tokenize'
  final String version;       // '1.0.0'
  final String description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final ToolVisibility visibility; // modelVisible | orchestratorOnly
  final Duration timeout;
  final int maxCallsPerRun;
}

class ToolResult {
  final bool ok;
  final Map<String, Object?> data;
  final ToolError? error;
  final ToolProvenance provenance;
}
```

统一结果：

```json
{
  "ok": true,
  "data": {},
  "error": null,
  "provenance": {"tool": "mdict.lookup", "tool_call_id": "call_1", "elapsed_ms": 12}
}
```

错误：

```json
{
  "ok": false,
  "data": {},
  "error": {"code": "DICTIONARY_LOOKUP_FAILED", "message": "词典查询失败", "retryable": false},
  "provenance": {"tool": "mdict.lookup", "tool_call_id": "call_1", "elapsed_ms": 12}
}
```

- 模型可见工具只有 `unidic.tokenize`、`mdict.lookup`、`mdict.suggest`。
- `ocr.recognize`、`dictionary.sample`、`unidic.profile` 是 `orchestratorOnly`；
  模型不能传入图片路径，也不能自行触发 OCR/采样。
- 每次模型工具调用必须有 `tool_call_id`；最多 6 次额外调用，单工具 60s，单次运行
  额外工具总预算 90s。超限返回 `TOOL_BUDGET_EXCEEDED`，不静默丢弃。
- 所有 `data` 在进入模型前经 sanitizer：去 HTML、去 `file://`/`content://` 路径、
  去 base64、去 MDD/MDX 路径、去音频/图片引用、截断。单本词典失败不阻断其他词典。

### 1.2 错误码

| 错误码 | 含义 | 可重试 |
|---|---|---|
| `NOT_CONFIGURED` | Provider/UniDic/词典未配置 | 否 |
| `MODEL_MISSING` | 必需 OCR 模型缺失 | 否（需下载/导入） |
| `MODEL_INVALID` | 模型文件无效 | 否 |
| `DICTIONARY_NOT_READY` | 没有可用词典/词典未选中 | 否 |
| `DICTIONARY_LOOKUP_FAILED` | 词典查询失败 | 是（可重试一次） |
| `UNIDIC_NOT_READY` | UniDic 未配置/初始化失败 | 否 |
| `TOOL_TIMEOUT` | 工具超时 | 是 |
| `TOOL_CANCELLED` | 用户取消 | 否 |
| `TOOL_BUDGET_EXCEEDED` | 超过调用次数/时间预算 | 否 |
| `INVALID_ARGUMENTS` | schema/字段/越界参数 | 否 |
| `PROVIDER_AUTH_FAILED` | 401/403 | 否 |
| `PROVIDER_RATE_LIMITED` | 429 | 是（退避） |
| `PROVIDER_UNAVAILABLE` | 5xx/网络失败 | 是（最多 2 次） |
| `PROVIDER_EMPTY_OUTPUT` | 流式只返回 reasoning_content、正文为空 | 否（换模型/调整输出上限） |
| `PROVIDER_REFUSED` | 模型拒绝 | 否 |
| `VALIDATION_FAILED` | 模型输出未通过标签/引用/原文校验 | 视情况修复一次 |
| `INTERNAL_ERROR` | 未分类内部错误 | 否 |

原生异常、路径、堆栈、API Key 不得进入 `message`；`message` 使用中文用户可读文案。

## 2. 工具定义

### 2.1 `unidic.tokenize`

- 可见性：modelVisible
- 输入：

```json
{"text": "何卒宜しくお願い致します。"}
```

- 输出：

```json
{
  "tokens": [
    {
      "id": "t1",
      "surface": "何卒",
      "reading": "なにとぞ",
      "lemma": "何卒",
      "pos": "副詞",
      "pos1": "副詞",
      "pos2": "*",
      "pos3": "*",
      "pos4": "*",
      "c_type": "*",
      "c_form": "*",
      "goshu": "漢",
      "start": 0,
      "end": 2,
      "content": true,
      "lookup_candidates": ["何卒", "なにとぞ"]
    }
  ],
  "degraded": false
}
```

- 约束：`text` ≤ 20,000 UTF-16 字符；`start/end` 为 UTF-16 offset；UniDic 未配置
  返回 `UNIDIC_NOT_READY`；29 字段异常时 `degraded=true`，读音可为空。
- 错误：`UNIDIC_NOT_READY`、`TOOL_TIMEOUT`、`INVALID_ARGUMENTS`。

### 2.2 `mdict.lookup`

- 可见性：modelVisible
- 输入：

```json
{
  "query": "何卒",
  "candidates": ["何卒", "なにとぞ"],
  "dictionary_ids": ["dict_a", "dict_b"],
  "match_mode": "exact",
  "max_entries_per_dictionary": 3
}
```

- 输出：

```json
{
  "query": "何卒",
  "candidates": ["何卒", "なにとぞ"],
  "groups": [
    {
      "dictionary_id": "dict_a",
      "dictionary_title": "講談社 日本語大辞典",
      "dictionary_order": 0,
      "entries": [
        {
          "citation_id": "source-1",
          "entry_key": "何卒",
          "matched_key": "何卒",
          "headword": "何卒",
          "snippet": "なにとぞ。どうか。",
          "has_more": false
        }
      ],
      "suggestions": [],
      "error_code": null
    }
  ]
}
```

- 约束：
  - `dictionary_ids` 必须是本会话允许集合的子集；工具层再次校验，越界返回
    `INVALID_ARGUMENTS`。
  - 结果按 `dictionary_order` 排序，不能由模型重排。
  - `snippet` 经 HTML 清洗、去路径/资源、≤400 字符；不返回原始 HTML。
  - `entry_key` 是最终可导航词条（`headword`）；`matched_key` 仅追溯。
  - `citation_id` 由 `CitationRegistry` 发放；模型不能自造。
  - 单本词典失败写入 `error_code`，其他词典继续。
- 错误：`DICTIONARY_NOT_READY`、`DICTIONARY_LOOKUP_FAILED`、`INVALID_ARGUMENTS`。

### 2.3 `mdict.suggest`

- 可见性：modelVisible
- 输入：`{"prefix": "なに", "dictionary_ids": ["dict_a"], "limit": 10}`
- 输出：`{"suggestions": [{"text": "何卒", "dictionary_id": "dict_a"}]}`
- 约束：`limit` ≤ 20；只返回词形，不返回 HTML；用于补充查词和 OCR 修复。
- 错误：同 `mdict.lookup`。

### 2.4 `ocr.recognize`（orchestratorOnly）

- 可见性：orchestratorOnly；模型不可见，不能传入路径。
- 输入：`{"image_handle": "img-1", "mode": "auto"}`；可选增加
  `"engine": "paddle_v5"` 或 `"engine": "manga_ocr"`。
- 输出：`{"engine": "paddle_v5", "elapsed_ms": 1200, "confidence": 0.93, "text": "...", "blocks": [...]}`
- 约束：
  - `image_handle` 只在本机解析为私有路径；路径/文件名/base64 永不进入模型请求。
  - 必须先 `ensureReady`；省略 `engine` 时保持 Phase 4.5 的单引擎 best-of 语义。
  - `engine` 是本地可选约束：`paddle_v5` 或 `manga_ocr`。设置后原生侧必须返回该
    引擎，不能静默回落到另一个引擎；MangaOCR 只允许竖向组合。
  - 多版本由编排器按需多次调用 `ocr.recognize`，显式组合为
    `paddle_v5/horizontal`、`manga_ocr/vertical`、`paddle_v5/vertical`，再以
    `auto` 补足；不暴露给模型。
- 错误：`MODEL_MISSING`、`MODEL_INVALID`、`UNSUPPORTED_ENGINE`、
  `UNSUPPORTED_MODE`、`IMAGE_DECODE_FAILED`、`TOOL_TIMEOUT`、`TOOL_CANCELLED`、
  `INTERNAL_ERROR`。

### 2.5 `dictionary.sample`（orchestratorOnly）

- 可见性：orchestratorOnly。
- 输入：`{"dictionary_id": "dict_a", "max_entries": 12}`
- 输出：`{"dictionary_id": "...", "metadata": {...}, "samples": [...]}`
- 约束：有界探针；不遍历全词典；样本只含纯文本摘要/结构特征；不含路径/HTML。
- 错误：`DICTIONARY_NOT_READY`、`DICTIONARY_LOOKUP_FAILED`、`INVALID_ARGUMENTS`。

### 2.6 `unidic.profile`（orchestratorOnly）

- 可见性：orchestratorOnly。
- 输入：`{"sentences": ["これはテストです。", "..."]}`
- 输出：`{"feature_layout": 29, "observations": {...}, "samples": [...]}`
- 约束：只观察分词输出；不假装 UniDic 有词条查询接口；不含路径。
- 错误：`UNIDIC_NOT_READY`、`INVALID_ARGUMENTS`。

## 3. Agent 输入信封 `rikai.agent.input.v1`

完整 schema：`docs/schemas/agent/input.v1.schema.json`。

```json
{
  "schema": "rikai.agent.input.v1",
  "session_id": "sess-1",
  "mode": "strict",
  "user_text": "请解释这句话在语境中的意思",
  "context": "漫画第 3 页，两个人在争吵",
  "dictionaries": [
    {"id": "dict_a", "title": "講談社 日本語大辞典", "order": 0}
  ],
  "sources": [
    {
      "id": "src-1",
      "kind": "image_ocr",
      "image_id": "img-1",
      "selected_variant_id": "var-1",
      "variants": [
        {
          "id": "var-1",
          "engine": "paddle_v5",
          "mode": "auto",
          "text": "何卒宜しくお願い致します。",
          "confidence": 0.93,
          "elapsed_ms": 1200
        }
      ]
    },
    {"id": "src-2", "kind": "user_text", "text": "..."}
  ]
}
```

硬规则：

- 逻辑最小单元是 `{image_id, ocr_text}`；`sources[]/variants[]` 只是多图/多版本的
  结构化承载。
- `image_id` 是 opaque handle；禁止出现 `image_path`、`file_name`、`file://`、
  `content://`、`base64`、`data:image`、EXIF。
- 每张图片一个 `source`，`image_id` 与 OCR 文本一一对应；用户文本单独 `source`。
- `variants` 最多 4 个；`selected_variant_id` 必须指向其中一个。
- `dictionaries` 按 `order` 升序；只包含本会话选中的词典。

### 3.1 P6.6 本地 OCR 变体与修复契约（2026-11-02）

以下字段/对象只在本地内存和 UI 中使用，不改变 provider 输入信封：

```text
AgentImageInput (local)
  id, localPath, mode,
  variants: [AgentOcrVariant], selectedVariantId

AgentOcrVariant (serialized subset)
  id, engine, mode, text, confidence, elapsedMs
  origin: ocr | dictionary_repair   // local only, not serialized

OcrQuality (local)
  charCount, meaningfulChars (script-neutral), duplicateNoiseRatio,
  meanConfidence, dictionaryHitRate?, contentWords
  // No kana/kanji/Latin ratio is used for quality or ranking.

OcrTextDiff (local)
  baseSpans[], candidateSpans[]  // {text, start, end, changed}, UTF-16
  baseChangedChars, candidateChangedChars

OcrRepairSuggestion (local)
  original, start, end, candidates[
    {text, dictionaryIds, score}
  ]

OcrRepairSelection (local)
  suggestion, candidate  // at most one per suggestion/word

OcrVariantLookupPreview (local)
  hitCount, entries[{dictionaryId, dictionaryTitle, headword, snippet}]
  // max 3 entries per variant; snippet <=240 chars; never a formal citation
```

硬规则：

- 多版本识别只能由用户显式触发；默认 run 仍只用一个 `auto` 变体。
- 用户选择变体或采用词典候选后，必须重新执行分词/查词/分析；不能把旧结果的
  citation 直接套到新文本。
- 不自动合并版本、不静默替换原文；`dictionary_repair` 只在用户采用候选后生成
  新的本地变体。
- 修复候选 UI：未选灰色，选中浅蓝底/蓝字；同一 suggestion 最多选一个候选，
  不同 suggestion 可同时各选一个。至少一个选中时右下角的蓝色
  `FilledButton.tonal`“使用此版本重新分析”才启用；无选择时该按钮灰色禁用。
  该按钮与切换 OCR 版本时的同名按钮保持同一右下角大按钮样式。
- 应用多个选择时 `OcrConsensus.applyRepairs` 按 suggestion 起点从后往前替换，
  保持其余 UTF-16 offset 不变；重叠或越界选择被忽略，原 variant 不被修改。
- 质量评分、diff 和候选只在本机计算；不得把图片、路径、base64、完整 HTML 或
  API Key 放入这些对象或 provider 请求。
- `AgentRunResult.ocrQuality` 以 `image_id` 为键，仅用于本地 UI。
- 变体文本会进入 provider 的 `variants[]`；`origin` 不序列化。当前只把选中变体
  写入 `AgentSourceVersion`，所有变体的持久化留给 P6.7 历史工作。
- 版本组合按 `(engine, mode)` 唯一，最多 4 个（含选中版本）。显式对比的优先级为
  `paddle_v5/horizontal`、`manga_ocr/vertical`、`paddle_v5/vertical`、`auto`；
  同一引擎+朝向只保留一个结果。模型/朝向标签必须来自原生实际返回的 engine、
  不能把回落结果伪装成另一个模型。
- 差异高亮使用 `AgentTokens.diffHighlightSurface`/`diffHighlightText`；版本 chip
  左对齐并在 `Wrap` 中自动换行，所有状态固定同一高度并预留推荐图标槽位。
- 展开的详细解析按小块跨帧追加（`_ProgressiveResultBody`），每个词典依据组内的
  citation 行也使用同一分块器；只让前 `AgentFadeIn.maxAnimatedItems` 个块播放
  淡入。长结果不能在一帧内构建整棵结果树。

## 4. 证据包 `rikai.agent.evidence.v1`

完整 schema：`docs/schemas/agent/evidence.v1.schema.json`。

```json
{
  "schema": "rikai.agent.evidence.v1",
  "sources": [
    {
      "id": "src-1",
      "kind": "image_ocr",
      "text": "何卒宜しくお願い致します。",
      "tokens": [
        {
          "id": "t1",
          "surface": "何卒",
          "reading": "なにとぞ",
          "lemma": "何卒",
          "pos": "副詞",
          "start": 0,
          "end": 2,
          "content": true,
          "lookup_candidates": ["何卒", "なにとぞ"]
        }
      ]
    }
  ],
  "patterns": [
    {
      "id": "p1",
      "surface": "何卒",
      "token_ids": ["t1"],
      "start": 0,
      "end": 2,
      "citation_ids": ["source-1"]
    }
  ],
  "citations": [
    {
      "id": "source-1",
      "kind": "mdict",
      "dictionary_id": "dict_a",
      "dictionary_title": "講談社 日本語大辞典",
      "dictionary_order": 0,
      "entry_key": "何卒",
      "matched_key": "何卒",
      "headword": "何卒",
      "snippet": "なにとぞ。どうか。",
      "tool_call_id": "call_1"
    }
  ],
  "truncated": false,
  "budget": {
    "source_chars": 12,
    "unique_targets": 4,
    "citations": 1,
    "max_targets": 120,
    "max_citations": 60
  }
}
```

- 证据包只含清洗后的摘要；不含 HTML/路径/MDD/音频。
- 重复 token 只查一次，但保留所有 span；token ID 在 run 内唯一。
- `citations` 按 `dictionary_order` 排序。

## 5. 分析输出 `rikai.agent.analysis.v1`

> **2026-11-01 运行时格式**：模型输出下面的标签文本，不再输出 JSON。
> 解析器：`lib/services/agent/analysis_tag_parser.dart`。标签内的正文按目标语言
> 纯文本输出；`type` 只出现在标签属性中，前端根据 type 渲染推断类别和代码分配的
> 置信度（多个 OPTION 会归一化为总和 100%）。

```text
[TRANSLATION quote="q1"]translated text[/TRANSLATION]
[SEGMENT type="fact" quote="q1"]
[MEANING]interpretation[/MEANING]
[WORD id="t1"]surface|reading|sense|source-1,source-2[/WORD]
[GRAMMAR id="p1"]grammar explanation|source-1[/GRAMMAR]
[/SEGMENT]
[OPTION id="i1" label="A" citations="source-1"]alternative meaning[/OPTION]
[UNRESOLVED quote="q1"]reason[/UNRESOLVED]
[SUPPLEMENT]loose-mode commentary[/SUPPLEMENT]
```

- `type`：`fact` / `structure` / `inference` / `translation`。解析器也容忍旧内部名
  `dictionary_fact` / `structural_analysis` / `context_inference`。
- 置信度由解析器分配（fact 0.95、structure 0.9、inference 0.6、translation
  0.95；OPTION 先给 0.5/0.7 的相对权重），模型不输出数值。存在多个 OPTION 时，
  `normalizeAnalysis`/`salvageAnalysis` 用最大余数法把相对权重归一化为总和
  100% 的相对置信度（例如两个都标 0.7 的选项显示 50%/50%，三个显示
  34%/33%/33%）；单个 OPTION 保留启发式值。这样 2 个选项不会再显示
  70%+70%=140%，也不需要在 prompt 中要求模型输出概率。
- 解析器会剥离正文中泄漏的 `context_inference`/`dictionary_fact`/
  `structural_analysis`、`(90%)`、`置信度: …` 和 `[source-N]` 标记。
- 至少需要一条 TRANSLATION 和一条 SEGMENT。解析后还检查标签块完整性：未闭合、
  结束标签错序/多余、根级标签被嵌套、`MEANING`/`WORD`/`GRAMMAR` 不在 `SEGMENT`
  内、同一 `SEGMENT` 重复 `MEANING`。解析失败或完整性失败时发送一次格式纠错请求，
  要求保持所有正文文字不变、只补齐标签；修复后仍不完整则 validation 不通过并进入
  既有 salvage 路径。
- 旧的 JSON 输出回退已移除；模型必须返回标签文本。

以下 JSON 结构仅作为内部 DTO/存储结构，不是模型响应格式：

完整 schema：`docs/schemas/agent/analysis.v1.schema.json`。

```json
{
  "schema": "rikai.agent.analysis.v1",
  "source_id": "src-1",
  "translation": [
    {"quote_id": "q1", "text": "请多关照。", "label": "模型译文"}
  ],
  "segments": [
    {
      "id": "seg-1",
      "quote_id": "q1",
      "literal": "何卒宜しくお願い致します。",
      "interpretation": "用于正式请求对方关照的固定表达。",
      "word_notes": [
        {"token_id": "t1", "surface": "何卒", "reading": "なにとぞ",
         "sense": "请务必", "citation_ids": ["source-1"]}
      ],
      "grammar_notes": [
        {"pattern_id": "p1", "explanation": "お願い致します是谦让表达",
         "citation_ids": ["source-1"]}
      ],
      "epistemic": "dictionary_fact",
      "confidence": 0.86
    }
  ],
  "interpretations": [
    {"id": "i1", "label": "A", "meaning": "正式请求", "confidence": 0.8,
     "citation_ids": ["source-1"]}
  ],
  "unresolved": [
    {"quote_id": "q2", "reason": "词典中未找到依据"}
  ],
  "citations_used": ["source-1"],
  "model_supplements": [
    {"text": "也可用于商务邮件结尾。", "label": "模型补充"}
  ]
}
```

字段规则：

- `epistemic`：`dictionary_fact`、`structural_analysis`、`context_inference`、
  `translation`。严格模式校验规则见设计文档 §10。
- `quote_id` 必须来自编排器发放的 QuoteRef；`quote_text` 可选，但必须通过
  `analysis_text` 的 NFKC + 空白归一化 substring 校验。
- `literal` 由编排器填充，模型不得改写；如模型给出不同值，以 quote 文本为准。
- `citations_used` 仅作提示；编排器从各 claim 的 `citation_ids` 重新汇总。
- `model_supplements` 严格模式必须为空/隐藏；宽松模式必须带“模型补充”标签。
- `reading` 必须匹配 token 读音或 citation 摘要；否则标 `未验证` 或移除。

### 5.1 覆盖审查 `[COVERAGE]` 标签（DTO `rikai.agent.coverage.v1`；F7，Wave 3 已实现）

初始证据后调用一次，判断是否缺少词典资料。这是独立的轻量审查，不直接复用
较重的 `analysis.v1`；模型输出标签文本，不再输出 JSON。`source_id` 由解析器
使用本次主源 ID 填充，模型不写。解析器先执行 `coverageTagIntegrityErrors`：
COVERAGE 根块唯一、MISSING/DUPLICATE/NOTES 必须位于 COVERAGE 内、同一 COVERAGE
下 NOTES 唯一、标签必须闭合；解析或完整性失败只做一次格式修复。机器可读 DTO
结构见 `docs/schemas/agent/coverage.v1.schema.json`，仅作内部 DTO/序列化结构，
不是模型响应格式；当前代码没有 coverage JSON 的持久化调用，“存储结构”不能写成
已使用。

2026-11-02 稳定性修正（已实现）：

- 单个畸形 `MISSING`/`DUPLICATE` 项（未知 kind、`source-1` 形式 refs、priority
  越界等）只丢弃该项，不再让整份 review 失效并弹“覆盖审查不可用”；未知 kind
  映射到 word，priority 夹到 1–5，reason 截断到 500 字符。**每次自动修正或丢弃**
  （kind、refs、priority、reason 截断）都写入 debug 日志，包含项序号、原值和修正
  后值；`source-N` 映射到主 source 也记录原值，避免静默改写。
- `[COVERAGE verdict="sufficient"]` 缺少结束标签、写成自闭合或包在 Markdown
  fence 中时，解析器会先规范化；`verdict=sufficient` 下多余的 MISSING/DUPLICATE
  被忽略。修复请求使用**规范化后的文本**（规范化幂等），不会再次提交原始 wrapper
  错误。
- 覆盖审查输入改为紧凑投影（仅选中文本、token/pattern id、清洗 citation 摘要），
  不再发送完整 input envelope（含全部 variants）和完整 evidence JSON。token/
  pattern 的 start/end、citation 的 `entry_key`/`matched_key`/`headword` 与
  citation→token 的 `citation_ids` 保留；只去掉内部 `tool_call_id` 等编排字段。
- 覆盖审查使用**独立预算** `AgentLimits.coverageReviewMaxTokens`，由 MISSING 上限 ×
  （query/refs/reason/标签开销）+ duplicate 上限 × （dictionary/keys/reason/标签
  开销）+ 根块/NOTES + 安全边际计算，不跟随分析请求的 maxTokens。系数与各项开销
  常量统一在 `AgentLimits.coverage*`（`coverageCharsPerToken` 取 1.0，按 CJK 可能
  接近 1 UTF-16 单元/token 保守取值）；本契约不复制具体数值。仍只做一次修复；
  真实 provider 的 400/超时保留证据并产生 warning，debug 记录脱敏错误码/解析原因。

```text
[COVERAGE verdict="missing"]
[MISSING kind="usage" query="何卒" refs="t12,p3" priority="1"]缺少正式请求语境下的释义[/MISSING]
[DUPLICATE dictionary="dict_a" keep="何卒" remove="何卒（副）|何卒（別）"]词条相同且释义大部分重合[/DUPLICATE]
[NOTES]可选说明[/NOTES]
[/COVERAGE]
```

`verdict="sufficient"` 时返回：

```text
[COVERAGE verdict="sufficient"][/COVERAGE]
```

- `verdict`: `sufficient | missing`；`missing` 最多 20 项，`duplicate_groups`
  最多 10 组（来自 `AgentLimits`）。
- `MISSING` 的 `kind` 为 word/grammar/sense/usage/reading/example/context；
  `refs` 用逗号或 `|` 分隔，只能引用 source/tN/pN；`priority` 可选 1–5。
- `query` 必须可追溯到源文本/token surface/lemma/reading/lookupCandidates/
  语法模式/已有 citation key；不可追溯项由 orchestrator 丢弃，不能让模型任意
  浏览词典。当前 Agent 管线不使用 `suggest` 作为补查来源。
- 2026-11-06 复合词补查：未知 `kind=word` query 还必须满足——源文本连续子串、
  不含换行，且至少一处匹配覆盖 ≤ `AgentLimits.maxCoverageCompoundTokens`
  （默认 6）个 source token；无 tokenizer 或该 source 无 tokens 时只接受已知
  token/pattern/citation key。校验按 token 跨度，不设字符数上限；
  `AgentLimits.maxCoverageQueryChars` 仅作为超长字符串的全局安全上限。丢弃
  计入 `droppedMissing`。
- `DUPLICATE` 仅是建议；orchestrator 必须本地验证同词典、摘要大部分重合后才可
  删除，且保留信息密度较高（摘要更长）的条目。`keep`/`remove` entry key 只用于
  定位候选，不要求彼此完全相同（例如 `何卒` 与 `何卒（副）` 可因摘要高度重合成组）。
- 未达 citation 上限走流程 A（按 missing 补充检索，模式 exact→prefix→suffix→
  incremental，某模式无新增也继续下一个模式）；已达上限走流程 B（先删可验证
  重复腾槽位，再走流程 A）。
- 每个用户请求最多一次覆盖审查 + 一次回退；失败/无重复/无可追溯 query 时保留
  原证据并显示 warning，不让整次 run 失败。`AgentRunResult.warnings` 承载
  本地化 warning，`coverageFallbackUsed` 标记是否执行过补充检索。
- 2026-11-06 P0 自适应触发：只看内容词 citation 命中率，排除助词、标点、符号
  和纯功能词；命中率 `< AgentLimits.coverageContentHitRateThreshold`
  （默认 0.8）时才运行。删除“citation 达到全局上限强制审查”和固定
  `quote ≤ 2 && 文本 < 50 字符` 短路。
  `AgentLimits.adaptiveCoverageReview=false` 可强制每次都审查。
- 2026-11-03 去重：MISSING query 已被现有 citation 或带 citation_ids 的
  token/pattern 覆盖时跳过；重复 query 跳过。主证据采用 breadth-first
  （每个 target 每词典先 1 条）；depth 默认关闭，只在显式多义/coverage 补查时
  按需获取。Coverage MISSING 的 `sense`/`usage`/`example` 类允许补充查词每本
  词典取 2 条；`word`/`grammar`/`reading` 类仍只取 1 条。
- 运行时输出为标签文本（`stream:false`，不发 `response_format`/
  `json_schema`）；解析或标签块完整性失败只做一次“正文不变、只补标签”的格式
  修复。模型返回的 coverage 建议必须经过本地可追溯性/重复校验，不能直接删除或
  查询任意词条。

### 5.2 输出语言（2026-10-31 F1；默认/文案 Wave 2、F1b Wave 3 已实现）

- `AgentResponseLanguage` 默认 `zh`；旧 `follow` 迁移为 `zh`，不得按输入假名/
  拉丁字符推断语言。**已实现**。
- system prompt 要求所有人类可读字段使用目标语言；源语言形式仅用于原文 quote、
  词形、读音、词典例句，以及紧邻 `[YOMI]` 发音标注的表面形。RUBY/YOMI 是语言
  无关的发音标注，不限定书写系统。**已实现**；`AgentUiStrings` 同步 Agent 本地
  文案。
- 结果后校验只检查人类可读字段（translation/segments interpretation/word
  sense/grammar explanation/unresolved reason/model supplement），不检查原文
  与 citation 摘要。偏离目标语言时允许一次语言修复；仍偏离则保留结果并显示
  warning，不得丢弃已生成内容。API 无法保证 100% 语言一致，契约不承诺绝对。
  **F1b 已实现**：`AgentLanguageValidator` + `LANGUAGE CORRECTION TASK` 单次
  修复；校验字段为 translation/segment interpretation/word sense/grammar
  explanation/option meaning/unresolved reason/model supplement，不检查 quote、
  词形、读音和 citation 摘要。仍偏离时在 `AgentRunResult.warnings` 写入本地化
  警告，结果保留。

### 5.3 富文本后处理标签（2026-11-03 增量实现）

结果生成后，可选一次轻量模型后处理，只允许插入显示标签：

```text
[RUBY=reading]base[/RUBY]
[BOLD]短文本[/BOLD]
[UNDERLINE]短文本[/UNDERLINE]
```

结果生成模型可在 `[MEANING]` 的解释文字中，把读音直接写在日语词之后：

```text
word[YOMI]reading[/YOMI]
```

YOMI 内容是**不带括号**的读音；单词与读音相同（例如假名词）时只写单词，不输出
YOMI。模型应输出 YOMI；结果构建时本地把 YOMI 和读数
`reading【surface】`（例如 `すき【好き】`）一律转成 RUBY，预览首帧即可见，
不等待后处理模型。禁止模型同时输出 RUBY 与 `reading【surface】`。普通括号
`（...）` 是解释性文字，不是读音，不转换。本地生成的词典事实注释
（`agentSegmentNotesSource`）也使用同一格式；旧数据中的 `reading【surface】`
仍由本地转换兼容。
**标签优先**：结果模型用 `[YOMI]`、格式化模型用
`[RUBY]`/`[BOLD]`/`[UNDERLINE]`、可能理解用 `[OPTION]` 的
`label`/`confidence` 结构化字段；`reading【surface】` 只是纯显示/导出与本地
兜底形式，不是新的模型主协议。UI 不从 `A：...（70%）` 等自由文本反解标签。

AI 气泡摘要（`[TRANSLATION]`）用本地 `localReadingsToRuby` 渲染 RUBY，但不参与
模型 BOLD/UNDERLINE 后处理；RUBY/BOLD/UNDERLINE 的模型格式化只用于详细解析的
“原文”、逐句理解和词典事实解释（词义/语法，不含 citation snippet）。原文注音由后处理 AI 生成，不读取
UniDic 读音表，避免多读音误判；后处理 Prompt 明确要求只标注能从词形和上下文
确定的读音。

- 标签必须成对且正确嵌套：RUBY 可以位于 BOLD/UNDERLINE 内，BOLD/UNDERLINE
  也可以相互包裹；BOLD/UNDERLINE 不得进入 RUBY 的 `base`，同一标签不得嵌套
  自身。RUBY 的 `base` 必须是原文连续文本。RUBY 是语言无关的发音标注，不限定
  书写系统，但不能包含标签或换行。
- 当 base 末尾已经带有与 RUBY 读音相同的 `【reading】`，或 `[/RUBY]` 后（即使
  中间夹着 `[/BOLD]`/`[/UNDERLINE]`）紧邻同一读音时，显示只保留一份读音：
  base 内的重复读数会被隐藏，`[/RUBY]` 后、强调标签外的重复 `reading【surface】`
  会被本地转换删除；`richTextToPlain` 输出 `reading【base】` 供 Markdown 纯文本
  复制。RUBY 位于 BOLD 内时读音随 base 一起加粗；任何 RUBY 读音都不加下划线
  （即使位于 UNDERLINE 内）。RUBY base 使用与周围正文相同的行高/metrics，以其
  alphabetic baseline 对齐，读音在其上方，不把 base 下沉。
- **标签感知的读数转换（2026-11-03 追加）**：模型可能输出
  `[BOLD]reading[/BOLD]【surface】`（或反向 `[BOLD]surface[/BOLD]【reading】`）。
  本地转换必须把读音移入仍打开的强调 span：
  `[BOLD][RUBY=reading]surface[/RUBY][/BOLD]`，使读音继承粗体；不能留下
  `[BOLD]surface[/BOLD]【reading】` 的非粗体读数。括号在强调 span 内时同样转
  RUBY；UNDERLINE 同理（RUBY 读音本身仍不加下划线）。普通括号 `（...）` 是
  解释性文字，永远不转换。
- UNDERLINE 不使用 `TextStyle.decoration`（其位置依赖字体/字形 metrics，全角
  `；` 与汉字会落在不同高度），而由 `_UnderlineSpanWidget` 在 alphabetic
  baseline 下方固定偏移处绘制；汉字、标点和 RUBY base 使用同一条基线相对线。
- 富文本后处理模型不得修改、删除或增加原文任何字符（含标点/空格/换行），只允许
  在字符之间插入 `[RUBY]`/`[BOLD]`/`[UNDERLINE]`。输入中的 YOMI 块按原文保留；
  prompt 要求不得新增、删除、改写、移动或嵌套 YOMI。代码端仍兼容“整块删除
  YOMI 并替换为等价 RUBY”的旧输出，但不再要求模型做此转换。prompt 明确要求：
  源文本已有 `reading【surface】`（或反向 `surface【reading】`）时整段替换为
  `[RUBY=reading]surface[/RUBY]`，不得保留括号，也不得同时输出 RUBY 和
  `reading【surface】`；这是“不得改动原文字符”规则的唯一例外（base 字符仍不得
  变化）。普通括号 `（...）` 不是读音，prompt 要求不转换。单词位于
  BOLD/UNDERLINE 内时 RUBY 必须放在同一强调 span 内，不能先关闭强调再写
  `reading【surface】`。prompt 见 `agent_prompts.dart` 的
  `buildRichTextPostProcessRequest` / `buildDetailedRubyPostProcessRequest`。
- **结果构建时的本地显示基线（2026-11-03 追加）**：provisional、正常和 salvage
  结果在 `_buildResult` 中先用 `localReadingsToRuby` 填充 `richOriginalText`/
  `richSegmentTexts`/`richSegmentNotes`：YOMI 和 `reading【surface】`/阅读括号都
  转成 RUBY，标签感知（`[BOLD]reading[/BOLD]【surface】` 会变成
  `[BOLD][RUBY=reading]surface[/RUBY][/BOLD]`）。因此用户看到结果预览时已经有
  RUBY，不必等待 `onRichTextReady`。模型格式化只追加 BOLD/UNDERLINE；某个
  section 被拒绝或返回空时，`copyWithRichText` 保留本地 RUBY 基线，不退化为
  括号纯文本。
- 代码端必须先用 `stripRichTextTags` 剥离显示标签，并按 YOMI 规则比较：
  删除的 YOMI 块允许消失；保留的 YOMI 块必须内容不变、位置不变。**比较前会先去除
  YOMI 内容中的全角/半角标点符号**，因此 `（いま）` 与 `いま` 视为同一读音注记。
  `reading【surface】` 与 `[RUBY=reading]surface[/RUBY]` 也视为同一显示形式：
  比较前本地归一化，base 字符仍需逐字符一致；普通括号（解释性文字）不转换。
  标签感知转换发生在比较两侧，因此 `[BOLD]reading[/BOLD]【surface】` 的候选输出
  不会被误判为 `text_changed`。随后与原文逐字符严格比较；只有完全相等才采用。
  任何差异、未闭合/错误嵌套标签、改写/移动 YOMI、空输出或 provider 失败都丢弃
  该后处理 section，保留本地 RUBY 基线，不影响核心结果。
- 模型输出的 `[RUBY=内容]` 也会先清洗内容中的全角/半角标点符号，再作为最终
  RUBY 读音；清洗后为空或等于 base 时移除该 RUBY，只保留 base 文本。
- 每个 RUBY 的读音不得与被标注 base 完全相同（如 `[RUBY=reading]reading[/RUBY]`）；
  这类冗余 RUBY 会被移除，保留 base 文本。
- 结构化结果在显示前把保留的 YOMI 块和 `reading【surface】` 本地转成 RUBY
  （不再把 YOMI 直接剥离成括号）；Markdown 复制/导出仍通过
  `richTextToPlain` 输出 `reading【surface】`，不会把标签原文泄漏到 UI 或
  Markdown。
- 当前渲染范围：AI 气泡摘要使用 `AgentRichText` 渲染本地 RUBY（不加载模型
  BOLD/UNDERLINE）；详细解析的“原文”使用
  `AgentRunResult.richOriginalText`（整个 section 一个结果，不是每个 quote 一个
  字段），逐句理解使用 `AgentRunResult.richSegmentTexts`（与 segments 对齐），
  词典事实中的词义/语法解释使用 `AgentRunResult.richSegmentNotes`（与 segments
  对齐，不包含 citation snippet）。三者都由 `AgentRichText` 渲染，并在结果
  构建时预填本地 RUBY；AI 气泡摘要、逐句引用行、无 pitch 数据的词注/语法注、
  可能的理解、未解决原因和模型补充也通过 `localReadingsToRuby` 显示 RUBY，
  而不是括号；citation snippet 仍是词典原文，不转换。可能的理解按 `[OPTION]`
  的 `label`/`confidence` 结构化字段渲染为正文下方的“情况X”绿色胶囊 +
  “可能性N%”文本，不把 `A：...（70%）` 拼进正文。若所有情况的可见 citation
  集合相同，citation chip 只在最后一个情况下方渲染一次（与其他板块统一）；
  集合不同时保留逐情况 chip，避免把依据错配到另一个解释。
  `buildAgentResultMarkdown` 使用 `richTextToPlain` 把 RUBY 转为
  `reading【base】` 并移除 BOLD/UNDERLINE/YOMI 标签，复制结果不带标签。失败
  不回退 run，也不写用户可见错误。
- 标签只用于本地 Flutter 富文本渲染，不执行 HTML/JS/Markdown，不进入 provider
  请求、日志、导出或持久化。
- 2026-11-03 性能/稳定性增量：输出预算按输入长度计算，不再固定 4000。
  App 控制器通过 `onRichTextReady` 在 `done`
  之后回填富文本，核心结果不再等待格式化；同步调用方（测试/直接调用）仍可等待
  最终结果。2026-11-03 起不再在调用模型前预注入 RUBY：模型输入保留结果模型
  原始文本及 `word[YOMI]reading[/YOMI]`，只做显示标签插入；prompt 也不再要求
  “保留已有 RUBY”“不要原样返回”“把 YOMI 转成 RUBY”。本地
  `localReadingsToRuby` 在结果构建时始终执行（预览首帧即 RUBY），模型
  `onRichTextReady` 只负责后续 BOLD/UNDERLINE；provider/校验失败、模型保留
  YOMI/`reading【surface】` 或某个 section 被拒绝时，同一本地转换兜底，不会
  退回括号纯文本。
  该调整的前提检查（当前 `docs/agent_output` 回归样本的读音/依据覆盖 9/9，
  =100%）见 `docs/phase6-status.md`。salvage 路径（校验失败但仍有可显示内容）
  也执行同一格式化，不再因为提前 return 而让用户只看到读数；debug 日志
  `[AgentValidation]`/`[AgentSalvage]` 记录失败原因，`[AgentRichText]` 的
  `tags`/`ruby`/`bold`/`underline`/`local_only` 区分“本地 RUBY”“模型确实加了
  强调”和“只是原样返回”。
- **2026-11-04 批量与独立降级**：原文 + 逐句理解合并为一次
  `buildBatchedRichTextPostProcessRequest`，使用
  `<<<RIKAI_SECTION id>>>` / `<<<RIKAI_END id>>>` marker；词注/词典事实解释
  不再发给格式化模型，继续由本地 `localReadingsToRuby` 渲染。响应按 section
  逐个解析、逐个执行 YOMI/标签/`reading【surface】` 归一化/逐字符 diff；某个
  marker 缺失或某个 section 的 diff 失败时只降级该 section，不得整批回退。
  只有 provider 错误、空响应、批量响应完全缺失 marker 或总字符超过
  `AgentLimits.maxRichTextChars` 才允许整批本地回退。见 `T-137`、
  `R-AGENT-LIMITS-001`。
- 该后处理是 P7 任务解耦的增量原型（见
  `docs/agent_docs/p7-task-decomposition-plan.md`）；完整任务拆分/模型路由/
  并发流式仍待 P7。
- P6.7 声调不使用富文本标签，也不由 AI 生成；只在词注/词典事实行由本地
  `PitchAccentText` 渲染 UniDic 数据，详见 §14.2。

### 5.4 输出上限与 NO_ANALYSIS（2026-11-04 实现）

- **硬上限**：SEGMENT 40、每 quote 每 type 1 段、OPTION 8、每段
  WORD/GRAMMAR 20。parser 超限时截断并设置 `AgentAnalysis.truncated=true`；
  即使模型继续输出，超出部分不得进入结果。
- **显式警告**：`truncated=true` 必须在 UI（`AgentRunResult.warnings`，由
  `agentAnalysisTruncatedWarning` 生成）和 Markdown 导出
  （`strings.analysisTruncated`）中出现；禁止静默丢弃。规则见
  `R-AGENT-LIMITS-001`。
- **`[NO_ANALYSIS]`**：唯一合法的零结果路径，格式为
  `[NO_ANALYSIS reason="short reason"]`（兼容
  `[NO_ANALYSIS]reason[/NO_ANALYSIS]`）。只能单独出现，不能与
  TRANSLATION/SEGMENT/OPTION/UNRESOLVED/SUPPLEMENT 共存；validator 接受
  “零翻译零段落”，UI 显示“无法可靠分析”+原因+证据；语言后校验包含该
  reason。乱码 OCR 不得被硬翻译成看似合理的译文。
- `AgentAnalysis` 新增 `no_analysis_reason`、`truncated`；历史 JSON 向后兼容
  （缺省为空/false）。

## 6. 词典档案 `rikai.dictionary.profile.v1`

> **2026-11-01 运行时格式**：模型输出 `[PROFILE]...[/PROFILE]` 扁平标签块
> （`lib/services/agent/familiarization/dictionary_profile_tag_parser.dart`）：
> `[ID]`/`[TITLE]`/`[KIND]`/`[INTRO]`/`[LANGUAGES]`/`[HEADWORD_FIELDS]`/
> `[DEFINITION_FIELDS]`/`[FLAGS]`/`[EXACT_FORMS]`/`[PREFIX]`/`[SEARCH_NOTES]`/
> `[STRENGTHS]`/`[CAVEATS]`/`[RECOMMENDED]`/`[ENTRY_NOTES]`。列表使用 `|`。
> 解析失败、缺少某本词典或标签块完整性校验失败时，发送一次保持正文不变、仅补
> 标签的格式纠错请求；修复后仍不完整时保留可解析档案并记录 warning。以下 JSON
> 结构仅作为内部存储/DTO，不是模型响应格式；旧 JSON 输出回退已移除。

完整 schema：`docs/schemas/agent/dictionary-profile.v1.schema.json`。

```json
{
  "schema": "rikai.dictionary.profile.v1",
  "dictionary_id": "dict_a",
  "title": "講談社 日本語大辞典",
  "kind": "国語辞典",
  "intro": "国語辞典。語義と用例が充実した中級向けの辞典。",
  "languages": ["ja", "zh"],
  "language_pairs": [
    {"source": "ja", "target": "ja", "confidence": 0.85}
  ],
  "coverage": {
    "sample_entries": 20,
    "entry_count": 120000,
    "headword_scripts": ["han", "hiragana", "katakana"],
    "definition_scripts": ["han", "hiragana"],
    "feature_count": 3,
    "sample_truncated": true,
    "unsampled_probe_count": 6
  },
  "entry_structure": {
    "headword_fields": ["見出し", "読み"],
    "definition_fields": ["語義", "用例"],
    "has_ruby": true,
    "has_kanji_info": false,
    "has_examples": true,
    "has_audio": false,
    "has_images": true,
    "notes": "HTML 表格为主，含少量 MDD 图片。"
  },
  "search_behavior": {
    "exact_forms": ["漢字", "かな", "活用形"],
    "prefix_suggestions": true,
    "notes": "片假名查询需转平假名候选。"
  },
  "strengths": ["多义项", "例句丰富"],
  "caveats": ["部分条目含图片，需要查看完整词条"],
  "recommended_query_forms": ["lemma", "orthBase", "kana"],
  "confidence": 0.85,
  "schema_version": 1
}
```

- 档案只保存结构与短样例；不保存大段原文/HTML/路径。
- `intro` 是模型生成的一句简介；`language_pairs` 和 `coverage` 由本地样本
  分析（`dictionary_sample_analysis.dart`）确定，模型不输出数值/置信度。
  方向性语言对优先使用标题脚本提示和样本文字脚本；模型 `[LANGUAGES]` 只作
  低置信度回退，不额外发请求。无 tokenizer/无法判断时语言对可为空。
- 采样截断：`DictionarySample` 的本地字段 `truncated`/`unsampled_probes`
  记录因 `maxEntries` 上限未执行的检查；`DictionaryCoverage` 只持久化
  `sample_truncated`/`unsampled_probe_count`。这些字段用于本地告警，不进入
  profile 模型 prompt；截断时档案 Markdown、档案卡片和 familiarization
  warnings 必须显示**用户可读**的提示（“另有 N 项检查未覆盖（不影响基本使用）”），
  不能静默丢弃；内部仍使用 probe 术语。
- 词表覆盖（`word_list_coverage.dart`）是语义场景覆盖，不是 POS 覆盖率；
  不新增 POS schema/指标。
- 用户可编辑 Markdown 摘要；该 Markdown 是 prompt 的权威版本，JSON 作为结构备份。
- **语言对修正**：确认/编辑 sheet 允许用户增删 `language_pairs`；保存时同时更新
  `DictionaryProfile.languagePairs`、`profile_json` 与 Markdown 的“语言”行，
  `ProfileConfirmation.profile` 把修正后的 profile 传给 inbox/manager 持久化。
  后续 prompt 使用修正后的 Markdown；指纹不因人工修正而变化。
- profile prompt 版本已升到 2（新增 INTRO/本地分析字段）；旧档案通过指纹失效后
  重新生成，JSON schema 标识仍为 v1（新字段可选，旧 JSON 可读）。
- 指纹：`dictionary_id + mdx size/mtime + entryCount + encoding +
  profile_schema_version + prompt_version`；`model_id` 只作元数据。

## 7. Citation 与 Quote

### 7.1 Citation

```json
{
  "id": "source-1",
  "kind": "mdict",
  "dictionary_id": "dict_a",
  "dictionary_title": "講談社 日本語大辞典",
  "dictionary_order": 0,
  "entry_key": "何卒",
  "matched_key": "何卒",
  "headword": "何卒",
  "snippet": "なにとぞ。どうか。",
  "tool_call_id": "call_1"
}
```

### 7.2 Quote

完整 schema：`docs/schemas/agent/quote.v1.schema.json`。

```json
{
  "schema": "rikai.agent.quote.v1",
  "id": "q1",
  "source_id": "src-1",
  "start": 0,
  "end": 12,
  "text": "何卒宜しくお願い致します。",
  "origin": "ocr"
}
```

- `origin`：`ocr` | `user_text` | `user_edit` | `dictionary_repair`。
- offset 为 UTF-16；`text` 必须与 `source` 的 `[start,end)` 一致。
- citation 与 quote 分开：citation 指向词典事实，quote 指向原文。

## 8. 状态机

```text
idle
  → prepare
  → ocr
  → familiarizing（只读本地已确认/已拒绝档案）
  → tokenizing
  → evidence
  → coverage（一次覆盖审查，可选补充检索）
  → reasoning
  → validating
  → formatting（可选富文本后处理；失败保留本地 RUBY 基线）
  → done | error | cancelled
```

- 2026-11-06 P0 起 `familiarizing` **不阻塞**：缺失档案在当前 run 使用
  `noProfileInstruction`，分析结束后后台生成并进入应用级待确认队列；Agent 页
  不自动弹 sheet（只显示待处理数量），档案管理页显式确认。确认/“不再询问”后
  保存并在**下次 run** 生效；未确认的同一档案不会重复生成。`awaitingProfile`
  保留为历史/兼容状态，不再是正常首跑路径。页面离开、重建或 dismiss sheet 不得
  自动 skip；`unavailable` 档案无确认内容，记录 issue 后不阻塞。队列属于应用级
  controller，不属于 `AgentPage`。**Wave 2 已实现，P0 改为非阻塞**
- 2026-11-06 P0 全局 Run Deadline：`AgentLimits.runDeadlineSeconds` 默认 30
  （0/负数禁用）。controller 超时取消 provider/OCR，状态为可恢复的
  `TOOL_TIMEOUT`，保留 current provisional/retained result；done/error/cancel/
  newSession 清理计时器。直接调用 orchestrator 的测试/集成不经过该计时器。
  （`AgentProfileInboxController` + `DictionaryFamiliarizationService.generateMany`）。
- 确认窗口的“不再询问”= 保存当前档案并开启 `agent_profiles_auto_accept`；
  默认关闭。开启后新生成的档案直接保存并信任，Agent 设置可再次关闭。确认窗口
  由 `AgentProfileInboxHost` 统一呈现：Agent 页、档案管理页和 Agent 设置页共用，
  同一 proposal 不会重复弹出。手动或自动保存成功时，只要上述任一宿主仍在，
  由宿主用底部 toast 提示一次（同一批只提示一次）。档案重新生成由应用级
  `AgentProfileRegenerationController` 持有：离开页面不会丢失；不同词典可并行，
  同一词典在请求完成前不会重复发起；进度文本列出当前全部活动词典并随新增/
  完成实时更新。生成期间编辑/删除仍可用，仅目标词典的“重新生成”禁用。
- `coverage` 是 2026-10-31 F7 的一次性覆盖审查（Wave 3 已实现）；每个请求最多
  触发一次补充检索，`coverageFallbackUsed=true` 后不得再次回退。审查失败、
  schema 无效、query 不可追溯或没有可验证重复时保留原证据并显示 warning。
- `formatting` 是 2026-11-03 的 P7.0 增量：对已校验的详细结果追加
  BOLD/UNDERLINE。结果构建时已经预填本地 RUBY，因此 `formatting` 不是读音
  可见性的前提；标签剥离 diff 失败、provider 失败或输出为空时保留本地 RUBY
  基线（强调标签不生效），不回退成括号纯文本，不改变 run 成功状态，也不产生
  用户可见错误。App 控制器通过 `onRichTextReady` 接收结果，因此 `done` 可先于
  格式化完成；同步调用方仍会在 `formatting` 阶段等待最终结果。
- 异步 formatting 通过 `onRichTextFormattingChanged(true/false)` 驱动
  `AgentRunSnapshot.richTextFormatting`。为 true 时 Agent 页在会话上方显示可
  关闭的绿色“界面美化正在进行中…”横幅；完成、失败或取消后回调 false，横幅
  自动消失。关闭横幅只隐藏当前 run 的提示，不取消 formatting，也不改变结果。
- `validating` 期间，首个可展示分析（parse/validate 后；必要时用本地 salvage）
  必须立即通过 `onProvisionalResult` 交给 UI，不得等待 format/language repair 或
  `formatting` 完成。UI 显示“结果已出，正在复核…”，`done` 时用最终结果替换。
  修复请求仍属于 `validating` 阶段，不把状态回退为 `reasoning`。
- 任何阶段可取消；取消后状态为 `cancelled`，保留已完成的本地结果。
- 阶段事件带 `run_id, stage, message, progress`；UI 不从页面 State 推断。
- 重试从失败阶段开始；OCR 可重新识别，provider 可重试，校验失败可做一次修复。

## 9. 预算默认值

当前实现/计划中的源文本、target、citation、每词典条数、摘要、profile、Provider
超时/重试、图片与覆盖审查 missing/duplicate 上限统一见 `docs/project-data.md` §8。
本契约不复制这些数字；代码/测试读取 `AgentLimits`/请求级 policy，文档引用
project-data。覆盖审查的**输出 token 预算**不是独立配置项，而是由
`AgentLimits.coverageReviewMaxTokens` 按上述上限和 `AgentLimits.coverage*` 常量
派生；具体系数/开销只在该类维护。

历史 tool loop 预算（6 次/单工具 60s/总 90s）仅作未来契约参考，不是当前实现。
超预算时设置 `truncated=true`，UI 显示“已按预算缩减，未分析的部分不会出现在结果
中”；不得静默截断长文本。

## 10. 校验规则（伪代码）

```text
validate(analysis, evidence, quotes, mode):
  if analysis.no_analysis_reason non-empty:
      assert translation/segments/interpretations/supplements are empty
      return ValidationResult(valid=true, used_citations=[])
  assert parse_tagged_analysis(raw) != null
  assert tag_blocks_complete(raw)
  known = {c.id for c in evidence.citations}
  used = {}
  for claim in all_claims(analysis):
      for id in claim.citation_ids:
          assert id in known
          used.add(id)
      if mode == strict:
          if claim.epistemic in {dictionary_fact, structural_analysis}:
              assert claim.citation_ids non-empty
          if claim.epistemic == context_inference:
              assert claim.citation_ids non-empty or claim in analysis.unresolved
          assert claim.model_supplement is empty
  if mode == strict:
      for note in all word_notes:
          assert note.citation_ids non-empty
      for option in analysis.interpretations:
          assert option.citation_ids non-empty
      for segment in analysis.segments:
          if segment.epistemic == dictionary_fact:
              for grammar in segment.grammar_notes:
                  assert grammar.citation_ids non-empty
  for segment in analysis.segments:
      quote = quotes[segment.quote_id]
      assert quote.text == source_text[quote.start:quote.end]
      assert segment.literal == quote.text (or recompute)
  for note in word_notes:
      if note.reading:
          assert note.reading in {token.reading, citation snippet}
  assert citations_sorted_by_dictionary_order(evidence.citations)
  return ValidationResult(used_citations=used, errors=[...])
```

- 严格模式拒绝无依据事实；不静默删除用户可见内容。**WORD/OPTION 的 citation
  要求写在 prompt 中**（无 citation 时省略该 WORD/OPTION 并改用 UNRESOLVED）；
  `dictionary_fact` 段中的 GRAMMAR 同样需要 citation。validator 与 prompt 必须
  同时维护。
- 2026-11-06 citation 归属：WORD note 的每个 citation 必须属于该 token 的
  `citation_ids`；GRAMMAR note 的每个 citation 必须属于该 pattern 的
  `citation_ids` 或其组成 token 的 `citation_ids`，否则校验失败。repair prompt 的
  `Available ids` 以 `token/pattern ... citations ...` 形式携带该映射，修复时不重发
  evidence。EvidenceBuilder 的 breadth/depth 与 coverage 补充检索按 target/query
  序号轮转词典起点，避免第一本词典独占全局 citation 预算；选中词典最终 0 条
  citation（且无查询错误）时写入 `AgentRunResult.warnings`。
- 修复：一次格式修复调用，使用 **small model + 紧凑 prompt**：只发送
  `availableIds`（quote/token/pattern/citation id 列表）、previous output
  （untrusted）和 validation errors（untrusted），不重发 input/evidence/
  dictionary profiles；`maxTokens` 按 `rawOutput.length + margin` 计算。语言修复
  使用 complex model + 紧凑 prompt（previous output + mismatched fields），同样
  不重发完整 evidence。仍失败则返回部分结果 + 可见错误。
- 分析请求的 `maxTokens` 统一引用 `AgentLimits.analysisMaxTokens`（当前 12,000，
  仅 Anthropic 发送；OpenAI-compatible 由 provider 配置决定）。

## 11. Provider 请求契约

- 当前 `LlmRequest` 含 `model`、`messages`、`maxTokens`、`stream`；**不含
  `responseFormat`、`tools`**。输出格式由 system prompt 的标签协议约束。若未来
  恢复 tool loop，才增加 tools/tool_result 契约。
- 发送前本地校验（`provider_payload.dart`）：model 去空白后非空；丢弃空白
  message；至少保留一条非 system 消息；Anthropic 合并连续同 role 消息。任一条件
  不满足时抛 `INVALID_ARGUMENTS`，不发 HTTP 请求。
- `LlmRequest` 仍带 `maxTokens`，但发送策略按 provider 不同：
  - **OpenAI-compatible 默认不发送 `max_tokens`**。不同服务/模型对隐藏 reasoning
    是否计入预算没有统一语义；固定 12,000 曾导致推理模型只输出
    `reasoning_content`、正文为空。由服务端/模型默认输出上限决定。
  - 可选的 provider 级 `maxOutputTokens`（持久化在 `capabilities_json` 的
    `max_output_tokens`；0=未设置）：大于 0 时作为该服务的 `max_tokens` 发送，
    OpenAI-compatible 与 Anthropic 都适用。
  - **Anthropic 必须发送 `max_tokens`**：优先使用 provider 的
    `maxOutputTokens`，否则使用请求构造器的值（分析 12,000）。
  - 本地仍校验请求 `maxTokens` 为正整数；HTTP 400 由 provider 的真实 error body
    分类：上下文超限、输出参数不支持、reasoning/tool 参数不兼容、通用参数无效。
    debug 只记录请求 shape（model/message 数/roles/prompt 字符数/max_tokens
    是否存在/stream），不记录正文或 Key。
- 流式收到 reasoning_content 但没有任何正文时，抛 `PROVIDER_EMPTY_OUTPUT`，
  **不再重复一次非流式请求**；只有真正空流（无 reasoning、无正文）才回退到
  非流式。日志记录 SSE 事件数、text/reasoning 字符数和 `finish_reason`。
- **流式中断续传（2026-11-06）**：`_collect` 在 `done` 前收到可重试错误
  （`PROVIDER_UNAVAILABLE`/`PROVIDER_RATE_LIMITED`/`TOOL_TIMEOUT`）时，最多追加
  `AgentLimits.streamReconnectAttempts`
  （默认 2）次请求。已有 partial 时取最后一个 `\n` 之前的安全前缀，作为
  `assistant` 消息附在原 `messages` 后，再追加固定 user 指令
  (`streamContinuationInstruction`) 要求从断点继续、不重复、保持标签格式；没有
  安全前缀则重发原请求。取消、鉴权、参数/上下文错误不重试。最终输出 =
  安全前缀 + 续写；仍失败时保留 partial 交给原错误/校验/抢救路径。续传请求仍受
  同一 `assertNoImagePayload` 与消息校验约束，不新增图片/路径字段。
- `LlmMessage.content` 只有 `LlmTextPart`；**没有 image/file 类型**。
- 发送前 `assertNoImagePayload`：递归检查 JSON 键/值，禁止
  `image`、`image_url`、`input_image`、`base64`、`data:image`、`file://`、
  `content://`、`.jpg/.png/.webp/.heic` 路径。
- Anthropic：`x-api-key` + `anthropic-version: 2026-10-21`；
  `POST /v1/messages`；不发送 `temperature/top_p/top_k`。
- OpenAI-compatible：`Authorization: Bearer`；`POST /chat/completions`；不发送
  `max_tokens`、`temperature`、`top_p`、`top_k`。
- 两种 provider 都不发送 `response_format`、`json_schema` 或 `output_config`；
  模型输出由标签协议和解析器校验。
- 测试捕获实际 HTTP body，断言不含图片/路径/Key；请求日志只记录
  `tool`、`model`、`elapsed_ms`、token 数，不记录 body/Key。

## 12. Dart 模型与文件映射

| 契约 | Dart 文件（实施时创建） |
|---|---|
| `input.v1` | `lib/core/models/agent/agent_input.dart` |
| `evidence.v1` | `lib/core/models/agent/agent_evidence.dart` |
| `analysis.v1` | `lib/core/models/agent/agent_analysis.dart` |
| `dictionary-profile.v1` | `lib/core/models/agent/agent_profile.dart`（`AgentDictionaryProfile`） |
| `tool-result.v1` | future-only；当前无 ToolResult DTO，`agent_tool.dart` 仅保留错误码 |
| `quote.v1` | `lib/core/models/agent/agent_quote.dart` |
| Ports | `lib/services/agent/ports/` |
| Tool registry/adapters | 2026-10-31 已删除；仅作未来契约参考 |
| Orchestrator | `lib/services/agent/agent_orchestrator.dart` |
| Validator | `lib/services/agent/agent_validator.dart` |
| Citation registry | `lib/services/agent/citation_registry.dart` |
| Store | `lib/services/storage/agent_store.dart` |
| Secret | `lib/services/security/secret_store.dart` |
| `history-entry.v1` / `history-result.v1` | `lib/core/models/agent/agent_history.dart`（P6.7，已实现） |
| 历史 UI | `lib/features/agent/agent_history_page.dart`、`agent_history_detail_page.dart`（P6.7，已实现） |
| 历史仓储 | `lib/services/storage/agent_history_store.dart`、`lib/state/agent_history_recorder.dart`（P6.7，已实现） |
| 档案队列持久化 | `lib/services/storage/agent_profile_inbox_store.dart`（P6.7，已实现） |
| `pitch.v1` | `lib/core/models/agent/agent_pitch.dart`、`lib/services/mecab/unidic_accent_parser.dart`（P6.7，已实现） |
| 声调 UI | `lib/features/agent/agent_pitch_accent.dart`（P6.7，已实现） |
| `annotation.rules.v1` | `lib/services/agent/annotation/`（P6.7，待建） |

## 13. 测试夹具

- `test/fixtures/agent/input_basic.json`
- `test/fixtures/agent/evidence_basic.json`
- `test/fixtures/agent/analysis_strict.json`
- `test/fixtures/agent/analysis_loose.json`
- `test/fixtures/agent/profile_basic.json`
- `test/fixtures/agent/tool_result_error.json`
- Fake provider 捕获请求体；断言无图片/路径/Key。
- 真实 MDict/UniDic 设备测试复用现有 integration_test 的 `--dart-define` 方式。
- P6.7 测试：历史 codec/store/recorder/UI、DB v2→v3 迁移、profile inbox 持久化、
  UniDic 声调真实样例与本地-only 请求体断言已实现；annotation DSL 夹具/测试仍
  待建。

## 14. P6.7 契约（2026-11-03）

> §14.1 历史/持久化、§14.2 UniDic 声调与 §14.6 P6.6 遗留（失败态入口/逐版本
> 依据预览）已实现并有自动化测试；§14.3 annotation DSL、§14.4 的受限 Markdown
> 预览、§14.5 provider 测试连接仍待实现。与 `docs/phase6-agent-design.md`
> §17.2 配套；Wave 4 由另一工作流继续。

### 14.1 历史与持久化

#### 14.1.1 历史条目 `rikai.agent.history-entry.v1`

```json
{
  "schema": "rikai.agent.history-entry.v1",
  "run_id": "run-1760000000000000-1",
  "session_id": "session-1760000000000000",
  "title": "何卒宜しくお願い致します。",
  "status": "done",
  "mode": "strict",
  "provider_label": "DeepSeek",
  "small_model": "deepseek-chat",
  "complex_model": "deepseek-reasoner",
  "started_at": 1760000000000,
  "finished_at": 1760000005000,
  "image_count": 1,
  "has_result": true,
  "error_code": ""
}
```

- 一条 = 一次 run（一次分析），不是多轮会话。列表按 `finished_at`/`started_at`
  倒序。
- `status` 只允许 `done`、`error`、`cancelled`、`interrupted`。运行中的 run 不
  出现在历史列表，直到完成、失败、取消或启动扫描标记中断。
- `title` 取用户文本首行（截断）；只有图片时用“图片分析”。不把 provider/
  citation 文本当标题。
- **不存在** `image_path`、`thumbnail`、`local_path`、`file_name`、`base64`
  字段。`image_count` 只是整数。

#### 14.1.2 历史详情 `rikai.agent.history-result.v1`

```json
{
  "schema": "rikai.agent.history-result.v1",
  "run_id": "run-...",
  "user_text": "何卒宜しくお願い致します。",
  "result": { "...": "AgentRunResult.toJson()" },
  "source_versions": [ "...": "AgentSourceVersion JSON" ],
  "citations": [ "...": "AgentCitation JSON" ],
  "ocr_quality": { "img-1": { "...": "OcrQuality JSON" } },
  "warnings": []
}
```

- `result` 必须包含 `AgentRunResult` 的全部字段：input/evidence/quotes/analysis/
  validation/sources/dictionaryProfiles/profileWarnings/unavailableProfiles/
  warnings/coverageFallbackUsed/ocrQuality/richOriginalText/richSegmentTexts/
  richSegmentNotes/telemetry。`telemetry` 只含调用数、字符数、耗时和 citation
  计数，不含正文、路径、Key 或 provider body。
- `AgentRunSnapshot` **不整对象入库**；只持久化安全的 run 元数据（status/mode/
  provider label/models/timestamps/error_code）。`sentImagePaths`、页面状态、
  取消 token、profile 回调、provider 原始 body 一律不存。
- `AgentSourceVersion` 的 `image_id` 是不透明 id；历史详情按它分组显示变体，
  但不得还原为文件路径。`source_versions` 保存所有变体文本和 `selected` 标记。
- `error_detail` 不入库；只存 sanitized `error_message`/`error_code`，避免 provider
  原始响应或 Key 进入历史。
- 未知 `schema` 版本：显示“历史格式不兼容，无法渲染”的只读空态，保留原始行，
  不崩溃、不尝试猜测解析。

#### 14.1.3 DB v3 迁移

`rikai_agent.db` 从 v2 升到 v3；`onCreate` 直接建新列，`onUpgrade` 对 v2 逐列
`ALTER TABLE`：

| 表 | 新增列 | 说明 |
|---|---|---|
| `agent_runs` | `user_text TEXT NOT NULL DEFAULT ''` | 历史详情/纯文本重试 |
| `agent_runs` | `image_count INTEGER NOT NULL DEFAULT 0` | 只计数，不存路径 |
| `agent_runs` | `result_json TEXT NOT NULL DEFAULT ''` | `history-result` JSON |
| `agent_runs` | `result_schema_version INTEGER NOT NULL DEFAULT 0` | 版本化解析 |
| `agent_runs` | `updated_at INTEGER` | 列表/中断扫描 |
| `agent_source_versions` | `selected INTEGER NOT NULL DEFAULT 0` | 当时选中的变体 |
| `agent_source_versions` | `variant_order INTEGER NOT NULL DEFAULT 0` | 稳定显示顺序 |
| `annotation_rule_sets` | `builtin INTEGER NOT NULL DEFAULT 1` | 内置/用户来源 |
| `annotation_rule_sets` | `schema_version INTEGER NOT NULL DEFAULT 1` | DSL schema |

新增档案队列表（待确认提案，确认前不写 `dictionary_profiles`）：

```text
agent_profile_inbox(
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  dictionary_id TEXT NOT NULL,
  title TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  draft_json TEXT NOT NULL,
  markdown TEXT NOT NULL,
  status TEXT NOT NULL,          -- pending | save | skip_once | decline
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
```

- 启动时加载 `pending` 提案；用户保存/跳过/拒绝后才删除或写入对应 profile。
- 进程重启后仍显示“待处理档案 N 个”；dismiss 只保留 pending，不自动 skip。

#### 14.1.4 启动中断、删除与 citation

- 启动扫描 `status IN ('preparing','ocr','familiarizing','awaiting_profile',
  'tokenizing','reasoning','validating')` 的 run，统一更新为 `interrupted`，
  写 `finished_at=now`、`updated_at=now`；不自动续跑、不重复请求 provider。
- 删除单条或多选：按 run_id 删除 `agent_runs`、`agent_messages`、
  `agent_tool_calls`、`agent_source_versions`、`agent_citations`；若 session 无
  其他 run，删除 `agent_sessions`。多选在一个事务内级联删除；全选后删除等价于
  清空 Agent 历史，但同样必须二次确认，且不删语料/词典档案/provider/Key。
- 历史 citation 点击：按 `dictionary_id + entry_key` 精确查；失败再试
  `matched_key`；仍失败只显示保存的 `snippet`，不打开任意词条。查询必须使用
  当前词典注册表，但不得改变历史中保存的词典顺序。
- 图片 run 的 `interrupted` 详情只显示 OCR 文本/变体，不显示原图；重试只允许
  纯文本 run。

#### 14.1.5 测试

- `history-entry`/`history-result` codec round-trip；未知 schema 降级。
- DB v2→v3 迁移；`onCreate` 与迁移后的列一致。
- 启动扫描 running→interrupted；不自动调用 provider。
- 删除单条/多选/清空级联；session 清理；多选 id 去重。
- 历史 JSON、日志、导出断言不含图片路径/字节/base64/Key/provider body。
- citation 精确回查、matched_key 回退、词典缺失只显示 snippet。
- profile inbox 持久化、dismiss 不 skip、全部处理后才进入查词。

### 14.2 声调 `rikai.agent.pitch.v1`

#### 14.2.1 Token 字段

UniDic 2025.12 真实输出已验证：

| 索引 | 名称 | 用途 |
|---|---|---|
| 24 | `aType` | 单词アクセント型；整数 0..moraCount |
| 25 | `aConType` | アクセント連接型（如 `C1`/`C3`）；P6.7 不使用 |
| 26 | `aModType` | アクセント修飾型（多为 `*`）；P6.7 不使用 |

`Token` 增加：

```dart
final String accentTypeRaw;   // features[24] ?? ''
final String accentConType;   // features[25] ?? ''
final String accentModType;   // features[26] ?? ''
final AgentPitchAccent? pitchAccent;
```

- 只有 `hasStandardLayout`（29 字段）时才解析；否则 `pitchAccent = null`。
- `aType` 必须是十进制整数；`*`、空、负值、非数字、`N > moraCount` 均为无效。
- `aConType`/`aModType` 保留原始值供调试/未来复合词使用，不进入 provider。

#### 14.2.2 `AgentPitchAccent`

```json
{
  "schema": "rikai.agent.pitch.v1",
  "source": "unidic",
  "accent_type": 2,
  "mora_count": 2,
  "mora_pattern": "LH"
}
```

- `source` 只能是 `unidic`；禁止 `ai`/`guess`/`inferred`。
- `mora_count` 由 `Token.reading` 拆分：小写ゃゅょ/ぁぃぅぇぉ并入前一 mora；
  `っ`、`ん`、`ー` 各算一个 mora；无法拆分则为 0 -> `null`。
- `mora_pattern` 使用 `L`/`H`，长度等于 `mora_count`：
  - `N=0`：`L` + `H` × (moraCount-1)；
  - `N=1`：`H` + `L` × (moraCount-1)；
  - `N>=2`：`L` + `H` × (N-1) + `L` × (moraCount-N)；
  - `N==moraCount` 时最后一段没有 `L`。
- 真实样例（用于测试夹具）：橋=2(LH)、箸=1(HL)、端=0(LH)、東京=0(LHHH)、
  日本=3(LHHL)、食べる=2(LHL)、花=2(LH)、雨=1(HL)、飴=0(LH)、今日=1(HL)。

#### 14.2.3 渲染契约

- `AgentPitchAccentText` 只在逐句理解下方的词注/词典事实行显示；不得用于 AI
  气泡、原文引用、逐句解释正文、证据卡片、citation snippet、Markdown 导出。
- 视觉：词上方 1.5dp 高低线；高段上轨、低段下轨，アクセント核处垂直下降；
  线宽按词宽均分为 mora 段，不按汉字字数逐字对齐。颜色 `textSecondary`。若该词
  有 RUBY/读音，纵向顺序固定为声调线 → RUBY 读音 → 词形，声调线在 RUBY 上方。
  声调线只作为 Ruby 上方的覆盖层，不改变现有 Ruby 布局/行高。
- 音调词行最前显示红色“音调信息”徽标（与 epistemic 徽标同尺寸；浅红底 +
  `error` 字），后接音调词；徽标只作本地说明，不进入 provider 请求、日志、
  citation 或导出。
- 200% 字号：线宽/偏移随文字缩放；空间不足时换行或省略声调线，不得覆盖文字/
  读音/下划线；不得缩小到不可读。
- 无 `pitchAccent`、读音为空、词形与 token 不匹配时按普通文本渲染；不显示
  “推测”“未知”占位，不用 AI 补。**汉字词没有独立振假名/读音时不画线**：
  `surface` 含汉字且 `reading` 为空或等于 `surface` 时，读音可能不唯一
  （多音词），不得显示该单词的声调线；纯假名词不受此限制。
- 复制/导出只输出 `reading【surface】`，不输出高低线/数字。
- 声调是本地数据，不进入 provider 请求、日志、citation、历史 JSON 的 provider
  payload（历史 result 可保留 `Token` 证据中的原始 accent 字段，但不得重发给
  模型）。

#### 14.2.4 测试

- `Token.fromFeatures` 对 24–26 字段的映射；29 字段缺失/非标准布局 -> null。
- 真实样例 10 个词的 mora_pattern。
- 非整数/越界/空读音/小写拗音/促音/长音边界。
- 只在词注/词典事实行渲染；AI 气泡/原文/逐句不出现声调线。
- 音调词行显示“音调信息”徽标；没有可显示音调词时不出现空徽标。
- 请求体断言无 pitch/声调字段；复制/导出无高低线。

### 14.3 标注 DSL `rikai.annotation.rules.v1`

#### 14.3.1 规则集

```json
{
  "schema": "rikai.annotation.rules.v1",
  "id": "builtin-reader-basic",
  "name": "基础注音",
  "version": 1,
  "targets": ["reader", "photo", "corpus"],
  "rules": [
    {"type": "ruby", "when": {"pos1": ["名詞", "動詞", "形容詞"]}},
    {"type": "pitch", "when": {"hasPitch": true}},
    {"type": "bold", "when": {"pos1": ["動詞"]}}
  ]
}
```

- `targets` 只允许 `reader`、`photo`、`corpus`；P6.7 不允许 `agent`。
- `version` 为单调递增整数；同一 target 只有一个启用版本。
- 规则节点白名单：`text`、`ruby`、`pitch`、`bold`、`underline`、`group`、
  `when`。`when` 只允许对 token 字段做相等/包含判断（`pos1`–`pos4`、`lemma`、
  `surface`、`hasReading`、`hasPitch`、`target`）。
- 禁止：函数调用、循环、递归、变量赋值、任意表达式、HTML、JavaScript、URL、
  `http(s)://`、`file://`、`data:`、图片、iframe、style、事件属性、外部链接。
- 边界：最多 64 条规则、嵌套 8 层、单目标 10,000 输出字符、每 token 最多 2 个
  标注；超限整份拒绝，不部分应用。

#### 14.3.2 求值与存储

- 求值器为纯 Dart、确定性、无网络/文件/模型调用；只使用本地 token/UniDic 数据。
- 同一 target 的预览和正式渲染必须调用同一求值器；预览不得使用另一套模板。
- `annotation_rule_sets` 保存 `id/name/version/rules_json/enabled/builtin/
  schema_version/updated_at`；切换/回滚写新版本，不覆盖历史。
- 规则集无效、求值异常或超限：保留上一个有效版本，显示可读错误；阅读器/照片集/
  语料不得空白或崩溃。
- P6.7 只提供内置规则集的选择/启用/预览/回滚，不开放自由文本或 JSON 编辑器；
  后续用户编辑器必须复用同一 AST/求值器。
- Agent 结果 P6.7 不接入；未来接入时不得新增 HTML/Markdown 渲染路径。

#### 14.3.3 测试

- schema/节点白名单/边界拒绝；HTML/JS/URL/图片/链接注入不生效。
- 同一规则集预览与正式渲染逐字一致；版本切换/回滚可复现。
- 无效规则集不覆盖上一个有效版本；不崩溃。
- Agent 结果路径不经过 DSL（P6.7）。

### 14.4 Markdown 使用边界

- 模型 wire format 为方括号标签；主结果由结构化 DTO/Flutter 组件渲染，**不是**
  Markdown。
- Markdown 只允许：
  1. `buildAgentResultMarkdown` 复制/导出；RUBY 转 `reading【base】`，剥离
     BOLD/UNDERLINE/YOMI，不输出标签；
  2. 用户可编辑词典档案的受限预览。
- 受限预览白名单：段落、标题、列表、粗体/斜体、行内代码；禁止 HTML、JS、图片、
  外部链接、自动 URL、iframe、style、事件属性；未知语法按纯文本；长度有界。
- 不引入通用 Markdown 渲染依赖；不把自由文本字段默认当 Markdown。
- 测试：导出无标签；预览注入 `<script>`/`<img>`/`http://`/`javascript:` 不执行、
  不加载、不自动链接；未知语法原样显示。

### 14.5 Provider 测试连接

```json
{
  "schema": "rikai.agent.provider-test.v1",
  "ok": true,
  "latency_ms": 128,
  "model": "deepseek-chat",
  "error_code": ""
}
```

- 只在用户显式点击时运行；发送一条最小纯文本请求；不发送图片、tools、
  schema、历史、citation 或 Key 以外的凭据。
- 复用正式 provider 的预校验/HTTP/错误映射；单次尝试，不自动重试。
- 成功显示延迟/模型；失败按 401/403、429、5xx、超时、模型不存在、网络错误
  分类；不显示 Key/请求体。
- 不写历史、不改 provider 配置、不落日志；Key 只从 SecretStore 或当前表单读取。

### 14.6 P6.6 遗留契约（已实现 2026-11-03）

- **失败态多 OCR 入口**：
  - 当 `sentImagePaths.isNotEmpty && (result != null || errorMessage != null)` 时，
    消息列表显示 OCR 变体区；失败态同时保留错误卡。
  - 生成使用本次 run 的本地图片路径；路径不存在时按钮禁用并显示“原图不可用，
    无法重新识别”，不得伪造变体或调用 provider。
  - 没有 result 时，首次本地识别得到的 baseline 存入
    `AgentOcrVariantsState.baselineVariants`；不写入历史或 provider。
- **逐版本依据预览**：
  - 对每个候选变体本地执行分词 + 词典查询，显示命中数/前 3 条摘要；不调用
    provider，不生成正式 citation。
  - 最多 4 个变体；摘要沿用 `htmlToPlainText` + `cleanDictionaryText`，最多
    240 字符；预览只存在 `AgentOcrVariantsState.previews`，不写入
    `agent_citations` 或历史。
  - 用户选中并“使用此版本重新分析”后，才由 orchestrator 重建正式 citation；
    预览不得替代正式校验。
- 测试：失败态面板出现/按钮禁用；路径失效；预览无 provider 请求；预览不写
  citation；确认后才重建。
