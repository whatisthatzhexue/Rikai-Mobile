# CLAUDE.md — Rikai-Mobile handoff

> 给下一个 agent 的工作交接。本文件只保留项目摘要、架构决策、当前状态、关键文件与
> 构建/验证命令；文档用途和查阅时机统一在 §0 维护。
> 用户使用中文沟通；代码/标识符用英文。

## 0. 文档导航（先读这里）

> **权威层级**：规则 → `docs/project-rules.md`；当前数据/文案 →
> `docs/project-data.md`；视觉数值 → `docs/design-tokens.md`；误区/踩坑 →
> `docs/project_tips.md`；Agent 字段/错误码 → `docs/phase6-agent-contracts.md` +
> `docs/schemas/agent/`；架构决策 → `docs/adr/`；历史阶段 →
> `docs/project-history.md`（流水）+ `docs/phase*-status.md`（详细快照）。
> 冲突时按此层级修正低权威文档。正文只保留具体小节指针（如
> `docs/project-data.md` §6），不重复文档用途说明。
>
> **导航约定**：文档用途与查阅时机只在本索引维护；规则、数据、设计 token、
> 误区、历史、开发环境六份文档之间不写相互引用。
>
> **Agent 开发门禁**：开发/修改 Phase 6 词典助手前，按
> `docs/agent_docs/README.md` 的必读顺序阅读；2026-10-31 的 F1–F17 未关闭前，
> 不在 P6.6/P6.7 上继续叠加新功能，也不把未实现能力写成已支持。

`docs/project-rules.md`：
内容：正面/反面 MUST/MUST NOT 规则的单一权威源，按 `R-<域>-<序号>` 编号；
覆盖产品/隐私/架构/Agent/UI/开发/文档治理。
何时查看：实现或审查任何功能前；判断某做法是否允许；文档冲突时。

`docs/project-data.md`：
内容：测试数量/设备结果/性能/构建产物/环境版本/开发数据统计/固定 UI 文案/
Agent 预算的单一事实源。
何时查看：需要任何当前数值、环境版本、固定文案或预算；更新测试/设备/构建
记录时。

`docs/design-tokens.md`：
内容：UI 视觉/布局/交互强制规范（颜色/字号/间距/圆角/组件/转场/页面结构/
Agent 对话式 UI）；实现入口为 `lib/core/theme/app_tokens.dart`。
何时查看：新增或修改任何 UI 前；检查页面是否硬编码颜色/字号/间距。

`docs/project_tips.md`：
内容：项目误区/踩坑与解决方案（`T-001`–`T-129`），含症状 → 处理速查附录。
何时查看：遇到报错、异常行为或准备重复试错前；接手 OCR/UniDic/MDict/采集/UI/
Agent 改动前。**今后的误区只在该文件新增。**

`docs/DEVELOPMENT_PLAN.md`：
内容：MVP 阶段计划与范围。
何时查看：确认当前阶段目标/边界；规划新阶段前。

`docs/phase0-status.md`：
内容：Phase 0 基建（vendored MeCab、`rikai_ocr` 骨架、ORT、模型 manifest、
许可）的验证记录。
何时查看：追溯 Phase 0 实现细节；历史值不作当前值。

`docs/phase1-status.md`：
内容：Phase 1（UniDic/MeCab、权限、阅读器、真实词典）验证记录。
何时查看：追溯 UniDic/MeCab 与权限实现；历史值不作当前值。

`docs/phase2-status.md`：
内容：Phase 2（MDict worker、查词/渲染/词典管理）验证记录。
何时查看：追溯 MDict/WebView 实现；历史值不作当前值。

`docs/phase3-status.md`：
内容：Phase 3（横向 PaddleOCR、拍照、模型管理）验证记录。
何时查看：追溯横向 OCR/采集实现；历史值不作当前值。

`docs/phase3.5-status.md`：
内容：Phase 3.5（采集/导入/语料/模型目录修复）验证记录。
何时查看：追溯采集与词典导入的修复来源；历史值不作当前值。

`docs/phase4-status.md`：
内容：Phase 4（纵向 MangaOCR、自动方向、设备合成测试）验证记录。
何时查看：追溯纵向 OCR/方向路由实现；历史值不作当前值。

`docs/phase4.5-status.md`：
内容：Phase 4.5 OCR 质量/性能收敛与第二轮设备反馈（已完成，2026-10-30
关闭）。
何时查看：追溯 OCR 懒加载/方向/双引擎评分与设备反馈修复；历史值不作当前值。

`docs/phase5-status.md`：
内容：Phase 5（首次引导、语料/历史、设置、发布打磨）完成记录。
何时查看：追溯引导/语料/发布实现；历史值不作当前值。

`docs/project-history.md`：
内容：Phase 0–Phase 5 的实现/修复/验收流水、已完成路径保护说明与历史提交锚点；
不等于当前状态或当前数据。
何时查看：追溯“当时做了什么、为什么这样修”；不要把它当当前任务清单。

`docs/phase6-agent-design.md`：
内容：Phase 6 词典助手设计 v2（固定流水线、模型无工具、隐私边界、任务工作流）。
何时查看：开发/修改 Agent 前；确认产品与流水线设计。

`docs/phase6-agent-contracts.md`：
内容：Agent 契约/schema/状态机/错误码/请求与响应字段。
何时查看：改 Agent DTO/provider/schema/validator 前；核对字段与错误码。

`docs/phase6-status.md`：
内容：Phase 6 当前实现记录（P6.1–P6.5、Wave 进展、已知差距）。
何时查看：确认 Agent 已实现/未实现范围；更新进度时。

`docs/agent_docs/README.md`：
内容：Agent 文档导航与硬规则（开发前必读顺序）。
何时查看：开发 Agent 前先读；需要当前评审/生命周期文档入口。

`docs/agent_docs/device-feedback-2026-10-31.md`：
内容：2026-10-31 实机反馈 F1–F17 的修正方案、依赖与执行波次；当前优先工作
队列。
何时查看：开发 Agent 或安排下一步前；决定 Wave 顺序时。

`docs/agent_docs/phase6-pipeline-review.md`：
内容：Agent 管线评审与已知问题（含 file:line 证据）。
何时查看：排查 Agent 管线问题；作为历史 gap 证据，不作当前任务清单。

`docs/agent_docs/agent-lifecycle-and-edge-cases.md`：
内容：Agent 运行生命周期、离开/返回页面、取消、并发、进程死亡等规范。
何时查看：改 Agent 运行状态/取消/并发逻辑前。

`docs/agent_docs/agent-maintainability-review.md`：
内容：Agent 代码可维护性评审（死抽象、god 文件、controller/测试、schema 债务）。
何时查看：重构 Agent 前；评估维护成本时。

`docs/agent_docs/non-agent-regression-review.md`：
内容：Agent 以外功能的回归检查（旧 integration test 文案、帮助页、构建风险）。
何时查看：Agent 改动后做非 Agent 回归前。

`docs/schemas/agent/`：
内容：Agent JSON Schema（input/evidence/analysis/quote/profile/coverage/
tool-result）。
何时查看：改请求/响应结构或校验器前。

`docs/adr/`：
内容：四个架构决策（ONNX OCR、UniDic 原地读取、MDict `dict_reader`、Agent
能力边界）。
何时查看：质疑/修改核心架构前；需要决策理由时。

`docs/dev-setup.md`：
内容：环境/字体/图标/构建/模拟器/adb 数据/网络/Gradle 排障，以及 MeCab/
MDict/MDD 音频/OCR 设备集成测试的完整命令。
何时查看：搭环境、跑设备测试、处理 Gradle/权限/模型目录/网络问题。

`docs/phase3-review.md`：
内容：Phase 3 代码评审与修复清单（H/M/L）。
何时查看：追溯 Phase 3/3.5 修复来源；不要当当前任务清单。

`docs/models.md`：
内容：OCR 模型来源/许可/下载与目录说明。
何时查看：处理模型下载/校验/导入/许可前。

`docs/licenses.md`：
内容：第三方许可与来源汇总。
何时查看：新增依赖/模型/词典或发布前。

`THIRD_PARTY_NOTICES.md` / `NOTICE`：
内容：第三方代码/模型/许可证与修改说明。
何时查看：发布、许可审查或修改第三方代码前。

`assets/fonts/README.md`：
内容：HarmonyOS Sans 字体下载与放置说明（字体不入库）。
何时查看：构建报缺字体或需要切换字体前。

`assets/models/manifest.json`：
内容：OCR 模型文件名/URL/SHA-256/角色清单（不含模型本体）。
何时查看：改模型下载/校验/导入逻辑前。

`项目初始文档.txt`：
内容：2026-10 中期 UI/功能修正的原始需求记录（历史）。
何时查看：追溯当时的中期 UI 修正来源；不要当作当前规则。

## 1. 项目是什么

Android 单端的 Flutter 日语阅读/查词应用。**核心离线**：拍照或输入文本 →
横向 PaddleOCR / 纵向 MangaOCR → UniDic（用户自备）分词与注音 → 点击单词查询
用户自备的 MDict 词典；另有搜索查词、词典偏好、语料保存。

**Phase 4.5（OCR 质量与性能收敛）已于 2026-10-30 通过 arm64/真实设备验收并关闭；
Phase 5（语料/历史、首次引导与发布打磨）也已于 2026-10-30 完成并由用户在冷启动
模拟器上确认测试通过。** Phase 5 包含首次引导、文本/照片语料保存、自动保存开关、
语料清空/删除、图片压缩、设置页存储/许可入口和 arm64 release APK。Phase 5 已由
用户发布为 1.0 release。

Phase 6（`docs/phase6-agent-design.md`，**设计 v2；P6.1–P6.5 已实现，P6.6/P6.7
未实现**；契约见 `docs/phase6-agent-contracts.md`）增加「词典助手」：可选地调用
用户配置的远程文本 LLM（DeepSeek/Claude 等），把本地 OCR、UniDic、MDict 作为
schema 化证据；采用固定流水线，模型无工具调用（2026-10-31 决策）。图片仅在本机
OCR，禁止视觉上云（固定隐私文案见 `docs/project-data.md` §7）；
核心离线功能不得依赖该 Agent。实现进度见 `docs/phase6-status.md`。
**2026-10-31 实机反馈 F1–F17 的修正计划见
`docs/agent_docs/device-feedback-2026-10-31.md`；未完成前优先按该文档执行，不要
开始 P6.6/P6.7。**

- 项目根目录：`C:\Projects\Rikai-Mobile`（ASCII 路径，旧的 `E:\MyData\大工\...` 已不存在）
- 包名/applicationId/namespace：`com.rikai.mobile`
- Flutter 工程名：`rikai_mobile`
- 环境/版本/SDK/NDK/模拟器基线见 `docs/project-data.md` §1；本文件不重复具体值。
- 仅 Android；不做 iOS、不做云 OCR/云翻译。Phase 6 可选 Agent 允许用户配置的
  **文本 LLM**（不是云 OCR/视觉）；未实现前不得默认联网或把图片发给模型。
- **UI 强制规范**：所有现有与新增界面必须遵循 `docs/design-tokens.md`
  （视觉数值、页面结构、控件位置与交互顺序的唯一权威）和
  `lib/core/theme/app_tokens.dart`；页面不得硬编码颜色/字号/间距/圆角。
  固定按钮文案见 `docs/project-data.md` §7；Phase 6 新 UI 仍须先补 token/测试。
- **字体/图标**：HarmonyOS Sans SC Regular 由用户按 `assets/fonts/README.md`
  下载（字体不入库）；构建前必须存在，图标生成见 `docs/dev-setup.md`。
- 历史提交锚点见 `docs/project-history.md`；当前工作区以 `git status` 为准。
  不要擅自 `reset`/`commit`，除非用户明确要求。

## 2. 已确认的架构决策（不要随意改；第 9 项为 Phase 6 设计边界）

1. **统一 ONNX Runtime OCR**：
   - 横向：PaddleOCR PP-OCRv5 mobile det + rec（官方 ONNX）。
   - 纵向：复用同一 DBNet 检测 + manga-ocr ONNX（encoder + decoder）。
   - 方向：框几何启发式 + 可选 PP-LCNet doc/textline orientation。
   - **不要引入 Paddle-Lite / OpenCV / NDK r21 / `.nb` 模型**。
2. **PaddleOCR4Android 只作为参考/可选后备**：
   - 其 `:PaddleOCR4Android` 是 Paddle-Lite + OpenCV，NDK r21、仅 arm、仅横排。
   - MVP 不编译它；保留 MIT 许可与 `third_party/paddleocr4android/` 说明。
   - 架构上预留 `OcrBackend` 扩展点（尚未写代码），二期可接，但不是当前任务。
3. **UniDic/MDict 原地读取，不复制**：
   - 用户提供目录/文件路径；应用不写入用户目录。
   - Android 11+ 使用 `MANAGE_EXTERNAL_STORAGE`（所有文件访问）；拒绝时引导放到
     `/sdcard/Android/data/com.rikai.mobile/files/`。
   - 不实现“导入时复制大型 UniDic”作为默认行为；数据规模见
     `docs/project-data.md` §6。不要在用户 UniDic 目录创建 `mecabrc`。
4. **MeCab**：vendored `mecab_for_dart` 2.0.5（BSD-3）在 `packages/mecab_for_dart`，
   路径依赖。已打补丁：`src/dart_ffi.cpp` 仅在 `<dicdir>/mecabrc` 存在时才传 `-r`。
   应用必须自己创建**私有** `mecabrc`，并通过 `Mecab.create(..., options: '-r "<私有rc路径>"')`
   传入。`options` 字符串由 `generateArgs()` 按空格/双引号解析。
   该方式已在 Android x86_64 模拟器 + 真实大型 UniDic 上验证成功（见
   `docs/phase1-status.md`；数据规模见 `docs/project-data.md` §6），不需要改 C++ 的
   `rcPath` 参数。
   **注意**：UniDic 的 feature 行是带双引号的 CSV，例如
   `"動詞%F2@1,形容詞%F4@-2"`；不能直接 `split(',')`，必须用
   `lib/services/mecab/mecab_output_parser.dart`。
5. **MDict**：`dict_reader` 1.6.1（MIT），长生命周期 worker isolate。
   - 开发测试词典为 MDict v2.0、UTF-8、zlib、未加密；条目数/大小见
     `docs/project-data.md` §6；
   - `locateAll` 命中后必须解析 `@@@LINK=目标` 重定向，再渲染；
   - 不支持 LZO / record block 加密 / checksum；导入时要预检并给出明确错误。
6. **词典 HTML 渲染**：离线 `flutter_inappwebview`，禁用 JS 与网络，HTML 清洗后加载；
   MDD 资源按需提取到缓存并重写为本地 `file://`。不要改用 `flutter_html`。
7. **附加功能**：核心 + 语料保存/识别历史（照片 + OCR 文本 + 分词结果），SQLite。
8. **MangaOCR 模型**：默认从 `l0wgear/manga-ocr-2025-onnx` 下载；模型卡许可未声明，
   **不得随包分发/不得提交**，下载前显示提示，支持本地导入。原项目 kha-white 是
   Apache-2.0，但当前下载源不是。INT8 draft 解码器 MVP 不做。
9. **Phase 6 词典助手（设计边界；P6.1–P6.5 已实现，P6.6/P6.7 未实现）**：
   - 核心 OCR/UniDic/MDict 仍在本机；Agent 是可选在线模块，只有用户配置
     API Key/provider 并主动发送请求时才联网。
   - 图片只能经本机 OCR；严禁把图片作为 LLM 视觉输入或调用 provider 的图像能力。
     发送给 provider 的只能是不含路径/文件名的文本 JSON（`{image_id, ocr_text}`）。
   - 采用**固定流水线、模型无工具**：orchestrator 预取 OCR/分词/逐词查词；
     模型只做理解、推断和引用已有证据，不采用自由 ReAct 大循环，也不能自行
     补查词典。2026-10-31 已删除 `lib/services/agent/tools/` 与
     `LlmTool`/`LlmCapabilities`；工具表在契约中仅作未来参考。
   - 能力接口化：OCR/UniDic/MDict 外包窄 Port；查词逻辑提取为纯
     `LookupGateway`，照片集与 Agent 共用底层查词实现。
   - 用户可选 small/complex 模型；严格模式必须引用真实词典查词结果，宽松模式
     允许标注过的模型补充。citation 由 orchestrator 发放，模型不能自造来源；
     原文引用、词典顺序（`DictionaryInfo.order`）和每会话词典选择均由 orchestrator
     校验/渲染。
   - 词典熟悉档案按词典指纹缓存并经用户确认；注音/标注规则使用受验证的安全 DSL，
     禁止执行任意代码（首版不实现 DSL）。
   - API Key 用 `flutter_secure_storage`/Android Keystore，不进
     SharedPreferences/日志/导出；Phase 6 不得破坏未配置 Agent 时的离线核心。
     契约/schema/状态机细节见 `docs/phase6-agent-contracts.md`，产品细节见
     `docs/phase6-agent-design.md`。
10. **Phase 4.5 OCR 运行时（已完成）**：
   - PaddleOCR 必需；MangaOCR/orientation 只在 auto/vertical 需要时懒加载，
     横向模式不得创建 Manga session。`prepare(mode)` 只做后台预热。
   - readiness 区分 `mangaAvailable`/`mangaLoaded` 等；UI 的“已安装”看 available。
   - 运行时指纹/路径校验先 stat（路径、大小、mtime），不要每次 ready 都全量
     SHA-256；下载/导入/迁移仍需 SHA-256。
   - doc orientation 只在长宽比与框布局矛盾时运行；90/270 旋转后必须重新 DBNet。
   - auto/vertical 的竖排页现在会同时评估 MangaOCR 和 PaddleOCR：按
     置信度、日文假名覆盖、重复噪声计算统一质量分，只有 Paddle 明显更好
     （分差 >0.04）才切换；最佳主候选低于 0.80 时才尝试 ±90° 旋转后的
     Paddle。最终仍只返回一个引擎，不要恢复按区域混合输出。手动 vertical
     在缺少 MangaOCR 时仍明确报 `MODEL_MISSING`。
   - 照片集“旋转”只改私有会话副本 90°，清该照片 OCR 缓存后重新识别；旋转会
     立即中断正在进行的 OCR，不要让用户先手动取消。不要改设备原图。

## 3. 当前状态

Phase 0–5 已全部完成：Phase 4.5 于 2026-10-30 通过 arm64/真实设备验收，Phase 5 于
2026-10-30 由用户在冷启动模拟器确认并发布 1.0。详细阶段流水、修复过程和历史提交
见 `docs/project-history.md`；当前测试/设备/性能/构建数据见
`docs/project-data.md` §2–§5。

- **Phase 6 P6.1–P6.5 已完成核心实现**：能力 Ports、LookupGateway/
  MDict sample/suggest、Provider 适配与 secure storage、词典/UniDic
  熟悉期、Orchestrator/证据/quote/校验、Agent 页面/Provider 设置/主页新增入口。
  x86_64 模拟器已用真实相册图片 + 用户配置的 DeepSeek 跑通“实时思考/生成 →
  中文译文/逐句/原文/词典依据”。
- **Phase 6 未完成**：2026-10-31 实机反馈 Wave 2–4（默认中文/UI 语言（决策已定、
  实现待做）、应用级档案确认队列、多图、结果操作行、检索完整度/覆盖审查等；
  Wave 1 的 F4/F5/F9/F10/F15/F16 已实现，设备手工验收待 Wave 4）、P6.6 多 OCR
  版本/词典辅助修复、P6.7 annotation DSL/Markdown/ruby/pitch、Agent 会话历史 UI、
  真实 provider/API Key 与真实词典 sample/suggest 设备验收。详见
  `docs/agent_docs/device-feedback-2026-10-31.md` 和 `docs/phase6-status.md`。

**下一步：**

- Phase 6：按 `docs/agent_docs/device-feedback-2026-10-31.md` 的 Wave 2–4 处理
  实机反馈；F2（档案队列）完成前不做 F7/F13/F14 的档案相关部分，F6 完成前不做
  F7。之后再做 P6.6/P6.7；未实现能力不得写成已支持。
- 分发前：release 仍使用 debug keystore，替换正式签名；Phase 5 可选增强
  （语料缩略图、更多空/错误态、无障碍细化）。
- 本开发环境只有 x86_64 模拟器 `Medium_Phone_API_36.1`；Phase 5 UI 已在冷启动
  模拟器确认，OCR 性能/真实漫画质量仍需 arm64 真机复测。
- 本机模拟器 DNS 无法解析 hf-mirror/Hugging Face，因此“应用内实网下载模型”
  尚未在设备验证；主机 curl 成功，Dart 本地 HTTP 测试已覆盖 Range 续传/校验。
- MangaOCR 仍未移植上游 mask/panel/free-text 全流水线，也没有 cross-bubble
  batching/INT8 draft/密集页 tiling；90/270 已实现整图旋转，但真实页仍需调参。

## 4. 未完成事项（按优先级）

### Phase 6：Mdict Agent（P6.1–P6.5 已实现，P6.6/P6.7 未实现）

先读 `docs/phase6-agent-design.md`、`docs/phase6-agent-contracts.md` 和
`docs/phase6-status.md`；本节只给交接摘要，细节以设计/契约/状态文档为准。

- 主页功能按钮已接入（数量/固定文案见 `docs/project-data.md` §7）。
- Agent 使用本地 OCR/UniDic/MDict 能力 + 用户配置的远程 LLM；DeepSeek/Claude/
  OpenAI-compatible 均通过 provider 适配层，不依赖 provider 的视觉能力。
- 固定流水线、模型无工具（2026-10-31 决策并删除死工具层）：orchestrator 预取
  OCR/分词/逐词查词；模型只做理解、推断和引用已有证据，不自行补查。OCR/采样/
  UniDic profile 全部由 orchestrator 调用。
- 语言：默认输出/UI 中文（zh）；旧 `follow` 映射为 `zh`；禁止按输入假名/拉丁
  字符推断（2026-11-01 决策；F1/F17 代码待改，见 `docs/phase6-status.md`）。
- 能力接口化：窄 Port（Ocr/Tokenize/Lookup/DictionarySample/Llm/Secret）包住现有
  `OcrService`/`MecabService`/`MdictService`；提取纯 `LookupGateway`，UI 与 Agent
  共用查词内核，不复制查词逻辑。`OcrWorkflow` 已于 2026-10-31 删除。
- 任务工作流（翻译/解释）：Step -1 词典熟悉（采样→LLM 归纳→用户确认→本地缓存）→
  Step 0 图片仅本机 OCR，按 `{image_id, ocr_text}` JSON 发送（禁止图片/base64/路径）→
  Step 1 UniDic 分词 + MDict 逐词/语法检索 → Step 2 结合语境推断（严格模式每个
  候选都要 citation）→ Step 3 结果+依据。回答必须引用原文；词典输出顺序严格按
  `DictionaryInfo.order`；每会话词典选择独立于查词全局偏好，不回写全局。
- 泛化（P6.6 待实现）：Agent 可调用多种本机 OCR 策略并结合 UniDic/MDict 修复；
  多个版本冲突时必须让用户选择，不能静默覆盖，也不能把图片发给模型。
- citation/quote/词典顺序由 orchestrator 发放并校验；模型自造/越界 citation 只按
  普通文本显示，不能打开任意词条。
- API Key 用 `flutter_secure_storage`/Android Keystore；不进 SharedPreferences/
  日志/导出。
- 已实现顺序：Ports/Tools → Provider/Secret → 熟悉期 → Orchestrator/Validator →
  Agent UI/Provider 设置/主页功能入口。待做：多 OCR（P6.6）→ annotation DSL/
  Markdown/ruby/pitch/历史 UI/发布（P6.7）。
- 禁止：把图片/base64/路径发给 LLM、把 provider 当云 OCR、把 API Key 放仓库/
  SharedPreferences/日志、执行模型生成的任意代码、把 P6.6/P6.7 未实现的能力
  描述成已支持。

### 分发前

- Release 仍用 debug keystore（`android/app/build.gradle.kts` TODO），替换正式签名。
- 可选：语料缩略图、更多空/错误态、无障碍细化。

### 真机/网络验收

- 真实 provider/API Key、secure storage 设备 I/O、真实词典 `sample`/`suggest`
  和 arm64 Agent 端到端仍未验收；不要把它们描述成已验证。
- 在可访问 hf-mirror 的设备上验证 PaddleOCR/MangaOCR/orientation 下载、断点续传、
  镜像回退、本地导入与许可确认；确认模型目录与删除流程。
- 相机/照片集/多选/语料做 arm64 真机回归，重点验证 MangaOCR 竖排质量、连续多
  气泡页性能/内存，以及真实的 180°/90° 旋转照片；本机仅 x86_64。

### OCR 后续调优

验收已通过（2026-10-30），后续调优时仍需在真机复测：

- 横排 2048px <5s、单页漫画 <10s、无 OOM；
- 横排/竖排/倒置/90°/270° 真实页面回归；
- 真实漫画多气泡/多面板顺序、振假名噪声、低置信度垃圾文本；
- 首次 auto/vertical 冷启动仍有 Manga session 创建成本（数值见 `project-data` §4）；
- 视情况继续做 panel grouping、cross-bubble batching、密集页 tiling。

### 不要重写已验证路径

- UniDic/MeCab、Phase 2 MDict、Phase 3 横向 OCR、Phase 4 纵向 MangaOCR 的
  实现细节与已知限制见 `docs/project-history.md` 的“已完成路径的保护说明”与
  对应 `phase*-status.md`；修改前先读，不要重写已验证的 Paddle 横向路径或
  MangaOCR 基础流水线。

## 5. 项目误区 → 解决方案

> **已迁移**：原 §5.1–§5.14 的 129 条误区/解决方案已移至
> `docs/project_tips.md`（`T-001`–`T-129`）。**今后的误区只在该文件新增**；
> 本文件不再保留误区正文。
>
> 何时查看：遇到报错/异常行为/准备重复试错前；先查
> `docs/project_tips.md` 附录 A 的症状表，再按 `T-###` 阅读完整条目。

## 6. 关键文件

> 文档用途/查阅时机见 §0；以下只列代码、模型清单与开发数据路径。

```text
lib/main.dart, lib/bootstrap.dart, lib/app.dart               # 启动页 / go_router
lib/core/theme/app_tokens.dart                                # UI token / AppTheme
lib/core/theme/app_fonts.dart                                 # 字体选项
lib/features/home/home_page.dart, app_drawer.dart             # 首页 / 抽屉
lib/features/settings/{help_page,copyright_page,font_dialog}.dart
assets/Rikai_Icon.jpg                                         # 图标/启动页源图
android/app/src/main/res/drawable-nodpi/launch_icon.png       # 原生启动图标
android/app/src/main/res/mipmap-*/                            # launcher icons
lib/core/models/token.dart                                    # Token / 29 字段映射
lib/core/models/dict_info.dart                                # 词典注册表模型
lib/core/models/lookup_models.dart                            # lookup 结果分组
lib/core/models/ocr_model.dart                                # OCR 模型清单/状态模型
lib/services/ocr/model_manager.dart                           # 下载/续传/校验/导入
lib/services/ocr/ocr_service.dart                             # 懒加载/预热/指纹会话
lib/services/ocr/ocr_text_composer.dart                       # 原生行块 → 阅读文本
lib/services/capture/capture_storage.dart                     # 会话副本/旋转/删除
lib/features/capture/                                         # 相机/照片集/多选/保存/缩放查看
lib/features/capture/photo_pane.dart                          # 共用照片区/白色拖拽条
lib/features/capture/capture_corpus.dart                      # 照片语料 blocks JSON/保存
lib/features/onboarding/onboarding_page.dart                  # 首次启动引导/许可确认
lib/features/corpus/corpus_page.dart                          # 语料两列卡片/清空/复制
lib/features/corpus/corpus_detail_page.dart                   # 语料详情/文本语料/翻页
lib/services/storage/history_store.dart                       # 语料 SQLite/压缩/清空
test/history_store_test.dart                                  # 语料图片/block 纯函数测试
lib/features/settings/model_page.dart                         # OCR 模型/目录/迁移
lib/features/settings/dictionary_import_page.dart             # MDict 文件夹导入
lib/services/mdict/dictionary_scanner.dart                    # 递归扫描 isolate
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/     # Paddle/MangaOCR 原生实现
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/MangaOcrRecognizer.kt
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/TextLayoutHeuristic.kt
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/DocOrientationRecognizer.kt
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/TextLineOrientationRecognizer.kt
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/OcrTextQuality.kt  # 竖排候选评分
lib/core/utils/kana.dart                                      # 假名转换
lib/core/utils/text_normalizer.dart                           # NFKC/假名/stripkey 候选
lib/services/mecab/unidic_validator.dart                      # UniDic 目录/头部校验
lib/services/mecab/mecab_output_parser.dart                   # 引号感知 CSV 解析
lib/services/mecab/mecab_service.dart                         # 私有 rc + 长生命周期 isolate
lib/services/mdict/mdict_worker.dart                          # MDict isolate / lookup / MDD
lib/services/mdict/mdd_key.dart                               # MDD key 变体
lib/services/mdict/mdict_header.dart                          # MDX 版本/Encrypted=2 校验
lib/services/mdict/entry_renderer.dart                        # HTML 清洗/CSS/MDD 重写
lib/features/lookup/dictionary_filter_bar.dart                # 简称/单选多选/全选/3.5 行滚动
lib/core/models/lookup_match_mode.dart                        # 增量/完全/前方/后方匹配
lib/features/lookup/lookup_mode_menu.dart                     # 标题栏书籍图标搜索模式菜单
lib/state/lookup_preferences.dart                             # 全局词典选择（持久化）
lib/state/lookup_search.dart                                  # 应用生命周期查词状态
lib/core/models/dictionary_selection.dart                     # 单选/多选枚举
lib/core/ui/rikai_toast.dart                                  # 非阻塞底部提示
lib/core/ui/no_scrollbar_behavior.dart                        # 长 token 列表去滚动条
lib/core/theme/unfocus_route_observer.dart                    # 路由退出清焦点
lib/core/utils/date_format.dart                               # 语料日期 09.12/2025.09.12
lib/features/settings/storage_permission_prompt.dart          # 沙盒外路径授权引导
lib/core/theme/page_route.dart                                # 220ms 滑入路由
lib/services/storage/settings_store.dart                      # SharedPreferences 设置
lib/services/storage/dictionary_store.dart                    # 词典注册表持久化
lib/services/storage/permission_service.dart                  # 权限 MethodChannel Dart 侧
lib/features/reader/                                          # 文本阅读区/共享字号注音菜单/分行
lib/features/reader/reader_options.dart                       # 阅读页与照片集共用字号/注音菜单
lib/features/reader/reader_lines.dart                         # 文本按行分组 ReaderBlock
lib/features/lookup/                                          # 查词弹层/搜索/词条/WebView
lib/features/settings/settings_page.dart                      # UniDic/权限/显示设置
lib/features/settings/dictionary_page.dart                    # 词典管理
lib/state/providers.dart                                      # Riverpod providers
packages/mecab_for_dart/                                      # vendored MeCab（补丁见 MODIFICATIONS.md）
packages/rikai_ocr/                                           # OCR 插件 + ORT 原生实现
assets/models/manifest.json                                   # 模型清单（不含模型本体）
build/ocr-models/                                             # 本地模型测试下载（已忽略）
integration_test/ocr_android_test.dart                        # 横向/倾斜/竖向/90°/270°/180° OCR 设备测试
android/app/src/main/kotlin/com/rikai/mobile/MainActivity.kt  # 权限 MethodChannel 原生侧
android/app/src/main/AndroidManifest.xml                      # 文件权限
android/app/build.gradle.kts                                  # SDK/NDK 见 project-data §1
tool/spike_mdict.dart                                         # MDict 主机 spike
integration_test/mecab_android_test.dart                      # 设备端 MeCab/权限/UI 测试
integration_test/mdict_android_test.dart                      # 设备端 MDict/渲染/UI 测试
integration_test/mdict_compat_android_test.dart               # Encrypted=2/MDD 兼容测试
integration_test/mdict_audio_android_test.dart                # MDD sound:// 音频渲染测试
integration_test/ocr_real_images_android_test.dart            # test_images 真实图片扫描
third_party/overlay-translator/                               # Apache 许可/修改说明
third_party/paddleocr4android/                                # MIT 许可/可选后端说明
```

Phase 6 新增（P6.1–P6.5 已创建；`ocr_consensus.dart`、annotation、
markdown_renderer 等 P6.6/P6.7 文件待建）：

```text
lib/features/agent/                                           # Agent 页/输入/模式/证据卡/OCR 版本/档案 sheet
lib/services/agent/ports/                                     # Ocr/Tokenize/Lookup/Sample/Llm/Secret 窄接口
lib/services/agent/providers/                                 # OpenAI-compatible/Anthropic/Fake provider
lib/services/agent/familiarization/                           # 词典/UniDic 档案采样、生成、缓存
lib/services/agent/agent_orchestrator.dart                    # 固定 Stage 流水线
lib/services/agent/evidence_builder.dart                      # token/语法/ citation 证据包
lib/services/agent/citation_registry.dart                     # orchestrator 发放 source-N
lib/services/agent/agent_validator.dart                       # schema/quote/order/strict 校验
lib/services/agent/ocr_consensus.dart                         # 按需多 OCR/词典辅助修复
lib/services/agent/annotation/                                # 注音/标注安全 DSL 与统一渲染（P6.7）
lib/services/agent/markdown_renderer.dart                     # Markdown/ruby/声调安全渲染（P6.7）
lib/core/models/agent/                                        # input/evidence/analysis/profile/quote/tool DTO
lib/services/storage/agent_store.dart                         # 会话/消息/引用/OCR 版本/档案 SQLite
lib/services/security/secret_store.dart                       # API Key 安全存储
lib/services/lookup/lookup_gateway.dart                       # 纯查词提取（UI/Agent 共用）
assets/agent/grammar_patterns_ja.json                         # 语法模式白名单
assets/agent/dictionary_probes.json                           # 词典熟悉有界探针
assets/agent/prompts/                                         # Prompt 版本文件
```

开发数据（不入库）：

```text
C:\Projects\Rikai-Mobile\unidic\unidic-cwj-202512\
C:\Projects\Rikai-Mobile\mdicts\講談社 日本語大辞典 第二版 双解版\
```

文件大小、条目数、编码和资源统计见 `docs/project-data.md` §6。

## 7. 构建与验证

- 环境/版本/测试/性能基线统一见 `docs/project-data.md` §1–§5；本文件不重复具体值。
- 常规流程（在 `C:\Projects\Rikai-Mobile`）：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

- 设备端集成测试（MeCab/MDict/MDD 音频/OCR/真实图片）、模拟器启动、`adb push`
  数据、网络与 Gradle 缓存排障、字体/图标生成、release `--config-only` 步骤，
  全部见 `docs/dev-setup.md`；不要在常规代码工作中展开这些长命令。
- 构建前必须按 `assets/fonts/README.md` 放置 HarmonyOS Sans SC 字体；字体与模型
  文件不入库。修改 `assets/Rikai_Icon.jpg` 后运行
  `dart run flutter_launcher_icons`。
- Phase 6 自动化测试只用 fake provider；不得用真实 API Key 跑测试。P6.6 多 OCR
  和 P6.7 annotation DSL 的测试尚未编写；真实 provider/secure storage/真实词典
  sample/suggest 仍需设备验收。
- 每个阶段结束运行 analyze/test/debug build；当前测试数量、设备套件结果与构建
  产物见 `docs/project-data.md` §2/§3/§5。

## 8. 建议的下一个动作

1. 运行 `git status`；不要覆盖未提交改动，不要擅自 commit/reset，除非用户明确要求。
   历史提交锚点见 `docs/project-history.md`。
2. Phase 5 已结束（2026-10-30 用户确认并发布 1.0）；不要再把它当进行中。分发前
   替换 release debug keystore；可选增强只有语料缩略图/空错误态/无障碍。
3. Phase 6 P6.1–P6.5 已实现（见 `docs/phase6-status.md`）；下一步先按
   `docs/agent_docs/device-feedback-2026-10-31.md` 的 Wave 2–4 处理实机反馈
   F1–F17，再继续 P6.6 多 OCR 版本/词典辅助修复，最后做 P6.7 annotation DSL/
   Markdown/ruby/pitch/历史 UI/发布。不要重写已验证的 Paddle 横向路径或 MangaOCR
   基础流水线；新增 OCR 优化（mask/panel、cross-bubble batching、INT8 draft、
   tiling）应作为独立增强并补回归。
4. Phase 6 的真实 provider/API Key、secure storage 设备 I/O、真实词典
   `sample`/`suggest` 和 arm64 Agent 端到端仍未验收；不要把它们描述成已验证。
5. 进行实网模型下载验证（本机模拟器 DNS 不可用）：在可访问 hf-mirror 的设备上
   验证 PaddleOCR/MangaOCR/orientation 下载、断点续传、镜像回退、本地导入与许可
   确认；确认模型目录与删除流程。
6. 进行相机/照片集/多选/语料的 arm64 真机回归，重点验证 MangaOCR 竖排质量、
   连续多气泡页性能/内存，以及真实的 180°/90° 旋转照片；本机仅 x86_64。
7. 新 UI 必须遵循 `docs/design-tokens.md` 与 `app_tokens.dart`；不得硬编码
   颜色/字号，字体与模型文件不入库。Phase 6 的功能按钮/Agent UI 也必须先补
   token，不能直接改既有页面。
8. 每个阶段结束运行 analyze/test/debug build；当前测试数量、设备套件结果与构建
   产物见 `docs/project-data.md` §2/§3/§5，不要在阶段文档中重复具体数字；
   设备端测试命令见 `docs/dev-setup.md`。
