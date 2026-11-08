# 项目规则（正面 / 反面）

> **单一规则源**：所有跨文档复用的 MUST / MUST NOT 规则以本文件为准。其他文档
> 只引用规则 ID，不再复制规则正文。
>
> 最后同步：2026-11-06。规则变更只改本文件。

## 0. 规则写法

- 本文件是规则的单一权威；使用 `R-<域>-<序号>` 稳定 ID。
- 其他文档只做摘要和引用；与规则冲突时以本文件为准并修正摘要。

规则表中的 **MUST** = 必须；**MUST NOT** = 禁止；**SHOULD** = 建议但允许有记录
的例外。每条规则附“反例/验证”和实现细节；细节不要在本文件重复。

## 1. 产品与范围（R-PROD）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-PROD-01 | MUST | 仅支持 Android 单端 | 不新增 iOS/桌面端目标 | `README` |
| R-PROD-02 | MUST | 核心 OCR、分词、查词在离线状态可用 | 未配置 provider 时仍可拍照/阅读/查词 | `docs/phase*-status.md` |
| R-PROD-03 | MUST | Agent 是可选在线模块；只有用户配置 provider/API Key 并主动发送时才联网 | 禁止启动即请求、后台自动上传 | `docs/adr/0004-*`、`phase6-agent-design` §1 |
| R-PROD-04 | MUST | 图片只经本机 OCR；禁止把图片作为 LLM 视觉输入 | 请求体捕获测试断言无图片/base64/路径 | `phase6-agent-design` §14、`phase6-agent-contracts` §11 |
| R-PROD-05 | MUST NOT | 不引入云 OCR、云翻译、云 ASR、ML Kit | 不新增相关 SDK/endpoint | `docs/DEVELOPMENT_PLAN` |
| R-PROD-06 | MUST | UniDic/MDict 由用户提供，不随包分发 | 仓库不出现 `.mdx/.mdd/UniDic` 数据 | `.gitignore`、`THIRD_PARTY_NOTICES.md` |
| R-PROD-07 | MUST | MangaOCR 权重不随包分发；下载前提示许可未声明 | 仓库不出现模型二进制 | `models.md`、`NOTICE` |

## 2. 隐私与安全（R-SEC）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-SEC-01 | MUST | Provider 请求只能是文本 JSON；不得含图片、base64、路径、文件名或 EXIF | `assertNoImagePayload` + 请求体测试 | `phase6-agent-contracts` §11 |
| R-SEC-02 | MUST | 不得把完整 MDict HTML、MDD 图片/音频或整条词条发给模型 | 只发 `htmlToPlainText` 清洗摘要（≤400 字符） | `phase6-agent-design` §8.2 |
| R-SEC-03 | MUST | API Key 只放 `flutter_secure_storage`/Android Keystore | 禁止 SharedPreferences/SQLite/URL/仓库 | `secret_store.dart`、`adr/0004` |
| R-SEC-04 | MUST | 日志、错误、崩溃报告不得含 Key、完整请求体、图片路径 | 日志/错误脱敏测试 | `provider_http.dart` |
| R-SEC-05 | MUST NOT | 不执行模型生成的代码、HTML、JS 或任意脚本 | UI 只渲染安全纯文本/结构化组件 | `phase6-agent-design` §14 |
| R-SEC-06 | MUST | citation 只能指向 orchestrator 发放的真实词典结果 | 伪造/越界 citation 只显示为文本 | `citation_registry.dart`、`agent_validator.dart` |
| R-SEC-07 | MUST | 所有用户可见错误必须是中文可读文案，不含原生异常/路径/堆栈/Key | 错误映射测试 | `agent_error_mapper.dart` |
| R-SEC-08 | MUST | Provider 由用户自行配置；不内置或代管任何 Key | 仓库/CI/测试不出现真实 Key | — |
| R-SEC-09 | MUST | 外部路径必须先确认 All Files Access；应用专属外部目录除外 | `ensurePathAccess` + 权限引导 | `settings` |
| R-SEC-10 | MUST | 用户 UniDic/MDict 目录只读；不得写入 `mecabrc`、缓存或档案 | 私有 `mecabrc`/私有 SQLite | `adr/0002` |

## 3. 架构与集成（R-ARCH）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-ARCH-01 | MUST | OCR 统一使用 ONNX Runtime | 不引入第二套推理运行时 | `adr/0001` |
| R-ARCH-02 | MUST NOT | 不引入 Paddle-Lite/OpenCV/NDK r21/`.nb` 模型 | 不编译 `PaddleOCR4Android` 核心 | `adr/0001` |
| R-ARCH-03 | MUST | 横向 PaddleOCR、纵向 MangaOCR；auto 只返回一个引擎 | mixed 结果 / 按区域混合禁止 | `ocr_service.dart` |
| R-ARCH-04 | MUST | 手动 vertical 缺 MangaOCR 必须报 `MODEL_MISSING`；不能静默走横向 | 错误码测试 | `ocr_service.dart` |
| R-ARCH-05 | MUST | 可选模型懒加载；横向模式不得创建 Manga session；readiness 先 stat | 懒加载测试 | `phase4.5-status`、`ocr_service.dart` |
| R-ARCH-06 | MUST | 90/270 旋转后必须重新 DBNet；textline 180° 只在 auto 横向 | OCR 设备套件 | `phase4.5-status` |
| R-ARCH-07 | MUST | UniDic/MDict 原地读取，不复制；MCab 用私有 `mecabrc` | 1.3GB 复制/写用户目录禁止 | `adr/0002` |
| R-ARCH-08 | MUST | UniDic feature 行必须用引号感知 CSV 解析；字段异常降级为可点击/无注音 | 不用 `split(',')` | `mecab_output_parser.dart` |
| R-ARCH-09 | MUST | MDict 走长生命周期 worker isolate；`@@@LINK` 最多 3 层；`Encrypted:2` 允许，LZO/v3 拒绝 | 设备 MDict 测试 | `adr/0003` |
| R-ARCH-10 | MUST | MDict HTML 在离线 WebView 渲染；禁 JS/网络；清洗 HTML；MDD 重写为 `file://`；禁止 `flutter_html` | 注入/网络测试 | `entry_renderer.dart` |
| R-ARCH-11 | MUST | 模型运行时下载/本地导入；精确 URL/SHA 以 `assets/models/manifest.json` 为准；不提交模型 | `git check-ignore` | `models.md`、`manifest.json` |
| R-ARCH-12 | MUST | 字体不入库；用户按 `assets/fonts/README.md` 下载 | 构建缺失字体只提示下载 | `assets/fonts/README.md` |
| R-ARCH-13 | MUST | 查词逻辑由 `LookupGateway` 共享；UI 与 Agent 不复制查词选择/排序 | 代码审查 | `lookup_gateway.dart` |
| R-ARCH-14 | MUST | 不删除 `unidic/`、`mdicts/`、`third_party` 参考数据来“清理仓库” | 仓库卫生检查 | — |

## 4. Agent 流水线（R-AGENT）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-AGENT-01 | MUST | 当前采用固定流水线，模型无工具，不采用自由 ReAct | 请求不带 tools；orchestrator 预取 | `phase6-agent-design` 顶部 |
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
| R-AGENT-13 | MUST | Agent 预算/上限只引用统一预算常量，不在业务代码散落魔法数 | 代码审查/测试 | 统一预算常量 |
| R-AGENT-14 | MUST | 当前工作优先级：先完成 2026-10-31 F1–F17；F2 未完成前不做 F7/F13/F14 档案部分；F6 未完成前不做 F7；P6.6/P6.7 只能由用户明确指示启动（P6.6 核心已于 2026-11-02 启动；P6.7 已于 2026-11-03 由用户指示启动，历史/声调已实现，其余仍待做） | `device-feedback` Wave 顺序 | `device-feedback-2026-10-31` |
| R-AGENT-15 | MUST | F1–F17/P6.6/P6.7 未完成前，不把这些能力写成已支持 | 文档/UI 审查 | `device-feedback`、`phase6-status` |
| R-AGENT-16 | MUST | 运行状态归应用级 `AgentRunController`；离开页面不取消；返回恢复最新进度；只有显式“停止”才取消 | 生命周期测试 | `agent-lifecycle-and-edge-cases` |
| R-AGENT-17 | MUST | 真实 provider/API Key、secure storage、真实词典 sample/suggest、arm64 Agent 未验收前不得声称已验证 | 状态文档 | `phase6-status` |
| R-AGENT-18 | MUST | 默认输出/UI 语言为中文（zh）；旧 `follow` 必须映射为 `zh`；禁止按输入文本的假名/拉丁字符推断语言（F1/F17） | 日语输入 + 默认设置 → 中文 UI/结果；旧 `follow` → 中文；不得读取 `sourceText` 推断 | `device-feedback` F1/F17 |
| R-AGENT-19 | MUST | 所有 Agent prompt 文本与请求构造集中在 `lib/services/agent/agent_prompts.dart`；其他文件不得硬编码 prompt | 代码审查：orchestrator/parser/controller/UI 无 prompt 字符串 | `agent_prompts.dart` |
| R-AGENT-20 | MUST | 多 OCR 版本只由用户显式触发；不得自动合并版本或静默替换原文；采用变体/词典候选后必须重新分词、查词和分析；图片/路径/base64/Key 不得进入该流程或 provider 请求 | 变体/修复测试；请求体断言无图片/路径/Key | `phase6-agent-contracts` §3.1 |
| R-AGENT-21 | MUST | Provider 请求发送前必须本地校验：model 非空、丢弃空白消息、至少一条非 system、Anthropic 合并连续 role、清理非法 Unicode/控制字符、`max_tokens` 为正整数；不得假设统一输出上限，400 必须按真实 error body 分类 | provider payload/HTTP body 测试 | `phase6-agent-contracts` §11 |
| R-AGENT-22 | MUST | 覆盖审查是可选增强：使用 `AgentLimits.coverageReviewMaxTokens` 独立预算（MISSING/duplicate 上限 × 长度 + 标签开销 + 安全边际），不跟随分析请求；自适应触发必须按 `AgentEvidenceBudget.targetsWithCitations` 与 `uniqueTargets` 判断是否存在未获得 citation 的 target，不得用 citation 总数代理；单项畸形只丢弃该项，标签/请求失败保留原证据；不得让整次 run 失败或伪装成功 | coverage parser/orchestrator/预算测试 | `phase6-agent-contracts` §5.1 |
| R-AGENT-23 | MUST | 富文本后处理只作用于详细解析的“原文”、逐句理解和词典事实解释（词义/语法，不含 citation snippet），AI 气泡摘要、可能的理解、未解决、模型补充、引用行和词注 fallback 都用本地 RUBY 渲染，不参与模型 BOLD/UNDERLINE 后处理；可能的理解按 `[OPTION]` 的 label/confidence 显示“情况X”绿色胶囊 + “可能性N%”，相同可见依据只在最后一个情况下方显示一次、不同则逐情况保留；只能插入 `[RUBY]`/`[BOLD]`/`[UNDERLINE]` 显示标签，不得改动原文；prompt 要求保留输入中的 `[YOMI]...[/YOMI]`，代码仍兼容“整块删除并替换为等价 RUBY”的旧输出；结果构建时本地先把 YOMI 和 `reading【surface】` 读数转成 RUBY，预览首帧即可见；模型格式化只追加 BOLD/UNDERLINE，失败或空输出保留本地 RUBY 基线；模型输入仍是原始 YOMI 文本。标签必须成对且正确嵌套：RUBY 可在 BOLD/UNDERLINE 内，BOLD/UNDERLINE 可相互包裹，但不得进入 RUBY base 或嵌套自身；RUBY 读音继承 BOLD、永不加下划线，并以 base 的 alphabetic baseline 对齐。采用前必须剥离标签、按 YOMI 规则比较后与原文逐字符严格相等；YOMI 内容比较忽略全/半角标点，RUBY 读音先清洗标点，保留的 YOMI 必须内容/位置不变，冗余 RUBY（读音等于 base）必须移除；`reading【surface】` 与 `[RUBY=reading]surface[/RUBY]` 视为同一显示形式并在比较前归一化（普通括号 `（...）` 是解释性文字，不转换，base 字符仍须一致）；读数转换必须标签感知：BOLD/UNDERLINE 在读数前关闭时，把读数移入强调 span 内作为 RUBY（读音继承粗体）；RUBY 后紧跟同一读数的 `reading【surface】` 要去重；模型该 section 失败时保留本地 RUBY 基线，不退化为括号纯文本；批量格式化请求必须按 section 独立解析/校验/降级，单个 marker 或 diff 失败只影响该 section，词注/词典事实解释不进入批量请求 | `rich_text_tags`/processor/orchestrator/`agent_rich_text` 测试；`T-135`、`T-137` | `rich_text_post_processor.dart`、契约 §5.3 |
| R-AGENT-24 | MUST | P6.7 助手历史一条=一次分析（run），只读回看，不并入主页语料历史；AgentStore/历史 JSON/日志/导出不得保存图片字节、缩略图、路径、文件名、base64、API Key 或 provider 原始 body，只存 `image_count` 和 OCR 文本/变体；citation 失效只显示保存摘要；单条/多选删除（含全选后删除）必须二次确认，不自动删除 | 历史 codec/迁移/删除/隐私测试；grep 无 `image_path`/`localPath`/`base64` | 设计 §17.2.2、契约 §14.1 |
| R-AGENT-25 | MUST | 声调只允许来自 UniDic 字段 24–26（`aType` + 读音 mora 数），不得用 AI/模型推测或补全；只在词注/词典事实行显示，AI 气泡/原文/逐句/证据/citation/导出不显示；无可靠数据、越界、读音为空或词形不匹配时不画线；**汉字词没有独立振假名/读音时不画线**（可能是多音词）；声调不进入 provider 请求/日志 | pitch parser/UI/请求体测试；真实 UniDic 样例夹具；汉字无读音用例 | 设计 §17.2.3、契约 §14.2 |
| R-AGENT-26 | MUST | annotation DSL v1 只接受安全 JSON AST 的**装饰子集**（ruby/pitch/bold/underline + when），禁止 text/group、任意代码、HTML、JS、URL、网络、文件访问、图片和外部链接；求值器纯本地、确定性；无效/超限规则集整体拒绝并保留上一有效版本；P6.7 只做内置规则+实时预览/恢复默认，先覆盖阅读器/照片集/语料，不接入 Agent 结果，不开放自由编辑器；完整 text/group AST 与用户规则编辑器列为后续，不得写成已支持（2026-11-08 roadmap 收窄） | DSL schema/求值/注入/恢复默认测试 | 设计 §17.2.4、契约 §14.3、`agent-runtime-roadmap-2026-11-08.md` |
| R-AGENT-27 | MUST | 模型 wire format 保持方括号标签；Markdown 只用于结果复制/导出和用户可编辑档案的受限预览，不得作为主结果渲染协议，不得引入通用 Markdown 渲染器；受限预览禁止 HTML/JS/图片/外部链接/自动 URL，未知语法按纯文本 | 导出/预览注入测试；依赖审查 | 设计 §17.2.5、契约 §14.4 |
| R-AGENT-28 | MUST | **模型输出容忍原则**：模型不可能完美遵守 prompt；解析/校验失败后必须先做本地清洗（删除无效 quote/citation/note、把无依据严格事实转为 unresolved、合并重复段）。清洗后仍有非空译文或至少一个非空逐句理解（或独立 `[NO_ANALYSIS]`）时，必须直接采用该结果，不得再调用格式修复，也不得显示“部分内容未通过校验”类格式 warning；只有清洗后无可用内容时才调用一次格式修复/失败；语言修复仍按 F1b 单独处理。`validation.valid` 保留契约语义（可为 false），`validation.usable` 表示可显示；错误仍保留用于调试/历史。语言不一致、截断/依据上限、覆盖审查/词典/无依据 warning 仍必须显示 | parser/orchestrator/result-view/history 测试；fake provider 调用次数 | 设计 §6.5、契约 §5/§10 |
| R-AGENT-LIMITS-001 | MUST | **有损上限原则**：为防止长文本导致 API 超时和 UI 渲染崩溃，系统强制执行 SEGMENT 40、每 quote 每 type 1 段、OPTION 8、每段 WORD/GRAMMAR 20 等硬上限。任何被上限截断的内容必须在 UI 和 Markdown 导出中显式警告（`AgentAnalysis.truncated` + 本地化警告），严禁静默丢弃；`[NO_ANALYSIS]` 是唯一合法的零结果路径，且不得与 TRANSLATION/SEGMENT/OPTION/UNRESOLVED/SUPPLEMENT 共存。词典档案采样达到 `maxEntries` 时必须记录未执行的探针（`DictionarySample.truncated`/`unsampledProbes`），在档案 Markdown/卡片显示，且截断元数据不得进入 provider prompt | parser cap/`truncated`/UI warning/Markdown export 测试；`NO_ANALYSIS` 共存测试；profile sample truncation/JSON prompt 测试 | `analysis_tag_parser.dart`、`agent_orchestrator.dart`、`agent_result_view.dart`、`agent_result_markdown.dart`、`mdict_worker.dart`、`dictionary_familiarization_service.dart`、契约 §5.4/§6 |

## 5. UI / UX（R-UI）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-UI-01 | MUST | 所有页面使用设计 token 与 `app_tokens.dart`；页面不得硬编码颜色/字号/间距/圆角 | grep 硬编码审查 | `app_tokens.dart` |
| R-UI-02 | MUST | 所有页面统一深蓝 `header` AppBar + 白字白图标；词条 TabBar 白字 | 页面局部改 AppBar 禁止 | `app_tokens.dart` |
| R-UI-03 | MUST | 主页按钮数量/顺序/文案以固定 UI 文案表为准（当前五个） | 不提前改名/新增 | — |
| R-UI-04 | MUST | 阅读面/结果/工具区白色；工具区仅 1px divider 收边；分词不用灰色；弹层无关闭叉；读音==词形不显示读音 | 阅读器审查 | `app_tokens.dart` |
| R-UI-05 | MUST | 设置页白底扁平、无卡片；长提示 14sp 完整换行；用户不可变信息 16sp 纯文本 | 设置页审查 | `app_tokens.dart` |
| R-UI-06 | MUST | 所有页面转场使用 `SlideOverPageTransitionsBuilder` 右滑覆盖；不淡入淡出/缩放 | 路由测试 | `app_tokens.dart` |
| R-UI-07 | MUST | 照片集/语料/多选页的删除/保存/复制位置、尺寸、二次确认按 `app_tokens.dart` | 页面/设备测试 | `app_tokens.dart` |
| R-UI-08 | MUST | Agent 使用对话式布局：消息区优先、固定 composer、证据折叠、状态可见、错误卡保留内容 | Agent UI 审查 | `app_tokens.dart` |
| R-UI-09 | MUST | citation 使用短胶囊+自动换行；词典筛选 3.5 行；颜色/触控按 tokens | 窄屏/200% 测试 | `app_tokens.dart`；F4/F9 |
| R-UI-10 | MUST NOT | 禁止全屏 loading、阻塞式弹窗、无原因错误、气泡满宽、生成中整块“正在输入” | UI 审查 | `app_tokens.dart` |
| R-UI-11 | MUST | 空态/错误态必须提供下一步操作，文案引用固定 UI 文案表 | 页面审查 | — |
| R-UI-12 | MUST | 所有图标/操作有 Semantics；触控 ≥40dp；支持 200% 字体；当前仅浅色主题 | 无障碍检查 | `app_tokens.dart` |
| R-UI-13 | MUST | 固定 UI 文案只在固定文案表维护，不在设计/契约/测试中另立当前版本文案 | 文案审查 | — |
| R-UI-14 | MUST | UI 视觉数值只以设计 token 为准；数据文件不复制 token 数值 | 文档审查 | `app_tokens.dart` |

## 6. 开发、构建与发布（R-DEV）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-DEV-01 | MUST | 固定 minSdk/compileSdk/targetSdk/NDK，禁止降级 | 检查 `build.gradle.kts` | `android/app/build.gradle.kts` |
| R-DEV-02 | MUST | 阶段结束跑 `flutter analyze`、`flutter test`、debug build；数据只写统一数据表 | CI/本地验证 | CI/本地验证 |
| R-DEV-03 | MUST NOT | 用户未明确要求时不得 commit/reset/push，不覆盖未提交改动 | `git status` 检查 | — |
| R-DEV-04 | MUST NOT | 模型/字体/词典/UniDic/API Key 不入库 | `.gitignore`/`git ls-files` | — |
| R-DEV-05 | MUST | 分发前替换 release debug keystore | 检查 `build.gradle.kts` TODO | `phase5-status` |
| R-DEV-06 | MUST | 集成测试后手动安装前重新 debug build；release 前先 `--config-only` | 构建检查 | — |
| R-DEV-07 | MUST | 所有文件访问用原生 MethodChannel，不用 `permission_handler` | Android 审查 | — |
| R-DEV-08 | MUST NOT | 不添加 `sqflite_common_ffi`（会触发 Android native-assets 下载失败） | 依赖审查 | — |
| R-DEV-09 | MUST | 主机 MeCab/MDict 脚本放隔离 Dart 包，不在根包 `dart run` | 开发流程 | — |
| R-DEV-10 | MUST | 模型下载/导入必须有许可确认、SHA-256、断点续传；清理只删临时文件 | 模型页/测试 | `models.md`、`phase4.5-status` |

## 7. 文档、数据与文案治理（R-DOC）

| ID | 级别 | 规则 | 反例 / 验证 | 权威细节 |
|---|---|---|---|---|
| R-DOC-01 | MUST | 当前测试/设备/性能/构建/环境/预算/固定文案只在数据文件维护 | 其他文档复制当前数字/文案 | 数据文件 |
| R-DOC-02 | MUST | 规范性 MUST/MUST NOT 规则只在本文件维护；其他文档只引用规则 ID/链接 | 在其他文档复制规则正文 | 本文件 §0 |
| R-DOC-03 | MUST | 视觉数值与 UI 布局/交互细节只在设计 token 规范维护；UI 实现用 `app_tokens.dart` | 在其它文档复制 token 数值或页面布局规则 | `app_tokens.dart` |
| R-DOC-04 | MUST | Agent 字段/错误码/状态机只在 contracts/schemas 维护 | 在 design/README 另立字段表 | `phase6-agent-contracts`、`docs/schemas/agent` |
| R-DOC-05 | MUST | ADR 只记录决策；历史文件只记录阶段流水；phase status 只记录当时快照，均不得写当前规则/数据 | 在历史文档更新当前值 | `docs/adr/`、`docs/phase*-status.md` |
| R-DOC-06 | MUST | 项目说明/交接文档只做摘要和引用；发现与权威文档冲突时修正摘要 | 摘要复制冲突数值/规则 | — |
| R-DOC-07 | MUST | 冲突处理：以对应权威内容为准，并修正低权威摘要 | 任意文档冲突 | 本文件 §0 |
| R-DOC-08 | MUST | 数据变更更新 `last_verified`/`last_verified_code_commit`；规则变更更新本文件版本/日期；历史值标注“历史值” | 文档审查 | 数据文件头部 |
| R-DOC-09 | MUST | 误区/踩坑与解决方案只在误区文件维护（`T-###`）；其他文档只引用 T-ID/链接 | 在其他文档新增误区正文 | 误区文件 |
| R-DOC-10 | MUST | 阶段开发历史只在历史文件汇总；交接文档只保留当前状态/下一步；详细 phase 快照留在 phase status | 在交接文档复制 Phase 0–5 流水账 | 历史文件 |
| R-DOC-11 | MUST | 修改 `docs/project-data.md` 中**原有 Agent 相关数据**（预算、token 上限、测试基线、Agent UI 固定文案等）前，必须先取得用户明确同意 | 未经同意直接改既有 Agent 数据行 | `docs/project-data.md` |

## 8. 当前未来/部分规则

以下规则是**目标或未来**，不能写成已实现：

| ID/来源 | 状态 | 说明 |
|---|---|---|
| R-AGENT-02 tool loop | future | 只有新 ADR/批准后才可恢复；当前无模型工具 |
| R-AGENT-14 F7 coverage | implemented | Wave 3：一次 `[COVERAGE]` 标签审查 + 最多一次可追溯补充检索；预算来自 `AgentLimits` |
| F6 lookup completeness | implemented | Wave 3：`AgentLimits` 单一来源；exact→prefix→suffix→incremental；某模式无新增仍继续；UniDic 失败 raw surface 兜底 |
| R-AGENT-18 F1/F17 language | implemented | Wave 2 默认 zh/文案；Wave 3（F1b）结果字段语言后校验 + 一次修复 + warning |
| R-AGENT-09 F8 session dictionary | implemented | Wave 2：独立 key/模式持久化，不读写查词偏好 |
| R-AGENT-19 prompt centralization | implemented | 所有 Agent prompt 文本/请求构造集中在 `agent_prompts.dart`；旧 prompt 文件为兼容 re-export |
| R-UI-09 F4/F9 | partial | 短胶囊/3.5 行规范已定，设备/窄屏验收待 Wave 4 |
| F11 多图 | implemented | Wave 2：相机/相册多选、追加、移除；上限 6 见统一预算常量 |
| P6.6 multi-OCR | implemented (automation) | 2026-11-02 用户指示后实现：显式多版本、质量/diff、词典候选、用户确认后重新分析；UI 标题/缩略图/每图独立状态/无假名比例已修正；真机验收待 Wave 4 |
| R-AGENT-21 provider payload | implemented | model/messages 预校验、Anthropic role 合并、非法 Unicode/控制字符清理、`max_tokens` 正整数校验；400 按真实 error body 分类，不设统一上限 |
| R-AGENT-23 rich-text post-process | implemented（P7.0 增量） | 仅对详细“原文”、逐句理解和词典事实解释插入 RUBY/BOLD/UNDERLINE；AI 气泡/理解/未解决/补充/引用行/词注 fallback 本地 RUBY 化、不加模型强调；结果构建时本地 RUBY 化，预览首帧即可见；标签正确嵌套、剥离后逐字符 diff；模型失败保留本地 RUBY；`reading【surface】` 标签感知转换，BOLD/UNDERLINE 外的读数移入并继承强调，重复读数去重；普通括号不转换；可能的理解用 `[OPTION]` 结构化 label/confidence 显示“情况X”绿色胶囊 + “可能性N%”；相同可见依据只在最后一个情况下方显示一次，不同则逐情况保留 |
| R-AGENT-22 coverage stability | implemented | 紧凑输入、单项容错、空 sufficient 规范化、独立预算公式、debug 诊断；真实请求失败仍 warning |
| R-AGENT-28 model tolerance | implemented（2026-11-08 P1） | parser 接受 partial；先本地清洗后修复；`validation.usable` 隐藏格式 warning；语言/截断/覆盖/词典 warning 保留；可清洗结果不额外调用模型 |
| P1 technical（P2 执行） | implemented（2026-11-08） | rich-text 12k chars/16k tokens、style-tag 本地修复、accepted/rejected/repaired telemetry；token 600/profile 2k+6k prompt 预算；富文本解释语言参数化；Han-only SCRIPT AMBIGUOUS |
| R-AGENT-LIMITS-001 lossy caps | implemented（2026-11-04；profile 采样截断 2026-11-06） | SEGMENT 40/每 quote 每 type 1/OPTION 8/每段注 20；解析器设置 `AgentAnalysis.truncated`，UI `result.warnings` 与 Markdown 导出均显示截断警告；`[NO_ANALYSIS]` 仅允许独立结果。词典档案采样记录 `DictionarySample.truncated`/`unsampledProbes`，`DictionaryCoverage.sampleTruncated` 在 Markdown/档案卡片/warnings 显示；截断元数据不进入 provider prompt |
| P6.7 | partial（2026-11-03） | 历史/持久化、UniDic 声调已实现并有自动化测试；annotation DSL、provider 测试连接、无障碍/发布验收仍待做；真机/视觉验收未完成 |

## 9. 变更流程

1. 规则变化：只改本文件；更新规则 ID/状态，不复制到其他文档。
2. 数据/文案变化：只改数据文件；更新 `last_verified`/commit 锚点。
3. 视觉数值变化：只改设计 token 与 `app_tokens.dart`。
4. Agent 字段/错误码变化：只改 contracts/schemas + 代码/测试。
5. 其他文档：只加/改引用；发现重复时删除旧正文。
6. 误区/经验变化：只改误区文件，追加 `T-###` 并同步附录 A。
7. 阶段开发历史：只改历史文件，不复制详细流水账。
8. 历史 phase 文档：保留当时值，标注“历史值/历史快照”，不要用当前值回填。
