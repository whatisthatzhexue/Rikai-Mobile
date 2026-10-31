> ⚠️ 历史快照：本文档记录特定历史时期的审查结论。当前修复状态请以 docs/phase6-status.md 和各 phase 状态文件为准。

# Phase 3 未提交代码审查问题清单

- 日期：2026-10-28
- 范围：`git diff HEAD` 覆盖的已跟踪改动 + 全部未跟踪的 Phase 3 文件
  （`packages/rikai_ocr` 原生实现、`lib/services/ocr/*`、`lib/features/capture/*`、
  `lib/features/settings/model_page.dart`、`assets/models/manifest.json`、测试）。
- 依据：`CLAUDE.md`（§2 架构决策、§5 项目误区、§7 验证方式）、`docs/design-tokens.md`、
  `docs/phase3-status.md`、`docs/models.md`。
- 基线验证：`flutter analyze` -> No issues found；`flutter test` -> 97 tests passed。
- 说明：本次审查**没有修改任何代码**，以下问题全部待修复；行号以当前工作树为准。
- **Implementation status (2026-10-29)**: H1–H3, M1–M7 and L1–L10 have been
  addressed in `docs/phase3.5-status.md`; P1 remains a Phase 4 item.

## 摘要

| 级别 | 数量 | 编号 |
|---|---:|---|
| 高（功能不可用/明显错误） | 3 | H1–H3 |
| 中（完整性/稳定性缺口） | 7 | M1–M7 |
| 低（UI 规范/一致性/潜在问题） | 10 | L1–L10 |
| Phase 4 注意事项 | 1 | P1 |

建议修复顺序：**H1 → H2/H3 → M1/M3 → M5/M6 → M2/M4/M7 → L 系列**。

---

## 高

### H1. 「本地导入」模型实际不可用

- 位置：
  - `assets/models/manifest.json:18,27,36`（三个文件的上游 URL 均为 `inference.onnx` / `inference.yml`）
  - `lib/services/ocr/model_manager.dart:432-471`（`importSet`）
  - `lib/features/settings/model_page.dart:127-151`（`_import`）
- 问题：
  - `importSet` 按 manifest 的 `det.onnx` / `rec.onnx` / `keys.yml` **精确匹配文件名**
    （`model_manager.dart:440`），而用户从清单 URL 下载得到的文件叫 `inference.onnx` /
    `inference.yml`，必然进入 `missing` 并抛出 `IMPORT_INCOMPLETE`。
  - det 与 rec 同名 `inference.onnx` 时，`byName` 只会保留最后一个，进一步导致缺文件。
  - 只检查**本次选择**的文件，不检查目标目录中已存在的文件，因此逐个导入永远失败。
  - 抛出前已把选中的文件复制进目标目录（`:452-456`），形成部分安装状态；
    `_import` 的 catch 不调用 `_load()`，页面状态停留在旧值。
- 失败场景：用户按 `docs/models.md` 的说明从 HF/hf-mirror 下载后直接点「本地导入」，
  每次都提示「仍缺少文件：det.onnx、rec.onnx、keys.yml」。这是镜像不可用时文档承诺的
  兜底路径，目前走不通。
- 建议修复：
  - 按「角色」匹配文件：允许上游文件名（`inference.onnx`/`inference.yml`），
    结合文件大小、扩展名和选择顺序映射到 det/rec/keys；或改为选择目录后自动识别。
  - 同时把目标目录中已存在且校验通过的文件计入 `missing` 判断。
  - 导入失败时也刷新状态，避免页面显示过期信息。
- 状态：待修复

### H2. 初始化阶段的「取消识别」是空操作

- 位置：`lib/features/capture/capture_page.dart:172-187, 217-220`；
  `packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/RikaiOcrPlugin.kt:126`
- 问题：`_recognizing = true` 在 `await _ocr.initialize(...)` **之前**设置，因此加载
  约 21MB ONNX 模型期间就显示「取消识别」。此时点击取消只调用 `_ocr.cancel()`，
  原生侧 `recognizeJob` 还是 null；随后 `recognize` 在 `RikaiOcrPlugin.kt:126`
  把 `cancelRequested` 重置为 false，识别照常执行。
- 失败场景：用户点取消后识别仍跑完，并 `context.push('/reader')` 打开阅读页。
- 建议修复：Dart 侧维护本次运行自己的取消标志，在 `initialize` 返回后、调用
  `recognize` 前检查；原生侧区分「初始化取消」与「识别取消」，不要无条件重置标志。
- 状态：待修复

### H3. 取消请求可能永远不回调，Dart `await` 悬挂

- 位置：`packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/RikaiOcrPlugin.kt:126-158`
- 问题：`recognize` 先 `scope.launch`，之后才赋值 `recognizeJob`。如果 cancel 在
  `Dispatchers.Default` 真正调度执行协程体之前到达，取消未启动的协程会导致协程体
  整体不执行——没有 catch、没有 finally、也没有 `replySuccess/replyError`。
- 失败场景：`await _ocr.recognize(...)` 永不完成，`_recognizing` 一直为 true，
  进度条持续转圈且「开始识别」不可用，只能退出页面。
- 建议修复：保证每个 `MethodChannel.Result` 恰好回复一次。可用
  `CoroutineStart.ATOMIC` 启动、或在 `invokeOnCompletion` 中检查「是否已回复」并补发
  `CANCELLED`（配合 `AtomicBoolean`）。
- 状态：待修复

---

## 中

### M1. manifest 的 `sha256` 全部为 null，实际只校验文件大小

- 位置：`assets/models/manifest.json:22,31,40,58,67,76`；
  `lib/services/ocr/model_manager.dart:411-414, 422-426`
- 问题：`paddle_v5` 与 `manga_ocr` 的所有 `sha256` 都是 `null`，下载校验与安装状态
  判断在哈希为空时直接通过，只剩字节长度检查。这与 `docs/phase3-status.md:36`、
  `docs/models.md:22-23` 声称的「size/SHA-256 validation」不符。
- 失败场景：镜像返回错误页后中断、再由另一个镜像续传，最终文件长度恰好等于声明值，
  内容却是损坏的；应用判定「已安装」，之后每次初始化都报 `MODEL_INVALID`，
  用户只能手动删除文件恢复。
- 建议修复：为已验证的模型文件计算并填入 SHA-256；在补齐之前，至少在文档中明确
  「paddle/manga 仅校验大小」。
- 状态：待修复

### M2. 每次「开始识别」都重建 ONNX 会话，且 `SessionOptions` 泄漏

- 位置：`lib/features/capture/capture_page.dart:182`；
  `packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/PaddleOcrEngine.kt:73-90`
- 问题：每次识别都调用 `initialize`，原生 `initialize` 先 `closeSessions()` 再重新
  加载 4.8MB det + 16.5MB rec 模型。同时 `PaddleOcrEngine.kt:76` 创建的
  `OrtSession.SessionOptions()` 从未 `close()`（ORT 1.28 该类为 AutoCloseable，
  无 finalizer），每次识别泄漏一个 native 对象。
- 失败场景：识别一页 → 返回再识别同一张图，仍要重新解析全部模型；多次识别后
  native 内存持续增长（模型文件本身也会反复读盘）。
- 建议修复：Dart 侧按模型路径缓存初始化状态，路径不变时跳过 `initialize`；
  Kotlin 侧用 `options.use { ... }` 包住两个 `createSession`。
- 状态：待修复

### M3. HTTP 416 分支不可达，错误响应体会写入 `.part`

- 位置：`lib/services/ocr/model_manager.dart:344-348, 358-363, 372`
- 问题：`:348` 已经在 `existing == file.size` 时 return，所以 `:363` 的
  `statusCode == 416 && existing == file.size` 永远不成立。若服务端对 Range 请求
  返回 416（`validateStatus` 允许该状态码），代码会以 append 模式把 416 的响应体
  写进 `.part`，再抛 `DOWNLOAD_INCOMPLETE`。
- 失败场景：源站文件比本地 `.part` 短（或已更新）时返回 416，`.part` 被写入错误内容，
  下一次续传从被污染的长度开始，下载永远无法完成。
- 建议修复：
  - 416 时删除 `.part` 并从 0 重下；
  - 206 响应校验 `Content-Range` 的起始值等于当前 `.part` 长度，否则删除重下；
  - 任何非续传失败也删除 `.part`。
- 状态：待修复

### M4. OOM 被静默吞掉 / 初始化 OOM 被误报为模型损坏

- 位置：`packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/PaddleOcrEngine.kt:396-399, 99-101`
- 问题：
  - `rotateBitmap` 用 `runCatching`（捕获 `Throwable`）包住旋转，`OutOfMemoryError`
    会被吞掉并返回 null，`recognizeQuad` 于是静默丢弃该行。
  - `initialize` 的 `catch (Throwable)` 会把加载模型时的 OOM 报成 `MODEL_INVALID`
    （「无法加载 OCR 模型」）。
- 失败场景：内存紧张时 OCR 结果缺行且无任何提示；或用户被引导去删除/重新下载
  本来完好的 21MB 模型。
- 建议修复：不要用 `runCatching` 捕获 `OutOfMemoryError`；单独映射 `OOM` 错误码并
  在 UI 提示降低图片尺寸/释放内存。
- 状态：待修复

### M5. 只读的状态查询也会创建目录，失败时模型页整页空白

- 位置：`lib/services/ocr/model_manager.dart:130-147`（`modelsRoot`/`setDirectory`），
  被 `status()`（`:149`）、`paddlePaths()`（`:174`）、`deleteSet()`（`:473`）调用；
  `lib/features/settings/model_page.dart:53-76`
- 问题：`modelsRoot()` 无条件 `directory.create(recursive: true)`，即使是只读的
  状态查询。使用 `--dart-define=RIKAI_OCR_MODELS_DIR=/sdcard/Download/...` 但没有
  All Files Access 时，`existsSync()` 为 false、`create()` 抛 `Permission denied`，
  `ModelPage._load` 在第一个 set 就中断，`_manifest` 保持 null，页面渲染为空列表，
  所有模型的下载/导入/删除入口消失。
- 失败场景：开发用 dart-define 但没有授予所有文件访问；或外部存储不可用。
- 建议修复：把「解析路径」与「创建目录」分开；`status()` 在权限/IO 失败时返回
  「未安装」并附带权限提示，而不是抛异常。
- 状态：待修复

### M6. 模型出错后采集页仍显示「PaddleOCR 已就绪」

- 位置：`lib/features/capture/capture_page.dart:195-205`（错误处理），
  `:354-365`（已就绪行），`:167`（就绪判断）
- 问题：`_paddleStatus` 只在 `initState` 和从 `/models` 返回时由 `_loadModels()` 更新，
  识别失败路径只设置 `_error`。模型文件在应用外被删除/改名后，`paddlePaths()` 抛
  `MODEL_MISSING`，但绿色「PaddleOCR 已就绪（20.5 MB）」和「开始识别」仍然存在。
- 失败场景：每次重试都以同样错误失败，页面内无法刷新状态，必须退出再进入。
- 建议修复：在 `OcrException` / `OcrModelException` 的 catch 中重跑 `status()`
  （或 `_loadModels()`），并在错误存在时禁用「已就绪」行。
- 状态：待修复

### M7. 离开采集页后识别仍继续执行，且可能泄漏新建会话

- 位置：`lib/features/capture/capture_page.dart:178-194`（`_recognize` 的 await 链），
  `:59-64`（`dispose`）；`RikaiOcrPlugin.kt:76-86`（`dispose` 分支）
- 问题：`_recognize` 在 `paddlePaths` / `initialize` / `recognize` 之间没有
  `mounted` 或本地取消检查；`dispose` 只发送一次 `dispose` 并关闭引擎。若用户在
  「准备 OCR 模型…」期间返回，`_recognize` 仍可能在 dispose 之后重新 `initialize`，
  创建约 21MB 的新会话（此后没有任何人再关闭它们），并跑完检测/识别后丢弃结果。
- 失败场景：返回主页后仍持续占用 CPU/内存数秒；极端时序下泄漏 ORT 会话。
- 建议修复：增加 `_disposed` 标志并 `mounted` 检查每个 await 之后的状态；
  `dispose` 时显式取消正在进行的识别流程。
- 状态：待修复

---

## 低

### L1. 进度显示错误

- 位置：`lib/features/capture/capture_page.dart:311, 425`；
  `PaddleOcrEngine.kt:140, 142`
- 问题：
  - 原生每行依次发送 `current=index` 和 `current=index+1`，Dart 的 `_stageLabel`
    又 +1，最后一行会显示「第 N+1/N 行」。
  - detect 结束时进度为 1.0，第一条 recognize 事件进度为 0.0，
    `LinearProgressIndicator(value: _progress > 0 ? _progress : null)` 会让进度条
    在识别中途从满格变成不确定态。
- 建议修复：统一由原生只发一种语义的 `current`；进度条按阶段计算，或对 0.0 保持
  当前值而不是切回 indeterminate。
- 状态：待修复

### L2. 新页面违反 `docs/design-tokens.md`

- 位置与问题：
  - 12sp `bodySmall` 用于长提示/许可说明：`lib/features/settings/model_page.dart:290-297`
    （许可、URL、`licenseNote`）、`lib/features/capture/capture_page.dart:295,382,393,480`。
    规范要求设置/表单灰色提示统一 14sp 且完整换行（`design-tokens.md:80,89-91`）；
    同文件 `model_page.dart:224` 已正确使用 `AppTypography.helper`，属自相矛盾。
  - `model_page.dart:190-191` 初始加载只有转圈无文字；规范要求加载状态必须有说明
    （采集页 `capture_page.dart:343` 已正确写「正在检查 OCR 模型…」）。
  - `capture_page.dart:458-467` 的 `_CapturePrompt` 用带边框圆角 Container 包住
    图标/提示/按钮，违反「禁止组件套组件」；首次进入时 `:405`「下载模型」和
    `:488`「拍照」同时是 FilledButton，违反「一屏最多一个主按钮」。
- 建议修复：长提示统一 `AppTypography.helper`（14sp）；加载状态补文字；
  首次进入页改为扁平布局，只保留一个主按钮，另一个用 OutlinedButton/TextButton。
- 状态：待修复

### L3. 重复实现与行为不一致

- 位置与问题：
  - 下载取消流程在 `capture_page.dart:112-155` 与 `model_page.dart:78-121` 基本
    复制粘贴（CancelToken、busy、SnackBar、finally）。
  - `_formatBytes` 有三份实现：`capture_page.dart:441-446`、`model_page.dart:352-357`、
    `settings_page.dart:523`；前两份没有 GB 单位，1KB 以下显示为 0。
  - 镜像来源不一致：模型页下载用未保存的 `_mirrorController.text`
    （`model_page.dart:93`），采集页用已保存的 `appSettingsProvider.ocrMirror`
    （`capture_page.dart:128`）。输入但未点「保存镜像」时，一个页面生效、另一个忽略。
  - 本地导入不会清理 `file_picker` 复制到 cache 的副本（`model_manager.dart:452`），
    导入 118MB 的 MangaOCR 解码器会在 cacheDir 留下 `deleteSet` 删不掉的副本。
  - `RikaiOcrPlugin.kt:56` 在 `onDetachedFromEngine` 的平台线程直接调用
    `@Synchronized engine.close()`，正在进行的识别会阻塞 UI 线程；`dispose` 分支
    已经改为协程 + 互斥锁，这里没有。
- 建议修复：抽取共享的下载/格式化工具；镜像统一从设置读取并保存后生效；
  导入完成后调用 `FilePicker.clearTemporaryFiles()` 或自行删除缓存副本；
  `onDetachedFromEngine` 的关闭也放到 `scope.launch` 中。
- 状态：待修复

### L4. `ocrModelManifestProvider` 未关闭 Riverpod 重试

- 位置：`lib/state/providers.dart:85-87`
- 问题：manifest 是随包资产，损坏属于永久失败；该 provider 没有像
  `mecabServiceProvider` / `mdictServiceProvider` 那样设置 `retry: (_, __) => null`。
  Riverpod 3 默认重试会带来约 30 秒的后台重试，而 UI 已经显示错误、不会因后来成功
  而刷新（`CLAUDE.md` §5.7 #28 记录过同类坑）。
- 建议修复：设置 `retry: (_, __) => null`，或让 UI 在重试成功后刷新。
- 状态：待修复

### L5. `composeOcrText` 会丢弃相邻的相同文本行

- 位置：`lib/services/ocr/ocr_text_composer.dart:16`
- 问题：仅按文本比较就丢弃相邻相同行。测试 `test/ocr_text_composer_test.dart`
  将其固化为预期行为，但遇到歌词、重复对话、表格单元格时会静默丢内容。
- 建议修复：如确需去重，应结合检测框几何位置（重叠/包含）判断，而不是只比文本；
  或把该行为明确写进产品说明。
- 状态：待确认（产品行为）

### L6. 自定义镜像格式错误时被静默忽略

- 位置：`lib/services/ocr/model_manager.dart:291-295`；
  `lib/features/settings/model_page.dart:44-51`（`_saveMirror`）
- 问题：`_candidateUrls` 对解析失败、无 scheme 或 host 为空的镜像直接返回原 URL 列表。
  用户输入 `hf-mirror.com`（漏写 `https://`）保存后没有任何提示，而页面文案
  （`model_page.dart:222`）声称会替换服务器地址。
- 失败场景：正因为官方地址不可达才设置镜像，结果仍以通用网络错误失败，用户不知道
  是自己的输入格式有问题。
- 建议修复：保存镜像时校验必须是带 host 的 http/https URL，并就地报错。
- 状态：待修复

### L7. 通过「本地导入」进来的 MangaOCR 文件无法在 UI 删除

- 位置：`lib/features/settings/model_page.dart:321-337`
- 问题：「删除」按钮被 `!phaseFour` 挡住，但「本地导入」对 manga_ocr 可用。用户导入
  约 140MB 后状态显示已安装，却没有任何删除入口；叠加 file_picker 的 cache 副本，
  这是唯一能在应用内占用数百 MB 且无法回收的路径。
- 建议修复：phaseFour 也显示删除按钮（只是不提供下载）。
- 状态：待修复

### L8. `cancel()` / `dispose()` 绕过错误转换

- 位置：`packages/rikai_ocr/lib/rikai_ocr.dart:175-181`；
  `lib/features/capture/capture_page.dart:217-220`
- 问题：两个方法直接调用 `_channel.invokeMethod`，没有走 `_invoke()` 的
  `PlatformException -> OcrException` 转换；`_cancelRecognize` 也没有 try/catch，
  平台侧失败会变成按钮回调里的未处理异步异常。
- 建议修复：两者都改走 `_invoke()`，并在 UI 侧捕获异常、显示错误信息。
- 状态：待修复

### L9. `replaceDraft` 改写全局草稿，双 ReaderPage 时下方页面 token 过期

- 位置：`lib/features/reader/reader_page.dart:54-61`
- 问题：controller 来自容器级 `readerDraftControllerProvider`，而
  `_analysedText` / `_tokens` 是 State 级。若栈里同时存在两个 ReaderPage，两个输入框
  都会变成 OCR 文本，但下层页面的分词结果要手动再点「分词」才会更新。
- 失败场景：当前不可达（`/capture` 只从主页进入，且会 `await push('/reader')`），
  属于潜在隐患。
- 建议修复：为 OCR 文本使用独立 controller，或监听 controller 变化自动重新分词。
- 状态：待修复（潜在）

### L10. `isInstalled` 对空文件列表恒为 true

- 位置：`lib/core/models/ocr_model.dart:71-74`（`whereType<Map>()` 静默丢弃格式错误的
  条目）；`lib/services/ocr/model_manager.dart:41`
- 问题：`installedFiles == fileCount` 在 `files` 为空时为 `true`，一个损坏的 manifest
  条目会被判定为「已安装」。
- 失败场景：当前 manifest 随包且格式正确，不可达；属于解析器健壮性问题。
- 建议修复：`OcrModelSet.fromJson` 对空 `files` 或格式错误的条目显式抛出
  `FormatException`。
- 状态：待修复（潜在）

---

## Phase 4 注意事项

### P1. 竖排相关代码目前只是占位，不能视为已支持

- 位置：`packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/PaddleOcrEngine.kt:248-255, 445-468`
- 现状：
  - 高宽比 > 1.5 的 crop 会旋转 -90° 并标记 `orientation="vertical"`。
  - `orderBlocks` 仍按 `centerY -> left` 的 LTR 顺序排序，多列竖排会得到相反顺序。
  - `orientation` 字段虽然经 MethodChannel 传到 Dart，但目前没有任何消费者。
  - 采集页的「自动」与「横向」送进原生后走完全相同的路径（引擎只对 `vertical`
    返回 `UNSUPPORTED_MODE`），`docs/phase3-status.md:27,107` 已声明仅支持横向。
- 结论：这不是 Phase 3 的回归，但 Phase 4 接入 MangaOCR 时必须重做 RTL 阅读顺序、
  气泡聚类和方向路由，不能复用当前 LTR 排序；识别历史/语料若开始持久化
  `orientation`，需要先明确其语义。

---

## 已核对无问题（不要重复排查）

- `DBPostprocessor` 角点排序与 `minAreaRect` 的顺序等价（LT/RT/RB/LB），与
  PaddleOCR 的 `get_mini_boxes` 一致。
- 共享 `OrtEnvironment` 不在任何引擎 `close()` 中关闭，符合 `CLAUDE.md` §5.1 #4。
- `CtcDictionary` 对真实 18,383 键解析正确（U+3000 保留、`''''` 转义处理）。
- 各 Bitmap recycle 路径无重复回收；检测/识别输入通道与 mean/std 正确。
- 模型二进制均被 `.gitignore` 覆盖（`**/*.onnx`），没有入库。
- 两个新页面继承全局深蓝 AppBar 与 `SlideOverPageTransitionsBuilder` 转场。
- `initialize` 与 `recognize` 均由 `operationMutex` + `@Synchronized` 串行化，
  `closeSessions()` 不会落在识别中途。
- 每个 catch/finally 都有 `mounted` 保护，没有发现 setState-after-dispose。

---

## 复现与验证

- 自动化：`flutter analyze`（No issues）、`flutter test`（97 passed）。
- 设备端基线见 `docs/phase3-status.md`（x86_64 模拟器、真实 PaddleOCR 模型，
  2 项 OCR 测试通过）。
- 本清单中的问题均为静态审查 + 源码核对确认；H1、M1、M5、L6 可在主机上直接复现，
  H2/H3/M7 需要设备端操作时序，M4 需要可控内存压力。
