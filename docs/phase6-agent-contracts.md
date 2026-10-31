# Phase 6 — 词典助手接口契约 v1

> **2026-10-31 实现决策**：当前为固定流水线、模型无工具。工具表（`ToolSpec`/
> `ToolResult`、`unidic.tokenize`、`mdict.lookup`、`mdict.suggest`、预算/可见性）
> 仅作为未来契约保留；`lib/services/agent/tools/` 已删除，模型请求不携带 tools。

- 状态：**设计契约；P6.1–P6.5 核心已实现，P6.6/P6.7 未实现**；与
  `docs/phase6-agent-design.md` v2 配套。实现状态见 `docs/phase6-status.md`。
  **2026-10-31 实机反馈的 F1–F17 修正计划见
  `docs/agent_docs/device-feedback-2026-10-31.md`；其中覆盖审查 `coverage.v1`、
  输出语言校验和应用级档案队列仍是待实现契约，不能写成已支持。**
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
| `PROVIDER_REFUSED` | 模型拒绝 | 否 |
| `VALIDATION_FAILED` | 模型输出未通过 schema/引用/原文校验 | 视情况修复一次 |
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
- 输入：`{"image_handle": "img-1", "mode": "auto"}`
- 输出：`{"engine": "paddle_v5", "elapsed_ms": 1200, "confidence": 0.93, "text": "...", "blocks": [...]}`
- 约束：
  - `image_handle` 只在本机解析为私有路径；路径/文件名/base64 永不进入模型请求。
  - 必须先 `ensureReady`；`auto` 保持 Phase 4.5 单引擎语义。
  - 多版本由编排器按需多次调用 `ocr.recognize`（auto/horizontal/vertical），不暴露
    给模型。
- 错误：`MODEL_MISSING`、`MODEL_INVALID`、`IMAGE_DECODE_FAILED`、`TOOL_TIMEOUT`、
  `TOOL_CANCELLED`、`INTERNAL_ERROR`。

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

### 5.1 覆盖审查 `rikai.agent.coverage.v1`（2026-10-31 F7，待实现）

初始证据后调用一次，判断是否缺少词典资料。这是独立的轻量 schema，不直接复用
较重的 `analysis.v1`。机器可读草案：
`docs/schemas/agent/coverage.v1.schema.json`（尚未接入运行时，字段变更需升
版本）。

```json
{
  "schema": "rikai.agent.coverage.v1",
  "source_id": "src-1",
  "verdict": "missing",
  "missing": [
    {
      "kind": "word",
      "query": "何卒",
      "source_refs": ["t12", "p3"],
      "reason": "缺少正式请求语境下的释义",
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

- `verdict`: `sufficient | missing`；`missing` 最多 20 项，`duplicate_groups`
  最多 10 组（来自 `AgentLimits`）。
- `query` 必须可追溯到源文本/token lemma/lookupCandidates/语法模式/suggest；
  不可追溯项由 orchestrator 丢弃，不能让模型任意浏览词典。
- `duplicate_groups` 仅是建议；orchestrator 必须本地验证同词典、同 headword/
  entryKey、摘要大部分重合后才可删除，且优先删除信息密度较低者。
- 未达 citation 上限走流程 A（按 missing 补充检索，模式 exact→prefix→suffix→
  incremental）；已达上限走流程 B（先删可验证重复腾槽位，再走流程 A）。
- 每个用户请求最多一次覆盖审查 + 一次回退；失败/无重复/无可追溯 query 时保留
  原证据并显示 warning，不让整次 run 失败。

### 5.2 输出语言（2026-10-31 F1，待实现）

- `AgentResponseLanguage` 默认 `zh`；旧 `follow` 迁移为 `zh`，不得按输入假名/
  拉丁字符推断语言。
- system prompt 要求所有人类可读字段使用目标语言；日语仅用于原文 quote、词形、
  读音、词典例句。
- 结果后校验只检查人类可读字段（translation/segments interpretation/word
  sense/grammar explanation/unresolved reason/model supplement），不检查原文
  与 citation 摘要。偏离目标语言时允许一次语言修复；仍偏离则保留结果并显示
  warning，不得丢弃已生成内容。API 无法保证 100% 语言一致，契约不承诺绝对。

## 6. 词典档案 `rikai.dictionary.profile.v1`

完整 schema：`docs/schemas/agent/dictionary-profile.v1.schema.json`。

```json
{
  "schema": "rikai.dictionary.profile.v1",
  "dictionary_id": "dict_a",
  "title": "講談社 日本語大辞典",
  "kind": "国語辞典",
  "languages": ["ja", "zh"],
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
- 用户可编辑 Markdown 摘要；该 Markdown 是 prompt 的权威版本，JSON 作为结构备份。
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
  → familiarizing
  → awaitingProfile（应用级档案队列，逐个用户处理）
  → tokenizing
  → evidence
  → coverage（一次覆盖审查，可选补充检索）
  → reasoning
  → validating
  → done | error | cancelled
```

- `awaitingProfile` 只在需要熟悉且仍有未处理档案时出现；**必须由用户显式处理
  （信任/本次跳过/不再询问）全部已生成档案后，才进入 tokenizing**。页面离开、
  重建或 dismiss sheet 不得自动 skip；`unavailable` 档案无确认内容，记录 issue
  后不阻塞。队列属于应用级 controller，不属于 `AgentPage`。
- `coverage` 是 2026-10-31 F7 的一次性覆盖审查；每个请求最多触发一次补充检索，
  `coverageFallbackUsed=true` 后不得再次回退。
- 任何阶段可取消；取消后状态为 `cancelled`，保留已完成的本地结果。
- 阶段事件带 `run_id, stage, message, progress`；UI 不从页面 State 推断。
- 重试从失败阶段开始；OCR 可重新识别，provider 可重试，校验失败可做一次修复。

## 9. 预算默认值

| 项 | 默认值 |
|---|---|
| 单次分析源文本 | ≤ 6,000 日文字符（超限选段，不静默截断） |
| 唯一检索目标 | ≤ 120 |
| citation 总数 | ≤ 60（`AgentLimits.maxEvidenceEntries`，唯一来源，禁止硬编码） |
| 每词每典条数 | ≤ 3 |
| 摘要长度 | ≤ 400 字符 |
| 每词典档案 | ≤ 2,000 字符 |
| 模型额外工具调用 | ≤ 6 |
| 单工具超时 | 60s |
| 额外工具总预算 | 90s |
| provider 超时 | 180s（当前实现默认；旧契约 120s 以此为准统一） |
| provider 重试 | 429/5xx 最多 2 次；401/403 不重试 |
| 覆盖审查缺失项 | ≤ 20 |
| 覆盖审查重复组 | ≤ 10 |
| 覆盖检索回退 | ≤ 1 次/用户请求 |

超预算时设置 `truncated=true`，UI 显示“已按预算缩减，未分析的部分不会出现在结果
中”；不得静默截断长文本。

## 10. 校验规则（伪代码）

```text
validate(analysis, evidence, quotes, mode):
  assert schema(analysis)
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

- 修复：一次修复调用，带 `validation_errors`；仍失败则返回部分结果 + 可见错误。
- 严格模式拒绝无依据事实；不静默删除用户可见内容。

## 11. Provider 请求契约

- `LlmRequest` 只含 `messages`、`tools`（schema）、`response_format`、`max_tokens`、
  `stream`。
- `LlmMessage.content` 只有 `LlmTextPart`；**没有 image/file 类型**。
- 发送前 `assertNoImagePayload`：递归检查 JSON 键/值，禁止
  `image`、`image_url`、`input_image`、`base64`、`data:image`、`file://`、
  `content://`、`.jpg/.png/.webp/.heic` 路径。
- Anthropic：`x-api-key` + `anthropic-version: 2026-10-21`；
  `POST /v1/messages`；不发送 `temperature/top_p/top_k`。
- OpenAI-compatible：`Authorization: Bearer`；`POST /chat/completions`；
  JSON schema 支持因 provider 而异，用 capability flag + JSON object 回退。
- 测试捕获实际 HTTP body，断言不含图片/路径/Key；请求日志只记录
  `tool`、`model`、`elapsed_ms`、token 数，不记录 body/Key。

## 12. Dart 模型与文件映射

| 契约 | Dart 文件（实施时创建） |
|---|---|
| `input.v1` | `lib/core/models/agent/agent_input.dart` |
| `evidence.v1` | `lib/core/models/agent/agent_evidence.dart` |
| `analysis.v1` | `lib/core/models/agent/agent_analysis.dart` |
| `dictionary-profile.v1` | `lib/core/models/agent/dictionary_profile.dart` |
| `tool-result.v1` | `lib/core/models/agent/agent_tool.dart` |
| `quote.v1` | `lib/core/models/agent/agent_quote.dart` |
| Ports | `lib/services/agent/ports/` |
| Tool registry/adapters | `lib/services/agent/tools/` |
| Orchestrator | `lib/services/agent/agent_orchestrator.dart` |
| Validator | `lib/services/agent/agent_validator.dart` |
| Citation registry | `lib/services/agent/citation_registry.dart` |
| Store | `lib/services/storage/agent_store.dart` |
| Secret | `lib/services/security/secret_store.dart` |

## 13. 测试夹具

- `test/fixtures/agent/input_basic.json`
- `test/fixtures/agent/evidence_basic.json`
- `test/fixtures/agent/analysis_strict.json`
- `test/fixtures/agent/analysis_loose.json`
- `test/fixtures/agent/profile_basic.json`
- `test/fixtures/agent/tool_result_error.json`
- Fake provider 捕获请求体；断言无图片/路径/Key。
- 真实 MDict/UniDic 设备测试复用现有 integration_test 的 `--dart-define` 方式。
