# 项目规则（正面 / 反面）

> **单一规则源**：所有跨文档复用的 MUST / MUST NOT 规则以本文件为准。其他文档
> 只引用规则 ID 或链接本文件，不再复制规则正文。
>
> - 数据/数字/固定文案：`docs/project-data.md`
> - 误区/踩坑与解决方案：`docs/project_tips.md`
> - UI 视觉数值/布局/交互：`docs/design-tokens.md`
> - Agent 字段/错误码/Schema：`docs/phase6-agent-contracts.md` / `docs/schemas/agent/`
> - 架构决策：`docs/adr/`
> - 历史阶段记录：`docs/project-history.md`（阶段流水汇总）/
>   `docs/phase*-status.md`（详细快照，只代表当时状态）
>
> 最后同步：2026-11-01。规则变更只改本文件；数据变更只改 `project-data.md`；
> 视觉/UI 布局变更只改 `design-tokens.md`；误区变更只改 `project_tips.md`；
> 阶段流水变更只改 `project-history.md`。

## 0. 权威层级与写法

1. **规则**：本文件；使用 `R-<域>-<序号>` 稳定 ID。
2. **当前数据/文案**：`docs/project-data.md`。
3. **视觉数值与 UI 行为细节**：`docs/design-tokens.md` +
   `lib/core/theme/app_tokens.dart`。
4. **Agent 字段/错误码/状态机**：`docs/phase6-agent-contracts.md` + `docs/schemas/agent/`。
5. **架构决策**：`docs/adr/`。
6. **历史阶段**：`docs/project-history.md` 汇总阶段流水；`docs/phase*-status.md`
   保留详细快照。允许保留“当时值”，不得当作当前规则/数据。
7. **误区/踩坑**：`docs/project_tips.md`；只记录历史经验与解决方式，不复制
   MUST/MUST NOT 规则或当前数值。
8. `README.md`、`CLAUDE.md` 及其他文档只做摘要和引用；与上面冲突时以上面为准并修正
   摘要。

规则表中的 **MUST** = 必须；**MUST NOT** = 禁止；**SHOULD** = 建议但允许有记录
的例外。每条规则附“反例/验证”和“权威细节”，实现细节不要在本文件重复。

## 1. 产品与范围（R-PROD）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-PROD-01 | MUST | 仅支持 Android 单端 | 不新增 iOS/桌面端目标 | `README` / `CLAUDE.md` §1 |
| R-PROD-02 | MUST | 核心 OCR、分词、查词在离线状态可用 | 未配置 provider 时仍可拍照/阅读/查词 | `docs/phase*-status.md` |
| R-PROD-03 | MUST | Agent 是可选在线模块；只有用户配置 provider/API Key 并主动发送时才联网 | 禁止启动即请求、后台自动上传 | `docs/adr/0004-*`、`phase6-agent-design` §1 |
| R-PROD-04 | MUST | 图片只经本机 OCR；禁止把图片作为 LLM 视觉输入 | 请求体捕获测试断言无图片/base64/路径 | `phase6-agent-design` §14、`phase6-agent-contracts` §11 |
| R-PROD-05 | MUST NOT | 不引入云 OCR、云翻译、云 ASR、ML Kit | 不新增相关 SDK/endpoint | `CLAUDE.md` §2.9、`docs/DEVELOPMENT_PLAN` |
| R-PROD-06 | MUST | UniDic/MDict 由用户提供，不随包分发 | 仓库不出现 `.mdx/.mdd/UniDic` 数据 | `.gitignore`、`THIRD_PARTY_NOTICES.md` |
| R-PROD-07 | MUST | MangaOCR 权重不随包分发；下载前提示许可未声明 | 仓库不出现模型二进制 | `models.md`、`NOTICE` |

## 2. 隐私与安全（R-SEC）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-SEC-01 | MUST | Provider 请求只能是文本 JSON；不得含图片、base64、路径、文件名或 EXIF | `assertNoImagePayload` + 请求体测试 | `phase6-agent-contracts` §11 |
| R-SEC-02 | MUST | 不得把完整 MDict HTML、MDD 图片/音频或整条词条发给模型 | 只发 `htmlToPlainText` 清洗摘要（≤400 字符） | `phase6-agent-design` §8.2 |
| R-SEC-03 | MUST | API Key 只放 `flutter_secure_storage`/Android Keystore | 禁止 SharedPreferences/SQLite/URL/仓库 | `secret_store.dart`、`adr/0004` |
| R-SEC-04 | MUST | 日志、错误、崩溃报告不得含 Key、完整请求体、图片路径 | 日志/错误脱敏测试 | `provider_http.dart`、`project_tips.md` T-078/T-113 |
| R-SEC-05 | MUST NOT | 不执行模型生成的代码、HTML、JS 或任意脚本 | UI 只渲染安全纯文本/结构化组件 | `phase6-agent-design` §14 |
| R-SEC-06 | MUST | citation 只能指向 orchestrator 发放的真实词典结果 | 伪造/越界 citation 只显示为文本 | `citation_registry.dart`、`agent_validator.dart` |
| R-SEC-07 | MUST | 所有用户可见错误必须是中文可读文案，不含原生异常/路径/堆栈/Key | 错误映射测试 | `agent_error_mapper.dart` |
| R-SEC-08 | MUST | Provider 由用户自行配置；不内置或代管任何 Key | 仓库/CI/测试不出现真实 Key | `project_tips.md` T-078 |
| R-SEC-09 | MUST | 外部路径必须先确认 All Files Access；应用专属外部目录除外 | `ensurePathAccess` + 权限引导 | `project_tips.md` T-088、`settings` |
| R-SEC-10 | MUST | 用户 UniDic/MDict 目录只读；不得写入 `mecabrc`、缓存或档案 | 私有 `mecabrc`/私有 SQLite | `adr/0002`、`project_tips.md` T-006/T-007 |

## 3. 架构与集成（R-ARCH）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-ARCH-01 | MUST | OCR 统一使用 ONNX Runtime | 不引入第二套推理运行时 | `adr/0001` |
| R-ARCH-02 | MUST NOT | 不引入 Paddle-Lite/OpenCV/NDK r21/`.nb` 模型 | 不编译 `PaddleOCR4Android` 核心 | `adr/0001`、`project_tips.md` T-001 |
| R-ARCH-03 | MUST | 横向 PaddleOCR、纵向 MangaOCR；auto 只返回一个引擎 | mixed 结果 / 按区域混合禁止 | `CLAUDE.md` §2.10 |
| R-ARCH-04 | MUST | 手动 vertical 缺 MangaOCR 必须报 `MODEL_MISSING`；不能静默走横向 | 错误码测试 | `ocr_service.dart` |
| R-ARCH-05 | MUST | 可选模型懒加载；横向模式不得创建 Manga session；readiness 先 stat | 懒加载测试 | `phase4.5-status`、`ocr_service.dart` |
| R-ARCH-06 | MUST | 90/270 旋转后必须重新 DBNet；textline 180° 只在 auto 横向 | OCR 设备套件 | `phase4.5-status` |
| R-ARCH-07 | MUST | UniDic/MDict 原地读取，不复制；MCab 用私有 `mecabrc` | 1.3GB 复制/写用户目录禁止 | `adr/0002`、`project_tips.md` T-006/T-007 |
| R-ARCH-08 | MUST | UniDic feature 行必须用引号感知 CSV 解析；字段异常降级为可点击/无注音 | 不用 `split(',')` | `mecab_output_parser.dart` |
| R-ARCH-09 | MUST | MDict 走长生命周期 worker isolate；`@@@LINK` 最多 3 层；`Encrypted:2` 允许，LZO/v3 拒绝 | 设备 MDict 测试 | `adr/0003`、`project_tips.md` T-011/T-013 |
| R-ARCH-10 | MUST | MDict HTML 在离线 WebView 渲染；禁 JS/网络；清洗 HTML；MDD 重写为 `file://`；禁止 `flutter_html` | 注入/网络测试 | `entry_renderer.dart`、`project_tips.md` T-014 |
| R-ARCH-11 | MUST | 模型运行时下载/本地导入；精确 URL/SHA 以 `assets/models/manifest.json` 为准；不提交模型 | `git check-ignore` | `models.md`、`manifest.json` |
| R-ARCH-12 | MUST | 字体不入库；用户按 `assets/fonts/README.md` 下载 | 构建缺失字体只提示下载 | `CLAUDE.md` §1、`project_tips.md` T-031 |
| R-ARCH-13 | MUST | 查词逻辑由 `LookupGateway` 共享；UI 与 Agent 不复制查词选择/排序 | 代码审查 | `lookup_gateway.dart` |
| R-ARCH-14 | MUST | 不删除 `unidic/`、`mdicts/`、`third_party` 参考数据来“清理仓库” | 仓库卫生检查 | `project_tips.md` T-023 |

## 4. Agent 流水线（R-AGENT）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-AGENT-01 | MUST | 当前采用固定流水线，模型无工具，不采用自由 ReAct | 请求不带 tools；orchestrator 预取 | `phase6-agent-design` 顶部、`CLAUDE.md` §2.9 |
| R-AGENT-02 | MUST | 恢复 tool loop 必须先有新的 ADR/批准，并扩展 `LlmMessage`/provider tool 往返 | 不得直接加回 tool registry | `phase6-agent-design` 顶部 |
| R-AGENT-03 | MUST | OCR/采样/UniDic profile 是 orchestratorOnly；模型只看文本证据 | 模型不可传图片路径/触发 OCR | `phase6-agent-contracts`、`adr/0004` |
| R-AGENT-04 | MUST | 先预取所有唯一 token/语法目标，按用户词典顺序检索 | 不允许模型决定先查哪本词典 | `phase6-agent-design` §6.3/§8.4 |
| R-AGENT-05 | MUST | citation 只由 `CitationRegistry` 发放；模型不能自造 | validator 拒绝未知 ID | `citation_registry.dart`、`agent_validator.dart` |
| R-AGENT-06 | MUST | 词典顺序唯一来源 `DictionaryInfo.order`；同一词条多词典分别保留/不合并 | UI 证据卡按顺序 | `phase6-agent-design` §8.4 |
| R-AGENT-07 | MUST | 严格模式事实必须有真实 citation；无依据进 `unresolved`；宽松补充必须独立标注 | strict/loose 测试 | `agent_validator.dart`、`phase6-agent-design` §10 |
| R-AGENT-08 | MUST | quote_id 由 orchestrator 发放；literal 由 quote 回填，模型不得改写原文 | quote/literal 校验 | `quote_builder.dart`、`agent_validator.dart` |
| R-AGENT-09 | MUST | 每会话词典选择从全局偏好快照后独立保存，不写回查词全局偏好；模型不能改 | 会话 A/B 测试 | `phase6-agent-design` §8.4；F8 待完成 |
| R-AGENT-10 | MUST | 熟悉期采样有界；档案必须用户确认后保存；按指纹复用；不写用户目录 | pending/save/decline 测试 | `dictionary_familiarization_service` |
| R-AGENT-11 | MUST NOT | 模型不能改变模式/词典/provider/model，也不能执行代码 | 只用 UI 修改这些设置 | `phase6-agent-design` §8.4/§14 |
| R-AGENT-12 | MUST | Provider 请求文本-only；不发送 tools/capabilities/视觉字段 | `LlmRequest` 无 tools | `llm_port.dart`、`provider_payload.dart` |
| R-AGENT-13 | MUST | Agent 预算/上限只引用 `project-data.md` §8，不在业务代码散落魔法数 | 代码审查/测试 | `project-data` §8 |
| R-AGENT-14 | MUST | 当前工作优先级：先完成 2026-10-31 F1–F17；F2 未完成前不做 F7/F13/F14 档案部分；F6 未完成前不做 F7 | `device-feedback` Wave 顺序 | `device-feedback-2026-10-31` |
| R-AGENT-15 | MUST | F1–F17/P6.6/P6.7 未完成前，不把这些能力写成已支持 | 文档/UI 审查 | `device-feedback`、`phase6-status` |
| R-AGENT-16 | MUST | 运行状态归应用级 `AgentRunController`；离开页面不取消；返回恢复最新进度；只有显式“停止”才取消 | 生命周期测试 | `agent-lifecycle-and-edge-cases` |
| R-AGENT-17 | MUST | 真实 provider/API Key、secure storage、真实词典 sample/suggest、arm64 Agent 未验收前不得声称已验证 | 状态文档 | `phase6-status` |
| R-AGENT-18 | MUST | 默认输出/UI 语言为中文（zh）；旧 `follow` 必须映射为 `zh`；禁止按输入文本的假名/拉丁字符推断语言（F1/F17） | 日语输入 + 默认设置 → 中文 UI/结果；旧 `follow` → 中文；不得读取 `sourceText` 推断 | `project-data` §8.4；`device-feedback` F1/F17 |

## 5. UI / UX（R-UI）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-UI-01 | MUST | 所有页面使用 `design-tokens.md`/`app_tokens.dart`；页面不得硬编码颜色/字号/间距/圆角 | grep 硬编码审查 | `design-tokens`、`app_tokens.dart` |
| R-UI-02 | MUST | 所有页面统一深蓝 `header` AppBar + 白字白图标；词条 TabBar 白字 | 页面局部改 AppBar 禁止 | `design-tokens` |
| R-UI-03 | MUST | 主页按钮数量/顺序/文案以 `project-data.md` §7 为准（当前五个） | 不提前改名/新增 | `project-data` §7、`CLAUDE.md` §1 |
| R-UI-04 | MUST | 阅读面/结果/工具区白色；工具区仅 1px divider 收边；分词不用灰色；弹层无关闭叉；读音==词形不显示读音 | 阅读器审查 | `design-tokens` §3.2 |
| R-UI-05 | MUST | 设置页白底扁平、无卡片；长提示 14sp 完整换行；用户不可变信息 16sp 纯文本 | 设置页审查 | `design-tokens` |
| R-UI-06 | MUST | 所有页面转场使用 `SlideOverPageTransitionsBuilder` 右滑覆盖；不淡入淡出/缩放 | 路由测试 | `design-tokens` |
| R-UI-07 | MUST | 照片集/语料/多选页的删除/保存/复制位置、尺寸、二次确认按 `design-tokens` | 页面/设备测试 | `design-tokens` |
| R-UI-08 | MUST | Agent 使用对话式布局：消息区优先、固定 composer、证据折叠、状态可见、错误卡保留内容 | Agent UI 审查 | `design-tokens` Agent v2 |
| R-UI-09 | MUST | citation 使用短胶囊+自动换行；词典筛选 3.5 行；颜色/触控按 tokens | 窄屏/200% 测试 | `design-tokens`；F4/F9 |
| R-UI-10 | MUST NOT | 禁止全屏 loading、阻塞式弹窗、无原因错误、气泡满宽、生成中整块“正在输入” | UI 审查 | `design-tokens` Agent v2 |
| R-UI-11 | MUST | 空态/错误态必须提供下一步操作，文案引用 `project-data.md` §7 | 页面审查 | `design-tokens`、`project-data` |
| R-UI-12 | MUST | 所有图标/操作有 Semantics；触控 ≥40dp；支持 200% 字体；当前仅浅色主题 | 无障碍检查 | `design-tokens` |
| R-UI-13 | MUST | 固定 UI 文案只引用 `project-data.md` §7，不在设计/契约/测试中另立当前版本文案 | 文案审查 | `project-data` §7 |
| R-UI-14 | MUST | UI 视觉数值只以 `design-tokens` 为准；`project-data` 不复制 token 数值 | 文档审查 | `project-data` §8.3 指针 |

## 6. 开发、构建与发布（R-DEV）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-DEV-01 | MUST | 固定 minSdk/compileSdk/targetSdk/NDK，禁止降级 | 检查 `build.gradle.kts` | `project-data` §1 |
| R-DEV-02 | MUST | 阶段结束跑 `flutter analyze`、`flutter test`、debug build；数据只写 `project-data` | CI/本地验证 | `project-data` §2/§5 |
| R-DEV-03 | MUST NOT | 用户未明确要求时不得 commit/reset/push，不覆盖未提交改动 | `git status` 检查 | `project_tips.md` T-020 |
| R-DEV-04 | MUST NOT | 模型/字体/词典/UniDic/API Key 不入库 | `.gitignore`/`git ls-files` | `project_tips.md` T-021/T-022 |
| R-DEV-05 | MUST | 分发前替换 release debug keystore | 检查 `build.gradle.kts` TODO | `phase5-status` |
| R-DEV-06 | MUST | 集成测试后手动安装前重新 debug build；release 前先 `--config-only` | 构建检查 | `project_tips.md` T-040/T-129 |
| R-DEV-07 | MUST | 所有文件访问用原生 MethodChannel，不用 `permission_handler` | Android 审查 | `project_tips.md` T-015 |
| R-DEV-08 | MUST NOT | 不添加 `sqflite_common_ffi`（会触发 Android native-assets 下载失败） | 依赖审查 | `project_tips.md` T-128 |
| R-DEV-09 | MUST | 主机 MeCab/MDict 脚本放隔离 Dart 包，不在根包 `dart run` | 开发流程 | `project_tips.md` T-010 |
| R-DEV-10 | MUST | 模型下载/导入必须有许可确认、SHA-256、断点续传；清理只删临时文件 | 模型页/测试 | `models.md`、`phase4.5-status` |

## 7. 文档、数据与文案治理（R-DOC）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-DOC-01 | MUST | 当前测试/设备/性能/构建/环境/预算/固定文案只在 `project-data.md` 维护 | 其他文档复制当前数字/文案 | `project-data` §10 |
| R-DOC-02 | MUST | 规范性 MUST/MUST NOT 规则只在本文件维护；其他文档只引用规则 ID/链接 | 在 CLAUDE/README/design 复制规则正文 | 本文件 §0 |
| R-DOC-03 | MUST | 视觉数值与 UI 布局/交互细节只在 `design-tokens.md` 维护；UI 实现用 `app_tokens.dart` | 在其它文档复制 token 数值或页面布局规则 | `design-tokens` |
| R-DOC-04 | MUST | Agent 字段/错误码/状态机只在 contracts/schemas 维护 | 在 design/README 另立字段表 | `phase6-agent-contracts`、`docs/schemas/agent` |
| R-DOC-05 | MUST | ADR 只记录决策；project-history 只记录阶段流水；phase status 只记录当时快照，均不得写当前规则/数据 | 在历史文档更新当前值 | `docs/adr/`、`docs/project-history.md`、`docs/phase*-status.md` |
| R-DOC-06 | MUST | `README.md`/`CLAUDE.md` 只做摘要和引用；发现与权威文档冲突时修正摘要 | 摘要复制冲突数值/规则 | `README`、`CLAUDE.md` |
| R-DOC-07 | MUST | 冲突处理：规则→本文件；数据→project-data；视觉→design-tokens；字段→contracts；误区→project-tips；历史→project-history/phase status；修复低权威文档 | 任意文档冲突 | 本文件 §0 |
| R-DOC-08 | MUST | 数据变更更新 `last_verified`/`last_verified_code_commit`；规则变更更新本文件版本/日期；历史值标注“历史值” | 文档审查 | `project-data` 头部 |
| R-DOC-09 | MUST | 误区/踩坑与解决方案只在 `project_tips.md` 维护（`T-###`）；其他文档只引用 T-ID/链接 | 在 CLAUDE/README/status 新增误区正文 | `project_tips.md` |
| R-DOC-10 | MUST | 阶段开发历史只在 `project-history.md` 汇总；`CLAUDE.md` 只保留当前状态/下一步；详细 phase 快照留在 `phase*-status.md` | 在 CLAUDE.md 复制 Phase 0–5 流水账 | `project-history.md` |

## 8. 当前未来/部分规则

以下规则是**目标或未来**，不能写成已实现：

| ID/来源 | 状态 | 说明 |
|---|---|---|
| R-AGENT-02 tool loop | future | 只有新 ADR/批准后才可恢复；当前无模型工具 |
| R-AGENT-14 F7 coverage | future | F6 完成后才做；预算见 `project-data` §8 |
| R-AGENT-18 F1/F17 language | partial | 2026-11-01 决策：默认 zh、旧 `follow` → zh、禁止输入推断；代码仍默认 `follow`/仍有输入启发式，待 Wave 2 |
| R-AGENT-09 F8 session dictionary | partial | 当前写隔离已满足，独立持久化待 Wave 2 |
| R-UI-09 F4/F9 | partial | 短胶囊/3.5 行规范已定，设备/窄屏验收待 Wave 1/4 |
| F11 多图 | future | 当前 UI 单图；上限 6 见 `project-data` §8 |
| P6.6/P6.7 | future | 在 F1–F17 关闭前不开始 |

## 9. 变更流程

1. 规则变化：只改本文件；更新规则 ID/状态，不复制到其他文档。
2. 数据/文案变化：只改 `project-data.md`；更新 `last_verified`/commit 锚点。
3. 视觉数值变化：只改 `design-tokens.md` + `app_tokens.dart`。
4. Agent 字段/错误码变化：只改 contracts/schemas + 代码/测试。
5. 其他文档：只加/改引用链接；发现重复时删除旧正文，保留一句“规则见
   `project-rules.md` / 数据见 `project-data.md`”。
6. 误区/经验变化：只改 `project_tips.md`，追加 `T-###` 并同步附录 A；不要复制到
   `CLAUDE.md`/README/phase status。
7. 阶段开发历史：只在 `project-history.md` 追加/更新；`CLAUDE.md` 只保留当前
   状态与下一步，不复制详细流水账。
8. 历史 phase 文档：保留当时值，标注“历史值/历史快照”，不要用当前值回填。
