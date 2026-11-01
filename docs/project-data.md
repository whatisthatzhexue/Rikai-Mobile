# 项目测试与验证数据

> **单一事实源**：所有跨文档复用的测试数量、设备结果、性能、构建产物、环境版本、
> 开发数据统计和固定 UI 文案以本文件为准。其他文档只引用本文件对应小节，不再
> 复制具体数值；历史 phase 文档可以保留“当时值”，但必须标注为历史快照。
>
> - last_verified: 2026-11-01
> - HEAD: `c6094b5`（`fix: OCR模型页面操作逻辑修正`）
> - 设备基线: `Medium_Phone_API_36.1`（x86_64 模拟器，API 36）；无 arm64 真机
> - 维护规则：数据变化时只改本文件，并同步更新 `last_verified`/`HEAD`；其他文档
>   的引用链接不需要改。

## 1. 环境与构建基线

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.38.9 / 3.10.8 |
| Android SDK / build-tools | 36 / 36.1.0 |
| compileSdk / targetSdk | 36 / 36 |
| minSdk | 26 |
| NDK | 28.2.13676358 |
| JDK | Android Studio JBR 21 |
| CMake | 3.22.1（仅在替换 MeCab native assets 时需要） |
| 包名 / namespace | `com.rikai.mobile` |
| Flutter 工程名 | `rikai_mobile` |
| 模拟器 | `Medium_Phone_API_36.1`（x86_64，API 36） |
| ONNX Runtime | 1.28.0 |
| `dict_reader` | 1.6.1 |
| `flutter_secure_storage` | 11.2.0 |

> 构建命令、权限和集成测试步骤不在这份数据文档中重复，见
> `docs/dev-setup.md` 与 `CLAUDE.md` §7。

## 2. 自动化测试

### 2.1 当前基线

| 项 | 值 |
|---|---:|
| 当前 test/testWidgets 声明数 | **213** |
| 当前测试文件数 | **60** |
| 最近 `flutter analyze` | No issues found |
| 最近 `flutter test` | 213 passed |
| 最近 `flutter build apk --debug` | success |

> 统计口径：`test/**/*.dart` 中的 `test(` + `testWidgets(`；不含 integration_test。
> 该数字对应 HEAD `c6094b5`。新增/删除测试后只更新本节。

### 2.2 历史测试基线（不要当作当前值）

| 阶段/时点 | 数量 | 说明 |
|---|---:|---|
| Phase 3 | 97 | `docs/phase3-status.md` / `phase3-review.md` 历史记录 |
| Phase 5 | 149 | `docs/phase5-status.md` 历史记录；当时 `flutter test` 149 passed |
| Phase 6 设计快照 | 199 | `docs/phase6-agent-design.md` 旧记录 |
| Wave 1 前 | 206 | Agent Wave 1 新增测试前 |
| Wave 1 后 | 212 | Agent Wave 1 完成时 |
| 当前 | **213** | 见 §2.1 |

> 历史 phase 文档保留当时值；引用当前值时使用
> `[当前测试基线](project-data.md#21-当前基线)`（docs/ 下页面）或
> `[当前测试基线](../project-data.md#21-当前基线)`（docs/agent_docs/ 下页面）。

## 3. 设备集成测试

| 套件 | 当前结果 | 备注 |
|---|---:|---|
| OCR（`integration_test/ocr_android_test.dart`） | **8/8** | 横向、6° 倾斜、横向懒加载、MangaOCR 自动+手动、90°、270°、倒置 180°、取消 |
| MeCab/UniDic（`mecab_android_test.dart`） | **4/4** | 权限、真实 UniDic、长文本、阅读器注音 |
| MDict（`mdict_android_test.dart`） | **当前 5/6** | 主页文案已可达搜索页；最后一个搜索页断言未找到 `とうきょう【東京】`，未改非 Agent 搜索逻辑 |
| MDict（历史 Phase 2） | 6/6 | 历史值，不要作为当前结果 |
| MDict 兼容（`mdict_compat_android_test.dart`） | **2/2** | `Encrypted: 2` 与 MDD 图片 |
| MDD 音频（`mdict_audio_android_test.dart`） | **1/1** | `00048.aac`，25,463 bytes；扬声器出声仍需人工确认 |
| 真实图片扫描（`ocr_real_images_android_test.dart`） | **7 张** | `test_images/` × auto/横向/竖向 |

> 设备均为 x86_64 模拟器（API 36）；arm64/真实设备验收不能从这些结果推断。
> 详细命令见 `docs/dev-setup.md`。

## 4. 性能记录

设备/日期：x86_64 模拟器（`Medium_Phone_API_36.1`），Phase 4.5 验收前后；
arm64 真机性能另需复测。

| 场景 | 数值 |
|---|---:|
| PaddleOCR 横向 | 195ms |
| PaddleOCR 6° 倾斜 deskew | 169ms |
| MangaOCR auto（冷） | 1003ms |
| MangaOCR vertical（热） | 312ms |
| 90° 旋转后 PaddleOCR | 832ms |
| 270° 旋转后 PaddleOCR | 648ms |
| 倒置 180° | 135ms |
| 早期 OCR 合成冒烟 | 320ms |
| MangaOCR 早期合成 | 自动 253ms / 手动 251ms |
| `MecabService.open` | 217ms（Phase 1 记录 246ms） |
| 1100 tokens 分词 | 276ms |
| `MdictService.open` / probe | 716ms / 675ms |
| 463k 词典首次 `initDict` / RSS | ~200ms / ~400MB |
| MDict 首次查询 / 热查询 | 425ms / 1ms |
| MDict warmup / warm 后首次 | 415ms / 7ms |
| arm64 release APK | 60.1MB |
| debug APK（全 ABI） | ~260MB |

> 性能数字必须带设备/日期上下文；不要把 x86_64 数字当作 arm64 验收结果。

## 5. 构建产物

| 产物 | 值 |
|---|---:|
| arm64 release APK | 60.1MB（`app-arm64-v8a-release.apk`） |
| debug APK | ~260MB（全 ABI，不代表 release） |
| 最近 debug build | success |

## 6. 开发数据与模型统计

| 项 | 值 |
|---|---|
| UniDic `sys.dic` | 283.9MB；头部版本 102、UTF-8、1,027,505 条词条 |
| UniDic `matrix.bin` | 1,029.5MB |
| UniDic `char.bin` / `unk.dic` / `dicrc` | 262KB / 5.8KB / 1KB |
| UniDic 总大小 | 约 1.313GB（常写作 1.3GB） |
| 开发 MDict MDX | 33.8MB，v2.0，UTF-8，463,312 条，391 个 key block，zlib |
| 开发 MDict MDD | 6.2MB，9,220 个资源；同目录 CSS 6.1KB |
| OCR 字符表 | 18,385 classes（blank + 18,383 keys + space） |
| 真实测试图片 | 7 张（`test_images/`） |
| 模型目录 | `getExternalFilesDir()/models/` |

> 模型 URL/SHA/文件名以 `assets/models/manifest.json` 为准；本表只记录统计值。

## 7. 固定 UI 文案/标签

> 视觉数值（字号、间距、颜色、圆角）以 `docs/design-tokens.md` 和
> `lib/core/theme/app_tokens.dart` 为准；本表只集中**用户可见文案**。

| 类别 | 固定值 |
|---|---|
| 主页五个按钮 | 拍照识别、查句子、查单词、历史记录、词典助手 |
| 模式 | 严格模式、宽松模式 |
| 结果区标题 | 原文、译文、逐句理解、可能的理解、未解决、词典依据 |
| 模型标记 | 模型译文、模型补充 |
| 证据折叠 | 依据 N 条 ▾ |
| 状态 | 本机 OCR、熟悉词典、分词、生成、校验、已停止、生成中断、无词典依据 |
| 输入占位 | 输入问题，或粘贴文本… |
| 档案操作 | 保存并信任、本次跳过、不再询问 |
| 隐私文案 | 图片只在本机 OCR，不会上传 |
| 设置分组 | 词典助手设置、模型服务、服务商、接口地址、快速模型、高精度模型、接口密钥（API Key） |

> 这些文案目前也出现在设计/契约/测试里；修改时只改本表，并同步 UI 实现/测试的
> 引用。历史评审中的旧文案保留为历史记录，不作为当前值。

## 8. Agent 当前预算/上限

| 项 | 当前值 |
|---|---:|
| 单次分析源文本 | 6,000 字符 |
| 唯一检索目标 | 120 |
| citation 总数 | 60 |
| 每词每典条数 | 3 |
| 摘要长度 | 400 字符 |
| 模型额外工具调用 | 0（当前固定流水线、模型无工具） |

> 历史 tool loop 预算（6 次、单工具 60s、总 90s）仅作未来参考，不是当前实现。
> 契约中的默认值仍以 `docs/phase6-agent-contracts.md` 为准；本表与契约冲突时先
> 以本表确认当前实现，再修契约。

## 9. 当前阶段/提交锚点

| 项 | 值 |
|---|---|
| 当前 HEAD | `c6094b5`（OCR 模型页操作逻辑修正） |
| Phase 5 基线 | `2534c3a` |
| Phase 6 P6.1–P6.5 提交起点 | `7be4b81` |
| Phase 6 文档提交 | `b208456` |
| 历史快照 banner | `3709d3d` |
| 当前工作队列 | `docs/agent_docs/device-feedback-2026-10-31.md`（F1–F17，Wave 2–4 待做） |

> 历史提交的完整列表在 `git log` 与各 phase status 中；本表只保留当前锚点，避免
> 每次提交都改多份文档。

## 10. 引用规则

- 当前测试/设备/性能/构建/环境/数据值：引用本文件，不复制数字。
- 历史 phase 文档：保留“当时值”，并加 `历史值` 标注；需要当前值则链接本文件。
- UI token、模型 hash、Schema/契约：分别以 `design-tokens.md`、
  `assets/models/manifest.json`、`phase6-agent-contracts.md`/`docs/schemas/agent/`
  为准；本文件不接管这些规范。
- 修改本文件后，仅需更新 `last_verified`/`HEAD`；其他文档的链接保持有效。
