# CLAUDE.md — Rikai-Mobile handoff

> 给下一个 agent 的工作交接。本文件只保留项目摘要、架构决策、当前状态、关键文件与
> 构建/验证命令；文档用途和查阅时机统一在 §0 维护。
> 用户使用中文沟通；代码/标识符用英文。

## 0. 文档导航（先读这里）

> **权威层级**：规则 → `docs/project-rules.md`；当前数据/文案 →
> `docs/project-data.md`；视觉数值 → `docs/design-tokens.md`；误区/踩坑 →
> `docs/project_tips.md`；Agent 字段/错误码 → `docs/phase6-agent-contracts.md` +
> `docs/schemas/agent/`；架构决策 → `docs/adr/`；历史阶段 → `docs/phase*-status.md`。
> 冲突时按此层级修正低权威文档。正文只保留具体小节指针（如
> `docs/project-data.md` §6），不重复文档用途说明。
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
内容：UI 强制规范（颜色/字号/间距/圆角/组件/转场/Agent 对话式 UI）；实现入口
为 `lib/core/theme/app_tokens.dart`。
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
内容：构建/环境/数据/缓存/集成测试命令与排障步骤。
何时查看：搭环境、跑设备测试、处理 Gradle/权限/模型目录问题。

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
  （蓝/白、3x 设计稿 72/48/36 → Flutter 24/16/12sp、4pt 间距、紧凑组件）。
  实现入口是 `lib/core/theme/app_tokens.dart`；页面不得硬编码颜色/字号/间距。
  二次修正后：**所有页面**统一深蓝顶栏（`#003A99`、白字白图标、
  词条页 TabBar 白字），主页左侧抽屉为直角；主页**当前五个** 72dp 功能按钮
  使用与顶栏相同的深蓝色，图标+文字居中对齐，文字 32sp（比首版 40sp
  小 20%）。固定按钮文案见 `docs/project-data.md` §7。Phase 6 P6.5 已接入第五
  个按钮，当前代码与测试均为五个；后续 P6.6/P6.7 新 UI 仍须先补 token/测试。
  设置页为白底扁平分区、无卡片；长提示 14sp 必须完整换行，
  用户不可变信息用 16sp 纯文本；帮助/著作权为 16sp 正文 + 18sp 栏目标题
  + 分割线；查词结果的词典名/条目数 16sp 同色、词条标题 24sp。启动页居中
  显示 `assets/Rikai_Icon.jpg` 与真实加载阶段；字体可在抽屉中切换
  HarmonyOS Sans / 系统字体。
  阅读器阅读面、结果区与输入/分词/复制工具区**均为白色**；工具区底边
  仅用 1px `divider` 浅色细线收边（类似查词搜索栏下方），不改变工具区
  底色、不得形成厚重色块；输入框 `filled: false`。分词结果不使用灰色
  （内容词蓝700、功能词/标点近黑、振假名品牌蓝）。查词搜索框占位符为「搜索……」；
  阅读页查词弹层不设关闭叉，读音与词形相同时不显示蓝色读音。
  查词/查词弹层的词典筛选不再显示“查询词典”标题行；多选/单选胶囊在查词页
  放 AppBar，在查词弹层放标题行并与词条标题同 y 居中；AppBar 上未选中的
  多选/单选文字为白色。查词、阅读、照片集、语料列表/详情标题栏都有书籍图标的
  搜索模式菜单（增量/完全/前方/后方）。阅读页有分词结果时，工具栏左侧显示灰色
  「隐藏输入框」，隐藏后 AppBar 下方左侧出现 28dp 恢复图标，隐藏高度全部给结果区。
  **所有页面转场**使用全局 `SlideOverPageTransitionsBuilder`：新页面从右侧
  滑入覆盖静止的旧页面，禁止淡入淡出，避免深蓝顶栏出现白色残影。
  拍照页使用实时相机预览 + 半透明底部控制遮罩；照片集的删除/保存是**整个画面**
  左下/右下角的 52dp 圆形图标（删除错误色、保存深蓝 `header` + 白图标），
  保存/删除均二次确认；照片区可拖拽下边缘调整高度（纯白单色指示条），
  拖到最上方时图片完全隐藏、只保留 40dp 拖拽条，点击进入黑底全屏缩放查看；
  每张照片有独立 OCR 模式（默认自动），OCR 中仍可删除照片，旋转可连续打断；
  照片集标题栏只保留字号/注音菜单与一个「多选」入口，
  多选页沿用同一套图标。照片集不再有“分析句子”：拍照 OCR 后若已配置 UniDic，
  直接按文本阅读页 TokenChip 显示并点词查词；未配置时显示 OCR 原文；分词失败
  使用叠在照片顶部、标题栏下方的红色横幅（含重试），不占用 OCR 结果区。
  复制按钮在照片显示区右下角，为深蓝长条，文案「复制文本」；语料预览卡片
  右下角的复制按钮仍为「复制」。识别方向、旋转、模型设置、页码导航贴近页面
  底部，页码箭头中心与左下/右下角按钮中心同高。
  主页按 Column 顺序排列：使用前须知 → 功能按钮区 → 边界说明；不再把
  按钮在剩余空间垂直居中（按钮数量/文案见 `docs/project-data.md` §7）。Phase 6
  功能按钮已接入；后续调整按钮布局仍须先更新
  设计 token/小屏滚动规则，不能直接硬编码。语料列表为两列紧凑卡片（完整 contain 照片 + 最多 3 行 OCR +
  日期 + 右上删除 + 右下复制）；点开后进入「语料」详情：照片/分词、照片右下
  复制、语料间页码、左下删除，不显示 OCR 原文/日期，无多选/方向/模型设置/保存。
  列表与详情标题栏右上角都有字号/注音菜单，分词字号随之变化。
  首次启动进入 `/onboarding`：深蓝顶栏、欢迎区、本地边界说明、准备清单
  （权限/UniDic/MDict/OCR 模型）、许可确认 Checkbox 与「开始使用/跳过」；
  已有 UniDic 路径的旧安装视为已完成。文本阅读保存的语料没有照片时，卡片和
  详情显示「文本语料」占位及复制按钮，不显示损坏图片。设置页新增「语料与存储」
  （自动保存识别结果、清空语料、清除词典资源缓存）与「关于与帮助」（帮助、
  著作权与许可、重新查看新手引导）分区；继续白底扁平、无卡片。
- **字体**：HarmonyOS Sans SC Regular，路径
  `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`。字体文件**不入库**（`.gitignore`
  已忽略）；用户自行从华为 HarmonyOS 设计资源下载，见 `assets/fonts/README.md`。
  构建前必须存在，否则 Flutter 报缺失资产。应用图标源 `assets/Rikai_Icon.jpg`
  由 `flutter_launcher_icons` 生成 Android 图标（配置在 `pubspec.yaml`）。
- 仓库已有多次提交（`d0d94a3`、`dc70cee`、`91dc386`、`deb6484`、
  `b12d24f`、`95f90e0`、`9e17984`、`f287603`、`c2ae03d`、`4d0100f`、`1e25750`、
  `b2ed785`、`1c7096b`、`979d1de`、`2534c3a`）。Phase 4 为 `f287603`，Phase 6
  文档为 `c2ae03d`，Phase 4.5 初版为 `4d0100f`；第二轮设备反馈修复为 `b2ed785`，
  横屏/搜索/采集改动为 `979d1de`，Phase 5（引导/语料/设置/发布）为 `2534c3a`。
  Phase 6 P6.1–P6.5 已提交（自 `7be4b81` 起；后续 docs/Wave 1 修正见 `git log`）。
  当前工作区如有后续评审/反馈改动，以 `git status` 为准。不要擅自 `reset`/`commit`，
  除非用户明确要求。

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

## 3. 当前进展（Phase 0–4 + Phase 3.5 已完成）

已完成：

- Flutter Android 工程、依赖、Material 3 首页、go_router 路由。
- Phase 0 基建：vendored MeCab/native assets、`rikai_ocr` 骨架（MethodChannel
  `rikai/ocr`、ORT 1.28.0）、模型 manifest、许可证、文档。
- Phase 1（本次完成）：
  - `lib/core/models/token.dart`：29 字段映射、注音优先级、查词候选、
    内容词/功能词分类、UTF-16 offset。
  - `lib/services/mecab/unidic_validator.dart`：校验 5 个必需文件、`sys.dic`
    magic/size、版本 102、UTF-8、词条数与声明长度。
  - `lib/services/mecab/mecab_output_parser.dart`：**引号感知 CSV 解析**，
    修复 `"動詞%F2@1,形容詞%F4@-2"` 这类字段被误拆的问题。
  - `lib/services/mecab/mecab_service.dart`：私有 `mecabrc`、长生命周期
    isolate、串行 analyze、按行分词保留换行、错误码/超时、优雅释放。
  - `lib/features/reader/*`：文本输入、`ReaderBlock`/`TokenChip`/
    `FuriganaText`、内容词高亮、注音开关、字号、复制全文、token 详情。
  - `lib/features/settings/settings_page.dart`：UniDic 路径/校验/权限引导、
    注音/字号设置。
  - All Files Access 原生 MethodChannel `rikai/storage_permission`
    （`MainActivity.kt`）；Android 11+ 检查/跳转，API ≤29 申请读取权限。
  - `integration_test/mecab_android_test.dart`：权限通道、真实 UniDic、
    长文本、UI 注音渲染共 4 项设备测试。
- Phase 2（本次完成）：
  - `lib/services/mdict/mdict_worker.dart`：长生命周期 worker isolate；
    `probe`/`lookup`/`resource`/`close`；懒打开、`@@@LINK` 最多 3 层、
    多词形候选、前缀建议、MDD 资源、错误码。
  - `lib/core/models/dict_info.dart` + `lib/services/storage/dictionary_store.dart`
    + `lib/state/providers.dart`：词典注册表、原地路径、同目录 MDD（同名）/
    CSS（目录内全部）发现、启用/排序/重新校验/删除；不复制文件。
  - `lib/core/utils/text_normalizer.dart`：NFKC、全半角、大小写、平/片假名、
    stripkey 候选。
  - `lib/services/mdict/mdd_key.dart`：MDD key 前导反斜杠/斜杠转换、file://
    与 percent-encoding 处理。
  - `lib/services/mdict/entry_renderer.dart` + `lib/features/lookup/*`：
    HTML 清洗、CSS 注入、MDD 图片缓存与 `file://` 重写、离线 WebView
    （JS/网络关闭，`entry://` 导航，外部链接拦截）、词条页多词典 Tab、
    阅读区查词弹层、搜索页、词典管理页。
  - `docs/design-tokens.md` + `lib/core/theme/app_tokens.dart`：蓝/白 token、
    3x 72/48/36 → 24/16/12sp、4pt 间距、紧凑组件、TDesign 映射；已迁移
    既有 UI。HarmonyOS Sans SC 字体按用户要求**不入库**。
  - 中期 UI/功能修正（`项目初始文档.txt`）：
    - `lib/bootstrap.dart` 启动页：应用图标 + 主界面/已安装词典/分词功能阶段；
      启动时预热已启用词典（MDict worker 常驻），修复首次跳词条卡顿。
    - `flutter_launcher_icons` + `assets/Rikai_Icon.jpg` 生成桌面图标；
      原生启动背景也显示图标。
    - **所有页面**统一深蓝顶栏（白字/白图标，TabBar 白字）；主页抽屉直角；
      主页功能按钮与顶栏同色、图标+文字居中、32sp（比首版 40sp 小 20%）。
    - 设置页改为白底扁平分区（无卡片、无组件套组件）：MDict → 阅读显示 →
      UniDic → 存储权限；UniDic 输入框与按钮直接位于页面；长提示独立 14sp
      文本完整换行；应用外部私有目录用 16sp 纯文本；权限提示 14sp 可换行。
    - 帮助/著作权改为纯文本：正文 16sp、栏目标题 18sp、栏间分割线，无卡片。
    - 查词结果：词典名/条目数 16sp 同色（与“查看全部”一致）、词条标题 24sp、
      摘要 14sp；点击单条只显示该条，≥2 条显示“查看全部（N 条）”。
    - 阅读页示例 `何卒宜しくお願い致します。`、去掉标题栏复制、居中分词、
      隐藏词数、输入草稿在整个应用生命周期保留；词性中的 `*` 不显示。
    - 每词典词条上限可在设置中配置（默认无限制）。
    - 渲染结果 LRU 缓存 + 启动预热；`EntryPage` 单/多词条按选择展示。
    - 字体可切换 HarmonyOS Sans / 系统默认（持久化）。
    - 阅读器打磨：阅读面、结果区与输入/分词/复制工具区均为纯白；工具区
      底边仅 1px `divider` 浅色细线（类似查词搜索栏下方）；输入框无填充；
      长文滚动不再出现厚重色块；分词结果不使用灰色（内容词蓝700、
      功能词/标点近黑、振假名品牌蓝）。
    - 查词搜索框占位符改为「搜索……」；阅读页查词弹层移除右上角关闭叉；
      读音与词形相同时不显示蓝色读音行。
    - **所有页面**改用全局右滑覆盖转场
      （`SlideOverPageTransitionsBuilder`）：新页面从右侧滑入覆盖旧页面，
      旧页面不移动、不淡出，避免深蓝顶栏出现白色残影。
    - `file_picker` 的文件选择会复制到 cache，词典路径改用目录选择器，
      保持原地读取。
    - **重要坑**：`flutter test integration_test/...` 会把
      `build/app/outputs/flutter-apk/app-debug.apk` 覆盖成集成测试入口 APK；
      手动安装前必须重新 `flutter build apk --debug`，否则应用会停在系统
      启动图（不是业务代码卡死）。
- Phase 3（本次完成）：
  - `packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/`：
    `RikaiOcrPlugin.kt`（MethodChannel `rikai/ocr` + EventChannel
    `rikai/ocr_progress`，串行识别、取消、进度）、`PaddleOcrEngine.kt`
    （PP-OCRv5 det/rec、EXIF/最长边 2048、960px DBNet、CTC、四点框）、
    `DBPostprocessor.kt`、`PaddleRotateCrop.kt`、`CtcDictionary.kt`。
    应用级单例 `OrtEnvironment`；不关闭共享环境。
  - `lib/services/ocr/model_manager.dart` + `lib/core/models/ocr_model.dart`：
    模型清单、`getExternalFilesDir()/models`、hf-mirror → HF、HTTP Range
    续传、大小/SHA-256 校验、本地导入/删除；`--dart-define=
    RIKAI_OCR_MODELS_DIR` 仅用于开发验证。
  - `lib/features/capture/*`：实时相机、连续拍摄/相册多选、照片集、
    OCR 缓存、多选批量操作；结果经 `ReaderRouteArgs` 进入阅读器。
  - `lib/features/settings/model_page.dart`：PaddleOCR/MangaOCR/方向模型
    状态、下载、本地导入、删除、模型目录/迁移（Phase 4 已把 MangaOCR 接入
    识别流水线）。
  - 主页拍照入口已接入 `/capture`；设置新增 OCR 模型入口。
  - OCR 结果已验证进入真实 UniDic 分词与点击查词流程；Phase 3 阶段仅横向，
    纵向在 Phase 4 接入。
- Phase 3.5（2026-10-29，本次完成，详见 `docs/phase3.5-status.md`）：
  - 修复 `docs/phase3-review.md` 的 H1–H3、M1–M7、L1–L10（P1 留 Phase 4）：
    本地模型导入按角色/大小匹配、取消 exactly-once、全量 SHA-256、会话复用、
    416/Content-Range 续传安全、OOM、只读状态、旧模型状态、离开页面取消等。
  - 实时相机 `camera` 插件、照片集/多选、照片+模式+模型指纹缓存、
    屏幕左下/右下角删除/保存、语料保存与语料页。
  - MDict 文件夹递归导入（isolate 扫描、预检、可导入/已存在/不支持、
    进度/取消）；扫描行不再显示 MDD/CSS 英文尾注，导入完成直接回词典管理页
    且不弹结果对话框。模型目录可配置、校验、默认迁移、仅切换。
  - 照片集 OCR 后自动分词（已配置 UniDic 时按阅读器 TokenChip 展示）、
    字号/注音、照片区下边缘拖拽调高、全屏缩放查看；复制改为照片右下角深蓝
    长条；分词错误为照片顶部红色横幅；模式保存在会话中。
  - OCR 缓存使用应用级模型指纹快路径：从模型设置、多选页或其它页面返回时，
    模式/指纹一致直接显示缓存；多选页只补识别未缓存照片。
  - 语料列表改为完整大照片 + 右上角红色圆形删除 + OCR + 日期；新增语料详情页，
    展示照片/OCR/分词并支持语料间翻页，仅左下删除、无保存/多选/方向/模型设置。
  - MDict 扫描/导入不再显示 `Instance of ...` 等调试英文；词典标题也会过滤
    此类字符串。
  - 阅读页查词键盘行为修复；OCR 阅读页使用本地草稿控制器。
- Phase 4（2026-10-29，本次完成，详见 `docs/phase4-status.md`）：
  - 新增 `MangaOcrRecognizer.kt`：复用 DBNet quads，按边缘距离聚成漫画气泡，
    crop planner 每 224×224 最多 6 个文本 band；encoder 一次、FP32 decoder
    贪心最多 48 token；输出气泡级 block，按“上→下、右→左”排序。
  - `PaddleOcrEngine` 独立加载可选 MangaOCR/orientation 模型；横向始终可用。
    `vertical` 缺少 MangaOCR 返回 `MODEL_MISSING`（中文下载提示），`auto`
    在模型缺失时回退横向。
  - 自动方向：`TextLayoutHeuristic` 按框几何/堆叠列路由；可选
    `DocOrientationRecognizer` 提供高置信 90/270 竖向提示；可选
    `TextLineOrientationRecognizer` 对横向行投票，单行高置信或两行多数
    180° 时旋转图片并重新检测，修复倒置照片。
  - Dart：`OcrRuntimePaths`、`runtimePaths`、`fingerprintForPaths` 把可选模型
    纳入照片集缓存指纹；`OcrService` 透传可选路径并暴露 `mangaReady`。
  - 模型页允许下载 MangaOCR，下载前确认许可未声明；照片集「竖向」启用，
    helper 根据 MangaOCR 是否就绪显示自动路由或下载提示。
  - 设备合成测试：自动/手动竖向均通过并输出 `これはテストです`；倒置横向页
    180° 重跑后输出 `ありがとう`。设备/性能数据见 `project-data` §3–§4。
- Phase 4.5（2026-10-29 实现，2026-10-30 arm64 验收通过，详见
  `docs/phase4.5-status.md`）：
  - **按需加载**：`PaddleOcrEngine.initialize` 只加载 Paddle；MangaOCR/
    orientation 路径注册但不建 session；`prepare(mode)` 后台预热。照片集
    `OcrService.prewarm` 在缓存/识别完成后预加载；横向模式不加载 Manga。
  - **readiness 拆分**：`mangaAvailable`/`mangaLoaded`、
    `docOrientationAvailable`/`Loaded`、textline 同理；旧 `mangaReady` 继续
    表示“已安装/可用”，不是 session 已加载。
  - **指纹/校验**：`runtimePaths`/`status` 先看存在+大小；SHA-256 只在下载/
    导入/迁移，`_verifiedFileStats` 按路径+size+mtime 缓存。`OcrService.ensureReady`
    单飞、会话内复用，模型页返回用 `refresh: true`。
  - **方向**：doc orientation 返回 angle/probability/margin；仅在
    landscape+vertical 或 portrait+horizontal 时运行；高置信 90/270 旋转整图并
    重新 DBNet。textline 180° 只在 auto 横向运行。
  - **auto 单引擎**：几何/方向选择后只跑 Paddle 或 Manga；Manga 平均置信度
    <0.75 时自动回退 Paddle；模式切换 `force` 重新 OCR，不复用旧缓存。
  - **Manga 质量**：气泡 gap/padding 按中位框尺寸自适应；竖向 crop 最多 3 个
    text band；清除控制/替换字符，丢弃低置信度气泡。
  - **缓存/交互**：手动横向可复用 auto 的 `paddle_v5` 结果，手动竖向可复用
    `manga_ocr` 结果；照片集“旋转”旋转私有副本 90°、清该照片 OCR 缓存。
  - 设备 OCR 套件（横向、6° 倾斜、lazy、Manga、90°、270°、倒置 180°、取消）
    在 x86_64 全部通过；具体套件数、耗时和真实图片结果见 `project-data` §3–§4。
    2026-10-30 用户确认 arm64/真实设备验收通过。
  - 第二轮设备反馈（2026-10-29）：MDD `sound://` 转为本地 `<audio>`；
    词典选择全局持久化、预留 3.5 行（第 4 行半可见）滚动、选中不漂移；查词状态跨页面保留；
    键盘焦点路由清理；非阻塞 `RikaiToast`；竖排双引擎评分；OCR 日文空格
    清理；长文本懒加载/去滚动条；旋转自动中断 OCR；语料日期格式；删除
    对话框统一复选框。冷启动真实图片复跑结果、MDD 音频测试结果见
    `project-data` §3–§4；详见 `docs/phase4.5-status.md`。
  - 横屏/布局收敛（2026-10-30）：批量导入扫描完成隐藏说明/状态；手动词典
    对话框不自动弹键盘；词条上限对话框可滚动到 10；照片区拖到顶部隐藏图片、
    保留 40dp 拖拽条；查词筛选去掉“查询词典”、模式胶囊进 AppBar/弹层标题行；
    阅读页可隐藏输入工具栏并在 AppBar 下方左侧恢复。新增竖屏/横屏 widget
    测试。
  - 搜索/采集精度轮（2026-10-30）：UniDic 支持父目录/matrix.bin 模糊查找，
    多有效目录用路径选择框；OCR 模型支持单模型目录/总目录自动解析；帮助页
    增加 MDict/UniDic 官方入口；所有查词界面增加书籍图标的增量/完全/前方/
    后方匹配模式；照片 OCR 模式改为逐照片独立；OCR 中允许删除；旋转可连续
    打断；语料详情去掉“分词结果”标题；TokenChip 去掉每词 Material/InkWell
    以减少长列表卡顿。
- Phase 5（2026-10-30 完成并由用户确认，详见 `docs/phase5-status.md`）：
  - 首次启动引导 `/onboarding`：本地边界、存储权限、UniDic、MDict/OCR 模型
    入口、许可确认、开始/跳过；已有 UniDic 路径视为已完成；设置可重新打开。
  - 语料：阅读页可保存纯文本文本；照片保存前 EXIF 校正、最长边 2048、JPEG 85；
    `HistoryStore.clear/imageBytes`；语料页可清空全部；文本语料无照片时显示
    「文本语料」占位；自动保存开关默认关闭，按照片+模式+文本做会话内去重。
  - 设置：「语料与存储」自动保存/清空语料/清除 MDict 资源缓存；
    「关于与帮助」帮助、著作权与许可、重新查看新手引导；新增 `/help`、
    `/copyright` 路由。
  - 新增测试 `onboarding_test`、`history_store_test`（纯图片压缩/block JSON，
    不依赖桌面 SQLite）、`reader_save_test`；Phase 5 当时的测试/构建记录见
    `docs/project-data.md` §2.2/§5。arm64 release APK 已构建，新界面真机
    验收待完成。

已验证：

历史测试/设备/性能/构建数据统一见 `docs/project-data.md` §2–§5；各阶段细节见对应 `phase*-status.md`。

**当前阶段状态：**

- **Phase 4.5 已完成**：2026-10-30 用户确认 arm64/真实设备验收通过；设备性能
  数据以用户验收记录为准。
- **Phase 5 已完成**：首次启动引导、文本/照片语料保存、自动保存开关、图片压缩、
  语料清空/删除、设置存储/许可入口和 arm64 release APK 已完成；Phase 5 的
  测试/构建记录见 `docs/project-data.md` §2.2/§5；用户于 2026-10-30 在冷启动
  x86_64 模拟器上确认测试通过。
- **Phase 6 P6.1–P6.5 已完成核心实现**：能力 Ports、LookupGateway/
  MDict sample/suggest、Provider 适配与 secure storage、词典/UniDic
  熟悉期、Orchestrator/证据/quote/校验、Agent 页面/Provider 设置/主页新增入口。
  当前测试/构建/设备基线见 `docs/project-data.md` §2/§3/§5；x86_64 模拟器已用
  真实相册图片 + 用户配置的 DeepSeek 跑通“实时思考/生成 → 中文译文/逐句/原文/
  词典依据”。
- Phase 6 未完成：**2026-10-31 实机反馈 Wave 2–4**（默认中文/UI 语言（决策已定、实现待做）、应用级
  档案确认队列、多图、结果操作行、检索完整度/覆盖审查等；Wave 1 的 F4/F5/F9/
  F10/F15/F16 已实现，设备手工验收待 Wave 4；测试/构建基线见
  `docs/project-data.md` §2/§5）、
  P6.6 多 OCR 版本/词典辅助修复、P6.7 annotation DSL/Markdown/ruby/pitch、
  Agent 会话历史 UI、真实 provider/API Key 与真实词典 sample/suggest 设备验收。
  详见 `docs/agent_docs/device-feedback-2026-10-31.md` 和
  `docs/phase6-status.md`。

**下一步：**

- Phase 6：继续按 `docs/agent_docs/device-feedback-2026-10-31.md` 的 Wave 2–4
  处理实机反馈；F2（档案队列）完成前不要做 F7/F13/F14 的档案相关部分，F6 完成
  前不要做 F7。之后再做 P6.6/P6.7；未实现能力仍不得写成已支持。
- 分发前：release 仍使用 debug keystore，替换正式签名；Phase 5 可选增强
  （语料缩略图、更多空/错误态、无障碍细化）。
- 本开发环境只有 x86_64 模拟器 `Medium_Phone_API_36.1`；Phase 5 UI 已在冷启动
  模拟器确认，OCR 性能/真实漫画质量仍需 arm64 真机复测。
- 本机模拟器 DNS 无法解析 hf-mirror/Hugging Face，因此“应用内实网下载模型”
  尚未在设备验证；主机 curl 成功，Dart 本地 HTTP 测试已覆盖 Range 续传/校验。
- MangaOCR 仍未移植上游 mask/panel/free-text 全流水线，也没有 cross-bubble
  batching/INT8 draft/密集页 tiling；90/270 已实现整图旋转，但真实页仍需调参。

## 4. 未尽事宜（按优先级）

### 已完成：UniDic/MeCab + Phase 1

实现与验收记录见 §3、§6 和 `docs/phase1-status.md`。不要重写：

- 私有 `mecabrc` + `-r` 已在 Android 实测成功；
- 大型 UniDic 外部存储 mmap 可用（数据规模见 `docs/project-data.md` §6）；
- 29 字段映射与引号 CSV 解析已由真实词典验证；
- All Files Access 原生通道已实现。

### 已完成：ORT 模型冒烟（PaddleOCR）

- 主机 Python ORT 与 Android x86_64 合成图片冒烟均通过；模型形状、字符表
  数量、耗时与置信度见 `docs/project-data.md` §4/§6。
- MangaOCR encoder/decoder 已在 Phase 4 完成设备冒烟（合成竖排气泡
  `これはテストです`）；模型许可未声明，不随包分发。

### 已完成：Phase 2

实现与验收见 §3、§6 和 `docs/phase2-status.md`。不要重写 MDict worker、
lookup/`@@@LINK`、EntryRenderer、搜索/词条/词典管理页。已知限制：
每词典词条上限可在设置中配置（默认无限制）、CSS 发现为目录内全部、
MDD 缓存未清理、无模糊搜索。

### 已完成：Phase 3 横向 PaddleOCR + 拍照

实现与验收见 `docs/phase3-status.md`。不要重写：

- 原生 OCR 代码在 `packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/`；
  已由真实 PP-OCRv5 det/rec 和合成图片设备测试验证。
- 模型是运行时下载/本地导入，不入库；native 只接收本地路径。
- `vertical` 模式已由 Phase 4 接入；不要把它改回 `UNSUPPORTED_MODE`，也不要在
  缺少 MangaOCR 时静默走横向（手动竖向必须明确提示下载模型）。
- 采集页和模型页属于已验收 UI；不要把模型二进制放回 assets 或提交。
- 已知限制：模拟器 DNS 导致实网下载未验证；无 arm64 真机。

### 已完成：Phase 4 纵向 MangaOCR + 自动方向

实现与验收见 §3、§6 和 `docs/phase4-status.md`。当前实现：

- `MangaOcrRecognizer.kt`：复用 DBNet quads、气泡聚类、crop planner、
  ViT encoder + FP32 greedy decoder、纵向 RTL 排序；
- 自动模式：框几何 + 可选 doc/textline orientation；手动竖向/横向覆盖；
  可选 textline 180° 重跑；
- 模型缺失时横向仍可用；手动竖向给出下载提示；
- 已知限制：未移植上游 mask/panel/free-text 完整流水线、无 INT8 draft、
  90/270 文档方向未做整图旋转、无 arm64 真机。

### Phase 4.5：OCR 质量与性能收敛（已完成，2026-10-30）

先读 `docs/phase4.5-status.md`。已完成：

- 可选模型懒加载、`prepare` 预热、readiness available/loaded 拆分；
- stat 优先指纹/校验，SHA-256 按文件修订缓存；
- 90/270 整图旋转 + 重新 DBNet；doc 模型只在长宽比与布局矛盾时运行；
- auto 单引擎（Paddle 或 Manga），Manga 低置信度自动回退 Paddle；模式切换
  强制重新 OCR；
- 2°–12° 轻微 deskew；Manga 尺寸自适应 gap/padding、竖向 3 band 上限和低置信
  度过滤；
- 手动模式安全复用 auto 缓存；照片集“旋转”入口；
- 设备反馈修复：MDict Encrypted=2/MDD、词典搜索单选多选与简称、词条标题、
  权限引导、拍照提示、语料卡片、下载后台/断点/清理、WebView 退出闪帧等，
  详见 `docs/phase4.5-status.md` 的 Device-feedback 小节。

验收已通过（2026-10-30）。后续 OCR 调优时仍需在真机复测：

- 横排 2048px <5s、单页漫画 <10s、无 OOM；
- 横排/竖排/倒置/90°/270° 真实页面回归；
- 真实漫画多气泡/多面板顺序、振假名噪声、低置信度垃圾文本；
- 首次 auto/vertical 冷启动仍有 Manga session 创建成本（x86_64 约 1.1s）；
- 视情况继续做 panel grouping、cross-bubble batching、密集页 tiling。

### Phase 5：语料保存/打磨/发布（已完成，2026-10-30）

先读 `docs/phase5-status.md`。已完成：

- 首次启动引导（本地边界 → 权限 → UniDic → 词典可选 → 模型可选 →
  许可确认；可跳过，设置可重开；已有 UniDic 路径视为已完成）。
- `HistoryStore`：文本语料、图片 EXIF 校正/2048/JPEG 85、清空、图片占用统计、
  同毫秒稳定排序；语料页清空入口；文本语料无照片占位。
- 阅读页“保存到语料”；照片集/多选页共用 `capture_corpus.dart`；
  “自动保存识别结果”默认关闭，按照片+模式+文本做会话内去重。
- 设置“语料与存储”和“关于与帮助”分区；MDict 资源缓存清理；`/help`、
  `/copyright` 路由。
- Phase 5 的测试/构建记录见 `docs/project-data.md` §2.2/§5；用户于 2026-10-30
  在冷启动模拟器确认首次引导/语料/设置流程。

分发前仍需：

- Release 仍用 debug keystore（`android/app/build.gradle.kts` TODO），替换正式签名。
- 可选：语料缩略图、更多空/错误态、无障碍细化。

### Phase 6：Mdict Agent（设计 v2；P6.1–P6.5 已实现，P6.6/P6.7 未实现）

先读 `docs/phase6-agent-design.md`、`docs/phase6-agent-contracts.md` 和
`docs/phase6-status.md`；本节只给交接摘要，细节以设计/契约/状态文档为准。
Phase 5 已完成并发布；Phase 6 P6.1–P6.5 已实现，P6.6/P6.7 待做。

- 主页功能按钮已接入（数量/固定文案见 `docs/project-data.md` §7）；当前代码与
  测试已同步。
- Agent 使用本地 OCR/UniDic/MDict 能力 + 用户配置的远程 LLM；DeepSeek/Claude/
  OpenAI-compatible 均通过 provider 适配层，不依赖 provider 的视觉能力。
- 固定流水线、模型无工具（2026-10-31 决策并删除死工具层）：orchestrator 预取
  OCR/分词/逐词查词；模型只做理解、推断和引用已有证据，不自行补查。OCR/采样/
  UniDic profile 全部由 orchestrator 调用。
- 语言：默认输出/UI 中文（zh）；旧 `follow` 映射为 `zh`；禁止按输入假名/拉丁
  字符推断（2026-11-01 决策；F1/F17 代码待改，见 `docs/phase6-status.md`）。
- 能力接口化：窄 Port（Ocr/Tokenize/Lookup/DictionarySample/Llm/Secret）包住现有
  `OcrService`/`MecabService`/`MdictService`；提取纯 `LookupGateway`，UI 与 Agent
  共用查词内核，不复制查词逻辑。`OcrWorkflow` 无生产调用，已于 2026-10-31 删除。
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

## 7. 环境、构建与验证

- 环境/版本/测试/性能基线统一见 `docs/project-data.md` §1–§5；以下只保留构建/
  设备测试命令与历史验证记录，不再重复当前数值。NDK 由
  `android/app/build.gradle.kts` 固定，数值见 `docs/project-data.md` §1。
- 构建命令（在 `C:\Projects\Rikai-Mobile`）：

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

- 设备端集成测试（真实 UniDic；Git Bash 必须禁用路径转换）：

```bash
export MSYS_NO_PATHCONV=1
flutter test integration_test/mecab_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_UNIDIC_PATH=/sdcard/Download/unidic-cwj-202512
```

  测试会在安装后/卸载前短暂存在；需用后台循环重新授予
  `MANAGE_EXTERNAL_STORAGE`，详见 `docs/dev-setup.md`。
  **测试会覆盖 `app-debug.apk` 为测试入口 APK；手动安装前必须重新
  `flutter build apk --debug`，否则会停在系统启动图。**
- 设备端 MDict 测试（把词典以 ASCII 名 push 到
  `/sdcard/Download/rikai-mdict/{dict.mdx,dict.mdd,dict.css}`）：

```bash
export MSYS_NO_PATHCONV=1
flutter test integration_test/mdict_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_MDICT_PATH=/sdcard/Download/rikai-mdict/dict.mdx
```

  同样需要 appops 授权循环；MDX/MDD 必须同 basename 才会自动发现。
- 设备端 MDD 音频测试（把 `日本語文型辞典 三语音频版` 的 `.mdx/.mdd` 以
  `dict.mdx/dict.mdd` push 到 `/sdcard/Download/rikai-mdict-audio/`）：
  `flutter test integration_test/mdict_audio_android_test.dart -d <device>`。
  测试查找词条 `あくまで` 的 `sound://xxxx.aac`、读取 MDD 资源并断言渲染出
  本地 `<audio>`；扬声器是否出声仍需人工确认。
- 设备端 OCR 测试（真实模型按 `paddle_v5/`、`manga_ocr/`、`orientation/`
  放在 `/sdcard/Download/rikai-models/` 下；测试脚本会自动寻找
  `paddle_v5` 的父目录中的可选模型）：

```bash
export MSYS_NO_PATHCONV=1
flutter test integration_test/ocr_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_OCR_MODEL_DIR=/sdcard/Download/rikai-models/paddle_v5
```

  同样需要 appops 授权循环。当前套件 8 项：横向、6° 倾斜、横向懒加载、
  MangaOCR（自动+手动）、90°、270°、倒置横向 180°、取消。应用内模型默认目录是
  `getExternalFilesDir()/models/`；模型不入库，下载/导入见
  `docs/phase4-status.md`。开发验证可用
  `--dart-define=RIKAI_OCR_MODELS_DIR=/sdcard/Download/rikai-models`。
- 字体：构建前按 `assets/fonts/README.md` 下载 HarmonyOS Sans SC 到
  `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`（不入库）。
- 图标：修改 `assets/Rikai_Icon.jpg` 后运行 `dart run flutter_launcher_icons`；
  它会更新 `mipmap-*` 与 `colors.xml`，不要手改生成结果。
- Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`。
- Release（需要时）：`flutter build apk --release --target-platform android-arm64 --split-per-abi`。
- 模拟器：`flutter emulators --launch Medium_Phone_API_36.1`（x86_64）。
- 真机/模拟器数据：

```bash
adb shell mkdir -p /sdcard/Download
adb push unidic/unidic-cwj-202512 /sdcard/Download/
adb push "mdicts/講談社 日本語大辞典 第二版 双解版" /sdcard/Download/
```

应用内授予“所有文件访问”后填写：

- UniDic：`/sdcard/Download/unidic-cwj-202512`
- MDX：`/sdcard/Download/講談社 日本語大辞典 第二版 双解版/講談社 日本語大辞典 第二版 双解版.mdx`

- 网络：Maven Central/dl.google/pub.dev 可用；GitHub 直连超时；HF 直连超时；
  **主机 curl hf-mirror.com 可用**（模型默认镜像）。当前模拟器 DNS 无法解析
  `hf-mirror.com`/`huggingface.co`，所以应用内实网下载需换网络或真机验证；
  本地 HTTP 测试服务器已验证 Range 续传/校验。maven.google.com 超时，但
  Gradle `google()` 走 dl.google.com，正常。
- Gradle 全局脚本缓存曾损坏（`metadata.bin` 缺失）。修复：
  `cd android; .\gradlew --stop;` 然后把
  `%USERPROFILE%\.gradle\caches\8.14\{kotlin-dsl,groovy-dsl,transforms,generated-gradle-jars,dependencies-accessors}`
  移走并重建；不要动 `modules-2`。详见 `docs/dev-setup.md`。
- Windows 主机 `dart run tool/spike_mdict.dart` 在根包会触发 MeCab native-assets
  hook 失败；用隔离 Dart 包运行（复制脚本 + 只依赖 `dict_reader`）。
- Phase 6 P6.1–P6.5 的自动化测试已加入：fake provider、请求体无图片/路径断言、
  citation/quote/strict 校验、熟悉文档复用/失效、provider payload、Agent page/
  result view。不得用真实 API Key 跑自动化测试。P6.6 多 OCR 和 P6.7 annotation
  DSL 的测试尚未编写；真实 provider/secure storage/真实词典 sample/suggest 仍需
  设备验收。

## 8. 建议的下一个动作

1. 运行 `git status`；Phase 4 为 `f287603`，Phase 6 文档为 `c2ae03d`，
   Phase 4.5 初版为 `4d0100f`，上一轮修复为 `1e25750`，第二轮设备反馈为
   `b2ed785`，横屏/搜索/采集为 `979d1de`，Phase 5 为 `2534c3a`；Phase 6
   P6.1–P6.5 已提交（自 `7be4b81` 起；后续 docs/Wave 1 修正见 `git log`）。
   当前工作区如有后续评审/反馈改动，以 `git status` 为准；不要覆盖或擅自 commit，
   除非用户明确要求。
2. Phase 5 已结束（2026-10-30 用户确认并发布 1.0）；不要再把它当进行中。
   分发前替换 release debug keystore；可选增强只有语料缩略图/空错误态/无障碍。
3. Phase 6 P6.1–P6.5 已实现（见 `docs/phase6-status.md`）；**下一步先按
   `docs/agent_docs/device-feedback-2026-10-31.md` 的 Wave 1–4 处理 2026-10-31
   实机反馈 F1–F17**，再继续 P6.6 多 OCR 版本/词典辅助修复，最后做 P6.7
   annotation DSL/Markdown/ruby/pitch/历史 UI/发布。不要重写已验证的 Paddle
   横向路径或 MangaOCR 基础流水线；新增 OCR 优化（mask/panel、cross-bubble
   batching、INT8 draft、tiling）应作为独立增强并补回归。
4. Phase 6 的真实 provider/API Key、secure storage 设备 I/O、真实词典
   `sample`/`suggest` 和 arm64 Agent 端到端仍未验收；不要把它们描述成已验证。
5. 进行实网模型下载验证（本机模拟器 DNS 不可用）：在可访问 hf-mirror 的
   设备上验证 PaddleOCR/MangaOCR/orientation 下载、断点续传、镜像回退、
   本地导入与许可确认；确认模型目录与删除流程。
6. 进行相机/照片集/多选/语料的 arm64 真机回归，重点验证 MangaOCR 竖排质量、
   连续多气泡页性能/内存，以及真实的 180°/90° 旋转照片；本机仅 x86_64。
7. 新 UI 必须遵循 `docs/design-tokens.md` 与 `app_tokens.dart`；不得硬编码
   颜色/字号，字体与模型文件不入库；**所有页面**统一深蓝顶栏和右滑覆盖转场。
   Phase 6 的功能按钮/Agent UI 也必须先补 token，不能直接改既有页面。
8. 每个阶段结束运行 analyze/test/debug build；当前测试数量、设备套件结果与构建
   产物见 `docs/project-data.md` §2/§3/§5，不要在阶段文档中重复具体数字；
   设备端测试按 §7 的命令运行。
