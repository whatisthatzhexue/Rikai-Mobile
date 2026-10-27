# CLAUDE.md — Rikai-Mobile handoff

> 给下一个 agent 的工作交接。先读本文件，再读 `docs/DEVELOPMENT_PLAN.md`（已批准的完整开发计划）
> 和 `docs/phase0-status.md`（当前验证结果）。用户使用中文沟通；代码/标识符用英文。

## 1. 项目是什么

Android 单端、完全离线的 Flutter 日语阅读/查词应用：

拍照或输入文本 → 横向 PaddleOCR / 纵向 MangaOCR → UniDic（用户自备）分词与注音 →
点击单词查询用户自备的 MDict 词典；另有搜索查词、词典偏好、语料保存。

- 项目根目录：`C:\Projects\Rikai-Mobile`（ASCII 路径，旧的 `E:\MyData\大工\...` 已不存在）
- 包名/applicationId/namespace：`com.rikai.mobile`
- Flutter 工程名：`rikai_mobile`
- 最低系统：minSdk 26；compileSdk/targetSdk 36；NDK 28.2.13676358
- 仅 Android；不做 iOS、不做云 OCR/云翻译/LLM。
- 仓库已初始化 git，目前一次提交 `d0d94a3 feat: First Version`。
  工作树可能有未提交的文档改动（README、docs/dev-setup、docs/phase0-status、本文件）；
  不要擅自 `reset`/`commit`，除非用户明确要求。

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
   应用必须自己创建**私有** `mecabrc`，并通过 `Mecab.create(..., options: '-r <私有rc路径>')`
   传入。`options` 字符串由 `generateArgs()` 按空格/双引号解析。
   该 `-r` 传递方式尚未在 Android 上实测；若 MeCab 解析重复参数失败，改用
   C++ 新增 `rcPath` 参数（Phase 1 spike 先验证）。
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

## 3. 当前进展（Phase 0）

已完成：

- Flutter Android 工程、依赖、Material 3 占位首页。
- `packages/mecab_for_dart` vendored + rc 补丁；Android native assets 成功产出
  `libmecab_dart.so`（arm64-v8a / armeabi-v7a / x86_64）。
- `packages/rikai_ocr` 插件骨架：MethodChannel `rikai/ocr`，ONNX Runtime 1.28.0；
  `initialize` 目前是空实现，`recognize` 返回 `NOT_IMPLEMENTED`。
- `assets/models/manifest.json`：PaddleOCR v5、MangaOCR、方向模型的 URL/大小/许可；
  默认 hf-mirror，HF 兜底；模型不入库。
- 许可证/来源文件：`NOTICE`、`THIRD_PARTY_NOTICES.md`、`third_party/*`、`assets/licenses/`。
- `lib/core/utils/kana.dart` 片假名↔平假名工具 + 8 个测试。
- 文档：`docs/DEVELOPMENT_PLAN.md`、`docs/dev-setup.md`、`docs/phase0-status.md`、`docs/adr/`。
- Debug APK 可构建：`build/app/outputs/flutter-apk/app-debug.apk`（约 260MB，全 ABI + debug）；
  含 `libmecab_dart.so`、`libonnxruntime.so`、`libonnxruntime4j_jni.so`。

已验证：

```text
flutter analyze  -> No issues found
flutter test     -> 8 tests passed
flutter build apk --debug -> success
```

主机的 MDict spike（`tool/spike_mdict.dart`，在隔离 Dart 包中运行）：

- `initDict()` ~200ms；463,312 条；RSS ~400MB；
- `locateAll("東京")` <1ms；词条是 `@@@LINK=とうきょう【東京】`，解析后得到完整 HTML；
- 前缀搜索正常。

**尚未完成 / 关键门槛：**

- 没有在 Android 真机/模拟器上实际加载 1.3GB UniDic 并跑 MeCab；
  `libmecab_dart.so` 已打包，但 `MecabService` 还没写。
- OCR 插件仍是骨架；PP-OCRv5/MangaOCR 模型没有实际执行过。
- 没有识别历史、词典管理、设置、搜索、拍照、阅读区等业务页面。
- Release APK 尚未构建（上一次 release 构建被用户中断；不要在没有必要时重复跑长构建）。
- 没有真机连接；只有 x86_64 模拟器 `Medium_Phone_API_36.1`；最终性能/竖排需 arm64 真机。

## 4. 未尽事宜（按优先级）

### P0：Phase 0 剩余门槛

1. **Android UniDic/MeCab**：
   - 写 `lib/services/mecab/mecab_service.dart`：
     - 校验目录：`sys.dic`、`matrix.bin`、`char.bin`、`unk.dic`、`dicrc`；
     - 校验 `sys.dic` 版本 102、UTF-8、词条数 > 0；
     - 在应用私有目录创建 `mecabrc`（可为空或 `charset = UTF-8`）；
     - 长生命周期 isolate 调 `Mecab.create(dictDir: path, options: '-r <private rc>')`；
     - 串行 `analyze`，把异常映射为错误码。
   - 用 `食べた東京` 验证分词和 29 字段映射。
   - 推 UniDic 到设备/模拟器（见 §7），确认外部存储 mmap 可用；失败时先记录，再与用户确认回退方案（不要擅自改成复制）。
2. **ORT 模型冒烟**：
   - 下载 PaddleOCR det/rec 与 MangaOCR encoder/decoder（hf-mirror 可用）；
   - 在插件里打开 ORT session，跑一张合成日文图片，确认模型算子/输入输出名；
   - 记录耗时/内存。

### Phase 1：分词、注音、阅读区

- `lib/core/models/token.dart`：surface/pos1-4/lemma/orth/orthBase/pron/pronBase/kana/kanaBase/goshu/cType/cForm/lid/lemmaId/start/end。
- 29 字段映射（已从真实 `sys.dic` 样本验证）：
  - 0-3 pos1-4；4 cType；5 cForm；6 lForm/語彙素読み；7 lemma；8 orth；9 pron；
    10 orthBase；11 pronBase；12 goshu；20 kana（仮名形出現形，注音首选）；
    21 kanaBase；24-26 accent；27 lid；28 lemma_id。
- 注音：`kana`(20) → `pron`(9) → `lForm`(6) → `surface`，片假名转平假名。
- 查词候选：`orthBase` → `lemma` → `orth` → `kanaBase` → `kana` → `pron` → `surface`。
- 阅读区：`ReaderBlock`/`TokenChip`/`FuriganaText`，内容词高亮、功能词弱化、复制全文。
- 设置页：UniDic 路径、校验状态、All Files Access 引导。
- **All Files Access 原生通道**：`permission_handler` 已移除（见 §5），需要在
  `MainActivity.kt` 或独立 MethodChannel 中实现：
  - 检查 `Environment.isExternalStorageManager()`；
  - 跳转 `Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`；
  - Android 10 及以下申请 `READ_EXTERNAL_STORAGE`。
- 单元测试：字段映射、假名、候选、标点/空白；Widget 测试阅读区。

### Phase 2：MDict 查词/搜索/渲染

- `lib/services/mdict/mdict_worker.dart`：长生命周期 isolate，持有 `DictReader`。
- `dictionary_repository.dart`：路径、元数据、排序、启用、失效检测（不复制）。
- `lookup`：归一化（NFKC/全半角/平片假名/stripkey）→ `locateAll` →
  `readOneMdx` → 解析 `@@@LINK=`（最多 3 层）→ 多词典分组。
- 无命中：`search(prefix, limit: 30)`；活用形可先用 MeCab 取 lemma。
- `EntryRenderer`：`package:html` 清洗脚本/iframe/对象/事件属性；注入外部 CSS；
  MDD 资源按需提取并重写 `src`。
- `flutter_inappwebview`：`javaScriptEnabled: false`、`blockNetworkLoads: true`、
  仅本地文件；`shouldOverrideUrlLoading` 处理 `entry://` 与外部 URL。
- 搜索页 + 词典管理页 + 词条页。

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
     `Mecab.create(dictDir: path, options: '-r <私有rc路径>')` 传入。
   - 先做 spike 验证 `-r` 通过 options 传递是否生效；若 MeCab 对重复/后置 `-r` 报错，
     改 C++ 增加显式 `rcPath` 参数，**不要**写用户目录。
7. **误区：把 UniDic 复制到 app 存储“更稳”。**
   - 正确做法：用户明确选择原地路径；不要默认复制 1.3GB。
   - 权限不足：引导 All Files Access，或让用户放到
     `/sdcard/Android/data/com.rikai.mobile/files/`。
   - 外部存储 mmap 失败：记录具体错误并**询问用户**，不要静默改成复制方案。
8. **误区：硬编码 29 字段并假设所有 UniDic 版本一致。**
   - 正确做法：解析前校验字段数；按 §4 Phase 1 的索引映射；字段数异常时降级为
     “可点击、无注音”，记录日志，不崩溃。当前 2025.12 版本为 29 字段。
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

## 6. 关键文件

```text
lib/main.dart, lib/app.dart, lib/features/home/home_page.dart   # 占位 UI
lib/core/utils/kana.dart                                      # 假名转换
packages/mecab_for_dart/                                      # vendored MeCab（已打补丁）
packages/rikai_ocr/                                           # OCR 插件骨架 + ORT
assets/models/manifest.json                                   # 模型清单（不含模型本体）
android/app/src/main/AndroidManifest.xml                      # 文件权限
android/app/build.gradle.kts                                  # minSdk 26 / NDK 28
docs/DEVELOPMENT_PLAN.md                                      # 已批准计划
docs/phase0-status.md                                         # 当前验证结果
docs/dev-setup.md                                             # 构建/数据/缓存修复
docs/adr/                                                     # 三个架构决策
tool/spike_mdict.dart                                         # MDict 主机 spike
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

1. 运行 `git status`，确认用户未提交的文档改动；不要覆盖。
2. 实现 `MecabService` + `Token` + 私有 `mecabrc`，做最小文本阅读页；
   用真实 UniDic 在模拟器/真机跑通 `食べた東京`。
3. 同时实现 All Files Access 原生通道（不要用 permission_handler）。
4. 通过后进入 Phase 2（MDict worker/lookup/WebView）。
5. 每个阶段结束运行 analyze/test/debug build，并记录到 `docs/phase0-status.md`
   或新的阶段状态文档。
