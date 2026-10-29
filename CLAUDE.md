# CLAUDE.md — Rikai-Mobile handoff

> 给下一个 agent 的工作交接。先读本文件，再读 `docs/DEVELOPMENT_PLAN.md`（MVP 计划）、
> `docs/phase4.5-status.md`（当前 OCR 收敛结果）、`docs/phase4-status.md`
> （Phase 4 基线）和 `docs/phase6-agent-design.md`（Phase 6 设计草案，未实现）。
> 用户使用中文沟通；代码/标识符用英文。

## 1. 项目是什么

Android 单端的 Flutter 日语阅读/查词应用。**核心离线**：拍照或输入文本 →
横向 PaddleOCR / 纵向 MangaOCR → UniDic（用户自备）分词与注音 → 点击单词查询
用户自备的 MDict 词典；另有搜索查词、词典偏好、语料保存。

**当前处于 Phase 4.5（OCR 质量与性能收敛），Phase 5 暂停。** 4.5 已完成
按需加载模型、stat 优先指纹、90°/270° 整图纠正、混合排版分区路由、Manga 置信度
过滤和照片旋转入口；但尚未做 arm64 真机/真实漫画页验收。验收通过前不要推进
Phase 5，也不要开始 Phase 6。

Phase 6（`docs/phase6-agent-design.md`，**设计草案，未实现**）计划增加「词典助手」：
可选地调用用户配置的远程 LLM（DeepSeek/Claude 等），把本地 OCR、UniDic、MDict
作为工具集；图片只在本机 OCR，禁止视觉上云。核心离线功能不得依赖该 Agent。

- 项目根目录：`C:\Projects\Rikai-Mobile`（ASCII 路径，旧的 `E:\MyData\大工\...` 已不存在）
- 包名/applicationId/namespace：`com.rikai.mobile`
- Flutter 工程名：`rikai_mobile`
- 最低系统：minSdk 26；compileSdk/targetSdk 36；NDK 28.2.13676358
- 仅 Android；不做 iOS、不做云 OCR/云翻译。Phase 6 可选 Agent 允许用户配置的
  **文本 LLM**（不是云 OCR/视觉）；未实现前不得默认联网或把图片发给模型。
- **UI 强制规范**：所有现有与新增界面必须遵循 `docs/design-tokens.md`
  （蓝/白、3x 设计稿 72/48/36 → Flutter 24/16/12sp、4pt 间距、紧凑组件）。
  实现入口是 `lib/core/theme/app_tokens.dart`；页面不得硬编码颜色/字号/间距。
  二次修正后：**所有页面**统一深蓝顶栏（`#003A99`、白字白图标、
  词条页 TabBar 白字），主页左侧抽屉为直角；主页**当前**四个 72dp 功能按钮
  使用与顶栏相同的深蓝色，图标+文字居中对齐，文字 32sp（比首版 40sp
  小 20%）。Phase 6 设计指南计划改为五个按钮（拍照识别/查句子/查单词/
  历史记录/词典助手），但当前代码和 UI 仍是四个；未实施前不得提前改名或
  新增第五个按钮。设置页为白底扁平分区、无卡片；长提示 14sp 必须完整换行，
  用户不可变信息用 16sp 纯文本；帮助/著作权为 16sp 正文 + 18sp 栏目标题
  + 分割线；查词结果的词典名/条目数 16sp 同色、词条标题 24sp。启动页居中
  显示 `assets/Rikai_Icon.jpg` 与真实加载阶段；字体可在抽屉中切换
  HarmonyOS Sans / 系统字体。
  阅读器阅读面、结果区与输入/分词/复制工具区**均为白色**；工具区底边
  仅用 1px `divider` 浅色细线收边（类似查词搜索栏下方），不改变工具区
  底色、不得形成厚重色块；输入框 `filled: false`。分词结果不使用灰色
  （内容词蓝700、功能词/标点近黑、振假名品牌蓝）。查词搜索框占位符为「搜索……」；
  阅读页查词弹层不设关闭叉，读音与词形相同时不显示蓝色读音。
  **所有页面转场**使用全局 `SlideOverPageTransitionsBuilder`：新页面从右侧
  滑入覆盖静止的旧页面，禁止淡入淡出，避免深蓝顶栏出现白色残影。
  拍照页使用实时相机预览 + 半透明底部控制遮罩；照片集的删除/保存是**整个画面**
  左下/右下角的 52dp 圆形图标（删除错误色、保存深蓝 `header` + 白图标），
  保存/删除均二次确认；照片区可拖拽下边缘调整高度（纯白单色指示条），点击进入
  黑底全屏缩放查看；照片集标题栏只保留字号/注音菜单与一个「多选」入口，
  多选页沿用同一套图标。照片集不再有“分析句子”：拍照 OCR 后若已配置 UniDic，
  直接按文本阅读页 TokenChip 显示并点词查词；未配置时显示 OCR 原文；分词失败
  使用叠在照片顶部、标题栏下方的红色横幅（含重试），不占用 OCR 结果区。
  复制按钮在照片显示区右下角，为深蓝长条，文案「复制文本」；语料预览卡片
  右下角的复制按钮仍为「复制」。识别方向、旋转、模型设置、页码导航贴近页面
  底部，页码箭头中心与左下/右下角按钮中心同高。
  主页把「使用前须知」放在上方，当前四个功能按钮在剩余空间垂直居中；
  Phase 6 计划五个按钮时必须先更新设计 token/小屏滚动规则，不能直接硬编码。
  语料列表为大照片（完整 contain）+ 右上角红色圆形删除 + OCR 结果 + 日期，
  复制在**卡片右下角**；点开后进入「语料」详情：照片/OCR/分词、照片右下复制、
  语料间页码、左下删除，无多选/方向/模型设置/保存。列表与详情标题栏右上角
  都有字号/注音菜单，OCR/分词字号随之变化。
- **字体**：HarmonyOS Sans SC Regular，路径
  `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`。字体文件**不入库**（`.gitignore`
  已忽略）；用户自行从华为 HarmonyOS 设计资源下载，见 `assets/fonts/README.md`。
  构建前必须存在，否则 Flutter 报缺失资产。应用图标源 `assets/Rikai_Icon.jpg`
  由 `flutter_launcher_icons` 生成 Android 图标（配置在 `pubspec.yaml`）。
- 仓库已有多次提交（`d0d94a3`、`dc70cee`、`91dc386`、`deb6484`、
  `b12d24f`、`95f90e0`、`9e17984`、`f287603`、`c2ae03d`）。Phase 4 已提交为
  `f287603`，Phase 6 文档为 `c2ae03d`；Phase 4.5 代码/文档当前未提交。
  Phase 6 只有文档设计，尚未实现。不要擅自 `reset`/`commit`，除非用户明确要求。

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
   - 不实现“导入时复制 1.3GB”作为默认行为。不要在用户 UniDic 目录创建 `mecabrc`。
4. **MeCab**：vendored `mecab_for_dart` 2.0.5（BSD-3）在 `packages/mecab_for_dart`，
   路径依赖。已打补丁：`src/dart_ffi.cpp` 仅在 `<dicdir>/mecabrc` 存在时才传 `-r`。
   应用必须自己创建**私有** `mecabrc`，并通过 `Mecab.create(..., options: '-r "<私有rc路径>"')`
   传入。`options` 字符串由 `generateArgs()` 按空格/双引号解析。
   该方式已在 Android x86_64 模拟器 + 真实 1.3GB UniDic 上验证成功（见
   `docs/phase1-status.md`），不需要改 C++ 的 `rcPath` 参数。
   **注意**：UniDic 的 feature 行是带双引号的 CSV，例如
   `"動詞%F2@1,形容詞%F4@-2"`；不能直接 `split(',')`，必须用
   `lib/services/mecab/mecab_output_parser.dart`。
5. **MDict**：`dict_reader` 1.6.1（MIT），长生命周期 worker isolate。
   - 开发测试词典为 MDict v2.0、UTF-8、463,312 条、zlib、未加密；
   - `locateAll` 命中后必须解析 `@@@LINK=目标` 重定向，再渲染；
   - 不支持 LZO / record block 加密 / checksum；导入时要预检并给出明确错误。
6. **词典 HTML 渲染**：离线 `flutter_inappwebview`，禁用 JS 与网络，HTML 清洗后加载；
   MDD 资源按需提取到缓存并重写为本地 `file://`。不要改用 `flutter_html`。
7. **附加功能**：核心 + 语料保存/识别历史（照片 + OCR 文本 + 分词结果），SQLite。
8. **MangaOCR 模型**：默认从 `l0wgear/manga-ocr-2025-onnx` 下载；模型卡许可未声明，
   **不得随包分发/不得提交**，下载前显示提示，支持本地导入。原项目 kha-white 是
   Apache-2.0，但当前下载源不是。INT8 draft 解码器 MVP 不做。
9. **Phase 6 词典助手（设计边界，未批准实施）**：
   - 核心 OCR/UniDic/MDict 仍在本机；Agent 是可选在线模块，只有用户配置
     API Key/provider 并主动发送请求时才联网。
   - 图片只能经本机 OCR；严禁把图片作为 LLM 视觉输入或调用 provider 的图像能力。
   - 用户可选 small/complex 模型；严格模式必须引用真实词典工具结果，宽松模式
     允许标注过的模型补充。
   - 工具调用必须遵循 schema；citation 由 orchestrator 发放，模型不能自造来源。
   - 词典熟悉文档按词典指纹缓存并经用户确认；注音/标注规则使用受验证的安全 DSL，
     禁止执行任意代码。
   - API Key 不进 SharedPreferences/日志/导出；Phase 6 不得破坏未配置 Agent 时的
     离线核心。所有细节见 `docs/phase6-agent-design.md`。
10. **Phase 4.5 OCR 运行时（已实现）**：
   - PaddleOCR 必需；MangaOCR/orientation 只在 auto/vertical 需要时懒加载，
     横向模式不得创建 Manga session。`prepare(mode)` 只做后台预热。
   - readiness 区分 `mangaAvailable`/`mangaLoaded` 等；UI 的“已安装”看 available。
   - 运行时指纹/路径校验先 stat（路径、大小、mtime），不要每次 ready 都全量
     SHA-256；下载/导入/迁移仍需 SHA-256。
   - doc orientation 只在长宽比与框布局矛盾时运行；90/270 旋转后必须重新 DBNet。
   - auto 混合页可按框方向分区：横向框 Paddle、纵向框 Manga，engine 记录
     `paddle_v5+manga_ocr`。不要把它扩展成无置信度的任意分割。
   - 照片集“旋转”只改私有会话副本 90°，清该照片 OCR 缓存后重新识别；不要改
     设备原图。

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
  - 主页「拍照识别」已接入 `/capture`；设置新增「OCR 模型」入口。
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
  - 设备合成测试：自动竖向 253ms、手动竖向 251ms，均输出
    `これはテストです`；倒置横向页 180° 重跑后输出 `ありがとう`。
- Phase 4.5（2026-10-29，进行中，详见 `docs/phase4.5-status.md`）：
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
  - **混合排版**：auto 把强横向框交 Paddle、其余交 Manga；或横向页中 ≥2 个
    强纵向框交 Manga。engine=`paddle_v5+manga_ocr`，按 top band 合并。
  - **Manga 质量**：气泡 gap/padding 按中位框尺寸自适应；清除控制/替换字符，
    丢弃低置信度气泡。
  - **缓存/交互**：手动横向可复用 auto 的 `paddle_v5` 结果，手动竖向可复用
    `manga_ocr` 结果，mixed 不复用；照片集新增“旋转”按钮，旋转私有副本 90°、
    清该照片 OCR 缓存并重新识别。
  - 设备 OCR 套件扩为 8 项：横向、lazy、Manga、混合、90°、270°、倒置 180°、
    取消；x86_64 全部通过。冷 auto ~1308ms（含 Manga 加载），热 vertical
    149ms；混合 338ms；90° 675ms、270° 550ms。arm64/真实漫画页验收未完成。

已验证：

```text
flutter analyze  -> No issues found
flutter test     -> 112 tests passed
flutter build apk --debug -> success
```

真实 UniDic 模拟器集成测试（x86_64 API 36，4 项全部通过）：

```text
Storage permission: sdk=36 allFilesAccess=true
MecabService.open: 217 ms
食べ	たべ	動詞・一般	食べる	0..2
た	た	助動詞	た	2..3
東京	とうきょう	名詞・固有名詞・地名・一般	トウキョウ	3..5
Analyzed 1100 tokens in 276 ms; non-standard layouts: 0
reader page renders furigana for 食べた東京
```

UI 修正后两个设备套件已重跑：MeCab 4/4、MDict 6/6（词性不再显示 `*`；
`warmUp=415ms firstLookupAfterWarmUp=7ms`）。

真实 MDict 设备集成测试（`integration_test/mdict_android_test.dart`，5 项全部通过）：

```text
MdictService.open=716ms probe=675ms title=講談社 日本語大辞典 第二版 双解版
entries=463312 encoding=UTF-8 version=2.0
lookup 東京=425ms matched=東京 headword=とうきょう【東京】 html=724
hot lookup 東京=1ms
suggestions=[とうきょうえき, とうきょうえき【東京駅】]
resource JC_Z24Z/A471.png -> 334 bytes
rendered 2 entries, html=19273
repository: 講談社 日本語大辞典 第二版 双解版 463312 entries
search page opens a dictionary entry with the real MDict
```

主机 MDict spike（`tool/spike_mdict.dart`，在隔离 Dart 包中运行）仍然有效：
463,312 条、`@@@LINK` 重定向、前缀搜索正常。

OCR 设备集成测试（`integration_test/ocr_android_test.dart`，Phase 4.5 后 8/8
通过；合成横向/纵向/混合/90°/270°/倒置 PNG，真实 PaddleOCR + MangaOCR +
orientation 模型）：

```text
PaddleOCR horizontal      291ms   1 block   "ありがとう"
horizontal lazy sessions  passed  mangaLoaded=false
MangaOCR auto (cold)     1308ms   1 block   "これはテストです"
MangaOCR vertical (warm)  149ms   1 block   "これはテストです"
Mixed routing             338ms   3 blocks  "これはテスト / ありがとう / です"
Sideways 90° correction   675ms   8 blocks  "ありがとう" x8
Sideways 270° correction  550ms   8 blocks  "ありがとう" x8
Upside-down 180°          144ms   1 block   "ありがとう"
Cancellation              passed
```

取消测试在检测阶段触发 `cancel()`，断言返回 `CANCELLED` 且不崩溃。

同时已手工走通：拍照识别 → 相册选择 → 开始识别 → 文本阅读 → 真实 UniDic
分词 → 点击词条弹层。识别文本为 `ありがとう\n東京で食べた。`。

**当前阶段状态：**

- **Phase 4.5 进行中**：4.5-A/B/C 的主要代码与 x86_64 合成测试已完成；arm64
  真机和真实漫画页验收未完成。Phase 5 在这一验收通过前暂停。
- Phase 5 尚未完成。基础 `HistoryStore`、语料列表/详情和部分设置已提前实现，
  但完整历史管理、首次启动引导、错误/空态打磨、release 构建仍未完成。
- Phase 6 只有 `docs/phase6-agent-design.md` 设计草案，**没有代码、依赖或
  provider 调用**；不得把 README/CLAUDE 的 planned 描述当成已实现。

**尚未完成 / 下一步：**

- Phase 4.5：arm64 真机回归（横排/竖排/混合/倒置/90°、连续多页内存/耗时）、
  真实漫画页质量、缓存命中和按需加载性能验收；必要时继续调 Manga 聚类/顺序。
- Phase 5（4.5 验收后）：完整识别历史/语料管理、首次启动引导、设置与发布打磨。
- 没有 arm64 真机；只有 x86_64 模拟器 `Medium_Phone_API_36.1`。
  x86_64 仅验证功能，性能/真实漫画质量需 arm64 真机。
- 本机模拟器 DNS 无法解析 hf-mirror/Hugging Face，因此“应用内实网下载模型”
  尚未在设备验证；主机 curl 成功，Dart 本地 HTTP 测试已覆盖 Range 续传/校验。
- Release APK 尚未构建（不要在没有必要时重复跑长构建）。
- MangaOCR 仍未移植上游 mask/panel/free-text 全流水线，也没有 cross-bubble
  batching/INT8 draft/密集页 tiling；90/270 已实现整图旋转，但真实页仍需调参。

## 4. 未尽事宜（按优先级）

### 已完成：UniDic/MeCab + Phase 1

实现与验收记录见 §3、§6 和 `docs/phase1-status.md`。不要重写：

- 私有 `mecabrc` + `-r` 已在 Android 实测成功；
- 1.3GB UniDic 外部存储 mmap 可用；
- 29 字段映射与引号 CSV 解析已由真实词典验证；
- All Files Access 原生通道已实现。

### 已完成：ORT 模型冒烟（PaddleOCR）

- 主机 Python ORT：det 输出 `(1,1,64,480)`，rec 输出 `(1,40,18385)`，
  合成 `ありがとう` 解码分数 0.9983。
- Android x86_64：插件 readiness keys=18383，合成图片 OCR 320ms，
  `ありがとう` 置信度 1.000。
- MangaOCR encoder/decoder 已在 Phase 4 完成设备冒烟（合成竖排气泡
  `これはテストです`，自动 253ms / 手动 251ms）；模型许可未声明，不随包分发。

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

### Phase 4.5：OCR 质量与性能收敛（进行中）

先读 `docs/phase4.5-status.md`。已完成：

- 可选模型懒加载、`prepare` 预热、readiness available/loaded 拆分；
- stat 优先指纹/校验，SHA-256 按文件修订缓存；
- 90/270 整图旋转 + 重新 DBNet；doc 模型只在长宽比与布局矛盾时运行；
- auto 混合排版按框方向分区路由；
- Manga 尺寸自适应 gap/padding + 低置信度过滤；
- 手动模式安全复用 auto 缓存；照片集“旋转”入口。

仍需：

- arm64 真机：横排 2048px <5s、单页漫画 <10s、无 OOM；
- 真实横排/竖排/混合/倒置/90° 页面回归；
- 真实漫画多气泡/多面板顺序、振假名噪声、低置信度垃圾文本验收；
- 首次 auto/vertical 冷启动仍有 Manga session 创建成本（x86_64 约 1.1s）；
- 视情况继续做 panel grouping、cross-bubble batching、密集页 tiling。
- **Phase 5 在上述验收通过前不启动。**

### Phase 5：语料保存/打磨/发布（未完成，被 4.5 阻塞）

- 基础 `HistoryStore`（sqflite：图片副本、OCR 文本、blocks、模式/时间）和语料
  列表/详情已提前实现；仍需完整历史管理、删除/清空、缓存清理和边界处理。
- 首次启动引导（权限 → UniDic → 词典可选 → 模型可选 → 许可证）。
- 设置、错误/空状态、字体、无障碍、关于/许可证页。
- Release：arm64、R8、`--split-per-abi`；许可证审计；README/dev-setup 完善。

### Phase 6：Mdict Agent（设计，未实现）

先读 `docs/phase6-agent-design.md`；本节只给交接摘要，细节以设计文档为准。
Phase 6 只能在 Phase 5 完成并经用户确认后实施。

- 主页计划五个按钮：拍照识别、查句子、查单词、历史记录、词典助手；当前代码仍是
  四个，实施前不要提前改名/加按钮。
- Agent 使用本地 OCR/UniDic/MDict 工具 + 用户配置的远程 LLM；DeepSeek/Claude/
  OpenAI-compatible 均通过 provider 适配层，不依赖 provider 的视觉能力。
- 严格模式必须有真实词典 citation；宽松模式允许标记过的模型补充。工具 schema、
  citation ID、词典熟悉文档、API Key 安全存储、注音/标注 DSL、Markdown/ruby/
  声调渲染均是硬要求。
- 推荐顺序：provider/密钥 → tool adapters + schema → agent loop/模式 → 渲染/
  citation → 熟悉期 → 标注规则 → 测试/发布。
- 禁止：把图片/base64 发给 LLM、把 provider 当云 OCR、把 API Key 放仓库/
  SharedPreferences/日志、执行模型生成的任意代码、在 Phase 6 未实现时把文档
  描述成已支持。

## 5. 项目误区 → 解决方案（重要）

> 每条先写“误区/表现”，再写“正确做法”。遇到相似问题直接照做，不要重复试错。

### 5.1 架构与 OCR

1. **误区：把 PaddleOCR4Android 的 Paddle-Lite/OpenCV/NDK r21 模块塞进 Flutter。**
   - 正确做法：MVP 统一 ONNX Runtime；横向用 PP-OCRv5 ONNX，纵向用 manga-ocr ONNX。
   - PaddleOCR4Android 只保留在 `third_party/paddleocr4android/` 作为可选后端说明；
     二期若接入，做成独立 AAR + `OcrBackend`，不要改主插件依赖。
2. **误区：把 `.nb` 模型给 ONNX Runtime，或把 ONNX 给 Paddle-Lite。**
   - 正确做法：模型格式由 `assets/models/manifest.json` 固定；`.nb` 只属于 Paddle-Lite，
     ONNX 只属于 ORT；不要混用，也不要改扩展名伪装。
3. **误区：用 `flutter_html` 渲染 MDict 词条。**
   - 正确做法：用 `flutter_inappwebview` 离线 WebView；词典 CSS/表格/MDD 图片需要完整
     浏览器布局。若 WebView 有问题，修 WebView 配置（本地文件、CSS 注入、资源重写），
     不要退回 `flutter_html`。
4. **误区：各 OCR 引擎 `close()` 时关闭共享 `OrtEnvironment`。**
   - 正确做法：`OrtEnvironment` 做应用级单例；引擎只关闭自己的 `OrtSession`。
     upstream `PaddleOcrEngine.close()` 有关闭共享环境的问题，抽取时必须修掉；
     R8 keep `ai.onnxruntime.**`。
5. **误区：在 x86_64 模拟器上评估 OCR 性能。**
   - 正确做法：模拟器只做功能冒烟；性能、内存、竖排质量用 arm64 真机，记录到
     `docs/phase0-status.md` 或阶段状态文档。

### 5.2 UniDic / MeCab

6. **误区：`mecab_for_dart` 要求 `<dicdir>/mecabrc`，于是往用户 UniDic 目录写文件。**
   - 正确做法：已 patch `packages/mecab_for_dart/src/dart_ffi.cpp`：只有该文件存在时才传
     `-r <dicdir>/mecabrc`。应用在**私有目录**创建 `mecabrc`，用
     `Mecab.create(dictDir: path, options: '-r "<私有rc路径>"')` 传入。
   - 该方式已在 Android x86_64 模拟器 + 真实 1.3GB UniDic 上验证成功；
     不需要改 C++ 的 `rcPath` 参数，**不要**写用户目录。
7. **误区：把 UniDic 复制到 app 存储“更稳”。**
   - 正确做法：用户明确选择原地路径；不要默认复制 1.3GB。
   - 权限不足：引导 All Files Access，或让用户放到
     `/sdcard/Android/data/com.rikai.mobile/files/`。
   - 外部存储 mmap 失败：记录具体错误并**询问用户**，不要静默改成复制方案。
8. **误区：硬编码 29 字段并假设所有 UniDic 版本一致；或用 `split(',')` 解析 feature。**
   - 正确做法：解析前校验字段数；按下述索引映射；字段数异常时降级为
     “可点击、无注音”，记录日志，不崩溃。当前 2025.12 版本为 29 字段。
   - **重要**：UniDic 的 feature 行是带双引号的 CSV，字段内可含逗号，例如
     `"動詞%F2@1,形容詞%F4@-2"`。直接用 `TokenNode.features`（朴素 split）会把
     助動詞/助詞解析成 30–31 字段。必须用
     `lib/services/mecab/mecab_output_parser.dart` 的引号感知解析器。
   - 索引：0-3 pos1-4；4 cType；5 cForm；6 lForm/語彙素読み；7 lemma；8 orth；
     9 pron；10 orthBase；11 pronBase；12 goshu；20 kana；21 kanaBase；
     24-26 accent；27 lid；28 lemma_id。
9. **误区：注音直接用 `lemma` 或 `pron`。**
   - 正确做法：优先 `kana`(20)，回退 `pron`(9) → `lForm`(6) → `surface`；
     片假名转平假名。未知词可从 MDict 词条提取读音作为 P2 兜底。
10. **误区：在根包用 `dart run` 跑 MeCab/MDict 主机脚本。**
    - 正确做法：根包依赖 `mecab_for_dart`，Windows 上会触发 native-assets hook 并失败。
      主机脚本放到隔离 Dart 包（只依赖 `dict_reader`），例如把
      `tool/spike_mdict.dart` 复制到临时包再跑；Android 上的 MeCab 验证在 app 内做。

### 5.3 MDict

11. **误区：`locateAll` 返回的就是最终 HTML。**
    - 正确做法：读取后先匹配 `^@@@LINK=(.+)$`，最多解析 3 层并防环，再清洗/渲染。
      真实测试词典的 `東京`、`食べる` 都是重定向；已用 `tool/spike_mdict.dart` 验证。
    - 参考实现：

      ```dart
      Future<({String key, String html})> resolve(
        DictReader reader,
        RecordOffsetInfo hit, [
        int depth = 0,
      ]) async {
        final html = await reader.readOneMdx(hit);
        final m = RegExp(r'^@@@LINK=(.+)$').firstMatch(html.trim());
        if (m != null && depth < 3) {
          final next = await reader.locate(m.group(1)!);
          if (next != null) return resolve(reader, next, depth + 1);
        }
        return (key: hit.keyText, html: html);
      }
      ```

12. **误区：启动时打开所有词典并常驻。**
    - 正确做法：懒初始化 + 长生命周期 worker isolate；只打开启用的词典。
      463k 词条实测 `initDict()` ~200ms、RSS ~400MB；需要时用
      `exportCache/importCache` 或 SQLite key 索引，不要在主 isolate 初始化。
13. **误区：用已废弃的 `init()`。**
    - 正确做法：用 `dict_reader` 1.6.1 的 `initDict()`。不支持 LZO / record block
      加密 / v3 时，在导入预检阶段明确报错，不要等运行时崩溃。
14. **误区：WebView 直接加载词典 HTML。**
    - 正确做法：`package:html` 清洗 `<script>/<iframe>/<object>/<embed>/<form>`、
      `on*` 事件、`javascript:` URL；注入外部 CSS；MDD 资源按需提取到缓存并重写
      `src` 为本地 `file://`。
    - WebView 设置：`javaScriptEnabled: false`、`blockNetworkLoads: true`、仅本地文件；
      `shouldOverrideUrlLoading` 拦截 `entry://` 与外部 URL。

### 5.4 Android / 权限 / 构建

15. **误区：`permission_handler` 可以处理“所有文件访问”。**
    - 正确做法：当前 `permission_handler_android 14.1.0` 的 Kotlin DSL 与
      Gradle/Kotlin 组合编译失败，已移除。改用原生 MethodChannel：
      - `Build.VERSION.SDK_INT >= 30`：
        `Environment.isExternalStorageManager()` 检查；
        未授权时跳转
        `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` +
        `Uri.parse("package:$packageName")`。
      - Android 10 及以下：申请 `READ_EXTERNAL_STORAGE`。
      - Manifest 已声明 `MANAGE_EXTERNAL_STORAGE`、`READ_EXTERNAL_STORAGE`
        （maxSdk 32）、`requestLegacyExternalStorage`。
      - 已实现于 `android/app/src/main/kotlin/com/rikai/mobile/MainActivity.kt`
        和 `lib/services/storage/permission_service.dart`（channel
        `rikai/storage_permission`），设备端测试已验证。
16. **误区：路径有中文就加 `subst` / `overridePathCheck` / `kotlin.incremental=false`。**
    - 正确做法：项目已在 `C:\Projects\Rikai-Mobile`（ASCII），这些配置已从
      `android/gradle.properties` 删除，不要恢复；直接构建即可。
17. **误区：Gradle `metadata.bin` 错误只能删整个缓存/重装。**
    - 正确做法：

      ```powershell
      cd C:\Projects\Rikai-Mobile\android
      .\gradlew --stop
      $c = "$env:USERPROFILE\.gradle\caches\8.14"
      Move-Item "$c\kotlin-dsl" "$c\kotlin-dsl.bak"
      Move-Item "$c\groovy-dsl" "$c\groovy-dsl.bak"
      Move-Item "$c\transforms" "$c\transforms.bak"
      Move-Item "$c\generated-gradle-jars" "$c\generated-gradle-jars.bak"
      Move-Item "$c\dependencies-accessors" "$c\dependencies-accessors.bak"
      ```

      保留 `modules-2`；再用 `.\gradlew :app:assembleDebug --no-daemon` 诊断。
18. **误区：NDK 用 Flutter 默认或 27 就行。**
    - 正确做法：`android/app/build.gradle.kts` 固定 **NDK 28.2.13676358**
      （`jni` 插件要求）；compileSdk/targetSdk 36；minSdk 26；不要降 NDK。
19. **误区：release 构建随时可跑、很快。**
    - 正确做法：release 需要 arm64 + R8，耗时数分钟；用户曾中断一次，需要时先确认。
      命令：`flutter build apk --release --target-platform android-arm64 --split-per-abi`。
      Debug APK ~260MB 不代表 release 大小。
20. **误区：未要求就 commit/push/reset。**
    - 正确做法：先 `git status`；只改代码/文档；不 commit/push；不覆盖用户未提交改动；
      结束时报告未提交文件。

### 5.5 许可 / 仓库 / 范围

21. **误区：模型/词典可以随仓库提交。**
    - 正确做法：`.gitignore` 已覆盖模型/词典/UniDic；只提交
      `assets/models/manifest.json` 和许可证。用
      `git check-ignore -v unidic mdicts`、`git ls-files | grep -E '\.(onnx|nb|mdx|mdd)$'`
      验证；模型下载到 `getExternalFilesDir()/models/`。
22. **误区：MangaOCR 权重是 Apache-2.0，可以打包。**
    - 正确做法：`l0wgear/manga-ocr-2025-onnx` 模型卡未声明许可；只下载/本地导入，
      不随包分发；下载前显示警告；保留 `NOTICE` 说明。
      `kha-white/manga-ocr-base` 是 Apache-2.0，但仅作为可选转换来源。
23. **误区：删除 `unidic/`、`mdicts/`、两个上游 clone 来“清理仓库”。**
    - 正确做法：它们被 `.gitignore` 忽略，是开发数据/参考；不要删除。
      用户自备数据不提交；`overlay-translator/`、`PaddleOCR4Android/` 仅作参考。
24. **误区：把 Phase 6 的在线 Agent 当成“给项目加 LLM/云 OCR”或反过来继续声称纯离线。**
    - 正确做法：MVP/核心仍锁定 Android 单端、离线 OCR/分词/词典；不引入 iOS、
      ML Kit 或云 OCR/云翻译。Phase 6 是**可选的用户配置文本 LLM Agent**：
      必须单独批准，默认不联网，图片不上传，不使用 provider 视觉，不把 API Key
      写入仓库/日志；未实现前 README/CLAUDE 只能写 planned/design。
25. **误区：恢复旧包名/旧 MainActivity。**
    - 正确做法：统一 `com.rikai.mobile`；唯一入口是
      `android/app/src/main/kotlin/com/rikai/mobile/MainActivity.kt`；
      旧 `com/rikai/rikai_mobile/MainActivity.kt` 只是注释，不要恢复类。

### 5.6 症状 → 处理速查

| 症状/报错 | 直接处理 |
|---|---|
| `Could not read workspace metadata ... metadata.bin` / 缺 transform workspace | 停 daemon，移走 `kotlin-dsl`/`groovy-dsl`/`transforms` 等脚本缓存（§5.4 #17），保留 `modules-2` |
| `Your project path contains non-ASCII characters` 或 shader 写入失败 | 确认项目在 `C:\Projects\Rikai-Mobile`；不要恢复旧 path 配置 |
| `permission_handler_android ... Unresolved reference: kotlin/compilerOptions` | 不要重装/降级插件；移除 permission_handler，用原生 MethodChannel（§5.4 #15） |
| MeCab 初始化返回 null / 报 rc 文件错误 | 检查 UniDic 5 个文件；创建私有 `mecabrc`；传 `-r <私有路径>`；确认 Android 可读路径 |
| `dict_reader` 读取后页面只显示 `@@@LINK=...` | 解析重定向（§5.3 #11），最多 3 层 |
| WebView 空白或图片缺失 | 检查 `loadDataWithBaseUrl` 的 base URL、MDD 提取路径、`src` 重写、本地文件权限；确认 JS 关闭不影响布局 |
| `dart run` 在根包失败并出现 Visual Studio 安装清单 | 根包 native-assets hook（MeCab）在 Windows 失败；改用隔离 Dart 包跑主机脚本（§5.2 #10） |
| Debug APK 很大（~260MB） | 正常：全 ABI + debug。需要时构建 arm64 release；不要把 debug 大小当 release |
| 词典/模型/UniDic 出现在 `git status` | 立即 `git check-ignore -v` 检查规则；不要提交；只保留 manifest/许可证 |
| `flutter analyze` 报 vendored `mecab_for_dart` 的 lint | 该包 `analysis_options.yaml` 已关闭相关 lint；不要改上游源码或删除包 |
| UniDic 加载后 OOM/卡死 | 确认 64 位；不要整体读入内存；检查 mmap/路径；记录设备内存；不要默认复制 |
| adb/flutter 收到的 `/sdcard/...` 变成 `C:/GitBash/sdcard/...` | Git Bash 路径转换；`export MSYS_NO_PATHCONV=1`（§5.7 #26） |
| 集成测试 `allFilesAccess=false` 或 `Cannot open file` | `flutter test` 重装应用丢失 appops；在测试运行期间循环重新授权（§5.7 #27） |
| 助動詞/助詞 feature 数为 30/31、注音为空 | 引号内逗号被误拆；用 `mecab_output_parser.dart`（§5.2 #8） |
| 分词失败后 loading 永不结束 | Riverpod 3 默认重试；给 provider 设 `retry: (_, __) => null`（§5.7 #28） |
| MDict 查词命中但 WebView 图片空白 | 用 `mdd_key.dart` 生成 key 变体，资源写入缓存并重写为 `file://`（§5.7 #32） |
| 词条页空白 / CSS 图片不加载 | 使用 `InAppWebViewInitialData` + file base URL、`allowFileAccess: true`（§5.7 #33） |
| 词典 HTML 注入或外部资源加载 | `EntryRenderer` 清洗 + 禁用 JS/网络；不要绕过（§5.7 #34） |
| 假名/全角查询无命中 | 使用 `text_normalizer.dart` 的 NFKC/假名/stripkey 候选 |
| 构建报 `unable to find asset ... HarmonyOS_Sans_SC_Regular.ttf` | 字体不入库；按 `assets/fonts/README.md` 下载到指定路径 |
| 用户选择 MDX 后词典被复制到 cache、同目录 MDD 找不到 | 不要用 `file_picker.pickFiles`；用 `getDirectoryPath` 选择文件夹后列出 `.mdx`（§5.7 #36） |
| 启动页一直转圈/词典首次跳转慢 | 检查 `BootstrapApp` 的 warmup 与 timeout；词典应通过启动预热常驻 worker（§5.7 #37） |
| 搜索结果点击后显示其他词典内容 | 传单条 `DictionaryLookupGroup(entries:[entry])`；≥2 条才给“查看全部”（§5.7 #38） |
| 设备测试后手动安装 app-debug.apk 停在系统启动图 | 集成测试覆盖了 app-debug.apk；重新 `flutter build apk --debug` 再安装（§5.8 #40） |
| 某个页面顶栏还是白底/深色字 | 不要页面局部覆盖 AppBar；全局 `AppTheme` 已统一深蓝白字（§5.8 #41） |
| 设置页灰色提示被截断/太小 | 提示改为输入框外独立 14sp Text；不要用 `helperText` 单行显示（§5.8 #42） |
| 查词结果词典名/条目数太小 | 16sp 同色；词条标题 24sp；摘要 14sp（§5.8 #45） |
| 页面跳转时顶栏发白/页面互相淡入淡出 | 不要用默认 Material 转场；全局 `SlideOverPageTransitionsBuilder` 右滑覆盖（§5.8 #48） |
| 阅读器输入区/结果区出现灰白色块分界或缺少收边 | 阅读面与工具区均白底；工具区仅加 1px `divider` 底边；输入框 `filled: false`（§5.8 #49） |
| 阅读分词结果发灰、看不清 | 内容词蓝700、功能词/标点近黑、振假名品牌蓝；禁用 textSecondary（§5.8 #50） |
| 查词弹层右上角关闭叉多余/ありがとう重复显示读音 | 移除关闭叉；仅 `hasDistinctReading` 时显示蓝字读音（§5.8 #51） |
| adb push 模型到 Android/data 后 app 报 permission denied | 先让 app 创建目录；或 push 到 /sdcard/Download 配合集成测试 All Files Access（§5.9 #52） |
| 模型路径变成 `C:/GitBash/sdcard/...` / `Creation failed path='C:'` | Git Bash 转换了 `--dart-define`；`export MSYS_NO_PATHCONV=1`（§5.9 #53） |
| file_picker 报 `platform` getter 不存在 | v13 静态 API；`FilePicker.pickFiles()` 返回 `List<PlatformFile>`（§5.9 #54） |
| PP-OCR 字符表解析为空/首字丢失 | 不要 trim U+3000；CtcDictionary 只去 CR/LF（§5.9 #55） |
| OCR 全错/输出乱码 | 检查 BGR 通道、检测/识别 mean/std、EXIF 方向、模型 keys 索引（§5.9 #58） |
| 相机页黑屏/无预览 | 确认 `CAMERA` 权限、`availableCameras` 非空、预览宽高交换与 `BoxFit.cover`（§5.10 #59） |
| 照片集删除/保存按钮位置不对 | 按钮固定在**整个画面**左下/右下角；不要放回照片区 Stack（§5.10 #60） |
| 照片集/多选页出现重复“多选/全选/保存” | 标题栏只保留一个“多选”；多选页标题用“选择照片”，删除/保存只保留图标（§5.10 #61） |
| 照片集仍有“分析句子”/不显示分词 | 删除分析按钮；配置 UniDic 后自动分词并用 ReaderBlock 渲染，未配置显示原文（§5.10 #62） |
| 照片区不能放大/不能查看细节 | 下边缘拖拽调整高度；点击照片打开 InteractiveViewer 全屏查看（§5.10 #63） |
| MDict 导入弹结果框/列表尾部有英文 | 扫描行只显示中文状态；导入完成直接返回，失败只用 SnackBar（§5.10 #64） |
| 本地导入仍提示缺少 det.onnx/rec.onnx | 上游文件名为 inference.onnx/inference.yml；按大小+角色匹配（§5.10 #65） |
| 模型目录切换后仍读旧文件 | 保存设置后 manager 回调读取新路径；默认迁移校验后再保存（§5.10 #66） |
| 返回照片集或多选页又重跑 OCR | 模式存会话、指纹存 OcrService；命中缓存直接渲染，多选只补缺失（§5.10 #67） |
| 主页使用前须知仍在按钮下方 | 须知放上方，四个按钮在剩余空间垂直居中（§5.10 #68） |
| 语料仍是缩略图/点击进文本阅读 | 大照片完整 contain + 右上删除 + OCR + 日期；点击进语料详情（§5.10 #69） |
| 语料详情只显示 OCR 或只显示分词 | 两段都显示；OCR 原文 + ReaderBlock 分词，可点词查词（§5.10 #70） |

### 5.7 Phase 1 设备实测经验（2026-10-27）

26. **误区：在 Git Bash 里直接传 `/sdcard/...` 给 adb 或 `--dart-define`。**
    - 正确做法：MSYS 会把路径改写成 `C:/GitBash/sdcard/...`。运行前
      `export MSYS_NO_PATHCONV=1`，对 `adb push`、`adb shell`、`flutter test` 都适用。
27. **误区：`flutter test integration_test/... -d ...` 跑完仍保留应用与权限。**
    - 正确做法：该命令测试前安装、测试后卸载应用，`MANAGE_EXTERNAL_STORAGE`
      appops 随之丢失。用同一 shell 的后台循环在应用出现后反复执行
      `adb shell appops set com.rikai.mobile MANAGE_EXTERNAL_STORAGE allow`；
      集成测试会轮询最多 120 秒等待 UniDic 可读。命令见 `docs/dev-setup.md`。
28. **误区：忽略 Riverpod 3 的默认 retry。**
    - 正确做法：Riverpod 3 默认指数退避重试失败 provider；无效 UniDic 会反复初始化，
      spinner 永不结束。`mecabServiceProvider` 已设 `retry: (_, __) => null`；
      其它加载大文件/原生资源的 provider 也应显式关闭。
29. **误区：外部存储 mmap 不可用。**
    - 正确做法：已在 x86_64 API 36 模拟器验证 `/sdcard/Download` mmap 可用；
      `MecabService.open` ~246ms。arm64 真机仍需复测。
30. **误区：widget 测试里用 `pumpAndSettle` 等待真实文件 I/O 或权限通道。**
    - 正确做法：mock `rikai/storage_permission`；真实文件 I/O 用 `tester.runAsync`
      让出事件循环，否则无限 spinner 会让 `pumpAndSettle` 超时。
31. **误区：把 HarmonyOS Sans 字体提交到仓库，或页面里硬编码颜色/字号。**
    - 正确做法：`assets/fonts/*.ttf` 已被 `.gitignore` 忽略；用户按
      `assets/fonts/README.md` 自行下载。UI 必须使用
      `lib/core/theme/app_tokens.dart` 与 `AppTheme.light()`，禁止散落
      `Color(0x...)`/`fontSize: 数字`（阅读区用户字号除外）；规范见
      `docs/design-tokens.md`。
32. **误区：把 MDD key 直接当作 HTML 的 `src` 交给 `DictReader.locate`。**
    - 正确做法：HTML 常写 `JC_Z24Z/A471.png`，MDD 实际 key 是
      `\JC_Z24Z\A471.png`。必须用 `lib/services/mdict/mdd_key.dart` 生成
      前导反斜杠、斜杠/反斜杠、file:// 与 percent-encoded 变体。
33. **误区：WebView 直接加载原始 MDict HTML，或用字符串 loadData 而没有
      file base URL。**
    - 正确做法：`EntryRenderer` 清洗后，用 `InAppWebViewInitialData` +
      `baseUrl: WebUri('file://.../<dictId>/')`；`allowFileAccess: true`、
      `javaScriptEnabled: false`、`blockNetworkLoads: true`。MDD 图片先写入
      缓存目录并重写为绝对 `file://` URL，否则 Android WebView 图片空白。
34. **误区：只移除 `</style>` 就算清理了词典 CSS。**
    - 正确做法：CSS 注入前移除 `</style>`、`<script>` 等标签序列
      （`EntryRenderer._stripStyleClose`），防止字典 CSS 逃逸出 `<style>`。
      同时清洗 `on*`、`srcdoc`、`srcset`、`javascript:`/`vbscript:`/
      `data:text/html`，并阻断网络图片。
35. **误区：用 dictionary 原始文件名/中文路径做设备集成测试，或在搜索
      loading 时用 `pumpAndSettle`。**
    - 正确做法：把测试词典以 ASCII 名 push 为
      `/sdcard/Download/rikai-mdict/{dict.mdx,dict.mdd,dict.css}`（MDX/MDD
      必须同 basename 才会自动发现）；`flutter test` 会重装应用，需后台
      循环重授 All Files Access；搜索/词条页有持续动画时用定时
      `tester.pump` 轮询，不要 `pumpAndSettle`。
36. **误区：用 `file_picker.pickFiles` 选择用户的 .mdx，然后把返回路径存起来。**
    - 正确做法：该版本的 Android 文件选择会把文件**复制到应用 cache**，
      同目录 MDD 不会一起复制，违反原地读取。用
      `FilePicker.getDirectoryPath` 让用户选文件夹，再在 Dart 中列出该目录的
      `.mdx` 并确认；UniDic 同理只选目录。
37. **误区：每次打开词条都重新初始化词典/重新渲染 HTML。**
    - 正确做法：`BootstrapApp` 在启动页对 `enabledDictionariesProvider` 调用
      `MdictService.warmUp`（worker 常驻）；`EntryRenderCache` 以
      dictionaryId + 词条 HTML 哈希做内存 LRU；revalidate/remove 时失效。
38. **误区：点击一个搜索结果却把该词的所有词典/词条都显示出来。**
    - 正确做法：单条点击只传 `DictionaryLookupGroup(entries: [entry])`；
      同词典结果 ≥2 条时显示“查看全部（N 条）”，点击只传该词典的完整 group。
      `entry://` 链接取第一个结果。
39. **误区：改主页顶栏时直接改全局 `AppBarTheme`，导致设置/词条页也变深蓝。**
    - 正确做法（已被 2026-10-28 二次要求覆盖）：现在**所有页面**统一深蓝
      AppBar + 白字；不要再按页面单独设白底。详见 §5.8 #41。

### 5.8 2026-10-28 UI/启动二次修正经验

40. **误区：设备集成测试后直接安装 `build/app/outputs/flutter-apk/app-debug.apk` 手动验收。**
    - 表现：应用停在系统启动图，Dart isolate 空闲、无 Flutter 首帧；
      VM service 里出现 `ext.flutter.integrationTest`，缺少
      `ext.flutter.debugDumpApp` 等框架扩展。
    - 正确做法：`flutter test integration_test/...` 会用测试入口覆盖
      `app-debug.apk`；手动安装前必须重新 `flutter build apk --debug`。
      这是启动图卡死的首要排查项，不要误判为业务代码死锁。
41. **误区：只在主页设置深蓝顶栏，其他页面保留白色 AppBar。**
    - 正确做法：`AppBarTheme` 全局深蓝 `header` + 白字/白图标、
      `systemOverlayStyle: light`、无底部分割线；页面不要局部覆盖颜色。
      词条页 TabBar 位于深蓝顶栏内，使用白色 label/indicator，不要用品牌蓝。
42. **误区：设置页用 Card 包住输入框和操作按钮；把长提示塞进
    `InputDecoration.helperText`。**
    - 正确做法：白底扁平分区；TextField/按钮直接放在页面上；提示用输入框外
      独立 14sp Text，允许换行；用户不可变信息（外部私有目录）用 16sp 纯文本；
      长权限说明用自定义 Row/Column，而非可能截断的 ListTile subtitle。
43. **误区：主页功能按钮沿用首版的 40sp/左对齐/亮品牌蓝。**
    - 正确做法：按钮背景与顶栏相同 `AppColors.header`；图标+文字整体居中；
      文字 32sp（40sp 的 80%）；抽屉 `Drawer.shape` 使用直角。
44. **误区：帮助/著作权继续用 Card/ListTile 小字。**
    - 正确做法：白底纯文本；正文 16sp、栏目标题 18sp、每栏之间 Divider；
      不嵌套卡片。
45. **误区：查词结果沿用 12sp 的 titleSmall/labelSmall，且用 ListTile 承载
    24sp 标题。**
    - 正确做法：词典名/条目数 16sp 同色（与“查看全部”一致）；词条标题 24sp；
      摘要 14sp；用自定义 Card+InkWell+Column，避免大字号被 ListTile 裁切。
46. **误区：切换字体时只改 `ThemeData(fontFamily:)`，组件主题仍写死
    HarmonyOS。**
    - 正确做法：`AppTheme.light(fontFamily:)` 必须把 family 写入 AppBar、
      按钮、对话框、SnackBar、弹层、输入框、ListTile、TabBar 等所有显式
      TextStyle；系统字体时传 null。`ThemeData` 没有 `fontFamily` getter，
      测试检查 `textTheme.*.fontFamily`。
47. **误区：手动编辑 flutter_launcher_icons 生成的 mipmap，或把图标/字体
    混在一起提交。**
    - 正确做法：修改 `assets/Rikai_Icon.jpg` 后运行
      `dart run flutter_launcher_icons`；图标源提交，字体不入库；原生启动图
      使用 `drawable-nodpi/launch_icon.png`，Android 12+ 系统启动图使用
      adaptive icon（圆形遮罩属正常）。
48. **误区：页面跳转沿用 Material 默认的淡入/缩放转场。**
    - 表现：旧页与新页交叉淡化，深蓝顶栏在过渡瞬间发白，出现白色瑕疵。
    - 正确做法：`AppTheme.light()` 的 `pageTransitionsTheme` 在全部平台使用
      `SlideOverPageTransitionsBuilder`：新页面从右侧滑入覆盖旧页面，旧页面
      静止、无淡入淡出/缩放。不要给单个页面自定义转场；`Navigator.push`
      的 `MaterialPageRoute` 与 go_router 都会继承全局主题。
49. **误区：阅读器工具区没有浅色收边，或为了收边把工具区改成灰色底带。**
    - 表现：输入框/分词/复制区域与长文分词列表之间缺少自然分隔，或出现
      用户不想要的灰色底带；用户明确要求**保留白色工具区**，只保留细边。
    - 正确做法：阅读面、结果列表与工具区均为 `AppColors.surface` 白色；
      工具区底边仅 1px `AppColors.divider` 细线（`reader-controls-surface`
      的 `Border.bottom`）；`TextField` 设 `filled: false`，不额外铺色块。
      不要为了分隔感把工具区改成 `background`。
50. **误区：阅读器功能词、标点和振假名使用 `textSecondary` 灰色。**
    - 正确做法：内容词蓝50底 + 蓝700；功能词/标点透明底 + `textPrimary`
      近黑；振假名品牌蓝 `primary`。阅读器内不使用灰色文字，靠蓝色/黑色/
      字重建立层级；对应规范见 `docs/design-tokens.md` §3.2/TokenChip。
51. **误区：查词弹层保留右上角关闭叉；词形与读音相同仍显示蓝字读音。**
    - 正确做法：阅读页查词弹层可下滑/上滑/点击遮罩关闭，移除关闭 IconButton；
      仅在 `token.hasDistinctReading` 为 true 时显示蓝色读音行，
      `ありがとう（ありがとう）` 这类重复读音只保留黑色词形。

### 5.9 2026-10-28 Phase 3 OCR 经验

52. **误区：用 `adb push` 往 `/sdcard/Android/data/<pkg>/files/models` 塞模型，
    然后直接让 app 读取。**
    - 表现：`FileSystemException: Exists failed ... Permission denied (errno 13)`，
      因为目录是 shell 所有，FUSE 下 app 不能遍历。
    - 正确做法：先启动 app/模型页让 app 自己创建目录，再 push 文件到该
      app-owned 目录；或用应用内下载/本地导入。集成测试使用
      `/sdcard/Download/rikai-models` + All Files Access，避免该问题。
53. **误区：在 Git Bash 里给 `flutter build --dart-define=...=/sdcard/...` 传
    Android 路径。**
    - 表现：Dart 端看到 `C:/GitBash/sdcard/...`，模型页报 `Creation failed,
      path = 'C:'`。
    - 正确做法：`export MSYS_NO_PATHCONV=1` 后再 build/test；对 adb push、
      `flutter test --dart-define` 同样适用。
54. **误区：按旧版 file_picker API 写 `FilePicker.platform.pickFiles()` 并读
    `result.files`。**
    - 正确做法：v13 是静态 API：`FilePicker.pickFiles()` 直接返回
      `List<PlatformFile>`（取消为空列表）；目录选择用
      `FilePicker.getDirectoryPath()`。详见 `docs/dev-setup.md`。
55. **误区：解析 PP-OCRv5 的 `keys.yml` 时用 `trim()`/`rstrip()`。**
    - 表现：字符表变空或 CTC 首字符丢失；该字典第一个 key 是 **U+3000**
      全角空格，Kotlin 的 `trim()`/Python 的 `rstrip()` 会将其删掉。
    - 正确做法：按行处理时只去掉 `\r`/`\n`，YAML 标量只去掉 ASCII 空格；
      `CtcDictionary.kt` 已按此实现，输出 class 数应为 18385（blank + 18383
      keys + space）。
56. **误区：每个 OCR 引擎 close 时关闭 `OrtEnvironment`，或把竖排请求静默
    当横排处理。**
    - 正确做法：`OcrRuntime.environment` 应用级单例，不随引擎关闭；
      Phase 4 的 `vertical` 使用独立的 MangaOCR 引擎，手动竖向缺模型时必须
      返回 `MODEL_MISSING`，不得静默伪装成横向；只有 `auto` 允许在 MangaOCR
      缺失时回退 Paddle 横向。
57. **误区：以为 image_picker 需要 Android CAMERA 权限。**
    - 正确做法：它通过系统相机 Intent 取图，Manifest 只需已有
      `<uses-feature camera required=false>`；不要额外申请 CAMERA，
      否则反而会因为未授权导致相机 Intent 失败。
58. **误区：把 PaddleOCR 识别输入按 RGB 顺序送入模型。**
    - 正确做法：PaddleOCR 训练使用 OpenCV BGR；Bitmap 是 RGBA，必须在
      `bitmapToNchw` 中按 B/G/R 写三个通道，并按 0.485/0.456/0.406、
      0.229/0.224/0.225 归一化检测输入；识别输入用 0.5/0.5。

### 5.10 2026-10-29 Phase 3.5 采集/导入/语料经验

59. **误区：继续用 `image_picker` 的系统相机 Intent 冒充实时拍照页。**
    - 正确做法：实时预览必须引入 `camera` 插件并声明 CAMERA 权限；预览用
      `FittedBox` + 交换 `previewSize` 的宽高 + `BoxFit.cover`。应用进入后台
      或打开照片集/阅读页时 dispose 相机，返回时重建；不要用
      `permission_handler`。
60. **误区：把照片集的删除/保存按钮放在照片区域内部，或把保存做成白底。**
    - 正确做法：用户要求它们固定在**整个画面**左下/右下角；照片区只放照片。
      不再在底部额外预留 64dp；识别方向、旋转、模型设置、页码导航贴近页面
      底部，`CapturePageNavigation` 固定 52dp 高、底边距 12，使页码箭头中心与
      52dp 删除/保存按钮中心同高。
      两者统一使用 `CaptureRoundButton`（52dp、24dp 图标），删除为错误色、
      保存为深蓝 `header` + 白图标；白底按钮在照片背景下对比不足。
      均二次确认；保存写入 `HistoryStore`（照片副本 + OCR 文本 + blocks + 模式/时间）。
61. **误区：在照片集正文再放一个“多选”或“全选”，或再加一行保存文字按钮。**
    - 正确做法：照片集标题栏只保留一个「多选」；多选页标题改为「选择照片」，
      正文只显示已选数量，全选放标题栏；删除/保存沿用同一
      `CaptureRoundButton` 图标，不再放“保存到语料库（后续支持）”等重复文字。
62. **误区：照片集保留“分析句子”按钮，把分词错误塞进结果区，或把复制放标题栏。**
    - 正确做法：用户要求删除分析按钮；已配置 UniDic 时 OCR 完成后自动分词，
      直接使用 `ReaderBlock`/`buildReaderLines` 按文本阅读页渲染，点词打开查词弹层。
      未配置时显示 OCR 原文；分词失败用**红色横幅叠在照片顶部、标题栏下方**，
      带白字“重试”，不能占用/推挤 OCR 结果区。
      复制按钮改为照片显示区右下角的深蓝 `header` 长条（白字白图标，文案
      「复制文本」）；
      标题栏只留字号/注音菜单和“多选”。字号/注音使用与阅读页同一个
      `ReaderOptionsMenu`（16/20/24/28 + 显示注音）。
63. **误区：照片区高度写死；拖拽指示条是白线外套灰色胶囊；拖拽有 slop 不跟手。**
    - 正确做法：照片区下边缘提供 40dp 拖拽热区，指示条必须是**纯白单色**
      44×4dp（不要深色胶囊/描边）；向下拖动扩大照片区（默认 250、最小 120，
      给结果/操作区留空间）。必须用 `Listener` 直接处理 pointer down/move/up，
      以 drag 起点的绝对位移计算高度，不能再用 `onVerticalDragUpdate` 的
      delta+slop（会慢半拍）。点击照片进入黑底全屏 `InteractiveViewer`，
      支持双指缩放与平移，参考系统画册。
64. **误区：MDict 批量导入完成弹结果对话框，或扫描时显示 MDD/CSS、Instance of 等英文。**
    - 正确做法：扫描行只显示路径、大小和中文状态（可导入/已存在/不支持），
      不追加 `MDD n · CSS n` 等英文尾注，也不显示原始英文异常；扫描进度不显示
      文件名。词典标题若是 `Instance of ...`/`Exception ...` 等 Dart 调试文本，
      用 `displayDictionaryTitle` 回退文件名。词典管理的资源标签使用
      “资源/样式/无资源”。导入结束后直接返回词典管理页；仅在失败/取消时用
      非阻塞 SnackBar 报告数量，不要弹“导入结果”对话框。
65. **误区：本地导入模型按 manifest 的 det.onnx/rec.onnx 精确文件名匹配。**
    - 正确做法：上游下载常为两个 `inference.onnx` + `inference.yml`；按
      文件大小、扩展名和角色映射，命中已安装文件时只补缺失项；先写
      `.importing` 校验再替换，失败清理临时文件。
66. **误区：改模型目录只改 UI 文本，或先保存路径再迁移失败。**
    - 正确做法：先校验新目录读写/空间；默认复制并逐文件校验后再保存设置
      和删除旧文件，支持“仅切换”；目录失效时保留设置并提供重新选择，
      不崩溃、不清空其他设置。
67. **误区：每次从模型设置/多选/其它页面返回照片集都重新 OCR。**
    - 正确做法：OCR 缓存键是“照片 + 模式 + 模型指纹”，模式存在
      `CaptureSessionState.mode`（会话级，不得因页面重建重置为自动）。
      `OcrService.fingerprint` 在应用会话内保留；照片集先用它查缓存并直接渲染，
      无需 `ensureReady`。模型设置返回时只有指纹变化才清缓存并 `force`
      重新识别；指纹不变必须 `_refreshCurrent(force:false)`。多选页传入
      `initialFingerprint`，进入时先查缓存，只补识别缺失照片；全部命中时
      不要显示/闪一下进度。
68. **误区：主页功能按钮仍在最上方，使用前须知在下方。**
    - 正确做法：使用前须知卡片在上方；四个功能按钮在剩余空间垂直居中
      （小屏可滚动）。保持深蓝 `header`、32sp、整体居中。
69. **误区：语料页沿用 72dp 缩略图和右侧小删除按钮；点击语料仍跳文本阅读页。**
    - 正确做法：语料列表与详情标题栏右上角都提供 `ReaderOptionsMenu`；列表 OCR
      与详情 OCR/分词都按 `readerFontSize` 渲染。语料卡片展示完整大照片
      （`BoxFit.contain`，最大 `corpusPhotoMaxHeight`），右上角叠放与照片集同款的
      错误色圆形删除按钮（`corpusAction` 44dp，可适当缩小）；照片下是完整
      OCR 文本，再下是日期与 **卡片右下角**的深蓝 `PhotoCopyButton`（不要压在
      照片右下角，这是预览列表与查看页的区别）。
      点击卡片进入 `/corpus-detail`（`CorpusDetailPage`）：照片/OCR/分词结果，
      照片右下同样有「复制文本」按钮，语料间页码，标题「语料」，左下角删除；
      无多选/方向/模型设置/保存。该页只使用本机图片、`HistoryStore`、
      MeCab/MDict，不得联网。
70. **误区：语料详情把 OCR 原文和分词结果只显示其中一种。**
    - 正确做法：两者都显示：OCR 原文（`SelectableText`）+ 分词结果
      （`ReaderBlock`，可点词查词）；未配置 UniDic/失败时保留 OCR 原文并给出
      中文说明/重试。翻页/删除后重新分析当前语料，旧分析用 token 丢弃。
71. **误区：加入 MangaOCR 后仍只按 PaddleOCR 文件计算照片集缓存指纹。**
    - 正确做法：使用 `OcrRuntimePaths` + `fingerprintForPaths`，指纹包含
      Paddle、已安装的 MangaOCR（encoder/decoder/vocab）和 orientation 文件；
      可选模型缺失时写入 `manga=off` / `orientation=off`，安装/删除后必须使
      照片集缓存失效，否则 auto/vertical 会复用旧横向结果。
72. **误区：可选 MangaOCR/orientation 加载失败就让整个 OCR 初始化失败。**
    - 正确做法：Paddle 为必需；MangaOCR/orientation 独立加载，失败只记录
      `mangaError`/能力状态。横向 OCR 必须继续可用；只有手动 `vertical` 才
      返回 `MODEL_MISSING`/`MODEL_INVALID`，`auto` 在缺少 Manga 时回退横向。
73. **误区：用框高宽比单独判断竖向，方形字框组成的单列会误判为横排。**
    - 正确做法：`TextLayoutHeuristic` 额外识别“x 中心接近、y 连续堆叠”的
      方形框列（≥3 个、纵向跨度 ≥2.5 倍框高），作为竖向候选；仍由 MangaOCR
      处理。不要把它误当成横排 logo。
74. **误区：textline 180° 模型在只有一条文本行时永远不触发。**
    - 正确做法：两行以上要求 ≥2 个 180° 投票且占比 ≥0.6；只有一条高置信
      （≥0.99）180° 行时允许单独触发。旋转 180° 后必须重新跑 DBNet，不能只
      旋转识别用的 crop；坐标仍以旋转后的图像为准。

### 5.11 Phase 6 词典助手（设计阶段陷阱）

75. **误区：把图片/base64 或图片路径发给 LLM，让模型“顺便看看图”。**
    - 正确做法：图片只在本机走 OCR；provider 请求体只能包含文本、分词/词典
      工具结果和 schema。捕获请求测试必须断言没有图片字段/base64；严禁调用
      provider 的视觉能力。
76. **误区：严格模式没有词典依据时让模型补充一个“看起来合理”的答案。**
    - 正确做法：严格模式的事实性陈述必须有真实工具 citation；没有依据就明确
      说明未找到，不得编造词义/读音/翻译。宽松模式的模型补充必须与词典事实
      分开标注，不能混在一起。
77. **误区：把模型输出里的 `[来源1]` 直接当可信来源打开。**
    - 正确做法：citation ID 由 orchestrator 根据真实工具结果发放并校验；伪造/
      越界/失效 citation 只按普通文本显示，不能打开任意词典页。
78. **误区：API Key 放进 SharedPreferences、URL、日志或崩溃报告。**
    - 正确做法：使用 Android Keystore/安全存储；日志/导出/错误信息脱敏；提供
      清除 Key 和配置的入口；仓库中不得出现真实 Key。
79. **误区：每次新会话都重新让 Agent 探查词典。**
    - 正确做法：词典熟悉文档按词典路径/stat、UniDic 版本和 schema/prompt 版本
      缓存；用户确认后复用；词典变化/用户重置时失效。不要把熟悉文档写入用户的
      UniDic/MDict 目录。
80. **误区：允许 Agent 生成并直接执行任意 Dart/JS/Python 伪代码。**
    - 正确做法：转换成受验证的安全 DSL（白名单字段/样式），支持预览、用户确认、
      版本/回滚；统一 annotation engine 作用于所有 UniDic token 展示。禁止文件/
      网络/反射/任意代码执行。
81. **误区：为了 Phase 6 提前把主页改成五个按钮/改文案，或把 planned 写成已实现。**
    - 正确做法：当前仍是四个按钮；Phase 6 实施时先更新 README、CLAUDE、设计
      token 和测试，再改 UI。未实现前 README/CLAUDE 必须明确 planned/design。

### 5.12 Phase 4.5 OCR 收敛经验

82. **误区：每次 `ensureReady` 都重新创建全部可选 session / 全量 SHA-256。**
    - 正确做法：Paddle 必需；Manga/orientation 懒加载；readiness 先 stat；
      SHA 只对下载/导入/迁移等写入路径执行，并按
      path+size+mtime 缓存。不要把 `mangaReady` 当成 session loaded。
83. **误区：每次 auto 都跑 doc orientation，或在正方形/正常竖排页上旋转整图。**
    - 正确做法：只在图像长宽比与 DBNet 布局矛盾时运行；高置信 90/270 才旋转；
      旋转后必须重新 DBNet；textline 180° 只在 auto 横向。
84. **误区：按整页单路由处理混合排版。**
    - 正确做法：auto 下强横向框交 Paddle、其余交 Manga；横向页中至少两个强
      纵向框才交 Manga。合并结果的 engine 为 `paddle_v5+manga_ocr`，mixed 结果
      不得被手动模式缓存复用。
85. **误区：MangaOCR 固定 gap/padding，且不过滤低置信度噪声。**
    - 正确做法：gap/padding 按检测框中位尺寸缩放；清除控制/替换字符；低于保守
      阈值的 bubble 丢弃。不要为了提高召回保留明显乱码。
86. **误区：照片旋转直接改设备原图，或旋转后仍用旧 OCR 缓存。**
    - 正确做法：只旋转 `CaptureStorage` 私有会话副本 90°；清该照片 OCR 缓存、
      evict `FileImage`、重新识别；设备原图不变。

## 6. 关键文件

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
lib/features/corpus/corpus_page.dart                          # 语料大照片列表/删除
lib/features/corpus/corpus_detail_page.dart                   # 语料详情/OCR/分词/翻页
lib/services/storage/history_store.dart                       # 语料 SQLite + 图片副本
lib/features/settings/model_page.dart                         # OCR 模型/目录/迁移
lib/features/settings/dictionary_import_page.dart             # MDict 文件夹导入
lib/services/mdict/dictionary_scanner.dart                    # 递归扫描 isolate
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/     # Paddle/MangaOCR 原生实现
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/MangaOcrRecognizer.kt
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/TextLayoutHeuristic.kt
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/DocOrientationRecognizer.kt
packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/TextLineOrientationRecognizer.kt
lib/core/utils/kana.dart                                      # 假名转换
lib/core/utils/text_normalizer.dart                           # NFKC/假名/stripkey 候选
lib/services/mecab/unidic_validator.dart                      # UniDic 目录/头部校验
lib/services/mecab/mecab_output_parser.dart                   # 引号感知 CSV 解析
lib/services/mecab/mecab_service.dart                         # 私有 rc + 长生命周期 isolate
lib/services/mdict/mdict_worker.dart                          # MDict isolate / lookup / MDD
lib/services/mdict/mdd_key.dart                               # MDD key 变体
lib/services/mdict/entry_renderer.dart                        # HTML 清洗/CSS/MDD 重写
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
integration_test/ocr_android_test.dart                        # 横向/竖向/混合/90°/270°/180° OCR 设备测试
android/app/src/main/kotlin/com/rikai/mobile/MainActivity.kt  # 权限 MethodChannel 原生侧
android/app/src/main/AndroidManifest.xml                      # 文件权限
android/app/build.gradle.kts                                  # minSdk 26 / NDK 28
docs/DEVELOPMENT_PLAN.md                                      # MVP 计划（Phase 6 见设计草案）
docs/design-tokens.md                                         # UI 强制规范
assets/fonts/README.md                                        # 字体下载说明（字体不入库）
docs/phase0-status.md, docs/phase1-status.md,
docs/phase2-status.md, docs/phase3-status.md,
docs/phase3.5-status.md, docs/phase4-status.md               # 阶段验证结果
docs/phase4.5-status.md                                      # OCR 收敛（进行中）
docs/phase6-agent-design.md                                  # Phase 6 设计（未实现）
docs/dev-setup.md                                             # 构建/数据/缓存/集成测试
docs/adr/                                                     # 三个架构决策
tool/spike_mdict.dart                                         # MDict 主机 spike
integration_test/mecab_android_test.dart                      # 设备端 MeCab/权限/UI 测试
integration_test/mdict_android_test.dart                      # 设备端 MDict/渲染/UI 测试
third_party/overlay-translator/                               # Apache 许可/修改说明
third_party/paddleocr4android/                                # MIT 许可/可选后端说明
```

Phase 6 预计新增（**尚未创建**，实施时再落盘）：

```text
lib/features/agent/                                           # 对话/输入/模式/来源卡片
lib/services/agent/                                           # provider 适配、agent loop、工具 registry
lib/services/agent/tools/                                     # OCR/UniDic/MDict schema adapters
lib/services/agent/familiarization/                           # 词典熟悉文档生成/缓存
lib/services/agent/annotation/                                # 注音/标注安全 DSL 与统一渲染
lib/core/models/agent_models.dart                             # 会话/消息/工具调用/citation
lib/services/storage/agent_store.dart                         # 会话/熟悉文档/规则 SQLite
lib/services/security/secret_store.dart                       # API Key 安全存储
lib/services/agent/markdown_renderer.dart                     # Markdown/ruby/声调安全渲染
```

开发数据（不入库）：

```text
C:\Projects\Rikai-Mobile\unidic\unidic-cwj-202512\
  sys.dic 283.9MB, matrix.bin 1,029.5MB, char.bin 262KB, unk.dic 5.8KB, dicrc
C:\Projects\Rikai-Mobile\mdicts\講談社 日本語大辞典 第二版 双解版\
  .mdx 33.8MB (v2.0 UTF-8, 463,312 entries), .mdd 6.2MB, NihongoDaijiten.css
```

## 7. 环境、构建与验证

- Flutter 3.38.9 / Dart 3.10.8；Android Studio JBR 21；Android SDK 36；
  NDK **28.2.13676358**（`android/app/build.gradle.kts` 已固定）。
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
- 设备端 OCR 测试（真实模型按 `paddle_v5/`、`manga_ocr/`、`orientation/`
  放在 `/sdcard/Download/rikai-models/` 下；测试脚本会自动寻找
  `paddle_v5` 的父目录中的可选模型）：

```bash
export MSYS_NO_PATHCONV=1
flutter test integration_test/ocr_android_test.dart -d emulator-5554 \
  --dart-define=RIKAI_OCR_MODEL_DIR=/sdcard/Download/rikai-models/paddle_v5
```

  同样需要 appops 授权循环。当前套件 8 项：横向、横向懒加载、MangaOCR
  （自动+手动）、混合排版、90°、270°、倒置横向 180°、取消。应用内模型默认目录是
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
- Phase 6 尚未实现，当前没有 provider 测试命令或 API Key 配置。实施时必须加入
  fake-provider 集成测试、请求体“无图片/base64”断言、citation 解析/点击测试、
  strict/loose 模式测试、熟悉文档复用/失效测试、annotation DSL 校验测试和
  API Key 脱敏测试；不得用真实 Key 跑自动化测试。

## 8. 建议的下一个动作

1. 运行 `git status`；Phase 4 已提交为 `f287603`，Phase 6 文档已提交为
   `c2ae03d`；本次 Phase 4.5 改动默认未提交。不要覆盖或擅自 commit，除非用户
   明确要求。
2. 先完成 Phase 4.5 验收：arm64 真机横排 2048px <5s、单页漫画 <10s、无 OOM；
   横排/竖排/混合/倒置/90° 真实页回归；真实多气泡顺序/噪声质量。验收通过前
   不要开始 Phase 5。
3. 4.5 验收后进入 Phase 5：完整识别历史/语料管理、首次启动引导、设置/错误态/
   许可证页与 release 打磨。不要重写已验证的 Paddle 横向路径或 MangaOCR 基础
   流水线；新增优化（mask/panel、cross-bubble batching、INT8 draft、tiling）
   应作为独立增强并补回归。
4. Phase 6 必须先完成设计评审并得到用户批准，再按
   `docs/phase6-agent-design.md` 的顺序实施；Phase 6 不得抢占 Phase 4.5/5，
   在 Phase 5 未完成前不要开始 Phase 6 的 UI/数据层改造。
5. 进行实网模型下载验证（本机模拟器 DNS 不可用）：在可访问 hf-mirror 的
   设备上验证 PaddleOCR/MangaOCR/orientation 下载、断点续传、镜像回退、
   本地导入与许可确认；确认模型目录与删除流程。
6. 进行相机/照片集/多选/语料的 arm64 真机回归，重点验证 MangaOCR 竖排质量、
   连续多气泡页性能/内存，以及真实的 180°/90° 旋转照片；本机仅 x86_64。
7. 新 UI 必须遵循 `docs/design-tokens.md` 与 `app_tokens.dart`；不得硬编码
   颜色/字号，字体与模型文件不入库；**所有页面**统一深蓝顶栏和右滑覆盖转场。
   Phase 6 的五按钮/Agent UI 也必须先补 token，不能直接改现有四按钮。
8. 每个阶段结束运行 analyze/test/debug build（当前 112 unit tests / OCR 设备
   8 项；另有 MeCab 4、MDict 6），并记录到新的阶段状态文档；设备端测试按 §7
   的命令运行。
