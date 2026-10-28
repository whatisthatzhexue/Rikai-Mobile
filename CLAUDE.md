# CLAUDE.md — Rikai-Mobile handoff

> 给下一个 agent 的工作交接。先读本文件，再读 `docs/DEVELOPMENT_PLAN.md`（已批准的完整开发计划）、
> `docs/phase0-status.md` 和 `docs/phase1-status.md`（当前验证结果）。
> 用户使用中文沟通；代码/标识符用英文。

## 1. 项目是什么

Android 单端、完全离线的 Flutter 日语阅读/查词应用：

拍照或输入文本 → 横向 PaddleOCR / 纵向 MangaOCR → UniDic（用户自备）分词与注音 →
点击单词查询用户自备的 MDict 词典；另有搜索查词、词典偏好、语料保存。

- 项目根目录：`C:\Projects\Rikai-Mobile`（ASCII 路径，旧的 `E:\MyData\大工\...` 已不存在）
- 包名/applicationId/namespace：`com.rikai.mobile`
- Flutter 工程名：`rikai_mobile`
- 最低系统：minSdk 26；compileSdk/targetSdk 36；NDK 28.2.13676358
- 仅 Android；不做 iOS、不做云 OCR/云翻译/LLM。
- **UI 强制规范**：所有现有与新增界面必须遵循 `docs/design-tokens.md`
  （蓝/白、3x 设计稿 72/48/36 → Flutter 24/16/12sp、4pt 间距、紧凑组件）。
  实现入口是 `lib/core/theme/app_tokens.dart`；页面不得硬编码颜色/字号/间距。
  二次修正后：**所有页面**统一深蓝顶栏（`#003A99`、白字白图标、
  词条页 TabBar 白字），主页左侧抽屉为直角；主页四个 72dp 功能按钮
  使用与顶栏相同的深蓝色，图标+文字居中对齐，文字 32sp（比首版 40sp
  小 20%）。设置页为白底扁平分区、无卡片；长提示 14sp 必须完整换行，
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
- **字体**：HarmonyOS Sans SC Regular，路径
  `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`。字体文件**不入库**（`.gitignore`
  已忽略）；用户自行从华为 HarmonyOS 设计资源下载，见 `assets/fonts/README.md`。
  构建前必须存在，否则 Flutter 报缺失资产。应用图标源 `assets/Rikai_Icon.jpg`
  由 `flutter_launcher_icons` 生成 Android 图标（配置在 `pubspec.yaml`）。
- 仓库已有三次提交：`d0d94a3 feat: First Version`、`dc70cee docs: 更新文档`、
  `91dc386 feat: phase 1 UniDic tokenization, reader, and file access`。
  Phase 2 与设计规范改动当前仍在工作树中未提交；不要擅自 `reset`/`commit`，
  除非用户明确要求。

## 2. 已确认的架构决策（不要随意改）

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

## 3. 当前进展（Phase 0 + Phase 1 + Phase 2 已完成）

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

已验证：

```text
flutter analyze  -> No issues found
flutter test     -> 89 tests passed
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

**尚未完成 / 下一步：**

- Phase 3：横向 PaddleOCR + 拍照；先补 ORT 模型冒烟（见 §4）。
- Phase 4：纵向 MangaOCR、自动方向。
- 识别历史、语料保存、引导页未实现（Phase 5）。
- Release APK 尚未构建（不要在没有必要时重复跑长构建）。
- 没有 arm64 真机；只有 x86_64 模拟器 `Medium_Phone_API_36.1`。
  x86_64 仅验证功能，性能/竖排质量需 arm64 真机。

## 4. 未尽事宜（按优先级）

### 已完成：UniDic/MeCab + Phase 1

实现与验收记录见 §3、§6 和 `docs/phase1-status.md`。不要重写：

- 私有 `mecabrc` + `-r` 已在 Android 实测成功；
- 1.3GB UniDic 外部存储 mmap 可用；
- 29 字段映射与引号 CSV 解析已由真实词典验证；
- All Files Access 原生通道已实现。

### 待完成：ORT 模型冒烟（Phase 3 前置）

- 下载 PaddleOCR det/rec 与 MangaOCR encoder/decoder（hf-mirror 可用）；
- 在插件里打开 ORT session，跑一张合成日文图片，确认模型算子/输入输出名；
- 记录耗时/内存。

### 已完成：Phase 2

实现与验收见 §3、§6 和 `docs/phase2-status.md`。不要重写 MDict worker、
lookup/`@@@LINK`、EntryRenderer、搜索/词条/词典管理页。已知限制：
每词典最多 3 条、CSS 发现为目录内全部、MDD 缓存未清理、无模糊搜索。

### Phase 3：横向 PaddleOCR + 拍照

- 从 `overlay-translator`（Apache-2.0）抽取最小 Kotlin OCR 核心到
  `packages/rikai_ocr/android/...`：
  - `PaddleDetector` / `PaddleRecognizer` / `DBPostprocessor` / `BitmapPreprocessor`；
  - 方向启发式；阅读顺序；段落合并；
  - 删除 Hilt/Compose/Settings/R/BuildConfig/ML Kit/翻译/悬浮窗/截屏。
- `ModelManager`（Dart）：manifest、hf-mirror/HF/自定义镜像、Range 续传、
  SHA-256/大小校验、本地导入、删除。
- 拍照/相册（`image_picker`）、EXIF、最长边 ~2048、方向选择、进度、取消。
- MethodChannel 返回 blocks（text + 四点框 + confidence + orientation）。
- 横向 OCR → 阅读器 → 点击查词串通。

### Phase 4：纵向 MangaOCR + 自动方向

- 抽取 `MangaOcrEngine` 的 encoder/decoder、气泡聚类、crop planner、tiling、
  碎片合并、振假名噪声过滤；与 PaddleDetector 共用 DBNet。
- 自动方向：框几何 + 可选 doc/textline orientation；手动覆盖；90/180° 重跑。
- 纵向 RTL 阅读顺序；FP32 decoder；INT8 draft 为 P2。
- 目标 <10s/页（中端 arm64），注意内存。

### Phase 5：语料保存/打磨/发布

- `HistoryStore`（sqflite）：图片压缩、OCR blocks JSON、全文、引擎、方向、时间。
- 首次启动引导（权限 → UniDic → 词典可选 → 模型可选 → 许可证）。
- 设置、错误/空状态、字体、无障碍、关于/许可证页。
- Release：arm64、R8、`--split-per-abi`；许可证审计；README/dev-setup 完善。

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
24. **误区：加 iOS/云 OCR/ML Kit/LLM 会更完整。**
    - 正确做法：范围锁定 Android 单端、完全离线；OCR 用 ONNX；不引入 ML Kit
      （专有条款）、云 OCR、LLM、iOS。
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
lib/features/reader/                                          # 文本阅读区
lib/features/lookup/                                          # 查词弹层/搜索/词条/WebView
lib/features/settings/settings_page.dart                      # UniDic/权限/显示设置
lib/features/settings/dictionary_page.dart                    # 词典管理
lib/state/providers.dart                                      # Riverpod providers
packages/mecab_for_dart/                                      # vendored MeCab（补丁见 MODIFICATIONS.md）
packages/rikai_ocr/                                           # OCR 插件骨架 + ORT
assets/models/manifest.json                                   # 模型清单（不含模型本体）
android/app/src/main/kotlin/com/rikai/mobile/MainActivity.kt  # 权限 MethodChannel 原生侧
android/app/src/main/AndroidManifest.xml                      # 文件权限
android/app/build.gradle.kts                                  # minSdk 26 / NDK 28
docs/DEVELOPMENT_PLAN.md                                      # 已批准计划
docs/design-tokens.md                                         # UI 强制规范
assets/fonts/README.md                                        # 字体下载说明（字体不入库）
docs/phase0-status.md, docs/phase1-status.md,
docs/phase2-status.md                                         # 阶段验证结果
docs/dev-setup.md                                             # 构建/数据/缓存/集成测试
docs/adr/                                                     # 三个架构决策
tool/spike_mdict.dart                                         # MDict 主机 spike
integration_test/mecab_android_test.dart                      # 设备端 MeCab/权限/UI 测试
integration_test/mdict_android_test.dart                      # 设备端 MDict/渲染/UI 测试
third_party/overlay-translator/                               # Apache 许可/修改说明
third_party/paddleocr4android/                                # MIT 许可/可选后端说明
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
  **hf-mirror.com 可用**（模型默认镜像）。maven.google.com 超时，但 Gradle
  `google()` 走 dl.google.com，正常。
- Gradle 全局脚本缓存曾损坏（`metadata.bin` 缺失）。修复：
  `cd android; .\gradlew --stop;` 然后把
  `%USERPROFILE%\.gradle\caches\8.14\{kotlin-dsl,groovy-dsl,transforms,generated-gradle-jars,dependencies-accessors}`
  移走并重建；不要动 `modules-2`。详见 `docs/dev-setup.md`。
- Windows 主机 `dart run tool/spike_mdict.dart` 在根包会触发 MeCab native-assets
  hook 失败；用隔离 Dart 包运行（复制脚本 + 只依赖 `dict_reader`）。

## 8. 建议的下一个动作

1. 运行 `git status`；Phase 2 与设计规范改动尚未提交，不要覆盖或擅自 commit。
2. 先补 ORT 模型冒烟（PaddleOCR det/rec、MangaOCR encoder/decoder，
   hf-mirror 可下载），确认 ORT session 与输入输出。
3. 进入 Phase 3：抽取 PaddleDetector/PaddleRecognizer/DBPostprocessor/
   TextBlockReadingOrder，做 ModelManager、拍照/相册与横向 OCR 阅读器串联。
4. 新 UI 必须遵循 `docs/design-tokens.md` 与 `app_tokens.dart`；不得硬编码
   颜色/字号，字体文件不入库；主页深蓝顶栏只用于主页，不要改全局 AppBarTheme。
5. 每个阶段结束运行 analyze/test/debug build（当前 89 tests / 10 项设备测试），
   并记录到新的阶段状态文档；设备端测试按 §7 的命令运行。
