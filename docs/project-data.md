# 项目测试与验证数据

> **单一事实源**：所有跨文档复用的测试数量、设备结果、性能、构建产物、环境版本、
> 开发数据统计和固定 UI 文案以本文件为准。其他文档只引用本文件对应小节，不再
> 复制具体数值；历史记录可以保留“当时值”，但必须标注为历史快照。
>
> - last_verified: 2026-11-03
> - last_verified_code_commit: `04bf192`（`fix: 修复富文本后处理逻辑和prompt不统一`）
> - last_doc_sync: 2026-11-03（P6.6 自动化收尾：同步测试基线、多图/多变体描述与
>   当前提交锚点）
> - 设备基线: `Medium_Phone_API_36.1`（x86_64 模拟器，API 36）；无 arm64 真机
> - 维护规则：数据变化时只改本文件，并同步更新 `last_verified`/
>   `last_verified_code_commit`；其他文档的引用链接不需要改。不要把本文件自身的
>   文档提交哈希写成“当前 HEAD”，避免自引用。

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

> 构建命令、权限和集成测试步骤不在这份数据文档中重复。

## 2. 自动化测试

### 2.1 当前基线

| 项 | 值 |
|---|---:|
| 当前 test/testWidgets 声明数 | **350** |
| 当前测试文件数 | **77** |
| 最近 `flutter analyze` | No issues found |
| 最近 `flutter test` | **366 passed**（声明 350；参数化/循环用例产生 366 个执行用例） |
| 最近 `flutter build apk --debug` | success（2026-11-03 P6.6 收尾验证） |

> 统计口径：`test/**/*.dart` 中的 `test(` + `testWidgets(`；不含 integration_test。
> 该数字对应 P6.6 自动化收尾工作区（含 Wave 3、P6.6 多 OCR、P7.0 富文本修正）。
> 新增/删除测试后只更新本节。

### 2.2 历史测试基线（不要当作当前值）

| 阶段/时点 | 数量 | 说明 |
|---|---:|---|
| Phase 3 | 97 | `docs/phase3-status.md` / `phase3-review.md` 历史记录 |
| Phase 5 | 149 | `docs/phase5-status.md` 历史记录；当时 `flutter test` 149 passed |
| Phase 6 设计快照 | 199 | `docs/phase6-agent-design.md` 旧记录 |
| Wave 1 前 | 206 | Agent Wave 1 新增测试前 |
| Wave 1 后 | 212 | Agent Wave 1 完成时 |
| Wave 2 后 | 231 | Agent 语言/档案队列/多图/结果操作行 |
| Wave 2 follow-up | 246 | 档案队列复用、自动保存、标签输出、交互修正 |
| 标签完整性/旧 schema 清理 | 267 | 标签块校验、移除 JSON 响应 schema/回退；含并行新增 regeneration 测试 |
| 依据计数修正 | 268 | 展开栏“详细解析”依据数改为最终采用数 |
| Wave 3 | 291 | F1b 语言后校验、F6 四种模式递进/AgentLimits、F7 覆盖审查与一次回退 |
| Prompt/覆盖标签/raw 兜底 | 295 | agent_prompts 集中、coverage 标签、模式无新增继续、UniDic raw surface |
| P6.6 多 OCR 核心 | 321 | 质量/diff、版本比较、词典候选、用户确认后重新分析；设备验收待做 |
| P6.6 稳定性修正 | 332 | provider 预校验/400 分类、覆盖审查独立预算与容错、多 OCR 每图状态/UI、UniDic 清除 |
| Provider 推理修正 | 333 | OpenAI-compatible 默认不发送 max_tokens、reasoning-only 快速失败不重试、流式进度节流 |
| Provider 可选输出上限 | 336 | provider 设置 maxOutputTokens、OpenAI/Anthropic payload 覆盖与持久化测试 |
| P6.6 收尾 / P7.0 富文本修正 | 366（声明 350） | 富文本/YOMI 标签处理、结果渲染与 P6.6 多 OCR 回归；真机验收待做 |
| 当前 | **366（声明 350）** | 见 §2.1 |

> 历史 phase 文档保留当时值；需要当前值以本文件 §2.1 为准。

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

> 视觉数值（字号、间距、颜色、圆角）不在本表重复；本表只集中**用户可见文案**。

| 类别 | 固定值 |
|---|---|
| 主页五个按钮 | 拍照识别、查句子、查单词、历史记录、词典助手 |
| 模式 | 严格模式、宽松模式 |
| 结果区标题 | 原文、译文、逐句理解、可能的理解、未解决、词典依据 |
| 模型标记 | 模型译文、模型补充 |
| 证据折叠 | 依据 N 条 ▾ |
| 状态 | 本机 OCR、熟悉词典、分词、生成、校验、已停止、生成中断、无词典依据 |
| 输入占位 | 输入问题，或粘贴文本… |
| 查词占位 | 搜索…… |
| 档案操作 | 保存并信任、本次跳过、不再询问 |
| 隐私文案 | 图片只在本机 OCR，不会上传 |
| 设置分组 | 词典助手设置、模型服务、服务商、接口地址、快速模型、高精度模型、接口密钥（API Key） |
| 复制按钮 | 照片「复制文本」；语料卡片「复制」；语料详情「复制文本」 |
| 文本语料 | 文本语料（无照片占位的卡片/详情） |
| 阅读工具栏 | 隐藏输入框 |
| 多选页 | 选择照片 |
| 空态/错误 | 去设置、尚未配置模型、未找到可用的 OCR 模型 |
| Agent 状态 | 离线模式，仅本地功能可用、已停止 · 重试、生成中断 · 重试、待处理档案 N 个 |
| Citation | 来源N、依据 N 条 ▾ |
| 引导/设置 | 开始使用、跳过、重新查看新手引导、自动保存识别结果、清除词典资源缓存 |

> 这些文案目前也出现在设计/契约/测试里；修改时只改本表，并同步 UI 实现/测试的
> 引用。历史评审中的旧文案保留为历史记录，不作为当前值。

## 8. Agent / Provider / 语言与图片处理限制

### 8.1 当前 Agent 限制

| 项 | 当前值 | 状态/说明 |
|---|---:|---|
| 单次分析源文本 | 6,000 字符 | `AgentLimits.maxSourceChars`；orchestrator 拒绝超限 |
| 唯一检索目标 | 120 | `AgentLimits.maxTargets`；EvidenceBuilder |
| citation 总数 | 60 | `AgentLimits.maxEvidenceEntries`；EvidenceBuilder |
| 每词每典条数 | 3 | `AgentLimits.maxEntriesPerDictionary`；lookup |
| 摘要长度 | 400 字符 | `AgentLimits.maxSnippetChars`；citation 展示清洗另截断至 240 |
| 单个 source 的 quote 上限 | 40 | `quote_builder.dart` |
| 熟悉期每词典样本 | 12 | `DictionaryFamiliarizationService` |
| UniDic 熟悉样本句 | 4 | `UnidicFamiliarizationService` |
| 熟悉期 batch tokens | 4,000（最多 6,000） | 当前服务 |
| 分析请求 maxTokens | 12,000（仅 Anthropic 发送） | `analysis_prompts.dart`；provider 可选 `maxOutputTokens` 覆盖 |
| Provider 最大输出 tokens | 可选，0=未设置 | Agent 设置页；存于 `capabilities_json.max_output_tokens` |
| 模型额外工具调用 | 0 | 当前固定流水线、模型无工具 |
| 每词典档案 Markdown | 2,000 字符 | **设计/契约目标；当前代码未强制** |
| 输入 variants / sources | 4 / 8 | Schema 契约上限；当前 UI 支持多图（最多 6），每图最多 4 个 `(engine, mode)` 变体（P6.6） |
| 每次 run 图片数 | 6 | `AgentLimits.maxImagesPerRun`（F11 已实现） |
| 覆盖审查 missing / duplicate / fallback | 20 / 10 / 1 | `AgentLimits`（F7 已实现，单次回退） |
| 历史 tool loop | 6 次 / 60s / 90s | **未来参考，不是当前实现** |

### 8.2 当前 Provider/LLM 限制

| 项 | 当前值 | 状态/说明 |
|---|---:|---|
| Provider 默认超时 | 180 秒 | `AgentProviderConfig.timeoutSeconds` |
| 429/5xx 最大尝试次数 | 3（即最多 2 次重试） | `provider_http.dart` |
| 401/403 | 不重试 | 当前 provider 映射 |
| Anthropic API version | `2026-10-21` | 当前适配器 |
| 文本-only | 是 | 无 tool/capability 请求面 |

### 8.3 图片/语料处理限制

| 项 | 当前值 | 说明 |
|---|---:|---|
| OCR 输入最长边 | 2,048 | Paddle/Manga 预处理 |
| 保存语料图片最长边 | 2,048 | HistoryStore |
| 保存语料 JPEG 质量 | 85 | HistoryStore |

> UI 间距、字号、圆角、组件高度、筛选条 3.5 行、消息宽度 80%、气泡 16/4、
> composer 5 行、citation chip 24–28 等视觉数值不在这份数据文档中重复；本文件
> 只记录跨模块使用的处理/业务数值。

### 8.4 Agent 语言默认值

| 项 | 权威值 | 说明 |
|---|---|---|
| 默认输出/UI 语言 | 中文（zh） | **2026-11-01 决策**：旧 `follow` 一律映射为 `zh`；禁止按输入假名/拉丁字符推断 |
| 可选语言 | zh / en / ja | 用户显式设置；`follow` 仅兼容旧配置，解析为 `zh` |

> Wave 2 已实现默认 `zh`、旧 `follow` 解析为 `zh`，`resolveAgentUiLanguage`
> 只接收显式设置，输入假名/拉丁字符不再影响 UI 语言。Wave 3（F1b）已加入结果
> 人类可读字段的语言后校验与一次语言修复；修复仍失败时保留结果并显示 warning。

> 契约中的默认值若与本表冲突：以本表作为当前实现值，并修
> `docs/phase6-agent-contracts.md`；未来 tool loop/coverage 值必须标明 future。

## 9. 当前阶段/提交锚点

| 项 | 值 |
|---|---|
| 最近验证代码提交 | `04bf192`（P6.6 自动化收尾验证基线） |
| Phase 5 基线 | `2534c3a` |
| Phase 6 P6.1–P6.5 提交起点 | `7be4b81` |
| Phase 6 文档提交 | `b208456` |
| 历史快照 banner | `3709d3d` |
| 当前工作队列 | `docs/agent_docs/device-feedback-2026-10-31.md`（Wave 1–3 已实现；Wave 4 设备回归待做） |

> 历史提交的完整列表在 `git log` 与各 phase status 中；本表只保留当前锚点，
> 避免每次提交都改多份文档。

## 10. 维护规则

- 本文件只记录当前测试/设备/性能/构建/环境/预算/固定文案；其他文档不复制这些
  数值。
- 视觉数值、规范规则、误区正文和 Agent 字段不在这份数据文档中重复。
- 修改本文件后更新 `last_verified`/`last_verified_code_commit`；引用本文件的
  链接保持有效，历史记录保留“历史值”标注。
