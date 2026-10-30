# Rikai-Mobile 开发计划

> 目标：Android 单端、核心离线的 Flutter 日语阅读/查词应用。用户拍照或输入文本 → 横向 PaddleOCR / 纵向 MangaOCR → UniDic 分词与注音 → 点击单词查询用户自备的 MDict 词典；支持搜索查词、词典偏好、语料保存。
>
> 本计划基于 2026-10-26 对两个克隆仓库、UniDic/MDict 实际数据、本机 Flutter/Android 环境和网络连通性的调研。已确认的产品/技术决策见 §3。
>
> **Phase 6（Mdict Agent）是后期设计扩展，未纳入本 MVP 的时间估算。** 设计指南见
> `docs/phase6-agent-design.md`。MVP 的 OCR/UniDic/MDict 核心仍离线；Phase 6 才会
> 引入用户自备 API Key 的可选在线 LLM。Phase 6 开工前需 Phase 5 完成并经用户批准。
>
> **Phase 4.5（OCR 质量与性能收敛）已插入 Phase 4 与 Phase 5 之间。** 记录见
> `docs/phase4.5-status.md`。该阶段已于 2026-10-30 通过 arm64/真实设备验收并关闭；
> **Phase 5（语料/历史、首次引导与发布打磨）也已于 2026-10-30 完成并由用户确认。**
> 下一步是 Phase 6 设计评审与用户批准，未批准前不实施。

---

## 1. 背景与目标

初始文档的核心诉求：

1. 阅读日语原版书/街景时，用手机拍照留存语料，不再跳转 EB Pocket 等外部词典 App。
2. OCR 支持横写/竖写；横写优先 PaddleOCR，竖写优先 MangaOCR；用户可手动选择或让应用自动判断。
3. 文本经 UniDic 分词，每个词单元显示注音；点击词单元自动查 MDict。
4. 支持基础搜索查词、词典选择偏好（本次搜索使用哪些词典）。
5. UniDic 与 MDict 全部由用户提供，应用只负责加载、分词、信息提炼与词典检索。
6. MVP 核心完全离线；尊重 overlay-translator（Apache-2.0）与 PaddleOCR4Android（MIT）的许可证；模型大文件不入库。Phase 6 的可选在线 Agent 见 §11，不属于本 MVP 的离线承诺。

本期交付：可安装的 Android APK（arm64-v8a）、完整源码、开发/构建文档、许可证清单。

---

## 2. 调研结论（决定实现方式的事实）

### 2.1 UniDic（用户自备，开发期在 `unidic/`）

- 版本：現代書き言葉 UniDic ver. 2025.12，MeCab 编译后的二进制格式，**不是 CSV**。
- 必需运行文件：`sys.dic`（283.9MB）、`matrix.bin`（1,029.5MB）、`char.bin`（262KB）、`unk.dic`（5.8KB）、`dicrc`（1KB），合计 **约 1.313GB**。
- `sys.dic` 头部：版本 102、UTF-8、1,027,505 条词条。
- 许可证：GPL v2 / LGPL v2.1 / 修正 BSD 三选一；本项目**不随包分发**，仅读取用户路径，但仍需在“关于/许可证”中提示。
- 无 `mecabrc`；`mecab_for_dart` 默认强制 `-r <dicdir>/mecabrc`，直接使用原始目录会失败，且不应向用户的 UniDic 目录写文件。
- 29 个特征字段（已通过 `sys.dic` 样本验证）：
  - `0-3` pos1-4，`4` cType，`5` cForm，`6` lForm/語彙素読み，`7` lemma，`8` orth，`9` pron，`10` orthBase，`11` pronBase，`12` goshu；
  - `20` kana（仮名形出現形，**注音首选**），`21` kanaBase，`24-26` accent，`27` lid，`28` lemma_id。
- 1GB 矩阵必须按需 mmap，不能整体读入 Dart 内存；64 位 ABI 基本是硬要求。

### 2.2 MDict（用户自备，开发期在 `mdicts/`）

- 测试词典：講談社 日本語大辞典 第二版 双解版。
- `MDX`：33.8MB，MDict **v2.0**，UTF-8，`Encrypted="No"`，HTML，zlib 记录块，463,312 条词条，391 个 key block。
- `MDD`：6.2MB，v2.0，9,220 个资源；MDX 的 `StyleSheet` 为空，旁边有独立 `NihongoDaijiten.css`（6.1KB）。
- 可用 Dart 包 `dict_reader`（MIT，1.6.1）：
  - 支持 MDX/MDD v2，本次数据可直接读取；
  - API：`init` / `locate` / `locateAll` / `readOneMdx` / `readOneMdd` / `search(prefix, limit)`；
  - 使用 `RandomAccessFile` + 记录块缓存，不会整体载入词典；
  - 限制：不支持 LZO、record block 加密、checksum 校验；v3 支持不完整。导入时必须预检并给出明确错误。
- 463k 词条的 key 列表常驻内存的量级可接受（估算几十 MB），但首次 `init(readKey: true)` 需要实测；如过慢，使用 `exportCache/importCache` 或自建 SQLite key 索引作为后备。

### 2.3 OCR 仓库

**overlay-translator（Apache-2.0，Copyright 2026 ciddwd）**

- 已有成熟的端侧 OCR：
  - `PaddleOcrEngine`：PP-OCRv5 mobile **ONNX** 检测（DBNet）+ 识别（CTC），方向分类，框合并；
  - `MangaOcrEngine`：复用同一 DBNet 检测 → 气泡/文本块聚类 → manga-ocr ONNX（ViT encoder + 自回归 decoder）识别；
  - `AutomaticOcrRecognizer` + `OrientationClassifier` + `PaddleDocOriClassifier` + `PaddleTextLineOrientationClassifier`：自动横/竖排、旋转判别；
  - `TextBlockReadingOrder`：横排 LTR、竖排 RTL、漫画分栏阅读顺序；
  - `DBPostprocessor`：**纯 Kotlin** DBNet 后处理，无 OpenCV。
- 推理运行时：ONNX Runtime **1.28.2**（Java API，无自定义 JNI）。
- 模型：
  - PaddleOCR v5 mobile det/rec ONNX + `inference.yml` 内嵌字典，约 22MB，Apache-2.0；
  - manga-ocr 2025 ONNX：`encoder_model.onnx` ~22MB、`decoder_model.onnx` ~118MB、`vocab.txt` 6144 行 + 4 个 JSON，约 140MB（含 INT8 draft 约 205MB）；模型卡**未声明许可**，只能下载使用、不得随包分发；
  - 方向模型 `doc_ori.onnx` 6.8MB、`textline_ori.onnx` 1.0MB，Apache-2.0；
  - 气泡检测器 `detector-v4-s_int8.onnx` 11.1MB（Apache-2.0）仅用于译文气泡渲染，本项目 OCR 不需要。
- 可复用核心约 **9,200 行 / 34 个文件**；但耦合 Hilt、Compose、`Settings`、`BuildConfig`、`R`、Timber、ML Kit、翻译/悬浮窗逻辑，需要裁剪。已有 124 个 OCR 单元测试，可移植相关用例。
- 注意：`PaddleOcrEngine.close()` 会关闭共享 `OrtEnvironment`，而 `MangaOcrEngine` 依赖共享环境；抽取时必须改为应用级单例，避免重复关闭。

**PaddleOCR4Android（MIT，Copyright 2026 jangviktor-web）**

- `:PaddleOCR4Android` 是可独立打包的 Android library：
  - Paddle Lite C++/JNI + **OpenCV 4.2.0 静态链接**；`libNative.so` + 预编译 `libpaddle_light_api_shared.so` 等；
  - 仅 `arm64-v8a` / `armeabi-v7a`，**无 x86_64**；
  - 构建需要 **NDK r21e**（NDK 25+ 与 Paddle Lite 符号冲突）；OpenCV SDK 源码约 313MB；
  - 模型：PP-OCRv5 mobile `det.nb` 5.0MB + `cls.nb` 1.0MB + `rec.nb` 16.7MB，配套 `ppocr_keys_ocrv5.txt`（18,383 行，含日文）；
  - 仅支持横排；竖排会被当作 90° 旋转文本处理；
  - `labelPath` 只能从 Android assets 读取；`simpleText` 顺序不可靠，应使用带四点框的原始结果。
- 结论：**不纳入 MVP 编译**。原因：与 MangaOCR 的 ORT 运行时重复、原生体积大、NDK r21/OpenCV 构建链重、无 x86_64、竖排不支持。
- 处理方式：保留 MIT 许可证与来源声明；在插件中抽象 `OcrBackend` 接口，二期可将其作为可选 Paddle-Lite 后端接入。横向 OCR 继续使用 PaddleOCR 的 PP-OCRv5 模型，只是后端为 ONNX Runtime。

### 2.4 本机环境与网络

- Flutter 3.38.9 / Dart 3.10.8（`enable-native-assets` 已开启）。
- Android SDK 36.1.0、build-tools 36.1.0、platforms 33–36、NDK 27.0.12077973 / 28.2.13676358、CMake 3.22.1。
- JDK：Android Studio JBR 21.0.8；Flutter 工具链可用。
- 无 Android 真机连接，仅有 `Medium_Phone_API_36.1` 模拟器；最终性能/竖排 OCR 需 arm64 真机验证。
- 网络：
  - Maven Central、pub.dev、dl.google.com、services.gradle.org 可用；
  - `maven.google.com`、GitHub 直连超时；
  - `huggingface.co` 直连超时，**`hf-mirror.com` 可用**（manga-ocr 与 PaddleOCR 模型文件均可下载）；
  - 模型下载默认 `hf-mirror.com` 优先、HF 原站兜底，并支持自定义镜像/本地导入。

---

## 3. 已确认的产品/技术决策

| 决策点 | 选择 |
|---|---|
| 平台 | Android 单端；Flutter；Release 仅 `arm64-v8a`（debug 额外支持 x86_64 以跑模拟器） |
| OCR 架构 | **统一 ONNX Runtime**：PaddleOCR PP-OCRv5 det/rec + MangaOCR，共用 DBNet；不编译 Paddle-Lite |
| PaddleOCR4Android | MVP 作为参考/可选后备；抽象 `OcrBackend`，保留 MIT 许可；二期可接 Paddle-Lite |
| MangaOCR 模型 | 默认从 `l0wgear/manga-ocr-2025-onnx` 下载（不随包分发），显示“许可未声明”提示；支持本地导入自定义 ONNX |
| UniDic 获取 | **仅原地路径**：不复制；用户授权“所有文件访问”后直接读取，或使用应用外部私有目录路径 |
| MDict 获取 | 同样原地路径；读取 `.mdx`、同名 `.mdd`、可选 `.css`；不复制 |
| 附加功能 | 核心 + **语料保存/识别历史**（照片、OCR 文本、分词结果） |
| 界面语言 | 简体中文；代码结构预留 i18n，但本期不实现多语言 |
| 渲染 | 词典 HTML 用离线 WebView（禁用 JS/网络，注入 CSS，解析 MDD 图片） |
| 分词 | MeCab + UniDic；vendored `mecab_for_dart` 2.0.5（BSD-3），原生资源构建 |
| 状态管理 | Riverpod + go_router；SQLite 存历史；SharedPreferences/JSON 存设置 |
| 最低系统 | minSdk 26，target/compileSdk 36 |

> 表中“离线/本地”均指 MVP 核心。Phase 6 的词典助手是 post-MVP 可选扩展，
> 用户可配置远程文本 LLM；它不是云 OCR，不使用视觉能力，图片仍只在本机 OCR。
> 详见 `docs/phase6-agent-design.md` 和 §11。

> 关于“仅原地路径”的重要后果：Android 11+ 需要 `MANAGE_EXTERNAL_STORAGE`（所有文件访问）才能读取 `/storage/emulated/0/...` 下的 UniDic/MDict；若用户拒绝，只能把文件放在 `/storage/emulated/0/Android/data/<包名>/files/` 等应用可访问目录，并在设置中填写该路径。应用不会复制 1.3GB 的 UniDic。该权限在 Google Play 上受限，本项目按 sideload/学习用途设计。

---

## 4. 目标架构

### 4.1 数据流

```
拍照/相册 ──> 图像预处理(EXIF/缩放) ──> rikai_ocr 插件(ONNX Runtime)
                                              │
                          ┌───────────────────┴───────────────────┐
                    横向: PaddleOCR det+rec                纵向: DBNet det → MangaOCR
                          └───────────────────┬───────────────────┘
                                              ▼
                                   List<TextBlock>（文本+四点框+方向+顺序）
                                              │
输入文本 ─────────────────────────────────────┤
                                              ▼
                              MeCab 工作 Isolate + UniDic（原地路径）
                                              ▼
                          Token{surface, lemma, kana, pos, ...} + 注音
                                              ▼
                         阅读区（词块 + 振假名，可点击）
                                              │
                              点击词 ──> MDict 工作 Isolate（dict_reader）
                                              ▼
                          多词典命中 → 离线 WebView 渲染（CSS + MDD 图片）
```

### 4.2 目录结构（目标）

```
Rikai-Mobile/
├─ pubspec.yaml
├─ analysis_options.yaml
├─ .gitignore
├─ README.md
├─ NOTICE
├─ THIRD_PARTY_NOTICES.md
├─ 项目初始文档.txt
├─ android/                                  # Flutter Android host
│  ├─ app/build.gradle.kts                   # minSdk 26 / target 36 / NDK 27 / arm64
│  └─ app/src/main/AndroidManifest.xml       # MANAGE_EXTERNAL_STORAGE 等
├─ assets/
│  ├─ models/manifest.json                   # 模型 URL/大小/SHA-256/许可（不含模型本体）
│  ├─ fonts/NotoSansJP-*.otf                 # 可选，保证日文字形
│  └─ licenses/                              # 各许可证文本
├─ lib/
│  ├─ main.dart
│  ├─ app.dart                               # MaterialApp / router / theme
│  ├─ core/
│  │  ├─ models/{token.dart,text_block.dart,dict_info.dart,ocr_result.dart}
│  │  └─ utils/{kana.dart,text_normalizer.dart,reading_order.dart,paths.dart}
│  ├─ services/
│  │  ├─ mecab/mecab_service.dart            # isolate 包装
│  │  ├─ mdict/mdict_worker.dart             # 长生命周期 isolate
│  │  ├─ mdict/dictionary_repository.dart
│  │  ├─ mdict/entry_renderer.dart            # HTML 清洗/CSS/MDD 重写
│  │  ├─ ocr/ocr_service.dart                 # MethodChannel
│  │  ├─ ocr/model_manager.dart               # 下载/校验/导入/删除
│  │  ├─ storage/settings_store.dart
│  │  ├─ storage/history_store.dart           # sqflite
│  │  └─ storage/permission_service.dart      # 所有文件访问
│  ├─ features/
│  │  ├─ onboarding/
│  │  ├─ home/
│  │  ├─ capture/{capture_page.dart,ocr_progress.dart}
│  │  ├─ reader/{reader_page.dart,token_chip.dart,furigana_text.dart}
│  │  ├─ lookup/{search_page.dart,lookup_sheet.dart,entry_page.dart}
│  │  ├─ history/{history_page.dart,history_detail.dart}
│  │  └─ settings/{settings_page.dart,unidic_page.dart,dictionary_page.dart,model_page.dart,licenses_page.dart}
│  └─ state/providers.dart
├─ packages/
│  ├─ rikai_ocr/                              # Flutter plugin（Android Kotlin + ORT）
│  │  ├─ lib/rikai_ocr.dart                   # MethodChannel/EventChannel API
│  │  └─ android/src/main/kotlin/com/rikai/ocr/
│  │     ├─ OcrPipeline.kt
│  │     ├─ PaddleDetector.kt / PaddleRecognizer.kt
│  │     ├─ MangaRecognizer.kt
│  │     ├─ DBPostprocessor.kt
│  │     ├─ Orientation.kt / TextBlockReadingOrder.kt
│  │     └─ OcrChannel.kt
│  └─ mecab_for_dart/                         # vendored 2.0.5，BSD-3，打补丁
│     ├─ hook/build.dart
│     ├─ src/...                              # MeCab C++ 源码
│     └─ lib/...
├─ third_party/
│  ├─ overlay-translator/{LICENSE,MODIFICATIONS.md,NOTICE}
│  └─ paddleocr4android/{LICENSE,README.md}   # 评估记录 + 可选后端说明
├─ test/                                      # 单元/Widget 测试
├─ integration_test/
├─ docs/{architecture.md,dev-setup.md,models.md,licenses.md,DEVELOPMENT_PLAN.md}
└─ tool/                                      # 模型校验、MDX 测试夹具、脚本
```

### 4.3 Flutter/Android 依赖

- `flutter_riverpod`、`go_router`
- `dict_reader`（MIT）
- `mecab_for_dart`（vendored path dependency，BSD-3）
- `onnxruntime-android:1.28.0`（Maven Central，MIT）
- `image_picker`、`image`（EXIF/缩放）
- `dio`、`crypto`（模型下载与 SHA-256）
- `path_provider`、`shared_preferences`、`sqflite`
- `flutter_inappwebview`（离线词典渲染）
- `permission_handler`（所有文件访问；辅以原生 MethodChannel）
- `package_info_plus`、`url_launcher`
- 可选：`unorm_dart`（NFKC）、`flutter_launcher_icons`

> 不引入 `flutter_html`：词典 CSS/表格/图片复杂，WebView 更接近桌面词典效果。
> MVP 不引入 Paddle-Lite/OpenCV、ML Kit、云 OCR/翻译/ASR/LLM。Phase 6 的
> 可选 Agent 是独立的后期扩展，不在本 MVP 依赖表内；详见 §11。

---

## 5. 关键设计

### 5.1 UniDic 与 MeCab

**获取与校验**

- 设置页输入/选择 UniDic 目录；检查 `sys.dic`、`matrix.bin`、`char.bin`、`unk.dic`、`dicrc` 是否存在且非空。
- 校验 `sys.dic` 头部：版本 102、UTF-8、词条数 > 0；`matrix.bin` 大小合理。
- 不向用户目录写入任何文件；路径存入设置，启动时重新校验；SD 卡移除/路径变化时显示修复提示。
- 权限：Android 11+ 引导授予 `MANAGE_EXTERNAL_STORAGE`；拒绝时提示把 UniDic 放到应用外部私有目录并填写该路径。Android 10 及以下使用 `READ_EXTERNAL_STORAGE`。不做复制。

**MeCab 集成**

- 将 `mecab_for_dart` 2.0.5 源码 vendored 到 `packages/mecab_for_dart`，用 `dependency_overrides` 指向本地路径，保留 `package:mecab_for_dart/...` 导入名。
- 补丁 `src/dart_ffi.cpp` 的 `generateArgs()`：
  - 新增 `rcPath` 参数（Dart API 增加可选 `rcPath`）；
  - 使用应用私有目录下的 `mecabrc`（内容可为空，或 `charset = UTF-8`），**不再要求 `<dicdir>/mecabrc`**；
  - 仍传 `-d <dicdir>`，不修改用户文件。
- 原生构建走 `hook/build.dart` + `native_toolchain_c`（Flutter 3.38 已启用 native assets）；NDK 固定 27.0.12077973；若 Android native assets 构建失败，回退方案：把 MeCab `src/unix` 源码用 CMake 编进 `packages/rikai_mecab` 本地插件（BSD 许可允许）。
- 工作 Isolate：`MecabService` 启动后懒加载，串行 `analyze`；`Mecab.transferableState` 支持跨 isolate。保留一个长生命周期 isolate，避免重复 mmap 模型。
- 输出：默认 `%m\t%H\n`（`mecab_sparse_tostr`），按 29 字段解析；字段数异常时记录并降级为“surface 可点击、无注音”。

**Token 与注音**

- `Token` 字段：`surface`、`pos1..4`、`lemma`、`orth`、`orthBase`、`pron`、`pronBase`、`kana`、`kanaBase`、`goshu`、`cType/cForm`、`lid/lemmaId`、`start/end`。
- 注音优先级：`kana`(20) → `pron`(9) → `lForm`(6) → `surface`；片假名转平假名（`ァ-ヶ` → `ぁ-ゖ`，处理 ヴ/ヷ-ヺ，保留 ー/・/小写 ヵヶ）。若 UniDic 对未知词没有读音，可选从 MDict 词条 HTML 中提取读音作为兜底（P2，避免频繁查词典影响性能）。
- 词性样式：`名詞/動詞/形容詞/副詞/連体詞/接頭辞/接尾辞/感動詞` 为内容词，高亮可点击；助詞/助動詞/補助記号/記号 弱化显示但仍可点击。
- 查词候选（按顺序去重）：`orthBase` → `lemma` → `orth` → `kanaBase` → `kana` → `pron` → `surface`；再做平/片假名互转与 MDict stripkey 归一化。
- 行处理：OCR 文本按换行拆行，逐行分词以保留换行；无换行的块整体分词。
- 可选 P2：仅对汉字部分显示振假名（去掉匹配的送假名），减少重复注音。

### 5.2 MDict 词典

**导入与元数据**

- 设置页添加词典：选择/输入 `.mdx` 路径；自动发现同目录同名 `.mdd` 和 `.css`；允许额外添加 `.mdd`/`.css`。
- 读取 MDX header：标题、词条数、编码、版本、是否加密、StyleSheet；不接受 LZO/record 加密；失败时显示具体原因。
- 词典注册表（JSON）：`id`（路径哈希）、`title`、`mdxPath`、`mddPaths`、`cssPath`、`numEntries`、`enabled`、`order`、`lastValidated`。
- 不复制文件；路径失效时标记为不可用，不自动删除记录。

**查询**

- 长生命周期 `DictionaryWorker` isolate，持有每个词典的 `DictReader`；懒初始化。
- `lookup(word, dictIds)`：
  1. 归一化查询（NFKC、全/半角、平/片假名、stripkey 去空格/标点、大小写）；
  2. 对每个候选调用 `locateAll`，`readOneMdx` 读取；
  3. 处理 `@@@LINK=目标` 重定向（最多 3 层，防环）；
  4. 多词典结果按词典顺序分组返回。
- 无命中时：`search(prefix, limit: 30)` 返回建议词；若查询是活用形，先用 MeCab 分析并取 `lemma/orthBase` 再查。
- 性能：首次 `init(readKey: true)` 需实测；若 > 3s 或内存过高，启用 `exportCache/importCache` 或自建 SQLite key 索引。463k 词条目标：热查询 < 300ms。
- 方言/表记差异：候选中保留 hiragana↔katakana 变体；不做模糊编辑距离（MVP）。

**HTML 渲染**

- `EntryRenderer` 在 Dart 侧读取原始 HTML，使用 `package:html` 清洗：
  - 移除 `<script>/<iframe>/<object>/<embed>/<form>`、`on*` 事件属性、`javascript:` URL；
  - 保留正文、表格、ruby、图片、内联样式；
  - 处理 `entry://` 链接（转为应用内查词导航）、忽略 `sound://`。
- CSS：若 MDX `StyleSheet` 为空，读取旁边 CSS（如 `NihongoDaijiten.css`），注入 `<style>`；再注入阅读优化样式（字体、行高、最大宽度、暗色适配）。
- MDD：按需从 MDD 读取资源并缓存到应用缓存目录（按词典 id + 资源 key 哈希命名）；把 HTML 中的 `src` 重写为 `file://` 本地路径；缺失图片显示占位符。
- WebView（`flutter_inappwebview`）：
  - `javaScriptEnabled: false`、`blockNetworkLoads: true`、仅允许本地文件；
  - `loadDataWithBaseUrl` 指向缓存目录；
  - `shouldOverrideUrlLoading` 拦截外部 URL 与 `entry://`；
  - 每个词条页一个 WebView，退出释放。
- 暗色模式：优先保持词典原色；提供“深色阅读”开关，对白色背景做 CSS 反转/覆盖（可配置）。

### 5.3 OCR 插件

**抽取范围（overlay-translator，Apache-2.0）**

- 保留核心：
  - `PaddleOcrEngine` 的检测/识别逻辑，拆成 `PaddleDetector`、`PaddleRecognizer`；
  - `DBPostprocessor`、`PaddleDetectionSizing`、`PaddleQuadDeduplicator`、`PaddleTextColumnSplitPolicy`、`PaddleRotateCrop`、`PaddleRecognitionPipeline`、`PaddleRecognitionSizing`、`PaddleTextLineOrientationClassifier`；
  - `MangaOcrEngine` 的 encoder/decoder 与裁剪/聚类/合并策略：`MangaOcrCropPlanner`、`MangaOcrTiling`、`MangaOcrQuadFusion`、`BubbleClusterer`、`MangaOcrBatchPolicy`、`MangaOcrNoiseFilter`、`MangaOcrFragmentPolicy`、`MangaRecognizedTextConsolidator`、`MangaFreeTextParagraphRegrouper`、`MangaPanelGroupingPolicy`；
  - `TextBlock`、`TextBlockReadingOrder`、`OrientationClassifier`、`PaddleDocOriClassifier`、`BitmapPreprocessor`、`CpuThreadPolicy`、`ReusableDirectBufferPool`、`InferenceTiming`；
  - 可选 P2：`MangaSpeculativeDecoding`（INT8 draft），MVP 先只用 FP32 decoder。
- 删除：Hilt/Compose/DataStore/Settings/R/BuildConfig/LogRepository/ML Kit/云 OCR/翻译/悬浮窗/ASR/截屏/无障碍/气泡擦除/译文排版。
- 许可证：每个复制文件保留 Apache 头；`third_party/overlay-translator/MODIFICATIONS.md` 记录改动；根 `NOTICE` 增加 attribution。

**原生接口（MethodChannel `rikai/ocr`）**

```text
initialize(modelPaths) -> readiness
recognize(imagePath, mode, crop?, options?) -> OcrResult
  mode: auto | horizontal | vertical
  OcrResult: engine, elapsedMs, blocks[{text, points, rect, confidence, orientation, granularity}]
cancel()
dispose()
EventChannel: model load/prewarm/OCR stage progress
```

- 图像以**文件路径**传入，Kotlin 侧 `BitmapFactory` 解码，避免大 Bitmap 过 Channel；EXIF 旋转在 Kotlin 或 Dart 预处理阶段完成。
- `OcrBackend` 抽象：
  - `OnnxOcrBackend`（MVP）；
  - `PaddleLiteOcrBackend`（二期可选，接 PaddleOCR4Android AAR）。
- ORT：`OrtEnvironment` 应用级单例，不随引擎关闭；R8 keep `ai.onnxruntime.**`；`abiFilters` debug 加 x86_64、release 只 arm64。
- 串行化 `recognize`；取消用协程 job；错误码：`MODEL_MISSING/MODEL_INVALID/IMAGE_DECODE_FAILED/OOM/ENGINE_ERROR/CANCELLED`。

**流水线**

1. 解码 → EXIF 纠正 → 限制最长边 ~2048px（保留坐标比例）。
2. `PaddleDetector` 跑 DBNet 一次，得到文本行 quads。
3. 方向：
   - 手动模式直接选引擎；
   - 自动模式：`HeuristicOrientationClassifier.refineWithBoxes` 根据框高宽比判断；可选 `doc_ori/textline_ori` 处理整图旋转；低置信度默认横向。
4. 横向：对 quads 做透视裁剪 → `PaddleRecognizer` CTC 解码 → 可选 180° cls → 行合并成段落 → 横向 LTR 排序。
5. 纵向：quads → 气泡/列聚类 → `MangaOcrCropPlanner` 裁剪 → `MangaRecognizer`（encoder 224×224 + 贪心 decoder，vocab 6144）→ 去振假名噪声/碎片合并 → 纵向 RTL 排序。
6. 输出 `TextBlock` 列表；Dart 侧再做一次阅读顺序与段落分组校正。

**模型管理（Dart `ModelManager`）**

- `assets/models/manifest.json` 记录每个模型文件的名称、URL 列表、大小、SHA-256、许可证、来源；仓库不含模型二进制。
- 默认下载顺序：`hf-mirror.com` → `huggingface.co` → 用户自定义镜像；支持本地文件导入（文件选择器）。
- 断点续传（HTTP Range）、进度、取消、重试；下载到 `.part`，校验后原子重命名。
- 模型集：
  - `paddle_v5`：`det.onnx`（PP-OCRv5 mobile det，固定 revision）、`rec.onnx`（PP-OCRv5 mobile rec，固定 revision）、`keys.yml`（rec 的 inference.yml，内嵌字符表）；约 22MB，Apache-2.0。
  - `manga_ocr`：`encoder_model.onnx`、`decoder_model.onnx`、`vocab.txt`、`config.json`、`generation_config.json`、`preprocessor_config.json`、`special_tokens_map.json`；约 140MB（可选 draft 约 45MB）；来源 `l0wgear/manga-ocr-2025-onnx`，**许可未声明，不随包分发**；下载前必须显示提示并要求确认。
  - `orientation`：`doc_ori.onnx`、`textline_ori.onnx`；约 7.5MB，Apache-2.0。
- 模型缺失时：OCR 按钮引导下载；文本输入/查词不受影响。
- 目录：`getExternalFilesDir()/models/{paddle_v5,manga_ocr,orientation}`；支持删除/重新校验。

### 5.4 阅读器与注音 UI

- 页面：顶部图片缩略图/来源、重新 OCR、复制全文、注音开关、字号；正文按块显示。
- `ReaderBlock`：`Wrap` 排列 `TokenChip`；每个 chip = 上方小号振假名 + 下方词形；标点/空白不显示注音。
- 点击词：底部 `LookupSheet`，显示 surface/读音/lemma/词性，词典筛选 chips，按词典分组的结果；点击结果进入 `EntryPage`（WebView）。
- 无词典命中：展示前缀建议、可点“用 UniDic 词形再查”；无 UniDic 时仅显示文本。
- 文本输入页复用同一阅读器；输入后立即分词。
- 字体：日文正文优先内置 Noto Sans JP（OFL）或系统 JP 字体，避免中文设备把日文汉字渲染成中文字形；UI 文案用系统字体。
- P2：竖排显示、仅汉字振假名、长按复制/朗读。

### 5.5 语料保存/历史

- OCR 成功后自动保存一条记录（可设置关闭）：
  - 压缩后的原图（最长边 2048，JPEG 85）存 `history/images/<uuid>.jpg`；
  - OCR blocks（JSON）、全文、引擎、方向、耗时、创建时间、标题（首行前 30 字）。
- 文本输入会话可手动“保存到语料”。
- SQLite（`sqflite`）表 `sessions(id, created_at, title, image_path, text, blocks_json, engine, orientation)`。
- 历史页：缩略图/标题/时间列表；打开 → 阅读器（重新分词，保证使用当前 UniDic）；删除/清空；缓存大小显示。
- 隐私：全部本地；不做云同步；卸载即删除。

### 5.6 设置、模型与权限

- 设置页分组：UniDic、词典、OCR 模型、显示、存储、权限、关于/许可证。
- UniDic：路径、校验状态、文件清单、重新选择、说明 GPL/LGPL/BSD。
- 词典：添加/排序/启用/删除、词条数、路径、打开测试词。
- 模型：每个模型集状态、大小、来源/许可、下载/导入/删除、镜像设置。
- 显示：注音开关、字号、主题、默认 OCR 方向、自动保存历史。
- 权限：所有文件访问状态、跳转系统设置、应用私有目录说明。
- 许可证页：`showLicensePage` + 自定义 `LicenseRegistry`，列出 overlay/PaddleOCR/ORT/MeCab/dict_reader/UniDic 说明。

### 5.7 许可合规与仓库卫生

- 根 `NOTICE` / `THIRD_PARTY_NOTICES.md`：
  - overlay-translator：Apache-2.0，Copyright 2026 ciddwd；列出修改；
  - PaddleOCR4Android：MIT，Copyright 2026 jangviktor-web；说明 MVP 未编译，作为可选后端；
  - MangaOCR 原项目 kha-white（Apache-2.0）；当前下载源 l0wgear 许可未声明，**不随包分发**；
  - PaddleOCR/PP-OCRv5 模型、PP-LCNet 方向模型：Apache-2.0；
  - ONNX Runtime：MIT + ThirdPartyNotices；
  - MeCab / mecab_for_dart：BSD-3；
  - dict_reader：MIT；
  - UniDic：GPL/LGPL/BSD，用户自备，不随包分发；
  - MDict 词典：用户自备，不随包分发。
- `third_party/overlay-translator/LICENSE`、`MODIFICATIONS.md`；`third_party/paddleocr4android/LICENSE` + 评估说明。
- `.gitignore` 关键项：
  ```gitignore
  /unidic/
  /mdicts/
  /overlay-translator/
  /PaddleOCR4Android/
  **/*.onnx
  **/*.nb
  **/*.pdmodel
  **/*.pdiparams
  **/*.tflite
  **/*.gguf
  **/models/**/*.onnx
  build/
  .dart_tool/
  .gradle/
  local.properties
  key.properties
  *.jks
  *.keystore
  ```
  保留 `assets/models/manifest.json` 与所有源码/许可证。
- 不提交用户词典、UniDic、模型；不提交 `local.properties`、签名文件。
- 第一个实现任务：把本计划落盘为 `docs/DEVELOPMENT_PLAN.md`。

---

## 6. 分阶段实施计划

> 估算按 1 人全职开发；每个 Phase 结束必须可构建、可演示、有验收记录。

### Phase 0 — 基建与可行性验证（2–3 天）

任务：

1. `flutter create --org com.rikai --project-name rikai_mobile --platforms=android .`；将 `applicationId`/`namespace` 统一为 `com.rikai.mobile`；配置 minSdk 26 / compileSdk 36 / NDK 27、arm64 release、debug x86_64；`.gitignore`、`NOTICE`、许可证目录。
2. 建立 `packages/rikai_ocr` 插件骨架；`packages/mecab_for_dart` vendored + `dependency_overrides`；写入 ORT 依赖与 R8 keep 规则。
3. **Spike A**：Android 模拟器/真机上加载 1.3GB UniDic（原地路径），验证 MeCab native assets 构建、`mecabrc` 补丁、分词输出 29 字段。
4. **Spike B**：用 ORT 跑 PP-OCRv5 det/rec 与 MangaOCR 模型；通过 hf-mirror 下载；验证 x86_64 模拟器与 arm64 release 构建。
5. **Spike C**：`dict_reader` 直接打开测试 MDX/MDD，测量 init/lookup 内存与耗时；WebView 渲染一个词条（CSS + 图片）。
6. 记录 ADR：`docs/adr/0001-ocr-onnx.md`、`0002-unidic-in-place.md`、`0003-mdict-dict-reader.md`；若 spike 失败，写清回退方案并先与用户确认。

验收：

- `flutter analyze` 通过；`flutter build apk --debug` 成功。
- 三个 spike 有可复现的命令/截图/日志；MeCab 能对 `食べた東京` 输出正确分词。
- 模型可从 hf-mirror 下载并校验；不把模型/UniDic/MDict 加入 git。

### Phase 1 — UniDic 分词、注音与阅读区（3–4 天）

任务：

1. `MecabService`：路径校验、长生命周期 isolate、错误码、初始化进度。
2. 29 字段映射、Token 模型、片假名→平假名、查词候选、内容词/功能词分类。
3. 文本输入页 + 阅读器：`ReaderBlock`、`TokenChip`、`FuriganaText`、字号/注音开关、复制全文。
4. 设置页 UniDic 路径 + 所有文件访问引导；启动时校验并显示修复提示。
5. 单元测试：字段映射、假名转换、候选生成、标点/空白处理；Widget 测试：注音 chip、长文本换行。

验收：

- 输入「食べた東京」得到 `食べ/た`、`東京` 等 token；`食べ` 注音 `たべ`、`東京` 注音 `とうきょう`。
- 路径无效/文件缺失/权限不足均有明确提示；重启后保留路径。
- 1,000 字文本分词不卡 UI；500 字目标 < 100ms（真机）。

### Phase 2 — MDict 查词、搜索与渲染（3–4 天）

任务：

1. `DictionaryRepository`：路径导入、元数据、注册表持久化、排序/启用/删除。
2. `DictionaryWorker` isolate：`DictReader` 懒初始化、lookup/locateAll/readOne、前缀建议、`@@@LINK` 重定向。
3. 查词候选接入 Token 点击；多词典结果分组；本次搜索词典筛选。
4. `EntryRenderer` + WebView：CSS 注入、MDD 资源提取/重写、HTML 清洗、JS/网络禁用、`entry://` 导航。
5. 搜索页：输入、建议、词典筛选、最近搜索（可选）；`EntryPage`。
6. 测试：真实测试词典的精确/前缀/重定向/图片/CSS；不支持格式的错误提示；性能基准。

验收：

- 点击 `食べる` → 講談社词典词条正确显示，CSS 生效，MDD 图片可见。
- 搜索 `東京` 精确命中；输入 `とうきょう` 能通过假名变体命中。
- 463k 词条热查询 < 300ms；首次初始化有进度提示。
- LZO/加密/损坏词典显示明确错误，不崩溃。

### Phase 3 — 横向 PaddleOCR 与拍照流程（3–4 天）

任务：

1. 抽取/重构 `PaddleDetector`、`PaddleRecognizer`、`DBPostprocessor`、方向分类、裁剪、CTC 解码；ORT 单例与线程策略。
2. `ModelManager`：manifest、hf-mirror/HF/自定义镜像、断点续传、SHA-256、本地导入、删除。
3. `rikai_ocr` MethodChannel/EventChannel；文件路径输入；错误码；取消。
4. 拍照/相册流程：`image_picker`、EXIF、缩放、预览、方向选择（自动/横/竖）、进度。
5. 横向 OCR → 行合并 → 阅读器 → 点击查词串通。
6. 测试：合成日文图片 + 真机照片；框排序、段落合并、标点/空白清理。

验收：

- 横向日文页面 OCR 结果顺序正确，能分词并查词。
- 模型缺失时引导下载；下载中断可续传；取消 OCR 不崩溃。
- 2048px 图片在模拟器/中端真机 PaddleOCR < 5s（目标）。

### Phase 4 — 纵向 MangaOCR 与自动方向（3–4 天）

任务：

1. 抽取 `MangaRecognizer`（encoder/decoder/vocab）、气泡聚类、裁剪规划、tiling、碎片合并、振假名噪声过滤。
2. 与 `PaddleDetector` 共用 DBNet：检测一次，纵向走 MangaOCR，横向走 Paddle rec。
3. 自动方向：框几何启发式 + 可选 doc/textline 方向模型；手动锁定；90/180° 重跑策略。
4. 纵向 RTL 阅读顺序、漫画分栏/段落合并；输出块级文本。
5. 模型下载/本地导入；FP32 decoder；可选 INT8 draft（P2）。
6. 测试：竖排漫画页、混合横排、旋转图片；性能/内存。

验收：

- 竖排漫画页按“右→左、上→下”输出完整气泡文本，能分词查词。
- 自动模式能识别横/竖并选择对应引擎；手动覆盖生效。
- MangaOCR 目标 < 10s/页（中端真机）；内存不 OOM。
- 无 MangaOCR 模型时，纵向模式给出下载提示，横向仍可用。

### Phase 4.5 — OCR 质量与性能收敛（已完成，2026-10-30）

目标：先把“能用的 MVP”收敛到可接受的实际体验，再进入 Phase 5。详细记录见
`docs/phase4.5-status.md`。

任务：

1. **模型生命周期**：PaddleOCR 必需；MangaOCR/orientation 懒加载；横向模式
   不创建 MangaOCR session；提供后台 `prepare` 预热；readiness 区分
   available/loaded。
2. **校验与指纹**：运行时路径/指纹先 stat（路径、大小、mtime），SHA-256 只在
   下载/导入/迁移，并按文件修订缓存；原生加载做内容兜底。
3. **方向**：doc orientation 只在“图像长宽比与框布局矛盾”时运行；90/270
   旋转整图并重新 DBNet；textline 180° 只在 auto 横向运行。
4. **auto 单引擎**：只输出 Paddle 或 Manga 之一；Manga 平均置信度不足时回退
   Paddle；模式切换强制重新 OCR。另加 2°–12° 轻微 deskew。
5. **Manga 质量**：按检测框尺寸自适应气泡 gap/padding；竖向 crop 最多 3 个
   text band；过滤低置信度/控制字符噪声。
6. **交互与缓存**：手动模式复用兼容的 auto 结果；照片集提供“旋转 90° 并重新
   识别”入口；缓存命中时不重新识别。
7. **验收**：x86_64 设备套件通过；arm64 真机验证横排/竖排/倒置/90°/270°、
   连续多页内存与耗时；真实漫画页质量。

验收门槛：

- 横向-only 不加载 MangaOCR；首次进入照片集不因模型 SHA 校验卡顿。
- 2048px 横排页 PaddleOCR < 5s（arm64 中端机）；单页漫画 MangaOCR < 10s，
  无 OOM。
- 横排、竖排、倒置、90°/270° 旋转均有真实图片回归结果；auto 只返回一个引擎。
- 缓存命中返回照片集不重新 OCR；手动模式不重复生成兼容结果。
- 现有单元测试、OCR 设备套件和新增真实页回归全部通过。

> 状态：4.5-A/B/C 已完成；2026-10-30 通过 arm64/真实设备验收，Phase 5 已启动。

### Phase 5 — 语料保存、打磨与发布（已完成，2026-10-30）

> 前置条件已满足：Phase 4.5 的 arm64/真实页面验收于 2026-10-30 通过。
> Phase 5 已完成并由用户在模拟器上确认测试通过；记录见 `docs/phase5-status.md`。

任务：

1. `HistoryStore`（sqflite）+ 图片压缩 + 自动/手动保存 + 历史列表/详情/删除/清空。
2. 首次启动引导：权限 → UniDic → 词典（可选）→ 模型（可选）→ 许可证确认。
3. 设置完善：词典管理、模型管理、镜像、字体/主题、自动保存、缓存清理。
4. 错误处理/空状态/加载态/重试；无障碍（大点击区、语义标签）；日文字体。
5. 许可证页、README、`docs/dev-setup.md`、`docs/models.md`、`docs/licenses.md`。
6. Release：R8、`--split-per-abi`、arm64 APK；安装/冷启动/历史持久化测试；最终许可审计。

验收：

- 完整走通：拍照 → OCR → 分词注音 → 查词 → 保存 → 历史回看 → 重新查词。
- 重启后设置/词典/UniDic 路径/历史保留；失效路径有修复提示。
- `flutter analyze`、`flutter test` 全部通过；release APK 可安装。
- 仓库中无 `unidic/`、`mdicts/`、模型二进制、签名文件；许可证页完整。

### 阶段汇总

| Phase | 内容 | 估算 |
|---|---|---:|
| 0 | 基建 + 三个 spike | 2–3 天 |
| 1 | UniDic/分词/注音/阅读区 | 3–4 天 |
| 2 | MDict/查词/搜索/渲染 | 3–4 天 |
| 3 | 横向 PaddleOCR + 拍照 | 3–4 天 |
| 4 | 纵向 MangaOCR + 自动方向 | 3–4 天 |
| 4.5 | OCR 质量与性能收敛 | 已完成（2026-10-30） |
| 5 | 语料保存 + 打磨 + 发布 | 已完成（2026-10-30） |
| **合计** | | **17–23 天（不含 4.5）** |

> Phase 6（Mdict Agent）是 post-MVP 设计扩展，不计入上表的工期和 MVP 范围；
> 见 §11。

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| MeCab native assets 在 Android 构建失败 | 无法分词 | Phase 0 spike；vendored 源码 + CMake 本地插件回退；保留 BSD 许可 |
| 1.3GB UniDic 原地路径不可读 / 外部存储 mmap 不兼容 | 无法使用 | 所有文件访问权限引导；应用外部私有目录路径；Spike A 实测 mmap；若 FUSE 路径失败，引导使用应用内部存储或提供受控复制回退（需用户确认）；诊断日志 |
| `dict_reader` 不支持用户的某本词典（LZO/加密/v3） | 该词典不可用 | 导入预检 + 明确错误；后续可评估 Rust mdict/转换脚本 |
| 463k 词条首次初始化慢/内存高 | 启动卡顿 | 懒初始化 + isolate；测量后启用 cache/SQLite key 索引 |
| MangaOCR 模型许可未声明 | 合规风险 | 不随包分发；下载前提示；仅本地使用；支持用户导入 Apache-2.0 转换模型 |
| 模型下载源不稳定（HF/GitHub 受限） | 无法下载 | hf-mirror 优先；自定义镜像；本地导入；断点续传/重试 |
| ORT/Paddle 模型算子不兼容 | OCR 失败 | Phase 0 spike；固定 ORT 1.28.0；准备 PP-OCRv5 备用模型/版本 |
| 竖排/混合排版识别差 | 体验差 | Phase 4.5 已做 90° 纠正、auto 单引擎+置信度回退、deskew、尺寸自适应气泡；arm64 真实页待验 |
| WebView HTML 安全/兼容 | 安全问题或渲染异常 | 禁 JS/网络、HTML 清洗、仅本地文件；真实词典回归测试 |
| APK 体积/内存 | 安装门槛 | 模型按需下载；release 仅 arm64；限制图片尺寸；释放 ORT/Bitmap |
| 中文系统字体导致日文字形错误 | 阅读体验 | 内置 Noto Sans JP（OFL）或 JP 字体回退 |
| PaddleOCR4Android 未能直接复用 | 与初始文档预期有差异 | 已确认统一 ONNX；保留 MIT/许可与 `OcrBackend` 接口，二期可接 Paddle-Lite |
| 无真机 | 性能/竖排验证不足 | Phase 0 起用模拟器；最终需 arm64 真机验收；文档标注 |

---

## 8. 验证计划

### 8.1 自动化

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

- 单元测试：
  - `kana_test.dart`：片/平假名转换、特殊字符；
  - `mecab_token_test.dart`：29 字段映射、注音回退、查词候选；
  - `reading_order_test.dart`：横排/竖排/漫画分栏；
  - `text_normalizer_test.dart`：NFKC、全半角、stripkey、假名变体；
  - `manifest_test.dart`：模型 manifest 解析/校验；
  - `history_store_test.dart`：SQLite CRUD；
  - 移植 overlay 的 `DBPostprocessorTest`、`TextBlockReadingOrderTest`、`BubbleClustererTest`、`MangaOcrCropPlannerTest` 等纯逻辑测试（保留 Apache 头）。
- Widget 测试：`TokenChip`、`FuriganaText`、`ReaderBlock`、词典筛选、空状态。
- 集成测试（模拟器/真机）：
  - 文本输入 → 分词 → 点击 → 查词（使用测试 MDX 夹具或真实词典）；
  - 合成日文图片 → OCR → 阅读器；
  - 历史保存 → 重启 → 回看；
  - 错误路径（无 UniDic/无模型/坏词典）。

### 8.2 手工验收矩阵

1. 首次启动引导：权限拒绝/允许、UniDic 路径正确/错误、模型跳过。
2. 文本输入：汉字+假名+标点+英文数字；长文本；空输入。
3. 查词：精确、假名变体、活用形、无命中建议、多词典、`@@@LINK`、MDD 图片、CSS。
4. OCR 横排：书页照片、屏幕截图、倾斜/旋转；自动/手动。
5. OCR 竖排：漫画页、竖排书页；RTL 顺序；振假名噪声。
6. 语料保存：自动保存、手动保存、删除、清空、重启。
7. 路径失效：SD 卡移除/文件改名；提示与恢复。
8. 性能：冷启动、UniDic 首次加载、词典首次初始化、OCR、查词、滚动。
9. 内存/发热：连续 OCR 10 页、长时间阅读。
10. 许可证/仓库：`git ls-files` 无模型/词典/UniDic；关于页链接可打开。

### 8.3 性能目标（中端 arm64 真机）

| 项目 | 目标 |
|---|---|
| UniDic 首次加载 | < 5s（显示进度） |
| 500 字分词 | < 100ms |
| 词典首次 init（463k） | < 3s（可接受 5s，带进度） |
| 热查询 | < 300ms |
| PaddleOCR（2048px 页面） | < 5s |
| MangaOCR（单页漫画） | < 10s |
| 历史保存/读取 | < 500ms |
| 冷启动到首页 | < 2s（不含首次 UniDic 加载） |

### 8.4 开发数据准备

- 开发机路径：`C:\Projects\Rikai-Mobile\unidic\unidic-cwj-202512`、`mdicts\講談社 日本語大辞典 第二版 双解版\`。
- 模拟器/真机：
  - 方式 A（推荐）：`adb push unidic /sdcard/Download/`、`adb push mdicts /sdcard/Download/`，应用内填写路径并授予所有文件访问；
  - 方式 B：放入 `/sdcard/Android/data/com.rikai.mobile/files/`（applicationId 统一为 `com.rikai.mobile`，无需特殊权限），填写该路径。
- `unidic/`、`mdicts/` 始终被 `.gitignore` 忽略；自动化测试不依赖真实版权词典，使用自建小型 fixture 或 mock。

---

## 9. 不在本期范围 / 后续

- iOS（需要单独 ORT/MeCab 构建与 UI 适配）。
- PaddleOCR4Android 的 Paddle-Lite 后端（已预留 `OcrBackend`；二期可加）。
- kha-white `manga-ocr-base` → ONNX 转换脚本与一键安装（可后续补充）。
- 竖排文本的竖向排版渲染（本期横排显示 token + 振假名）。
- 生词本/收藏、导出/分享、云同步、多语言 UI。
- 批量多页 OCR、自动裁边/透视校正 UI。
- 模糊搜索/编辑距离、词典内部全文检索。
- MVP 不做 LLM/Agent；Phase 6 的「词典助手」是后期可选扩展，见 §11。

---

## 10. 实施顺序建议（第一批动作）

1. 落盘本计划到 `docs/DEVELOPMENT_PLAN.md`。
2. Phase 0：创建 Flutter 工程与插件骨架；vendored MeCab；跑通 Spike A/B/C。
3. 确认 spike 结果后，按 Phase 1 → 5 顺序推进；每个 Phase 结束提交可运行版本与验收记录。
4. 首个可演示里程碑：Phase 2（文本/OCR 文本 → 分词注音 → 点击查词），此时 OCR 可暂用占位/手动输入。
5. 第二个可演示里程碑：Phase 4（横/竖 OCR 全链路）。

---

## 11. Phase 6 — Mdict Agent（后期设计，未纳入 MVP 估算）

> 状态：**设计草案 v2，未实现**。设计细节、开放问题和验收标准见
> `docs/phase6-agent-design.md`；工具/JSON Schema/状态机契约见
> `docs/phase6-agent-contracts.md`。Phase 6 依赖 Phase 5 完成，并依赖 Phase 1–4
> 已提供的 OCR、UniDic、MDict 接口；开工前需要用户单独批准。v2 增加固定流水线、
> 词典熟悉、逐词/语法证据、原文引用、会话级词典选择和按需多 OCR。

### 11.1 目标

在现有阅读/查词应用上增加「词典助手」：把本地 OCR、UniDic 分词和 MDict 查词
组织成 schema 化的工具，支持图片、文字或图片+文字输入，由用户配置的远程 LLM
完成严格/宽松两种模式的学习辅助。核心 OCR/分词/查词仍离线；Agent 仅在用户
配置 API Key 并主动请求时联网。

### 11.2 主页与命名

Phase 6 计划将主页固定为五个按钮：

1. 拍照识别（不变）
2. 查句子（原文本阅读；当前实现名为「输入文本」）
3. 查单词（原查词）
4. 历史记录（原语料）
5. 词典助手（新 Agent）

当前实现仍是四个按钮；Phase 6 UI 实施前不得提前改名或添加按钮。

### 11.3 产品要求

- **两种模式**：严格模式必须以词典工具结果为事实依据；宽松模式允许模型补充，
  但必须与词典事实分开标注。
- **模型分流**：简单任务（词典查询/整理）用用户选择的 small model；复杂任务
  （词义推理/规则生成）用 complex model。
- **输入**：图片、文字、图片+文字；图片只经本机 OCR，严禁发送给 LLM 视觉接口。
- **输出**：首版用结构化结果组件（原文引用/译文/逐句/词注/证据卡）+ 可点击词典
  来源；安全 Markdown、ruby、日语声调横线在 P6.7 再接入。
- **接口层**：现有 OCR/UniDic/MDict 服务外包一层窄 Port（`OcrPort`、
  `TokenizePort`、`LookupPort`、`DictionarySamplePort`、`LlmPort`、`SecretPort`）；
  模型只看到 JSON Schema 工具（`unidic.tokenize`、`mdict.lookup`、
  `mdict.suggest`），OCR/采样/UniDic profile 是 orchestratorOnly。
- **编排**：固定流水线 `OCR → 词典熟悉 → 分词 → 证据 → 推断 → 校验`；编排器预取
  每个 token/语法目标的查词，模型只能在预算内补充查词，不能决定词典顺序或
  自造 citation。`performLookup`/`LookupSearchNotifier` 的查词逻辑提取为纯
  `LookupGateway`，照片集与 Agent 共用 `OcrWorkflow`。
- **工具集**：本地 OCR、UniDic tokenization、MDict lookup/suggest，全部通过
  JSON Schema 调用。
- **引用**：`[来源N]` 由 orchestrator 发放并映射到真实 MDict 词条；点击来源打开
  现有查词 sheet，再点击词条进入现有词条页。
- **任务工作流**：Step -1 词典熟悉（采样→LLM 归纳→用户确认→缓存）→ Step 0
  图片仅本机 OCR，按 `{image_id, ocr_text}` JSON 发送 → Step 1 UniDic 分词并
  逐词检索 MDict（语法语感/多义性）→ Step 2 结合语境推断 → Step 3 结果与依据。
  必须引用原文；严格模式每个候选都要真实 citation。
- **会话词典选择**：每个 Agent 会话独立选择可用词典，UI 复用查词的
  单选/多选/全选逻辑，但不改变查词全局偏好；词典输出顺序严格按用户设置。
- **多 OCR 版本**：Agent 可调用多种本机 OCR 策略并结合词典修复 OCR；版本冲突时
  提供给用户选择，不静默覆盖，图片始终不上云。
- **词典熟悉期**：首次使用 MDict/UniDic 前生成探针样本和 Markdown 规则说明，
  用户确认后缓存；词典不变则复用。
- **注音/标注规则**：用户可让 Agent 生成 app 专用安全 DSL，统一影响所有
  UniDic token 展示；禁止执行任意代码。该功能排在 P6.7，不进入首版 Agent。
- **隐私**：API Key 安全存储，日志/导出脱敏；不发送图片、词典文件、UniDic 文件；
  核心功能不依赖 provider 配置。

### 11.4 建议实施顺序

1. 能力 Ports、ToolRegistry、DTO 序列化、`LookupGateway`、`OcrWorkflow`、
   `MdictService.sample/suggest`、语法/采样资源。
2. Provider 配置、安全存储、隐私同意、fake-provider/fake-server 测试骨架。
3. 词典/UniDic 熟悉期、用户确认、profile 缓存与失效。
4. Orchestrator Stage -1–3、证据/引用/原文/词典顺序校验、AgentStore。
5. Agent 页、会话词典选择、citation UI、历史/设置、主页第五按钮、UI token；
   首版用结构化组件 + 安全纯文本。
6. 按需多 OCR 版本、差异/词典辅助修复、用户选择 UI。
7. annotation DSL、Markdown/ruby/声调渲染、性能/许可/发布验收。

### 11.5 验收

Phase 6 的验收必须覆盖：五按钮 UI、无图片上云、严格引用、宽松补充标注、模型
路由、citation 点击、逐词/语法检索、原文 quote 校验、词典顺序、每会话词典选择、
多 OCR 版本选择、熟悉档案用户确认/复用/失效、预算与截断、提示词注入、
annotation DSL 全局生效、API Key 脱敏、provider 失败恢复，以及未配置 provider
时核心离线功能不回归。完整清单见 `docs/phase6-agent-design.md`；契约见
`docs/phase6-agent-contracts.md`。
