# 项目阶段开发历史（Project History）

> **历史流水汇总**：本文件汇总 Phase 0–Phase 5 的实现、修复与验收过程，供追溯
> “当时做了什么、为什么这样修”时查阅；**不代表当前规则、当前数据或当前任务**。
> 各阶段详细快照见 `docs/phase*-status.md`；本文件是时间线汇总，细节以 phase
> status 为准。
>
> - last_migrated: 2026-11-01（从原交接文档 §3–§4 的已完成部分迁出）
> - 覆盖范围: Phase 0–Phase 5（记录截至 2026-10-30）
> - 维护规则: 新阶段完成后在本文件追加“完成记录”；当前测试/设备/性能/构建数据
>   不写在这里。

**结论**：Phase 0–5 已全部完成；Phase 4.5 于 2026-10-30 通过 arm64/真实设备验收，
Phase 5 已由用户确认并发布 1.0。当前焦点是 Phase 6。

## 阶段总览

| 阶段 | 结果 | 详细记录 |
|---|---|---|
| Phase 0 | 工程与基建完成 | `docs/phase0-status.md` |
| Phase 1 | UniDic/MeCab、权限、阅读器、真实词典完成 | `docs/phase1-status.md` |
| Phase 2 | MDict worker、查词/渲染/词典管理完成 | `docs/phase2-status.md` |
| Phase 3 | 横向 PaddleOCR、拍照、模型管理完成 | `docs/phase3-status.md` |
| Phase 3.5 | 采集/导入/语料/模型目录修复完成（2026-10-29） | `docs/phase3.5-status.md` |
| Phase 4 | 纵向 MangaOCR、自动方向完成（2026-10-29） | `docs/phase4-status.md` |
| Phase 4.5 | OCR 质量/性能收敛完成；2026-10-30 arm64/真实设备验收通过 | `docs/phase4.5-status.md` |
| Phase 5 | 语料/首次引导/设置/发布打磨完成；2026-10-30 用户确认并发布 1.0 | `docs/phase5-status.md` |

> Phase 6 不在本文件；实现进度见 `docs/phase6-status.md`。

## Phase 0 — 工程与基建

- Flutter Android 工程、依赖、Material 3 首页、go_router 路由。
- vendored MeCab/native assets、`rikai_ocr` 骨架（MethodChannel `rikai/ocr`、
  ORT 1.28.0）、模型 manifest、许可证、文档。

## Phase 1 — UniDic/MeCab + 阅读器

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

## Phase 2 — MDict + 查词/渲染 + 设计 token

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
- 设计 token + `lib/core/theme/app_tokens.dart`：蓝/白 token、
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

## Phase 3 — 横向 PaddleOCR + 拍照

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

## Phase 3.5 — 采集/导入/语料修复（2026-10-29）

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

## Phase 4 — 纵向 MangaOCR + 自动方向（2026-10-29）

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
  180° 重跑后输出 `ありがとう`。设备/性能数据见 `docs/phase4-status.md`。

## Phase 4.5 — OCR 质量/性能收敛 + 设备反馈

实现于 2026-10-29，2026-10-30 通过 arm64/真实设备验收；详见
`docs/phase4.5-status.md`。

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
- **Manga/倾斜**：2°–12° 轻微 deskew；气泡 gap/padding 按中位框尺寸自适应；
  竖向 crop 最多 3 个 text band；清除控制/替换字符，丢弃低置信度气泡。
- **缓存/交互**：手动横向可复用 auto 的 `paddle_v5` 结果，手动竖向可复用
  `manga_ocr` 结果；照片集“旋转”旋转私有副本 90°、清该照片 OCR 缓存。
- 设备 OCR 套件（横向、6° 倾斜、lazy、Manga、90°、270°、倒置 180°、取消）
  在 x86_64 全部通过；具体套件数、耗时和真实图片结果见
  `docs/phase4.5-status.md`。
  2026-10-30 用户确认 arm64/真实设备验收通过。
- 第二轮设备反馈（2026-10-29）：MDD `sound://` 转为本地 `<audio>`；MDict
  `Encrypted=2`/MDD 兼容、词典搜索单选/多选与简称、词条标题、权限引导、拍照
  提示、语料卡片、下载后台/断点/清理、WebView 退出闪帧；词典选择全局持久化、
  预留 3.5 行（第 4 行半可见）滚动、选中不漂移；查词状态跨页面保留；键盘焦点
  路由清理；非阻塞 `RikaiToast`；竖排双引擎评分；OCR 日文空格清理；长文本
  懒加载/去滚动条；旋转自动中断 OCR；语料日期格式；删除对话框统一复选框。
  冷启动真实图片复跑结果、MDD 音频测试结果详见 `docs/phase4.5-status.md`。
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

## Phase 5 — 语料/引导/设置/发布（2026-10-30）

- 首次启动引导 `/onboarding`：本地边界、存储权限、UniDic、MDict/OCR 模型
  入口、许可确认、开始/跳过；已有 UniDic 路径视为已完成；设置可重新打开。
- 语料：阅读页可保存纯文本文本；照片保存前 EXIF 校正、最长边 2048、JPEG 85；
  `HistoryStore.clear/imageBytes`，并提供图片占用统计与同毫秒稳定排序；语料页
  可清空全部；文本语料无照片时显示「文本语料」占位；自动保存开关默认关闭，
  按照片+模式+文本做会话内去重。阅读页“保存到语料”，照片集/多选页共用
  `capture_corpus.dart`。
- 设置：「语料与存储」自动保存/清空语料/清除 MDict 资源缓存；
  「关于与帮助」帮助、著作权与许可、重新查看新手引导；新增 `/help`、
  `/copyright` 路由。
- 新增测试 `onboarding_test`、`history_store_test`（纯图片压缩/block JSON，
  不依赖桌面 SQLite）、`reader_save_test`；Phase 5 当时的测试/构建记录见
  `docs/phase5-status.md`。arm64 release APK 已构建。
- Phase 5 已由用户于 2026-10-30 在冷启动 x86_64 模拟器上确认首次引导/语料/设置
  流程测试通过，并发布为 1.0 release。

## 已完成路径的保护说明

以下路径已经实现并验证，不要重写；需要修改时先读对应 `phase*-status.md`。

### UniDic/MeCab + Phase 1

- 私有 `mecabrc` + `-r` 已在 Android 实测成功；
- 大型 UniDic 外部存储 mmap 可用（数据规模见 `docs/phase1-status.md`）；
- 29 字段映射与引号 CSV 解析已由真实词典验证；
- All Files Access 原生通道已实现。

### ORT 模型冒烟（PaddleOCR）

- 主机 Python ORT 与 Android x86_64 合成图片冒烟均通过；模型形状、字符表
  数量、耗时与置信度见 `docs/phase3-status.md`。
- MangaOCR encoder/decoder 已在 Phase 4 完成设备冒烟（合成竖排气泡
  `これはテストです`）；模型许可未声明，不随包分发。

### Phase 2

不要重写 MDict worker、lookup/`@@@LINK`、EntryRenderer、搜索/词条/词典管理页。
已知限制：每词典词条上限可在设置中配置（默认无限制）、CSS 发现为目录内全部、
MDD 缓存未清理、无模糊搜索。

### Phase 3 横向 PaddleOCR + 拍照

- 原生 OCR 代码在 `packages/rikai_ocr/android/src/main/kotlin/com/rikai/ocr/`；
  已由真实 PP-OCRv5 det/rec 和合成图片设备测试验证。
- 模型是运行时下载/本地导入，不入库；native 只接收本地路径。
- `vertical` 模式已由 Phase 4 接入；不要把它改回 `UNSUPPORTED_MODE`，也不要在
  缺少 MangaOCR 时静默走横向（手动竖向必须明确提示下载模型）。
- 采集页和模型页属于已验收 UI；不要把模型二进制放回 assets 或提交。
- 已知限制：模拟器 DNS 导致实网下载未验证；无 arm64 真机。

### Phase 4 纵向 MangaOCR + 自动方向

- `MangaOcrRecognizer.kt`：复用 DBNet quads、气泡聚类、crop planner、
  ViT encoder + FP32 greedy decoder、纵向 RTL 排序；
- 自动模式：框几何 + 可选 doc/textline orientation；手动竖向/横向覆盖；
  可选 textline 180° 重跑；
- 模型缺失时横向仍可用；手动竖向给出下载提示；
- 已知限制：未移植上游 mask/panel/free-text 完整流水线、无 INT8 draft、无 arm64
  真机。Phase 4 时 90/270 文档方向未做整图旋转，Phase 4.5 已补上。

## 历史验证与提交锚点

历史测试/设备/性能/构建数据见各阶段 `docs/phase*-status.md`。不要把历史值当作
当前值。

仓库历史提交包括：`d0d94a3`、`dc70cee`、`91dc386`、`deb6484`、`b12d24f`、
`95f90e0`、`9e17984`、`f287603`、`c2ae03d`、`4d0100f`、`1e25750`、`b2ed785`、
`1c7096b`、`979d1de`、`2534c3a`。

- Phase 4：`f287603`
- Phase 6 文档：`c2ae03d`
- Phase 4.5 初版：`4d0100f`
- 上一轮修复：`1e25750`
- 第二轮设备反馈：`b2ed785`
- 横屏/搜索/采集：`979d1de`
- Phase 5：`2534c3a`
- Phase 6 P6.1–P6.5：自 `7be4b81` 起；后续 docs/Wave 1 修正见 `git log`。

当前工作区以 `git status` 为准；不要擅自 `reset`/`commit`，除非用户明确要求。
