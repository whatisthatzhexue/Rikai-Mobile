# Phase 6 — 词典助手（MDict Agent）设计草案

- 状态：**设计草案，未实现，未纳入 MVP 范围**
- 来源：`项目初始文档.txt` 第 25–44 行「项目后期第六阶段设计指南」
- 依赖：Phase 4.5 的 OCR 验收、Phase 5 的完整历史/引导/发布打磨；Phase 1–4 已提供的 OCR、UniDic、MDict 接口
- 约束：本文记录产品要求与建议架构，不代表已批准实施；不新增依赖、密钥或云端调用代码

## 1. 目标与边界

Phase 6 在现有阅读/查词应用上增加「词典助手」：把本地 OCR、UniDic 分词和 MDict
查词组织成可被 LLM 调用的工具集，支持图片、文字或图片+文字输入，输出带词典依据
的 Markdown 学习结果。

**核心边界**

- 核心 OCR、分词、查词仍在本机完成，离线可用。
- Agent 是**可选在线模块**：只有用户配置 API Key、provider 和模型后，用户主动
  发起请求时才联网。
- 图片只允许经过本机 OCR；严禁把图片作为 LLM 视觉输入，也严禁使用模型自带的
  图像识别能力。
- 不引入云 OCR/云翻译；不使用 provider 的图片/音频/文件上传能力。
- 不随包分发 LLM 权重、API Key、用户对话或词典内容。
- 模型输出按不可信内容处理：不执行 HTML/JS，不直接执行模型生成的代码。

## 2. 主页五按钮与命名迁移

Phase 6 设计要求主页固定五个按钮，顺序如下：

| Phase 6 标签 | 当前实现/旧称 | 说明 |
|---|---|---|
| 拍照识别 | 拍照识别 | 保持不变 |
| 查句子 | 文本阅读 / 当前「输入文本」 | 文本阅读、OCR 结果阅读入口 |
| 查单词 | 查词 | 现有搜索/词典查询 |
| 历史记录 | 语料 | 现有语料/识别历史；是否纳入 Agent 会话见开放问题 |
| 词典助手 | 新功能 | Phase 6 Agent 入口 |

当前代码仍是四个按钮；在 Phase 6 UI 实施前，不得提前改名或添加第五个按钮。
五按钮在现有 72dp 全宽布局下可能超出小屏高度，需在实施时补充滚动/紧凑规则
和设计 token，不能直接硬编码。

## 3. 词典助手 UX

建议页面结构（必须复用现有蓝/白 token、深蓝顶栏和共享组件）：

- 顶栏：标题「词典助手」；字号/设置入口；新会话/历史入口。
- 输入区：文字输入框 + 本地图片选择；支持图片、文字、图片+文字三种输入。
- 模式选择：严格模式 / 宽松模式（分段按钮，默认严格模式）。
- 模型路由：显示当前 small model / complex model；可在设置中配置，不在每次
  对话临时改密钥。
- 发送/停止：请求中显示阶段（本机 OCR、分词、查词、模型生成），支持取消。
- 结果区：Markdown 正文、ruby、声调横线、来源 citation chip。
- 空态：说明“需要配置 API Key”与“不会上传图片”。
- 错误态：provider 未配置、网络失败、限流、超时、模型拒绝、工具错误；
  错误信息不得包含 API Key 或完整请求体。

## 4. Provider 层（建议架构）

```text
AgentProvider
  - id / displayName
  - baseUrl / protocol
  - smallModel / complexModel
  - streamChat(messages, tools, responseFormat)
```

建议支持：

- DeepSeek（OpenAI-compatible 协议）；
- Anthropic Claude（Messages API）；
- 其他 OpenAI-compatible endpoint（用户可配置 base URL）。

要求：

- provider 适配器只接收文本消息、工具 schema 和工具结果；请求构造器没有图片字段。
- 小模型负责简单词典查询/格式整理；复杂模型负责推理、解释和规则生成。
- 用户可只配置一个模型，此时简单/复杂任务共用；缺失配置时明确提示，不静默降级
  到云 OCR 或 provider 视觉。
- 流式输出可选；无论是否流式，都必须支持取消、超时和限流错误。
- 不在文档或日志中记录 API Key；密钥读取只发生在 provider 调用边界。

## 5. 本地工具层

工具必须是用户本地能力，且全部通过 schema 调用。现有实现：

- OCR：`lib/services/ocr/ocr_service.dart`（Paddle/Manga）
- UniDic：`lib/services/mecab/mecab_service.dart`
- MDict：`lib/services/mdict/mdict_worker.dart` / 词典仓库
- 词典渲染：`lib/services/mdict/entry_renderer.dart` + 现有词条页

建议工具名与输入/输出（具体 schema 在实施时固定并版本化）：

| 工具 | 输入 | 输出 |
|---|---|---|
| `ocr.recognize` | 本地图片路径、方向模式 | 文本、blocks、引擎、耗时 |
| `unidic.tokenize` | 文本 | token、词性、读音、offset |
| `mdict.lookup` | 查询词、词典筛选 | 命中的词典/词条/摘要/ citation 候选 |
| `mdict.suggest` | 前缀、词典筛选 | 建议词 |
| `dictionary.probe` | 词典/UniDic 标识 | 熟悉期样本，供生成 md 文档 |

工具结果统一返回：

```json
{
  "ok": true,
  "data": {},
  "error": null,
  "provenance": {"tool": "mdict.lookup", "toolCallId": "..."}
}
```

错误时返回稳定错误码（如 `MODEL_MISSING`、`DICTIONARY_NOT_READY`、
`TOOL_TIMEOUT`），不得把原生异常或 API Key 直接传给模型/UI。

## 6. Agent 协议与两种模式

- 工具调用遵循 JSON Schema；未知工具、参数不匹配、超时、超过最大调用次数均拒绝。
- 每次工具调用/结果都带 `toolCallId`；citation 只能由 orchestrator 根据真实工具结果
  发放，模型不能自造来源。
- 消息、工具调用、citation 和模型输出均记录在本地会话中（是否默认持久化见开放问题）。

**严格模式**

- 先查词典/分词，后回答；事实性陈述必须对应 citation。
- 词典无依据时明确说明“词典中未找到依据”，不得编造翻译、读音或词义。
- 模型生成的自然语言解释也必须区分“词典依据”和“模型补充”；严格模式下后者默认
  不显示或标注为不可作为依据。

**宽松模式**

- 仍以词典结果为基础；允许模型补充见解、联想、例句。
- 词典事实必须有 citation；模型补充必须使用独立样式/标签（如“模型补充”），
  不能与词典原文混淆。

**模型分流**

- 简单任务（查词、格式化、提取）使用用户指定的 small model。
- 复杂任务（词义推理、比较、规则生成）使用 complex model。
- 路由策略应先做确定性判断，必要时才调用分类器；最终配置以用户设置为准。

## 7. 来源引用

建议 citation 结构：

```json
{
  "id": "source-1",
  "kind": "mdict",
  "dictionaryId": "dict_xxx",
  "entryKey": "ありがとう",
  "headword": "ありがとう",
  "snippet": "……",
  "toolCallId": "call_..."
}
```

- 模型输出使用 `[来源1]` 形式；渲染层解析为可点击 chip。
- 点击来源：调用现有查词 sheet，定位到对应词典/词条；再点击词条进入现有词条页。
- 来源 ID 只能引用本次会话内真实工具结果；找不到/伪造/越界引用显示为普通文本，
  不得静默打开任意页面。
- 严格模式无 citation 的词典断言视为不合规输出；宽松模式的模型补充必须标记。
- 查询结果来自多本词典时，citation 必须保留 `dictionaryId` 和具体 `entryKey`，
  不能只保存一个模糊的“查词结果”。

## 8. 词典熟悉期

在 Agent 使用 MDict/UniDic 前，必须生成并让用户确认“词典熟悉文档”：

1. 用有界探针生成若干查询（MDict：头词/前缀样本；UniDic：分词样本），不遍历整个
   词典。
2. 调用本地工具，观察条目/字段/HTML/分词输出的排列规律。
3. Agent 写 Markdown 说明（字段含义、可查形式、注意事项、推荐调用方式）。
4. 用户在应用内预览/编辑；无修改后确认保存。
5. 下次同一词典/UniDic 直接读取已确认文档，不重复探查。

建议缓存键：词典 ID + 文件路径 + 文件 stat + UniDic 路径/版本 +
schema/prompt 版本。词典文件变化、用户重置或确认文档被删除时失效。熟悉文档存
应用私有目录/SQLite，不写入用户的 UniDic/MDict 目录。

UniDic 当前是 MeCab 分词器而不是可逐条查询的词典；“熟悉”应定义为对分词输出、
feature 布局、读音/词性/offset 的观察，不假装存在 UniDic 词条查询接口。

## 9. 注音/标注规则

用户可指导 Agent 生成 app 专用“伪代码”，影响所有 UniDic 分词界面的注音/标注显示。
实现时必须把它降级为**受验证的安全 DSL**，而不是执行任意 Dart/JS/Python：

```json
{
  "id": "pitch-high",
  "when": {"pos": ["名詞"], "pitch": "high"},
  "apply": {"weight": "bold", "color": "brand"}
}
```

要求：

- 规则有名称、版本、作用域、优先级和启用状态；支持预览、编辑、回滚、重置。
- 只允许白名单字段/样式，不执行文件、网络、反射或任意代码。
- 由统一 annotation engine 解析，作用于 ReaderBlock/TokenChip/FuriganaText、
  照片集结果、语料详情以及 Agent 中的 UniDic token 展示。
- 规则生成必须经用户确认后保存；不得在后台静默改变全局阅读样式。
- 声调规则的数据源和匹配语义见开放问题；不得臆造 UniDic 不存在的字段。

## 10. Markdown、ruby 与声调横线

- 只渲染安全的 Markdown 子集（标题、列表、粗体、斜体、代码、表格、引用、
  受限链接）；禁止原始 HTML、脚本、iframe、事件属性和远程图片。
- ruby 建议使用应用自定义语法，例如 `{漢字|かんじ}`，由安全解析器转成现有
  `TextSpan`/ruby 渲染；具体语法待实现时固定。
- 声调横线建议使用受支持的 Unicode 组合上划线或专用 span 样式；具体标记法、
  多音拍/复合词规则待定，必须有单元测试和回退纯文本方案。
- citation chip 不经过 Markdown 链接渲染，而是由结构化 citation 数据生成。
- 模型输出的未知语法按普通文本显示，不崩溃、不执行。

## 11. 隐私与密钥

- API Key 建议使用 Android Keystore/安全存储；不得放进 `SharedPreferences`、
  源码、日志、崩溃报告、导出文件或 Git。
- 首次配置和每次新建 provider 配置时显示网络/数据说明；默认不自动发起请求。
- 只发送：用户输入文字、本机 OCR 文本、分词结果、词典查询结果、工具 schema。
- 永不发送：原始图片、图片路径、UniDic/MDict 文件、API Key、其他本地文件。
- 提供清除 Key、清除会话、删除熟悉文档/规则的入口。
- provider 的条款和隐私政策由用户与服务商承担；应用只提供适配层。
- 核心离线功能不得依赖 provider 配置；未配置时所有原有页面照常工作。

## 12. 数据模型（建议）

- `agent_conversations`：id、title、created_at、updated_at、provider_id、mode。
- `agent_messages`：conversation_id、role、content、created_at、model_id。
- `agent_tool_calls`：conversation_id、tool_name、input_json、result_json、status。
- `agent_citations`：message_id、citation_id、kind、dictionary_id、entry_key、snippet。
- `dictionary_familiarizations`：dictionary_id、fingerprint、markdown、confirmed_at。
- `annotation_rule_sets`：id、name、version、rules_json、enabled、updated_at。

对话/工具结果是否默认持久化、是否纳入「历史记录」见开放问题；所有数据仅本地，
不做云同步。

## 13. 测试与验收

Phase 6 实施后至少覆盖：

1. 五按钮顺序、命名和小屏布局；当前四按钮 UI 的回归。
2. 图片输入只调用本机 OCR；捕获 provider 请求，断言不含图片/base64/视觉字段。
3. 文字、图片、图片+文字三种输入路径。
4. 严格模式：每个词典事实有真实 citation；无证据时拒绝编造。
5. 宽松模式：词典事实有 citation，模型补充有明确标签。
6. 模型路由：简单/复杂任务命中对应模型；单模型配置可回退。
7. 工具 schema 校验：未知工具、坏参数、超时、最大调用次数。
8. citation 点击正确打开对应词典/词条；伪造/越界 citation 被拒绝。
9. 熟悉文档生成、用户编辑/确认、保存、复用、词典变化后失效。
10. 注音/标注规则预览、全局生效、回滚、非法规则拒绝。
11. Markdown/ruby/声调渲染安全；HTML/JS/远程资源不执行。
12. API Key 不在日志/导出/Git；清除配置后离线核心仍正常。
13. provider 失败/限流/网络断开时的错误与恢复。
14. 不把用户图片/词典文件/Key 发送给 provider 的集成测试。

## 14. 实施顺序（Phase 6，建议）

Phase 6 必须在 Phase 4.5 验收、Phase 5 完成并经用户确认后开始；以下顺序不是时间估算：

1. 6.1 Provider 配置、安全存储、隐私同意、fake provider 测试骨架。
2. 6.2 OCR/UniDic/MDict tool adapters + JSON Schema + citation 基础设施。
3. 6.3 Agent loop、严格/宽松模式、small/complex model 路由。
4. 6.4 Markdown/ruby/声调渲染、citation UI、错误/空态。
5. 6.5 词典熟悉期工作流和缓存。
6. 6.6 注音/标注规则 DSL、预览、全局渲染接入。
7. 6.7 会话/历史、性能/内存、许可与发布验收。

## 15. 开放问题

在实施前需要用户确认：

- 默认 provider、模型 ID、是否支持自定义 OpenAI-compatible endpoint 和本地 LLM。
- API Key 的存储实现（是否引入 `flutter_secure_storage`）、多配置/切换/删除方式。
- ruby 与声调横线的确切语法、Unicode/CSS 方案和多音拍规则。
- 严格模式无词典依据时是直接拒绝、建议切宽松，还是仅标注“无依据”。
- 五按钮在小屏上的布局：滚动、缩小、两列或折叠。
- 「历史记录」是否包含 Agent 会话；会话是否默认保存/可导出。
- UniDic“熟悉”探针的样本数量、字段范围和缓存失效策略。
- 标注 DSL 的字段、优先级、作用域，以及是否允许用户直接编辑。
- citation 是否还要支持 OCR/UniDic 来源，还是只允许 MDict 词条。
- provider 流式、超时、最大 token、重试/限流的具体策略。
- 是否需要视觉以外的多模态输入（当前明确禁止图片视觉）。

## 16. 需求追踪

| 初始文档要求 | 本文对应 |
|---|---|
| 主页五个按钮及重命名 | §2 |
| Agent 集成 OCR/MDict/UniDic，用户 API Key，多 provider | §1、§4、§5 |
| 严格/宽松模式 | §6 |
| 简单/复杂模型分流 | §4、§6 |
| 图片/文字/混合输入，禁止模型视觉 | §1、§3、§11、§13 |
| Markdown + ruby + 声调横线 | §10 |
| 本地工具集 | §5 |
| 词典熟悉期、用户确认、复用 | §8 |
| schema、严格模式引用、点击来源 | §6、§7 |
| 注音/标注伪代码影响所有分词界面 | §9 |
| 工具接口已存在 | §5（Phase 1–4 已实现） |
