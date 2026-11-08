# Phase 6 status — dictionary assistant core

Date: 2026-11-08
Base: Phase 5 complete (`docs/phase5-status.md`)
Design: `docs/phase6-agent-design.md` v2
Contracts: `docs/phase6-agent-contracts.md` / `docs/schemas/agent/`

> **Status: P6.1–P6.5 core and 2026-10-31 feedback Waves 1–3 are implemented;
> Wave 4 device acceptance is still pending (handled by a separate workstream).
> P6.6 multi-OCR core is implemented (2026-11-02) and its automated closeout
> completed on 2026-11-03; P6.6 device acceptance remains pending. P6.7
> history/persistence and UniDic pitch are implemented (2026-11-03); annotation
> DSL, provider test connection and release polish are still pending. P6.7
> device/visual acceptance remains pending. Phase 1a–3 of the Agent refactor
> and the Phase 4 safe subset (static coverage packs + non-Japanese script
> degradation) are implemented (2026-11-06); word-list UI/import/generation
> and non-Japanese tokenizers are not. Word-list coverage is semantic-only, not
> POS coverage; sample-cap truncation is explicitly reported.**

> Follow `docs/agent_docs/device-feedback-2026-10-31.md` for the remaining
> Wave 4 device checks. **Current test/device/build/environment numbers are
> centralized in `docs/project-data.md`; do not copy them here.** Normative
> MUST/MUST NOT rules live in `docs/project-rules.md`. Automated tests use fake
> providers and never a real API key. On
> 2026-10-30 a user-configured DeepSeek provider was smoke-tested on the x86_64
> emulator (key never logged); arm64/real manga-page and real-dictionary
> `sample`/`suggest` acceptance still remain. The review backlog in
> `docs/agent_docs/phase6-pipeline-review.md` is authoritative for open gaps.
>
> **2026-11-01 language decision (implemented in Wave 2–3)**: the default
> output/UI language is Chinese (`zh`); legacy `follow` maps to `zh`;
> `resolveAgentUiLanguage` takes only the explicit setting and never inspects
> source text. `AgentUiStrings` supplies Chinese/English/Japanese Agent-area
> copy. Wave 3 adds `AgentLanguageValidator` post-validation of human-readable
> fields plus one language repair with a visible warning when it still differs.

## 2026-11-06 P0 过度抓取 / 高延迟收敛

- `AgentLimits` 新增 `shortTextTargetThreshold=15`、
  `coverageContentHitRateThreshold=0.8`、`enableDepthPass=false`。
- `EvidenceBuilder` 广度轮改为每个 target 每本词典只取 1 条；短文本（selected
  target < 15）citation 上限为 `contentTargetCount × dictionaryCount`，
  不再允许 1 句文本预取 60 条。内容词排在 pattern/功能词之前；标点/符号只保留
  为上下文 token，不进入 lookup target。
- depth 默认关闭，仅在 `enableDepthPass=true` 的显式多义/补查场景补齐第 2/3 条；
  初始管线不再自动跑 depth。
- 查词递进改为缺口驱动：所有 target 先 exact；只有 exact 仍无 citation 的 target
  才进入 prefix，之后才是 suffix/incremental；已命中 target 不再跑后续模式。
- Coverage 触发改为内容词 citation 命中率 `<80%`；删除“citations>=60 强制审查”
  和固定 `quote≤2 && 文本<50` 短路。助词、标点、功能词不计入命中率；coverage
  补查仍可在初始短文本上限之外使用全局 60 条预算。MISSING 为
  `sense`/`usage`/`example` 时，补充查词允许每本词典取 2 条，作为显式多义的
  按需 depth 路径；`word`/`grammar`/`reading` 仍只取 1 条。
- `AgentRunTelemetry` 新增 `httpAttempts`（核心管线实际 HTTP 尝试，含 provider
  重试与续传）、`analysisTtftMs`（主分析首字延迟）、`analysisPrefillChars`
  （主分析实际 prefill 字符）；`targetsWithCitations/targetCount` 改为内容词
  统计；debug 输出 `[AgentTelemetry]`。
- `resultTruncated` 文案改为“词典依据已达上限，部分义项未送入模型（原文已分析）”，
  UI/Markdown 同时显示“预取 N 条 / 采用 X 条（上限 M）”。
- 测试：新增样本形态短文本（内容词 3、2 词典）断言 **6 条 citation（≤15）**、
  仅 exact 模式、prefill < 12,000 字符；新增 80% coverage 阈值、depth 关闭、
  breadth 每词典 1 条、provider HTTP attempt 回调测试。`flutter analyze` 无问题，
  完整 `flutter test` **547 项通过**。全部为 fake/local provider，未使用付费 Key；
  真实 provider/arm64/真实大词典仍未验收。

## 2026-11-06 首跑档案非阻塞 / 2026-11-07 慢请求提示

- 首跑不再等待词典档案生成或用户确认：
  `DictionaryFamiliarizationService.loadCached()` 只读取指纹有效的本地
  已确认/已拒绝档案；缺失档案当前 run 使用 `noProfileInstruction` 兜底分析。
- 分析结束后由 orchestrator `finally` 启动后台 `generateMany()`；生成结果进入
  应用级待确认队列。Agent 页 `AgentProfileInboxHost(autoPresent:false)` 不自动
  弹 sheet，只显示待处理数量；档案管理页仍可显式确认。确认/“不再询问”后才写档案，
  **下次 run 生效**；`AgentRunRequest.pendingProfileDictionaryIds` 防止对待确认
  档案重复生成。自动保存（`agent_profiles_auto_accept`）仍可用，当次 run 和之后
  的 run 都不阻塞。
- 2026-11-07 真机反馈 30 秒硬超时会终止大量正常的长思考请求，因此改为
  `AgentLimits.slowRequestWarningSeconds` 默认 **30 秒**（0/负数禁用）的慢请求
  提示：计时从主分析进入 `reasoning` 才开始，达到阈值**不取消** provider/OCR，
  只在 UI 显示橙色“本次处理时间较长，请耐心等待”；用户仍可主动停止。
- 时间显示按真实阶段区分：`AgentRunSnapshot.thinkingStartedAt` 为空时显示
  “任务已进行 X 秒”（准备/OCR/分词/查词/coverage），进入 `reasoning` 后显示
  “已思考 X 秒”，完成态显示“任务用时 X 秒”。done/error/cancel/newSession
  会清理提示计时器。直接调用 orchestrator 的测试/集成不经过 controller 计时器。
- 效率：分析/coverage prompt 去掉内部 token 偏移、标点 token 对象、quote
  `schema/offset/origin`、citation `dictionary_id/order/entry_key` 等模型不
  使用的字段；coverage snippet 上限 240 字符；后续 prefix/suffix/incremental
  查词只针对内容词和语法模式，助词等功能词只做 exact。新增
  `[AgentPromptBudget]` debug 打点。
- 测试：生命周期新增“慢分析显示橙色提示但继续完成”；UI 新增“任务已进行/
  已思考/任务用时”和橙色提示测试；prompt 精简与 function-word 查词测试已补。
  `flutter analyze` 无问题，完整 `flutter test` **567 项通过**。全部
  fake/local provider，未使用付费 Key；真实 provider 等待时长与 arm64/设备
  仍未验收。

## 2026-11-08 修正版执行路线

- 新增 `docs/agent_docs/agent-runtime-roadmap-2026-11-08.md`，作为 P6.7 收尾、
  P6.8-lite 与 P7-lite 的唯一实施顺序。范围：P6.7-3 只做装饰规则 v1；
  P6.8 先做译文预览/可选证据缓存；P7 只做路由表/任务遥测/预算，P7.1/P7.3/
  P7.4 暂缓。旧 P6.8/P7 规划已加修正头注；R-AGENT-26/契约 §14.3/设计 §17.2.4
  已按 v1 收窄。真实 provider/arm64/真机验收仍按 Wave 4 单独执行。
- **已实现**：
  - provider 设置“测试连接”（单次非流式请求、不写历史、不自动重试）；
  - 词典档案受限 Markdown 预览（白名单，不执行 HTML/JS/外链）；
  - annotation v1 装饰规则（ruby/pitch/bold/underline + when，内置规则，
    阅读器/照片集/语料，恢复默认式选择）；
  - P6.8-lite 译文预览（完整 `[TRANSLATION]` 块、续传去重、assistant summary
    稳定槽位；不写历史、不增加 provider 请求）；
  - P7-lite 路由表 + `formattingCalls` 遥测（`llmCalls` 现包含富文本调用）；
  - 文本 run 的内存 LRU 证据缓存（图片 run 暂不缓存）。
- **仍待**：P6.7-4b 无障碍/200%/许可/签名与真机视觉验收、Wave 4
  真实 provider/arm64/大词典/secure storage 验收；完整 segment streaming 与
  P7 任务拆分保持暂缓。当前测试/设备数据以 `docs/project-data.md` 为准。
- **1.1 UI/音调规则（2026-11-08）**：应用副标题改为“可扩充词典库的日语阅读
  工具”，pubspec 1.1.0+2、Android versionName 1.1、著作权页 1.1；provider
  测试按钮改为“测试快速模型连接”；新增 DeepSeek 快捷配置（自动填地址和
  `deepseek-chat`，重名加 `(1)`/`(2)`，非 API key 失败时开放模型编辑）；
  annotation 菜单移除“关闭标注”；“注音 + 音调”选择时提示音调来自 UniDic；
  动词/い形容词活用形后接非标点 token 时隐藏音调（音便动词和原形除外）；
  档案 Markdown 预览竖屏使用更高 sheet；provider 表单补充 API key 复用提示
  和 max_tokens 文案。完整真机视觉/200% 验收仍未完成。

## 2026-11-08 P0 证据预算/缓存修复

- **证据分配**：默认 breadth 改为每个内容词/语法模式 target 全局只取 1 条
  citation；不再按选中词典数复制。助詞/助動詞等功能词默认不进入 citation
  target（token 证据与语法模式 citation 保留）；只有 `enableDictionaryFanOut`
  的 per-dictionary 分析仍按每本词典 1 条取证据。
- **句子公平**：target 在内容层内按 quote round-robin 排序；`maxTargets` 与
  citation 上限不再由第一句按 token 顺序独占。
- **coverage 上限**：短文本有效上限为 `content/pattern targets +
  coverageCitationReserve`（新增 `AgentLimits.coverageCitationReserve=6`，最高
  60）；coverage 的 `remainingSlots` 改用 `evidence.budget.maxCitations`，
  prune/merge 保留该值，不再从短文本上限直接跳到全局 60。
- **缓存**：`CitationRegistry.restore` 在缓存命中时恢复 citation map 和
  `nextId`，coverage 补查不会从 `source-1` 重新发号覆盖缓存 citation。
- **salvage**：与 validator 共用 quote-token 映射、WORD surface/lemma 回退和
  读音归一化；free grammar note（空/未知 `patternId`）不再在 salvage 中被
  无条件丢弃。
- 回归测试覆盖：缓存命中 + coverage 补查、跨 quote target 交错、短文本有效
  citation 上限、free grammar/WORD 回退/片假名读音 salvage。`flutter analyze`
  无问题，完整 `flutter test` **622 passed**（声明 613）；全部 fake/local
  provider，未使用付费 Key。真实 provider/arm64/设备验收仍未进行。

## 2026-11-08 P1 技术项（按 P2 执行）

- **富文本预算**：`maxRichTextChars` 20,000 → 12,000，新增
  `richTextMaxTokens=16,000`；批量与单 section 共用，避免长 batch 输出截断。
- **标签级接受**：未闭合/错序/重复的 BOLD/UNDERLINE 先本地删除，保留其余合法
  标签与原文；RUBY/YOMI 畸形仍回退本地 RUBY 基线。新增
  `formattingAcceptedSections`/`Rejected`/`Repaired` telemetry。
- **prompt 预算**：未引用功能词不进入 token 证据；`maxPromptTokenEntries=600`，
  优先 cited > content > pattern；profile 每词典 ≤2000、总计 ≤6000。source /
  citation / snippet 上限共同构成输入预算。
- **富文本语言**：`RichTextPostProcessor` / 两个 rich-text prompt builder 接收
  `AgentResponseLanguage`；不再固定假设中文解释。
- **Han-only**：`isHanOnlyAmbiguous` + `SCRIPT AMBIGUOUS` prompt；保留日语
  tokenizer，但禁止把读音/结构当作确定事实。
- 测试：budget/profile/token 截断、style-tag 修复、语言 prompt、telemetry
  往返、Han-only 指令。`flutter analyze` 无问题，完整 `flutter test`
  **631 passed**（声明 622）；fake/local provider，无付费 Key；真机/真实
  provider 未验收。

## 2026-11-08 P1 模型输出容忍

- **原则**：模型输出不完美是常态。解析/校验失败后先本地 cleaning/salvage；
  清洗后仍有非空译文或至少一个非空逐句理解（或独立 `NO_ANALYSIS`）时直接采用，
  不再调用格式修复，也不显示“部分内容未通过校验”类格式 warning。只有清洗后
  无可用内容才 repair/失败。
- **parser**：允许只有 TRANSLATION 或只有 SEGMENT 的部分结果；不再因缺另一类
  直接返回 null。契约级 `validation.valid` 仍可为 false，新增
  `validation.usable` 表示可展示；历史/调试仍保留原始 errors。
- **顺序**：先本地清洗，可清洗结果跳过 repair（少一次模型调用）；语言不一致仍
  触发语言修复，语言/截断/覆盖/词典/无依据 warning 继续显示。
- **UI**：`AgentResultView` 只对 `!validation.displayable` 显示格式 warning；
  cleaned 结果静默展示。旧历史缺少 `usable` 时按 `valid` 兼容。
- 测试：partial translation/segment adoption、tag 错误本地清洗不 repair、
  可清洗结果不等待 repair、validation.usable JSON/历史、UI warning 抑制。
  `flutter analyze` 无问题，完整 `flutter test` **624 passed**（声明 615）；
  fake/local provider，无付费 Key；真机/真实 provider 未验收。

## 2026-11-07 短文本误报截断/校验与档案后台生成修复

- **短文本“已按上限缩减输出”根因**：样本 `2026-11-07-21-24.txt` 只有 3 个可见
  SEGMENT，未达到 SEGMENT 40/OPTION 8/每段 note 20。触发的是
  `maxSegmentsPerQuotePerType=1`：DeepSeek 常把同一 quote 拆成多个同 type 的
  `[SEGMENT]`（例如每个词一个 fact 段）；旧 parser 直接 `continue` 丢弃后续段并
  设置 `truncated=true`。现在重复 quote+type 段**合并**到首段：WORD/GRAMMAR note
  去重并合并 citation，MEANING 用“；”合并；只有真正超过 SEGMENT/OPTION/note
  上限才显示截断警告。
- **“部分内容未通过校验”根因（按样本结构复现确认）**：
  1. UniDic 读音是片假名，DeepSeek 常写平假名（如 ジブン → じぶん）；旧 validator
     逐字符比较，导致每个 WORD note 都报“读音与 UniDic 不一致”。
  2. DeepSeek 会给出白名单未收录的 GRAMMAR 说明且省略/自造 `pattern_id`；旧
     validator 对空/未知 id 直接报“语法注引用了不存在的模式”，使整次结果无效。
  3. 模型可能省略 WORD `id` 或写错 id；旧 validator 直接报“不存在的 token”。
  修复：读音比较先 NFKC + 片假名→平假名；GRAMMAR 空/未知 id 按 free grammar note
  处理，citation 必须属于当前 quote 范围内 token；WORD 在当前 quote 内按唯一
  surface/lemma 回退解析 token。样本结构 probe 修复后 `valid=true`，无
  validationPartial。
- **档案后台生成被切后台跳过**：分析 `done` 后 controller 立即停前台服务，而
  `generateMany` 仍在后台跑；Android 挂起进程后部分批次未完成，表现为只生成了
  一部分词典档案。现在 orchestrator 通过 `onBackgroundProfiles` 暴露生成 future，
  controller 用引用计数 `AgentBackgroundLease` 持有前台服务直到生成完成且
  proposals 入队/持久化；**不等待用户确认**（确认仍由应用级 inbox 处理）。手动
  档案重新生成也持有同一 lease；分析失败/取消不启动后台档案生成。`enqueue`
  返回持久化 future，`waitForAll` 先注册 completer 再入队，修复 cancel 竞态。
- **依据卡片标题**：明镜、大辞林等词典的 MDX key 可能是内部索引
  （`01570 03798`、`@daijirin2-...`），不能直接展示。新增
  `dictionary_entry_title.dart`：先取清洗后词条 HTML 第一行的最简单词形式，
  `【...】`/headword 元素仅作兼容回退；内部 key 只保留给查词/跳转；旧历史没有
  新标题时从保存的 snippet 回退。依据卡片、
  语义标签、Markdown 导出、历史 fallback、点击后的词条页、查词结果列表和 P6.6
  依据预览都不再显示内部 key。
- 测试：新增重复段合并、读音假名归一化、free grammar note、前台服务 lease 引用
  计数、生成中保持服务/完成后释放；依据标题提取/卡片/查词列表回归。`flutter
  analyze` 无问题，完整 `flutter test` **585 项通过**。全部 fake/local provider，
  未使用付费 Key；真实 DeepSeek 复测、arm64 后台与设备验收仍未进行。

## 2026-11-08 档案保存后“已失效”即时刷新

- **根因**：保存编辑后的档案已经写入当前 fingerprint，但档案页的 stale 检查
  future 只按 `dictionaryId` 缓存。`ref.invalidate(agentProfilesProvider)` 后，
  `AsyncValue.when` 默认 `skipLoadingOnRefresh=true`，会先用**旧 profile 列表**
  重建一次；这次重建把旧 revision 的 `Future(true)` 重新写入缓存，等新列表到达时
  `putIfAbsent` 继续复用旧结果，导致“已失效”一直存在，直到离开页面/切换语言等
  再次清空缓存。
- **修复**：`_staleFutures` key 改为
  `dictionaryId + fingerprint + profileLanguage`；provider data 变化时清空 stale
  future；编辑保存成功后记录旧 fingerprint，在刷新中间帧抑制该旧 revision 的
  stale badge，并用 `setState` 先让标签立即消失；新 revision 到达后清理抑制。
  `_clearStaleCache` 统一在删除、重新生成、语言切换、resolve proposal 时清理
  stale 与抑制状态。
- **测试**：新增“刷新被阻塞时，保存后 stale 标签立即从 2 个降为 1 个（仅未编辑
  词典保留）”回归；原“editing a stale profile clears its stale label
  immediately”继续通过。`flutter analyze` 无问题；完整 `flutter test`
  **613 项通过**。真实 SQLite 设备上的视觉确认仍未做。

## 2026-11-06 词典/阅读器/历史 UI 修正

- **entry:// 检索失败**：词典页内跳转仍限定当前词典 exact 查询；无命中时显示
  “当前词典中没有「word」”气泡，不打开空白词条页。2026-11-07 日志定位到
  toast 使用 `navigator.context`，`Overlay.maybeOf` 找不到 Navigator 下方的
  Overlay 而静默返回；改为页面 context，并给 `RikaiToast.show` 增加
  `NavigatorState.overlay` 兜底。日志同时发现该词典链接目标是内部 ID
  `daijirin2-011462-0000`；内部 ID/空目标改为通用提示“当前词典中没有对应的词条”，
  普通词仍显示原词。临时 `[EntryLink]` 日志已移除。
- **导入词典名统一为 MDX**：批量导入列表中，已存在词典复用注册表里由 MDX 头
  解析出的标题；新词典探测后使用 `displayDictionaryTitle(metadata.title, path)`；
  探测前显示“正在读取词典信息…”，副标题改为 MDX 文件名，不再以文件夹名充当词典名。
- **历史错误本地化**：历史只保存稳定错误码；详情页改用
  `AgentUiStrings.historyErrorMessageFor`，不再显示 `INVALID_ARGUMENTS` 等内部
  字串；`invalid_arguments` 显示本地化的“请求参数无效，请检查模型设置后重试”。
- **历史滚动位置**：历史列表用 `_cachedEntries` + `FutureBuilder.initialData`
  保持返回详情前的列表挂载；从详情页返回刷新时不再用 spinner 替换列表，保留用户
  滚动位置（仍保留 `PageStorageKey` 兜底）。
- **音调尾降对齐**：尾高下降线改为落在最后一个 mora 水平段的右端点
  `size.width`，不再左移 `strokeWidth/2`。
- **最小 Ruby/振假名**：新增 `minimalRubySegments`（最长公共 kana 前后缀 + 内部
  kana LCS 锚点），只标注未知部分：`悩んでも/なやんでも` → `悩（なや）んでも`，
  `申し込み/もうしこみ` → `申（もう）し込（こ）み`。Agent 富文本渲染与阅读器
  `TokenChip` 都使用该规则；无可靠对齐时保留整词 Ruby。
- **样本上限文案**：用户可见的“N 个探针未采样”改为短文案
  “词典样本达上限，N 项检查未覆盖”；档案 Markdown 同步为同一形式。内部
  `probe`/`unsampledProbeCount` 术语保留。
- **语言对可修正**：档案确认/编辑 sheet 增加语言对 chips 与源/目标语言选择器；
  保存时更新 `DictionaryProfile.languagePairs`、档案 Markdown 的“语言”行以及
  `profile_json`。pending proposal 通过 `ProfileConfirmation.profile` 传到 inbox，
  档案管理页编辑走 `DictionaryProfileRepository.save`；后续分析 prompt 使用修正后
  的 Markdown。
- **保存档案立即清除“已失效”**：编辑/保存档案时不再保留旧 `fingerprint`，而是用
  当前词典 stat、当前 prompt/schema 版本和当前档案语言重新计算并写入
  `dictionary_profiles.fingerprint`；随后清空 `_staleFutures` 并 invalidate
  `agentProfilesProvider`，卡片上的“已失效”立即消失。指纹计算通过
  `dictionaryProfileFingerprintProvider` 注入，widget 测试可避免真实文件 I/O。
  新增“编辑失效档案后只剩另一本未编辑档案仍失效”的回归用例。
- 验证：新增 minimal ruby（纯函数 + Agent/阅读器 widget）、语言对编辑/持久化、
  历史错误本地化、历史滚动保持、失效档案保存用例；`flutter analyze` 通过，完整
  `flutter test` 通过。真实设备视觉、MDX 标题与语言对修正的 provider 行为仍需
  真机验收。

## 2026-11-06 Agent 结果稳定性 / 后台持续 / 断流续传

- **结果复核闪烁**：AI 气泡摘要改为 provisional/final/error 共用同一个稳定
  summary 槽位，不再在“结果已出，正在复核…”结束后替换整棵子树；被最终结果替换
  的 provisional 通过 `AgentRunSnapshot.resultReplaced` 禁止结果块重播
  `AgentFadeIn`。复核阶段仍可展开详细解析，最终结果只更新内容。
- **Ruby/音调排版**：`_RenderRubySpan` 宽度改为 base/读音的较大值，读音更宽时
  base 居中，后续文字从保留宽度之后开始，修复相邻词读音重叠；音调词使用自定义
  RenderObject 上报词形 alphabetic baseline（不再用无 baseline 的 Stack），修复
  词注行 baseline 不对齐；尾高（accent type = mora count）在词尾补画垂直下降点。
- **下划线换行**：长 `[UNDERLINE]` 文本按汉字单字/拉丁词切分为相邻 WidgetSpan，
  RichText 可在行中换行；短词保持单个自绘下划线 span，`；` 与汉字仍使用固定
  baseline 偏移。
- **历史详情复制**：历史详情 AppBar 在存在结果时显示“复制结果为 Markdown”，
  与 AI 气泡复制内容一致；只读/无结果状态不显示。
- **档案删除锁定**：run 进行中删除按钮改为 `textSecondary` 灰色锁图标并禁用，
  tooltip 明确“分析进行中，暂不能删除档案”；run 结束后恢复删除图标。
- **会话设置**：选中的 provider 持久化到 SharedPreferences（重启/重进页面保持，
  删除后回退第一项）；严格/宽松按会话保存快照，新会话重置严格，返回页面沿用
  当前 run/会话模式。
- **启动加速**：`BootstrapApp` 只等待 SharedPreferences，随后立即进入主页；
  MDict warm-up 与 UniDic 预热并发在后台执行，不再阻塞启动页。MDict worker 的
  `warmup` 命令改为并发打开启用的词典。
- **后台持续**：新增 Android `AgentRunService`（`dataSync` 前台服务 + partial
  wake lock），run 开始即启动，done/error/cancel/newSession/dispose 停止；
  通知渠道 LOW、常驻无声音。仅进程存活时有保证，进程被杀仍需 interrupted/重试。
- **断流续传**：`_collect` 对 `PROVIDER_UNAVAILABLE`/`PROVIDER_RATE_LIMITED`/
  `TOOL_TIMEOUT` 自动续传最多 2 次；有 partial 时从最后完整换行前缀续写，空
  partial 重发原请求；取消/鉴权/参数错误/空输出不重试。续传耗尽仍有可用 partial
  时交给校验/抢救，不直接丢掉已生成文本。
- 自动化验证：`flutter analyze` 通过；完整 `flutter test` 通过（新增 ruby 宽度、
  下划线换行、音调 baseline/尾高、历史复制、档案锁定、provider 持久化、会话模式、
  后台服务 start/stop、断流续传用例）；Android `:app:compileDebugKotlin --offline`
  通过（AgentRunService/MainActivity）。未做 APK 构建（字体未放入工作区）。真实
  provider 弱网/断网、arm64 后台服务、通知权限与真机视觉验收仍未进行，不能写成
  已验证。

## 2026-11-04 输出上限 / NO_ANALYSIS / 批量降级

- **有损上限原则**：解析器强制执行 SEGMENT 40、每 quote 每 type 1 段、OPTION 8、
  每段 WORD/GRAMMAR 20；超限设置 `AgentAnalysis.truncated=true`。UI 通过
  `AgentRunResult.warnings`、Markdown 导出通过 `analysisTruncated` 显示截断警告，
  不静默丢弃（`R-AGENT-LIMITS-001`）。
- **NO_ANALYSIS**：`[NO_ANALYSIS reason="..."]` 只允许独立出现，parser/validator
  接受零翻译零段落；UI 显示“无法可靠分析”+原因+证据；语言后校验包含 reason。
- **批量富文本**：原文+逐句理解合并为一次 `processSections` 请求；词注/词典事实
  解释继续本地 RUBY。按 section 独立解析/校验/降级，单个 marker 或 diff 失败只
  影响该 section（`T-137`）；只有 provider/空响应/`maxRichTextChars` 超限才整批
  回退。
- **coverage 触发**：改用 `AgentEvidenceBudget.targetsWithCitations` 的 per-target
  判断，符合 design §6.3.1。
- **repair 路由**：格式修复改为 small model + 紧凑 prompt（只发 available ids/
  previous output/errors）；语言修复保持 complex model + 紧凑 prompt，不再重发
  完整 evidence/input。
- **自动化验证**：`flutter analyze` 通过；完整 `flutter test` 通过（含
  parser/validator/orchestrator/rich-text/result-view/coverage/evidence/models
  新增用例）。真实 provider、设备与 arm64 验收仍未进行，不能写成已验证。

## 2026-11-06 F7 复合词补查（Phase 1a）

- `coverageSystemPrompt` 增加复合词/固定搭配整体 `MISSING` 规则（例如
  `ところが` 而不是 `ところ` + `が`）。
- `validateCoverageReview` 对未知 `kind=word` query 增加 token 跨度校验：
  源文本连续子串、不含换行、至少一处匹配覆盖 ≤
  `AgentLimits.maxCoverageCompoundTokens`（默认 6）个 source token；无
  tokenizer 或该 source 无 tokens 时只接受已知 token/pattern/citation key。
  校验基于 token 跨度，不设字符数上限；`AgentLimits.maxCoverageQueryChars`
  保留为超长字符串的全局安全上限。
- 覆盖审查仍只做一次审查 + 一次补充检索，不构成工具循环；被丢弃的 query 计入
  `droppedMissing`。
- 自动化验证：`flutter analyze` 通过，完整 `flutter test` 通过（含 coverage
  unit/orchestrator 新增用例）；测试基线已按用户同意更新到
  `docs/project-data.md` §2。真实 provider/设备仍未验证。

## 2026-11-06 档案编译器 v2（Phase 1b）

- `DictionaryProfile` 增加可选 `intro`、方向性 `language_pairs`、`coverage`；
  profile v1 JSON schema 增加对应可选字段；profile prompt 版本升到 2，旧档案
  通过指纹失效并重新生成（schema 标识仍为 v1，旧 JSON 向后兼容）。
- 新增 `dictionary_sample_analysis.dart`：从标题脚本提示 + headword/definition
  文字脚本确定性检测方向性语言对，并计算样本条数、词条数、文字覆盖和结构特征数。
  低置信度使用同一档案请求的 `[LANGUAGES]` 回退，不额外发请求。
- 探针扩展到 16 条精确 + 11 条前缀；每词典样本上限 20；档案请求按 1–3 本/批
  合并（`maxBatchTokens=20000`），保留一次格式修复。
- Markdown 显示简介、`ja→zh` 方向对和覆盖段；档案卡片 subtitle 显示方向对；
  用户确认流程不变（R-AGENT-10）。
- 未新增“选中词典即自动联网”的后台预热（R-PROD-03）；档案仍在 run 开始或
  档案管理页显式生成，失败/待确认时保留 `noProfileInstruction` 降级。
- 自动化验证：新增/更新 profile parser、sample analysis、service、model、
  profile page 用例；真实 provider/设备仍未验证。

## 2026-11-06 请求管线收敛（Phase 2）

- 新增 `agent_intent.dart`：本地检测翻译/语法/解释/读音/校对和多问题，主 prompt
  增加 `Local request hint`；不单独发 intent 调用，用户请求仍是权威。
- 新增 `AgentRunTelemetry`：`llmCalls`/`analysisCalls`/`coverageCalls`/
  `repairCalls`/`languageRepairCalls`、输入/输出/推理字符、LLM/总耗时、
  citation/target 覆盖；随 run result JSON/history 回放，不含正文/路径/Key。
- 覆盖合并/删重后重新计算 `targetsWithCitations`，避免 telemetry 和后续
  coverage 判断使用旧值。
- fake provider 新增“5 词典 + 10 句、无覆盖审查 → 1 次主分析调用”断言；
  flow C 同时校验 telemetry 的调用数和 citation 覆盖。
- 真实 provider/设备仍未验证。

## 2026-11-06 条件词典 fan-out（Phase 3，默认关闭）

- `AgentLimits.enableDictionaryFanOut=false` 默认关闭；启用后按词典数
  (`dictionaryFanOutThreshold=8`) 或 source+citation 字符估算
  (`dictionaryFanOutEvidenceChars=16000`) 触发。
- `evidence_partition.dart` 按词典过滤 citation 与 token/pattern citationIds，
  保留 source/UniDic 结构；`Future.wait` + 有界 worker 并发（默认 2），每次
  调用只带一个词典的 input/evidence。
- `analysis_merge.dart` 按用户词典顺序合并：译文取第一个非空，quote+type 段
  合并 word/grammar notes，OPTION 去重并重新编号；合并后在完整 evidence 上
  重新 validator；segments/options 受 `AgentLimits` 上限约束。
- 单个词典失败只丢弃该词典并显示 `fanOutPartial` warning；全部失败回退单次
  主分析。fan-out 路径不做 per-dictionary 修复/语言修复/provisional 流式。
- 测试：证据分区、analysis 合并、2 词典成功合并、单词典失败保留其余结果；
  默认关闭。真实 provider/arm64 未验收。

## 2026-11-06 Phase 4 安全子集（静态词表 + 非日语降级）

- 新增静态词表包 `assets/agent/word_lists/{ja,zh,en}.json`，每包 21 项，内部
  tag 为 greeting/family/food/person_name/place_name（5/5/5/3/3）；
  `WordListPack` 本地校验数量/标签/重复/语言代码；不调用模型生成。
- 新增 `evaluateWordListCoverage`：只做本地 exact→prefix→suffix 查词，计算
  总命中率与分标签命中；词表不参与 profile 格式推断，也不进入档案指纹。
- 新增 `script_language.dart`：假名→日语 tokenizer；拉丁/韩文/西里尔/泰文/
  阿拉伯文/希腊文等明确非日语脚本跳过 UniDic，设置 `structureUnavailable`，
  只保留有界 raw-surface 查词；Han-only 暂按日语处理（歧义）。
- **未实现**：词表管理 UI、用户导入、模型生成词表、非日语 `TokenizerPort`、
  POS 覆盖率；不能写成已支持。真实 provider/设备未验收。

## 2026-11-06 Phase 4 补充：词表语义边界与采样截断显式化

- 词表方案定为 C：21 项词表只表示语义场景覆盖（寒暄/家庭/饮食/人名/地名），
  不是词性覆盖；不新增 POS 指标，也不给词表加 POS tag。`evaluateWordListCoverage`
  仍只做本地命中统计，且当前没有生产调用点。
- `DictionarySample` 新增本地 `truncated`/`unsampledProbes`：`maxEntries` 上限
  导致未执行的 exact/prefix 探针必须记录；`toPromptJson()` 明确排除这些内部
  字段，profile prompt 形状不变。
- `DictionaryCoverage` 新增可选 `sampleTruncated`/`unsampledProbeCount`；
  档案 Markdown、档案卡片和 familiarization warnings 显示本地化提示。
- 自动化验证：`flutter analyze` 通过；完整 `flutter test` 通过，新增 sample
  截断 round-trip、sample analysis coverage、familiarization warnings/Markdown、
  profile card warning 用例。真实 MDict 截断行为仍需设备/真实词典冒烟，不能
  写成已验证。

## 2026-11-06 P0 citation allocation / attribution

- `EvidenceBuilder` breadth/depth 的 group 顺序按 target 序号轮转用户词典起点；
  coverage `lookupExtraQueries` 按 query 序号轮转。5 词典 × 20 target 的合成
  全命中用例从“第一本词典 20 条”变为每本 12 条（全局上限 60），每个 target
  仍有至少一条依据。轮转按 `DictionaryInfo.order` 排名，不依赖调用方列表顺序。
- `AgentValidator` 增加 citation 归属：WORD note 的每个 citation 必须属于该
  token 的 `citation_ids`；GRAMMAR note 的每个 citation 必须属于该 pattern 或
  其组成 token 的 `citation_ids`。该规则在严格/宽松模式都生效。repair 仍失败时，
  `salvageAnalysis` 也会移除无效或未归属的 citation，避免降级结果继续展示错误依据。
- repair prompt 的 `Available ids` 改为 `token/pattern ... citations ...`，使一次
  格式修复可以重新归属 citation，同时仍不发送完整 evidence/input。
- 选中但最终 0 条 citation 且没有查询错误的词典写入
  `AgentRunResult.warnings`（中/英/日文案由 `AgentUiStrings` 提供），不再静默
  隐藏；查询错误仍由现有 `dictionaryIssues` 警告覆盖。
- 自动化验证：`flutter analyze` 无问题；完整 `flutter test` 通过。新增
  evidence builder 轮转、coverage 轮转、validator 归属、salvage 归属过滤、
  orchestrator 零引用警告和 repair id 映射测试。真实 provider/arm64/真实大词典
  仍未验收。

## Implemented

### P6.1 Capability layer

- `lib/core/models/agent/` DTOs: input envelope, evidence/citation, analysis,
  dictionary/UniDic profile, quote/source version, and `AgentToolErrorCode`
  (tool spec/result DTOs were removed with the 2026-10-31 tool-layer removal).
- `lib/core/models/lookup_request.dart`, `lib/core/models/dictionary_sample.dart`.
- `lib/services/agent/ports/`: OCR, tokenize, lookup, dictionary sample, LLM,
  secret, capability exception. Text-only LLM port has no image/file part.
- `lib/services/lookup/lookup_gateway.dart`: pure lookup validation/order used by
  UI lookup and the Agent. `performLookup` and `LookupSearchNotifier` now use it.
- `OcrWorkflow` was removed on 2026-10-31 (no production caller); the OCR port
  performs readiness/recognize/compose itself.
- `lib/services/mdict/mdict_worker.dart`: `sample` and `suggest` worker commands;
  `MdictService` implements `LookupBackend`; bounded samples produce plain-text
  snippets/features.
- **Tool registry/adapters were removed on 2026-10-31** with the fixed-pipeline/
  no-tools decision. `lib/services/agent/tools/` is absent; the contract keeps the
  tool table only as future reference. `AgentToolErrorCode` remains as the stable
  error vocabulary.
- `CitationRegistry` issues/keeps `source-N`, dedupes by dictionary + entry.
- Assets: `assets/agent/dictionary_probes.json`,
  `assets/agent/grammar_patterns_ja.json`; grammar longest-match catalog.

### P6.2 Provider/secret

- `flutter_secure_storage` 11.2.0; `FlutterSecureStorageSecretStore` and
  in-memory test store. Keys are namespaced; no SharedPreferences/SQLite key.
- `OpenAiCompatibleProvider` and `AnthropicProvider` (text-only, streaming and
  non-streaming), fake provider, provider factory.
- `assertNoImagePayload` rejects image/file keys and local/data URI values while
  allowing the opaque `image_id` handle.
- Provider request tests assert no image/path/key leakage; Anthropic test checks
  `x-api-key`, `anthropic-version: 2026-10-21`, top-level `system`, no temperature.

### P6.3 Familiarization

- Dictionary sample fingerprint (MDX stat + entry count/encoding + schema/prompt
  version) and UniDic fingerprint (runtime files + version + schema).
- `DictionaryFamiliarizationService`: bounded sample → small model JSON →
  user confirmation (`save/skip once/decline`) → SQLite profile; reuse and
  decline memory; mismatched dictionary id rejected.
- `UnidicFamiliarizationService`: deterministic token-layout observations, no
  fake UniDic entry lookup.
- `AgentStore` (`rikai_agent.db`) creates tables for providers, sessions, runs,
  messages, tool calls, source versions, citations, dictionary/UniDic profiles,
  annotation rule sets. Profile and provider CRUD implemented.

### P6.4 Orchestrator/evidence/validator

- `AgentOrchestrator` fixed stages: prepare → OCR → familiarizing → tokenize →
  evidence → reasoning → validate → done; cancellation, stage callback, source
  versions, budget, and stable `AgentRunFailure` codes.
- `EvidenceBuilder`: token/grammar targets, exact then prefix fallback, bounded
  unique targets/citations, per-token citation IDs, dictionary-order sorting.
- `QuoteBuilder`: sentence/clause UTF-16 quotes for original-text citation.
- `AgentValidator`: citation existence/ownership, quote/literal matching, strict
  dictionary-fact citations, structural token/pattern references, context
  inference unresolved rule, strict model-supplement rejection, reading check.
- Analysis prompt/schema and user prompt envelope (untrusted data labels).

### P6.5 Agent UI and settings

- Fifth home action `词典助手`; home labels now `拍照识别/查句子/查单词/
  历史记录/词典助手` (tests updated). Home body is a `SingleChildScrollView`
  so all five actions are built on small/landscape screens.
- `AgentPage` (292 lines after the split): only wiring; extracted
  `agent_session_panel.dart`, `agent_composer.dart`, `agent_message_list.dart`,
  `agent_message_widgets.dart`, `agent_evidence_panel.dart`, `agent_actions.dart`
  and `agent_progress_view.dart`. Run state lives in the app-scoped
  `AgentRunController`.
- User bubble renders sent image thumbnails (multiple images use Wrap) instead
  of a text-only “1 image” placeholder. Composer clears text + image after send.
- `AgentResultView`: original quotes, per-segment word/grammar notes,
  interpretation candidates, unresolved items, loose model supplements,
  dictionary-ordered evidence cards; citations are numbered “依据1/依据2…”
  once per segment, not repeated after every note.
- Citation tap re-runs an exact lookup in the cited dictionary and opens the
  existing `EntryPage`; missing entries show a toast.
- Familiarization confirmation sheet: editable Markdown, save/skip/decline.
- `AgentSettingsPage`: provider list/add/edit/delete, base URL, small/complex
  models, masked API key, secure storage, privacy copy. No real key is required
  for the empty-state/widget tests.
- `AgentTokens` semantic colors/sizes added to `app_tokens.dart`; no page-level
  hardcoded color/font-size values were introduced.

### Pipeline hardening after device test (2026-10-30)

- **SSE**: fixed Dio `Stream<Uint8List>` vs `utf8.decoder` runtime type mismatch;
  OpenAI-compatible streaming now parses text and DeepSeek `reasoning_content`.
  If a stream yields no text, the provider retries once non-streaming.
- **Visible generation**: Agent page shows the current stage, a four-step
  progress list (OCR → lookup → generate → validate), live retrieved-entry/
  citation counts, and a thinking-time label. Stage text and the timer follow
  the response-language setting. Legacy behavior (`follow` inferred Japanese
  from kana, English from Latin-only input, otherwise Chinese) is superseded by
  the 2026-11-01 decision: default `zh`, no input heuristic; implementation is
  pending. Raw streamed output, reasoning text
  and character counts are never rendered. Validated result items fade in one by
  one after validation; there is no streaming JSON partial display. Citations
  are numbered “依据1/依据2…” and consolidated once per segment instead of after
  every word note. The safe model-generated “summary” field is deferred (P3).
- **Tag format success**: analysis/familiarization use bracket-tag plain text,
  not JSON. Analysis requires non-empty `translation`/`segments`; tag-block
  integrity (balance/nesting/single-instance fields) is checked before repair.
  No `response_format`/`json_schema`/`output_config` is sent.
- **Normalization**: `literal` is filled from the selected quote; grammar notes
  with unknown `pattern_id` are dropped; result view shows epistemic/confidence
  badges.
- **Fewer requests / failure isolation**: familiarity profiles are split by a
  4K token estimate; missing/failed dictionaries produce `unavailable` issues
  with a per-dictionary retry, and the Agent continues with generic lookup.
- **Language split**: profile language (default 中文) and answer language are
  separate settings; profile language is stored/in the fingerprint, and changing
  it asks before invalidating existing profiles.
- **Input split**: with an image, the text field is an instruction/context and is
  not added to evidence sources; text-only input remains the source.
- **Cancellation/reentrancy**: `AgentRunController` is app-scoped. The page only
  subscribes to its snapshot; `dispose()` no longer cancels a run, repeated sends
  are ignored while a run is active, and old callbacks are discarded by the run
  cancellation token. Provider `CancelToken` and familiarization cancellation
  remain pending.
- **Composer lifecycle**: after sending, both the text field and the image
  attachment are cleared; the user bubble is the source of truth. Retry and
  “new session” use the controller's request snapshot rather than the empty
  composer.
- **UniDic optional**: a missing/broken UniDic no longer fails the run. The
  evidence bundle carries `structure_unavailable`, the prompt forbids token/
  grammar claims, the validator rejects structural claims, and the result view
  shows “结构分析不可用”.
- **Validation repair/salvage**: a parse/validation failure triggers one repair
  call with the original output + errors + the same evidence/quotes (no OCR or
  lookup rerun). If repair still fails, invalid citations/unknown tokens/patterns
  are removed, strict unsupported claims become `unresolved`, and the partial
  result is shown with a warning instead of an empty error card. A strict-mode
  error still offers “宽松重试”.
- **Strict mode**: word notes always require citations in strict mode; unknown
  source/citation and empty results are rejected; debug-only raw-output logs.

### 2026-10-31 real-device feedback backlog (Waves 1–2 implemented)

The user reported 17 additional issues after a real-device P6.5 trial. The
authoritative plan, current-code evidence, wave ordering and acceptance
criteria are in
[`docs/agent_docs/device-feedback-2026-10-31.md`](agent_docs/device-feedback-2026-10-31.md).
Summary:

- **Wave 1 (quick/low-risk)**: short citation pills (F4), remove `qN` markers
  (F5), 3.5-row dictionary filters (F9), Chinese provider labels/presets (F10),
  current-dictionary-only entry links (F15), app-scoped OCR download progress
  (F16).
- **Wave 2 (implemented, Agent lifecycle/UI)**: Chinese-first default and no
  input-language heuristic (F1a/F17), independent Agent dictionary preferences
  (F8), app-level dictionary-profile inbox that gates tokenizing (F2), elapsed
  time across page leave (F3), camera/gallery multi-image input (F11),
  full-screen sent-image viewer (F12), profile manager (F13), result action
  row/copy/edit/regenerate (F14). F1b is implemented in Wave 3.
- **Wave 3 (implemented)**: `AgentLanguageValidator` + one language repair
  (F1b); global `AgentLimits` and exact → prefix → suffix → incremental lookup,
  continuing past a zero-new mode, with normal progression ending at the global
  cap (cancellation aborts; per-target/per-dictionary caps skip queries, not
  modes) and N/M progress (F6); one `[COVERAGE]` tag review, source-id fill,
  tag-integrity checks, traceability filtering, locally verified duplicate
  pruning, flow A/B and at most one supplementary lookup (F7). All Agent prompt
  text is centralized in `agent_prompts.dart`; old prompt files are compatibility
  re-exports.
- F2 must precede F7/F13/F14 profile work. F6 must precede F7. F17 must precede
  all Agent UI localization work. The backlog itself does not authorize P6.6/
  P6.7; P6.6 was started separately on 2026-11-02 by explicit user instruction,
  while Wave 4 device acceptance remains pending.

Wave 1 implementation (2026-10-31):

- `DictionaryFilterBar` now reserves 3.5 rows; `AppSizes.dictionaryFilterVisibleRows`
  is the shared token.
- Provider settings use Chinese labels and `AgentProviderPreset` (`DeepSeek`,
  `Claude（Anthropic）`, other OpenAI-compatible); DeepSeek/Claude fill their
  default base URLs without overwriting a user-edited address.
- `entry://` links build an exact `LookupRequest` limited to the current entry
  tab's dictionary; global lookup selection/mode is not used.
- OCR model downloads moved to app-scoped `ocrModelDownloadControllerProvider`;
  the model page subscribes and re-enters with the current progress/cancel state.
- Citation chips use the compact 24dp pill and `Wrap`; evidence rows no longer
  use the long `依据N · 查看` string. Unresolved items no longer show `（q1）`.
- Wave 1 verification: `flutter analyze` clean; current test/build results in
  `docs/project-data.md` §2/§5. Device visual/navigation/download acceptance
  remains for Wave 4.

Wave 2 implementation (2026-11-01):

- **F1a/F17 language**: `AgentResponseLanguage` no longer has `follow`; stored
  `follow` maps to `zh`. `resolveAgentUiLanguage(setting)` takes no source
  text. New `AgentUiStrings` (zh/en/ja) supplies Agent page, session panel,
  composer, message/result copy, profile sheet/manager, and Agent settings
  labels. The analysis prompt contract now states that all human-readable
  fields use the configured language and Japanese appears only in quotes,
  word forms, readings and dictionary examples.
- **F8 selection**: `AgentDictionaryPreferences` uses separate
  `agent_dictionary_selected_ids` / `agent_dictionary_mode` keys. The Agent
  page never reads or writes `lookupPreferencesProvider`.
- **F2 profile inbox**: `DictionaryFamiliarizationService.generateMany()`
  returns all proposals without asking consent; `persistDecision()` writes only
  after an explicit decision. `AgentProfileInboxController` is app-scoped and
  `AgentRunController` waits in `AgentRunStatus.awaitingProfile`. Page detach
  cannot call `skipOnce`; closing the sheet keeps the item pending. Decisions
  are persisted by the inbox so run-generated and manager-generated proposals
  share one path.
- **F3 elapsed time**: `startedAt` remains in the app-scoped snapshot;
  `awaitingProfile` counts as running. A wall-clock elapsed test covers a
  10-second absence; run/profile tests assert no extra provider request before
  the user decides.
- **F11/F12 images**: composer supports a camera/gallery bottom sheet,
  multi-select, append, per-image removal and `AgentLimits.maxImagesPerRun`
  (6). Sent thumbnails open the existing `PhotoViewerPage`.
- **F13 profile manager**: `/agent-profiles` lists stored profiles with
  trusted/declined/pending/stale/ unavailable states, Markdown edit, single and
  batch regenerate, and multi-select delete. Regeneration uses the shared
  inbox, not a page-local familiarizer.
- **F14 result actions**: result bubble has regenerate then copy (Markdown via
  `buildAgentResultMarkdown`, no raw JSON/reasoning/paths). Long-press on a
  user message offers copy/edit. `regenerate()` replays the request from the
  familiarization stage, keeps the previous result visible until success, and
  restores it with a notice on failure.
- Wave 2 review follow-up (2026-11-01): profile-language changes apply without a
  dialog; `AgentProfileInboxHost` is shared by the Agent page, profile manager
  and Agent settings and uses a claim guard so a proposal never opens twice.
  Regeneration moved to app-scoped `AgentProfileRegenerationController` (no
  duplicate token spend after leaving/re-entering; title-bar text and
  indeterminate progress). Independent dictionaries may regenerate in parallel;
  only the same dictionary is refused while its request is active, and its
  edit/delete actions stay available. The title lists every active dictionary
  and updates as new requests are added or finish. “不再询问” now saves and
  enables `agent_profiles_auto_accept` (default off; new checkbox in Agent
  settings). Any save made while an Agent page or subpage is mounted (manual or
  auto-accept) shows the shared host toast once per batch. The “详细解析 ·
  依据 N 条” header now counts only adopted citations, matching the filtered
  evidence section and Markdown export. Retry-dictionary shows a spinner; Agent
  no longer auto-scrolls; the profile-manager mode toggle stays in place and the
  composer image notice is centered.
- Model output format: analysis and dictionary profiles use bracket-tag plain
  text (`analysis_tag_parser.dart`, `dictionary_profile_tag_parser.dart`).
  Leaked type/probability markers are stripped; types/confidence are derived
  locally. `tag_block_integrity.dart` checks unclosed/misordered/mis-nested
  blocks and duplicate single-instance tags before one “text unchanged, tags
  only” repair. Legacy JSON output fallback, runtime response schemas and the
  `response_format`/`json_schema` capability flag were removed; DTO JSON remains
  only for local storage.
- Wave 2 verification: `flutter analyze` clean; current test/build results in
  `docs/project-data.md` §2/§5. Device visual/provider/arm64 acceptance remains
  for Wave 4.

Wave 3 implementation (2026-11-01, F1b/F6/F7):

- **F1b**: `AgentLanguageValidator` checks translation, segment interpretation,
  word sense, grammar explanation, option meaning, unresolved reason and model
  supplement; source quotes, word forms, readings and citation snippets are not
  checked. Allowed source terms/readings/quoted material are stripped before a
  conservative script-ratio judgment. On mismatch the orchestrator sends one
  `LANGUAGE CORRECTION TASK` request that keeps tags/ids/citations/quotes and
  only translates human-readable prose; a structurally valid repaired result is
  used. A failed or still-mismatched repair keeps the result and adds a
  localized `warnings` entry rendered in the result view.
- **F6**: `AgentLimits` (`lib/core/models/agent/agent_limits.dart`) is the single
  budget source and is injectable through `agentLimitsProvider`. Evidence lookup
  runs mode-by-mode: all targets exact, then prefix, suffix, incremental. A mode
  with zero new unique citations does **not** stop later modes; normal mode
  progression ends at the global cap, while cancellation aborts and per-target/
  per-dictionary caps skip a target/dictionary without stopping the mode loop;
  duplicate `(dictionaryId, entryKey)` entries are linked, not reissued. When
  UniDic fails/returns no tokens, bounded raw-surface targets keep MDict lookups
  alive: chunks are split by newline/whitespace/punctuation, whole chunks ≤12 chars and
  2–6 char windows are added, candidates go through `lookupCandidatesFor`, and
  raw targets share the same modes and caps. Progress uses `已检索 N / M` from
  the run's limit snapshot.
- **F7**: After initial evidence, one `[COVERAGE]` tag review (small model, one
  tag-format repair). The parser fills `source_id` locally and checks the single
  COVERAGE root, MISSING/DUPLICATE/NOTES parentage, NOTES uniqueness and tag
  closure before accepting a review. Queries are kept only when traceable to
  source text, token surface/lemma/reading/candidates, pattern surface or an
  existing citation key; source refs must exist. Flow A supplements below the cap
  with the same F6 mode order. Flow B verifies model-suggested same-dictionary
  duplicate groups locally by snippet overlap, keeps the denser entry, prunes the
  rest from the bundle/registry, then supplements. At most one review and one
  fallback per run; failure, untraceable queries, no verified duplicates or no new
  evidence produce localized warnings and keep the original evidence.
  `AgentStage.coverage` maps to the lookup progress step; `coverageFallbackUsed`
  is recorded in the result. The `coverage.v1` JSON DTO/serialization remains
  internal; no persistence call is currently wired.
- All Agent prompt text/request builders live in
  `lib/services/agent/agent_prompts.dart`; other Agent files must not embed prompt
  literals.
- Wave 3 verification: `flutter analyze` clean; `flutter test` see
  `docs/project-data.md` §2.1; `flutter build apk --debug` succeeded after the
  prompt/coverage/raw-surface migration. Real provider/arm64/large-dictionary
  smoke remains Wave 4.

P6.6 implementation (2026-11-02, multi-OCR core):

- `AgentOcrVariant` now carries local `origin` (OCR or dictionary repair) and
  prepared variants can be passed through `AgentImageInput`; re-analysis reuses
  the selected OCR text and does not run recognition again. Source/quote
  provenance records `dictionary_repair` locally without serializing paths or
  origins to the provider.
- `OcrConsensus` (`lib/services/agent/ocr_consensus.dart`) computes local
  quality (confidence, script-neutral meaningful characters, duplicate-noise
  ratio, bounded dictionary hit rate), bounded character diff (prefix/suffix +
  LCS for small middles), deterministic variant ranking, and bounded
  dictionary-backed repair suggestions. No kana ratio/matching is used, so the
  signal remains usable for non-Japanese dictionaries. No provider call, image
  upload or automatic text replacement is involved.
- `AgentOcrVariantsController` (`lib/state/agent_ocr_variants.dart`) is
  app-scoped. After the user asks for a comparison it runs unique
  `(engine, mode)` combinations (`paddle_v5/horizontal`, `manga_ocr/vertical`,
  `paddle_v5/vertical`, then `auto`), never dedupes by text (text equality is not
  a duplicate signal), reports a stable error code on failure, and supports
  stop/clear.
- `AgentOcrVariantsPanel` shows variant chips (engine/mode/confidence), quality
  metrics, low-quality warning, difference preview with highlighted changed
  spans, dictionary candidates, and an explicit “re-analyze with this variant”
  action. Applying a candidate creates a `dictionary_repair` variant and starts
  a new run; it never edits the previous result in place.
- `AgentRunResult.ocrQuality` exposes the selected variant's local quality for
  the UI; it is never sent to the provider.
- Automated coverage: quality/diff/ranking/repair unit tests, controller
  generation/dedupe/error/clear tests, prepared-variant orchestrator test, and
  panel widget tests. Real-device visual/OCR quality and real dictionary
  suggestion quality remain Wave 4/P6.6 device acceptance.

P6.6 automated closeout (2026-11-03):

- The P6.6 implementation is frozen for automated verification: `flutter
  analyze` is clean, the suite has 350 declarations (366 executed cases) in 77
  files, and the debug APK builds. The current test baseline is recorded in
  `docs/project-data.md` §2.1.
- No new P6.6 feature is added in this closeout. The remaining P6.6 work is
  device acceptance (real manga pages, forced MangaOCR, the real 463k-entry
  dictionary, 200% font, re-analysis latency) and the gaps listed below.
- Known functional gaps at closeout: the comparison panel was mounted only
  when a displayable result existed, per-variant citations were rebuilt only
  after the user committed a variant, and only the selected variant was written
  to `AgentSourceVersion`. The first two gaps were closed by the P6.6 carryover
  implementation below; all-variant persistence was closed by P6.7 history.

P6.6 carryover implementation (2026-11-03):

- Failed-run multi-OCR entry: `AgentMessageList` now mounts the variant panel
  for an image run with a result **or** an error. It falls back to the
  controller's last local images when no result exists; the panel can generate
  a baseline locally and publish it as
  `AgentOcrVariantsState.baselineVariants`. A missing local path disables
  generation with “原图不可用，无法重新识别”.
- Per-variant lookup preview: `OcrConsensus.probeDictionary` performs the same
  bounded local tokenize/lookup pass used for quality scoring and also collects
  at most three cleaned snippets per variant (240-char cap). They live only in
  `AgentOcrVariantsState.previews`; no provider call, formal citation or
  history write is involved. The panel shows the selected variant's hit count
  and snippets before “使用此版本重新分析”.

2026-11-02 stability/feedback fixes:

- **Provider HTTP 400 hardening**: before any request the adapter validates a
  non-empty model, drops whitespace-only messages, requires at least one
  non-system message, merges consecutive Anthropic roles, sanitizes unpaired
  UTF-16 surrogates/control characters, and requires a positive `maxTokens`.
  It deliberately does **not** impose a universal output ceiling: model limits
  differ (deepseek-flash is far above 8,192). Providers have an optional
  `maxOutputTokens` (persisted in `capabilities_json` as `max_output_tokens`;
  0 = unset): OpenAI-compatible omits `max_tokens` when unset and sends it when
  set; Anthropic always sends `max_tokens`, preferring the provider value over
  the request builder's 12,000. HTTP 400 responses are classified from the real
  error body (context length, unsupported output parameter, reasoning/tool
  parameter mismatch, generic invalid parameter) and debug logs record only
  request shape, not prompt text or keys.
- **Reasoning-only stream**: if SSE produced `reasoning_content` but no text,
  the provider now raises `PROVIDER_EMPTY_OUTPUT` immediately instead of
  repeating the same expensive request non-streaming. `finish_reason` is logged
  with the SSE counters. Only a completely empty stream (no reasoning, no text)
  falls back. Stream progress publishes at most every 250 ms because reasoning
  models can emit >10k tiny deltas and the UI shows elapsed time, not characters.
- **P6.6 UI feedback**: the card title is “文字识别结果”; each image is shown as
  a tappable thumbnail using the same full-screen viewer as user messages;
  quality shows “置信度” and “词典命中” capsules with plain percentage values.
  Kana ratio/matching was removed from OCR quality and ranking, and character
  classification is script-neutral for future non-Japanese dictionaries.
- **Per-image comparison state**: `loadingImageIds` / per-image error codes
  replace the single global loading flag; comparing image 1 no longer shows a
  spinner on image 2 and no longer blocks image 2's comparison. Native OCR calls
  are serialized through an internal queue; UI state remains independent.
- **Missing alternative variants**: text-equality dedupe was removed (auto and
  horizontal often return identical text but are still distinct options), OCR
  readiness is awaited before checking vertical availability, and `auto` is
  offered as an alternative when the baseline used horizontal/vertical. The empty
  copy is now “没有可用的其他文字识别结果”.
- **Coverage review stability**: compact coverage input (selected text,
  token/pattern ids, cleaned citation snippets plus retained token/pattern
  offsets and citation `entry_key`/`matched_key`/`headword`), per-item tolerant
  parsing (one malformed MISSING/DUPLICATE no longer discards the review),
  normalization of empty/self-closing sufficient blocks, and debug diagnostics
  for request/parse failures. Every automatic correction (unknown kind, source-N
  remap, priority clamp, truncation) is logged with item index and before/after
  values. Repair requests reuse the normalized text, and normalization is
  idempotent. Its output budget is derived independently by
  `AgentLimits.coverageReviewMaxTokens` from the MISSING/duplicate caps, reason
  length, tag overhead and a safety margin; the estimator uses
  `AgentLimits.coverageCharsPerToken = 1.0` (conservative for CJK) and all
  overhead values live in named `AgentLimits.coverage*` constants. It does not
  follow the analysis request or a global provider ceiling. Genuine request
  failures still keep evidence and show the warning.
- **UniDic path clearing**: empty input (or the explicit “清除” button) clears the
  saved path and invalidates the MeCab service; non-empty invalid paths are still
  rejected and never saved.
- **P6.6 model x orientation matrix**: `OcrPort.recognize` now accepts an optional
  engine constraint. The native OCR plugin forces `paddle_v5` or `manga_ocr` when
  requested (default null keeps the existing best-of behavior) and rejects
  MangaOCR horizontal requests. The Agent generates up to four unique
  `(engine, mode)` variants: `paddle_v5/horizontal`, `manga_ocr/vertical`,
  `paddle_v5/vertical`, then `auto`, so horizontal and vertical no longer show
  near-identical PaddleOCR results under different labels. Maximum four variants
  per source is enforced in the controller and re-analysis.
- **P6.6 UI feedback**: variant chips are left-aligned and wrap by row; each chip
  has a fixed 28dp height and reserves the recommendation icon slot, so selection
  never changes its size. Diff highlights use the dedicated warm
  `AgentTokens.diffHighlightSurface`/`diffHighlightText` pair instead of the
  citation blue, and unchanged text is muted. Agent thumbnails decode at display
  resolution via `cacheWidth`/`cacheHeight` to avoid a full-photo decode when a
  lazily built card enters the viewport.
- **Expanded evidence scroll jank**: `AgentResultView` now splits its expanded
  detail into small blocks and appends them across frames
  (`_ProgressiveResultBody`, 4 initial + 3 per frame); each dictionary
  `_EvidenceGroup` uses the same chunker for its citation rows. Only the first
  `AgentFadeIn.maxAnimatedItems` blocks run the staggered fade, so expanding a
  dictionary evidence card no longer builds the whole result tree and starts
  dozens of animations in one frame. The inline `ExpansionTile` UX is unchanged.
- **Dictionary repair selection**: repair candidates now use the same chip design
  as OCR variants. Unselected candidates stay grey; selecting another candidate
  for the same word replaces the previous one; different words can each keep one
  selection. The “re-analyze with this variant” action stays a bottom-right blue
  `FilledButton.tonal` in both the dictionary-repair section and the OCR-variant
  diff section; it is enabled only when at least one candidate is selected and
  grey/disabled otherwise. Applying selections uses `OcrConsensus.applyRepairs`,
  which replaces spans from the end backwards so multiple words can be applied
  in one new `dictionary_repair` variant without invalidating earlier UTF-16
  offsets.
- **Interpretation percentages**: the tag parser assigns OPTION blocks relative
  weights (0.5 without citations, 0.7 with citations), not model probabilities.
  `normalizeAnalysis` and `salvageAnalysis` now normalize multiple OPTION blocks
  to integer percentages summing to 100 (two 0.7 options become 50%/50%; three
  become 34%/33%/33%). A single OPTION keeps its heuristic value. The prompt
  still forbids model-emitted confidence values; no prompt rule was added for
  this display invariant.
- **Agent output corpus**: `docs/agent_output/` now stores Markdown output
  samples named `YYYY-MM-DD-HH-mm.txt` for manual quality inspection; see
  [`agent_output/README.md`](agent_output/README.md). These files are not
  provider logs and contain no image paths or keys.

P7.0 rich-text post-processing (2026-11-03, incremental):

- After a validated analysis, small-model formatting passes insert
  `[RUBY=reading]base[/RUBY]`, `[BOLD]...[/BOLD]` and
  `[UNDERLINE]...[/UNDERLINE]` into the **detailed** result: the whole “原文”
  section and each segment interpretation. The AI bubble summary renders local
  RUBY (it does not receive the model's BOLD/UNDERLINE pass). The prompt uses
  the fixed strict constraint: no
  character may be changed/deleted/added, except a whole YOMI block may be
  deleted when replaced by equivalent RUBY. It has no vague “return the whole
  original text if uncertain” escape; only a specific uncertain word may be
  left unchanged. AI reads the text itself; UniDic readings are not supplied.
- The analysis prompt asks the result-generation model to write reading
  annotations as `word[YOMI]reading[/YOMI]` (bare kana, no parentheses) inside
  `[MEANING]` and word-entry explanations. If the reading equals the word, only
  the word is written. Parentheses `（...）` are ordinary explanations, not
  readings. The plain display/export form is `reading【surface】` (for example
  `すき【好き】`); the reversed `surface【reading】` is also accepted. Local
  word-note sources use the same format. Repair/language-repair prompts
  preserve YOMI blocks exactly. The formatter prompt requires replacing a
  source `reading【surface】` with `[RUBY=reading]surface[/RUBY]` (no leftover
  brackets) and placing the RUBY inside BOLD/UNDERLINE when the word is
  emphasized; the local converter is tag-aware as a safety net.
  `[TRANSLATION]` stays plain.
- `rich_text_tags.dart` strips every known tag and checks balanced, correctly
  nested tags and safe pronunciation annotations without assuming a script.
  RUBY may be nested inside BOLD/UNDERLINE (and BOLD/UNDERLINE may wrap each
  other); style tags may not appear inside a RUBY base. YOMI contents are
  compared after removing full-/half-width punctuation. It also verifies
  retained YOMI blocks are unchanged and in the same base position;
  whole-block deletion is allowed. Model RUBY readings are cleaned of full-/
  half-width punctuation before being stored; an empty or base-equal reading
  removes the RUBY pair. The bracket converter is tag-aware: when the
  formatter outputs `[BOLD]reading[/BOLD]【surface】`, the reading is moved
  inside the emphasis span as `[BOLD][RUBY=reading]surface[/RUBY][/BOLD]` so it
  inherits bold; duplicate readings after `[/RUBY]`, even across
  `[/BOLD]`/`[/UNDERLINE]`, are dropped. Parentheses are not converted.
  Markdown export (`richTextToPlain`) emits one `reading【surface】`.
  UNDERLINE is painted by a baseline-relative custom line, not
  `TextStyle.decoration`, so kanji and punctuation such as `；` share the same
  underline height; RUBY bases use the surrounding text metrics so they do not
  sit below plain runs. The
  processor accepts the result only when the tag-stripped, YOMI-normalized text
  equals the original **character for character** (no trim or Unicode
  normalization). Any change, malformed tag, empty output or provider failure
  discards the formatted block and renders it plain; the run itself is not
  failed and no user-facing error is shown.
- 2026-11-03 post-processing regression fix (P0): the formatter input is the
  result model's original text/`word[YOMI]reading[/YOMI]`; it is no longer
  pre-converted to RUBY. The formatter prompt keeps only tag format,
  insert-tags-without-changing-text and valid nesting; the “preserve existing
  RUBY”, “do not return unchanged” and “convert YOMI to RUBY” rule groups were
  removed. `localReadingsToRuby` now runs while building every provisional,
  final and salvaged result, so the first preview frame already has RUBY;
  provider/validation failure, retained YOMI/parentheses, or a rejected
  section falls back to the same local conversion. Precondition check on the
  current `docs/agent_output` regression samples: 9/9 annotated readings have
  matching local evidence (100%). The full P1 semantic RUBY-block comparison
  is still not applied; `copyWithRichText` only keeps the local baseline when
  a model section is empty or rejected.
- 2026-11-03 salvage formatting fix: when analysis validation fails and
  `salvageAnalysis` returns a displayable result, the orchestrator now runs the
  same rich-text pass before returning it. Previously the salvage path returned
  early, so the UI showed plain notes/bracket readings and no
  BOLD/UNDERLINE even though the post-processor was configured. Debug logs now
  include `[AgentValidation] errors=...` (also `after_repair=...`),
  `[AgentSalvage] errors=...`, and `[AgentRichText] accepted=/changed=/tags=/
  ruby=/bold=/underline=/local_only=/reason=` so a formatting outage,
  local-only RUBY fallback and actual model emphasis can be distinguished.
- 2026-11-03 RUBY-first preview: `_buildResult` pre-fills
  `richOriginalText`/`richSegmentTexts`/`richSegmentNotes` with
  `localReadingsToRuby`. The detailed preview therefore shows RUBY as soon as
  the result appears, instead of showing bracket readings until the
  asynchronous formatter finishes. The AI bubble summary, segment quote lines,
  non-pitch word-note and grammar-note fallbacks, possible understandings,
  unresolved reasons and model supplements use the same local conversion, so
  historical/fallback entries also stop showing bare bracket readings.
  Citation snippets remain dictionary text and are not converted. Possible
  understandings use the structured `[OPTION]` label/confidence and render a
  green “情况X” capsule plus “可能性N%” text below the meaning, not the inline
  `A：...（70%）` form. When all interpretations share the same visible citation
  set, the citation chips are rendered once below the last case; differing
  sets keep their per-case chips.
- `AgentRunResult.richOriginalText` carries the whole original section;
  `AgentRunResult.richSegmentTexts` is aligned with `analysis.segments`;
  `AgentRunResult.richSegmentNotes` carries the AI-formatted dictionary-fact
  word senses/grammar explanations (not citation snippets). All three are
  pre-filled locally with RUBY before the formatting model runs; retained
  YOMI and `reading【surface】` annotations are converted locally, not shown as
  bracket text. `AgentRichText` renders
  ruby/bold/underline in the detailed original, segment interpretation and
  dictionary-fact notes only. Ruby uses the body text color and aligns the
  annotated base to the line's alphabetic baseline (the reading sits above and
  never pushes the base down). A reading inside BOLD inherits the bold weight;
  a reading is never underlined, even inside UNDERLINE. Duplicate
  `reading【surface】` annotations produced by wrapping an existing note are
  collapsed to one reading. UNDERLINE is body-colored with 2x thickness. The
  Markdown export uses `richTextToPlain` (RUBY becomes `reading【surface】`;
  BOLD/UNDERLINE/YOMI tags are removed) so copied text contains no tags.
- `AgentLimits.enableRichTextPostProcess` (default true) is disabled in tests
  that assert provider request sequences; a `formatting` stage is reported.
- Internal system Prompt instructions are English-only; validation error text
  may remain localized. The user/answer language is still controlled by
  `AgentResponseLanguage`.
- Tests: `rich_text_post_processor_test.dart`, `agent_rich_text_test.dart`,
  `analysis_tag_parser_test.dart`, `agent_language_validator_test.dart`, and
  rich-text cases in `agent_orchestrator_test.dart`.
- P7.1–P7.4 (task split/model routing/concurrency/streaming) are **not**
  implemented; the plan is in
  [`agent_docs/p7-task-decomposition-plan.md`](agent_docs/p7-task-decomposition-plan.md).

Current known gaps:

- Wave 4 device acceptance is not done: real provider/API key, arm64 Agent
  end-to-end, real large-dictionary suffix/incremental smoke, and secure-storage
  device I/O remain unverified. Automated Wave 3 tests do not prove those.
- The coverage review uses the small model and tag text parsed locally; real
  provider tag reliability and latency still need device measurement.
- P7.0 rich-text formatting is applied only to the assistant summary; the
  detailed structured result and Markdown export remain plain. Real-provider
  formatting acceptance, ruby layout at 200% font and small screens still need
  device/visual verification.
- Test coverage gaps: there is no dedicated raw-surface-target cap test (current
  cap tests use token targets), and no dedicated duplicate-`[NOTES]` integrity
  test. The implementation has both paths but the tests do not yet pin them.
- `coverage.v1` still has JSON serialization methods, but no persistence call is
  wired; do not describe it as an active storage format.
- P6.6 device acceptance is pending: horizontal/vertical variant quality on
  real manga pages, dictionary candidate usefulness against the real 463k-entry
  dictionary, contrast/overflow at 200% font, and re-analysis latency.
- P6.6 failed-state comparison entry is implemented; the panel is mounted from
  the run's last images when no displayable result exists. Image paths that no
  longer exist stay unavailable (generation disabled) rather than being faked.
  Device acceptance on real failure paths remains pending.
- Native OCR calls are serialized through a queue; two image comparisons show
  independent loading/error state and can both be started, but the second waits
  for the first engine call to finish.
- Provider 400 handling now reports the actual error-body category, but it does
  not automatically repair context-length or model-specific parameter problems;
  the user still needs to shorten input or adjust the model/provider.
- Provider settings now include an optional `maxOutputTokens` as the last input
  field (Agent settings dialog, blank = default) and recommend leaving it blank
  for OpenAI-compatible services. OpenAI-compatible omits `max_tokens` when
  blank; Anthropic uses it when set, otherwise the request builder's value
  (12,000 for analysis). This is an explicit per-service choice, not a universal
  ceiling.
- Long reasoning-model latency is a model-choice issue, not a removable request
  parameter. The app has no reasoning-effort/thinking-off setting; selecting a
  non-reasoning complex model (for example deepseek-chat/flash) is the current
  way to shorten analysis time. Automated tests cannot prove real provider
  latency.
- P6.6 per-variant dictionary previews are now shown before the user commits
  to a re-analysis; formal citations are still rebuilt only after the selected
  variant is analyzed. All variant texts are persisted by P6.7 history, while
  `AgentSourceVersion.selected` marks the variant used by that run.
- Process-death recovery of the in-memory profile inbox remains P6.7; the queue
  survives page navigation but not process death.
- P6.7 之后的任务级流式规划：
  [`task-level-streaming-plan.md`](agent_docs/task-level-streaming-plan.md)
  （规划中，未实现）。

Agent output quality samples are stored under `docs/agent_output/` as
`YYYY-MM-DD-HH-mm.txt` Markdown copies (one run per file). They are manual
inspection fixtures, not provider logs; see that directory's README.

### 2026-11-03 Post-stream result latency

The provider stream ending (`finish_reason=stop`) is not the same as the UI
having a result. Three sequential costs used to sit between them:

1. The OpenAI-compatible/Anthropic adapters kept reading the SSE body until the
   socket closed. A proxy or keep-alive connection could therefore add seconds
   after the logical end. They now stop at `finish_reason`, `[DONE]`, or
   `message_stop`, and `_collect` treats `LlmEventType.done` as terminal and
   cancels the subscription.
2. The first parsed/validated analysis was held until the optional validation
   repair, language repair, and (previously) P7.0 rich-text post-processing calls
   finished. `AgentOrchestrator` now emits an `onProvisionalResult` callback
   immediately after the first parse/validation (salvage is used when that first
   analysis is invalid); repair stages stay in `AgentStage.validating` instead of
   returning to `reasoning`. `AgentRunSnapshot.provisionalResult` renders the
   summary with “结果已出，正在复核…”, and the final result replaces it on
   completion. The app controller now passes `onRichTextReady`, so display-only
   formatting starts after the core result and is applied when it arrives.
   `onRichTextFormattingChanged` drives `AgentRunSnapshot.richTextFormatting`;
   while true, the Agent page shows a dismissible green “界面美化正在进行中…”
   banner above the conversation. It disappears automatically on completion,
   failure or cancellation. Dismissing it only hides the current run's notice
   and never cancels formatting.
3. The progress counter now receives only the accumulated character count.
   `_collect` no longer converts the growing buffer to a String on every delta,
   and stage transitions publish the final count; the UI's elapsed label uses a
   local timer, so no 4 Hz whole-page state updates are needed.

No run-result SQLite write sits on this path; profile decisions are the only
persistence and happen before their futures are released. Debug builds log
`[AgentTiming]` for provider headers/first event/finish/stream close, each
`_collect` label, stage transitions, parse/validate/language timing, provisional
emission, controller state changes, and the first result frame. Logs contain
durations and counts only — never prompt text, citations, paths, or keys.
`test/agent_orchestrator_test.dart`, `test/openai_compatible_provider_test.dart`,
`test/provider_http_test.dart`, and `test/agent_wave2_ui_test.dart` cover the
provisional-before-repair, held-socket, `[DONE]`, and provisional-bubble cases.

**2026-11-03 performance pass 2**: rich-text sections use a bounded worker pool
(`AgentLimits.richTextConcurrency`) and per-run text dedupe with a length-derived
output budget; the app controller applies formatting after `done`. The analysis
prompt uses a compact projection (selected OCR variant once, no
`lookup_candidates`/`tool_call_id`/internal budget, evidence does not repeat the
source text). `_collect` publishes accumulated lengths instead of full strings.
Evidence lookups are batched per mode through `BatchLookupPort`/`lookupMany`
(`AgentLimits.lookupBatchSize`), and coverage review is adaptive
(`AgentLimits.adaptiveCoverageReview`). New tests:
`test/evidence_builder_batch_test.dart`, compact-prompt/async-rich-text cases in
`test/agent_orchestrator_test.dart`, and the post-done rich-text controller case
in `test/agent_lifecycle_test.dart`.

## Tests and build

```text
flutter analyze  -> No issues found (see docs/project-data.md §2.1)
flutter test     -> see docs/project-data.md §2.1
flutter build apk --debug -> see docs/project-data.md §5
```

Device integration: current suite counts/results are in
`docs/project-data.md` §3. Known issue: MDict's final search assertion does not
find `とうきょう【東京】`; this is the pre-existing non-Agent search test, not
an Agent path. No arm64/real-device Agent run was performed.

Device smoke: a real gallery image (`何卒宜しくお願い致します。\n東京で食べた。`)
completed on-device OCR → UniDic → MDict evidence → DeepSeek streaming analysis
→ Chinese translation/per-sentence notes/source quotes/dictionary-ordered
citations in the Agent page. The reasoning stream was large (~20k chars) and the
final JSON ~3k chars; DeepSeek `deepseek-flash` can take ~50s, which is why live
progress is required.

New test files include: `agent_models_test.dart`, `lookup_gateway_test.dart`,
`grammar_patterns_test.dart`,
`dictionary_probes_test.dart`, `provider_payload_test.dart`,
`openai_compatible_provider_test.dart`, `anthropic_provider_test.dart`,
`fake_provider_test.dart`, `profile_fingerprint_test.dart`,
`dictionary_familiarization_service_test.dart`,
`unidic_familiarization_service_test.dart`, `evidence_builder_test.dart`,
`agent_validator_test.dart`, `agent_orchestrator_test.dart`,
`agent_page_test.dart`, `agent_run_controller_test.dart`,
`agent_lifecycle_test.dart`, `agent_result_view_test.dart`,
`provider_http_test.dart`, `provider_retry_test.dart`,
`analysis_normalizer_test.dart`, `tag_block_integrity_test.dart`,
`agent_settings_page_test.dart`, `lookup_actions_test.dart`,
`ocr_model_download_controller_test.dart`.
Wave 2 adds `agent_language_test.dart`, `agent_dictionary_preferences_test.dart`,
`agent_profile_inbox_test.dart`, `agent_profile_regeneration_test.dart` and
`agent_wave2_ui_test.dart`, plus new queue/gate/regenerate/multi-image cases in
`agent_lifecycle_test.dart` and `agent_page_test.dart`.
Wave 3 adds `agent_language_validator_test.dart`, `agent_coverage_test.dart`
and `agent_coverage_orchestrator_test.dart`, plus lookup-mode/cap cases in
`evidence_builder_test.dart` and language/coverage cases in
`agent_orchestrator_test.dart`.
P6.6 adds `ocr_consensus_test.dart`, `agent_ocr_variants_test.dart` and
`agent_ocr_variants_ui_test.dart`, plus a prepared-variant case in
`agent_orchestrator_test.dart`.
P7.0 adds `rich_text_post_processor_test.dart`, `agent_rich_text_test.dart`, and
rich-text accept/fallback cases in `agent_orchestrator_test.dart`.
P6.7 adds `agent_history_test.dart`, `agent_history_recorder_test.dart`,
`agent_history_ui_test.dart`, `agent_store_migration_test.dart`,
`agent_profile_inbox_persistence_test.dart`, `unidic_accent_parser_test.dart`,
plus pitch cases in `evidence_builder_test.dart` and `agent_result_view_test.dart`.

## P6.7 design decisions (2026-11-03)

- **Gate**: F1–F17 / Wave 4 device acceptance is still open and is handled by a
  separate workstream. The user explicitly allowed this workstream to start
  P6.7 while that acceptance continues; P6.7 device/visual checks remain
  pending.
- **History**: independent `/agent-history` (not the home corpus history); one
  entry = one run/analysis, read-only; no images/thumbnails/paths in AgentStore;
  manual delete/clear only; startup marks unfinished runs `interrupted`; every
  OCR variant is persisted as text; pending profile inbox survives restart;
  citations re-open by exact key and fall back to the saved snippet.
- **Pitch**: only UniDic accent fields 24–26. Real 2025.12 output was probed on
  the x86_64 emulator and verified (`aType`: 橋=2, 箸=1, 端=0, 東京=0, 日本=3,
  食べる=2, 花=2, 雨=1, 飴=0, 今日=1). The temporary probe test was removed after
  use. The high/low line appears only in word notes/dictionary-fact rows;
  missing/invalid data renders plain text; no AI-inferred pitch.
- **DSL**: safe JSON AST + built-in rule sets + preview/version/rollback; reader,
  photo and corpus first; Agent results later; no free-form editor in P6.7.
- **Markdown**: bracket-tag wire format remains; Markdown only for copy/export
  and restricted profile preview; no general Markdown renderer.
- **P6.6 carryovers**: failed-run multi-OCR entry and per-variant lookup preview
  are implemented (2026-11-03); real-device acceptance still follows Wave 4.
- **Docs/schemas**: `docs/phase6-agent-design.md` §17.2,
  `docs/phase6-agent-contracts.md` §14, `docs/design-tokens.md` P6.7 rows,
  `docs/project-rules.md` R-AGENT-24–27, and new schemas under
  `docs/schemas/agent/` (`history-entry.v1`, `history-result.v1`, `pitch.v1`,
  `annotation-rules.v1`). JSON syntax was validated.

### P6.7-1/P6.7-2 implementation (2026-11-03)

- **History/store**: `AgentStore` is now DB v3 with history result/metadata
  columns, selected-variant/order columns, and `agent_profile_inbox`.
  `AgentRunResult`/`AgentHistoryEntry`/`OcrQuality`/`AgentValidationResult`
  have local JSON codecs. All OCR variants, citations and rich-text/pitch fields
  are persisted; image bytes/paths are never stored.
- **History UI**: `/agent-history` lists one entry per run (title/date/mode/
  status/provider/image count) and `/agent-history/detail/:runId` is read-only,
  showing the user text, summary, detailed result, citations and OCR variant
  text. The clear-all action was replaced by the dictionary-profile-style
  multi-select mode: row checkboxes, select all, and “delete selected” with one
  confirmation; the batch delete is transactional and refreshes the list
  immediately. Single-row delete remains available outside selection mode.
  History citations fall back to the saved snippet when the dictionary cannot
  be reopened.
- **Lifecycle**: `AgentHistoryRecorder` is started from app bootstrap, writes
  start/provisional/final states, and marks unfinished runs `interrupted` on
  startup. Profile inbox pending proposals are restored/persisted; dismiss still
  does not auto-skip.
- **Pitch**: `Token` now exposes UniDic accent fields 24–26;
  `parseUnidicAccent` derives `L/H` mora patterns from field 24 (`aType`);
  `AgentPitchAccentText` draws the high/low line only in word-note/dictionary-
  fact rows. It delegates reading rendering to the existing `AgentRichText`
  Ruby layout unchanged and overlays the pitch line above it without adding
  line height. A kanji surface without a distinct reading/furigana hides the
  pitch line (the reading may be ambiguous). The pitch word row starts with a
  red localized “音调信息” badge (same metrics as the epistemic badge, light
  red surface + `error` text) and then the existing pitch words; the badge is
  local-only and never enters a provider request/export.
  `AgentRunResult.pitchAccents` is local-only and omitted from
  `AgentEvidenceBundle.toJson`, so it never enters a provider request.
- **Tests/build**: added `agent_history_test`, `agent_history_recorder_test`,
  `agent_history_ui_test`, `agent_store_migration_test`,
  `agent_profile_inbox_persistence_test`, `unidic_accent_parser_test`, plus
  pitch cases in `evidence_builder_test`/`agent_result_view_test`, plus
  multi-select history UI/batch-delete, beautifying-banner, failed-run variant
  entry and per-variant lookup preview tests. Full `flutter test` passed (479
  executed, 470 declarations in 86 files) and debug APK built; the workspace
  also contains concurrent rich-text changes from another workstream.
  `docs/project-data.md` was synced with user consent.
- **Still pending**: full text/group annotation DSL/user editor,
  accessibility/release polish; real-device/visual acceptance. Provider test
  connection, restricted Markdown preview and annotation v1 shipped 2026-11-08.

## Not implemented / next

1. **2026-10-31 device feedback (F1–F17)**: Waves 1–3 are implemented and
   verified by unit/widget tests; Wave 4 device acceptance remains
   (real provider, arm64, large-dictionary suffix/incremental smoke). The
   2026-11-02 user instruction to continue development was used to start P6.6;
   this does not turn the pending Wave 4 device checks into verified results.
2. **P6.6 multi-OCR**: core implemented 2026-11-02 (quality/diff/ranking,
   dictionary-assisted candidates, user-confirmed variant re-analysis and UI);
   failed-run entry and per-variant lookup previews implemented 2026-11-03;
   all variant texts are persisted by P6.7 history. Remaining: real-device
   visual/OCR/dictionary acceptance.
3. **P6.7**: history/persistence and UniDic pitch are implemented (2026-11-03);
   provider test connection, restricted Markdown preview and annotation v1
   (decoration subset) are implemented (2026-11-08).
   Remaining: full text/group annotation DSL/user editor,
   accessibility/empty/error polish and release packaging/licence review;
   real-device/visual acceptance still pending.
4. Real device verification: provider network calls with a real key, MDict
   `sample`/`suggest` against the 463k-entry dictionary, Agent end-to-end on
   arm64, and secure-storage read/write/clear on device.
5. Agent conversation persistence: P6.7-1 is implemented. `AgentStore` v3
   persists one run per history entry with no image paths; startup marks
   unfinished runs `interrupted`; all variants and the profile inbox survive
   restart. Real-device storage/visual checks are still pending.
6. Tool calling: removed by decision (2026-10-31). The pipeline is fixed and the
   model has no tools; the contracts keep the tool table only as a future
   reference. Reintroducing tool calls requires a new ADR plus tool_use/
   tool_result message support.
7. Provider reliability: OpenAI/Anthropic now use a provider-neutral cancel
   token, retry 429/5xx/timeouts up to 3 attempts, parse multi-line SSE data and
   stream error objects. Remaining: familiarization cancellation and exposing a
   structured retryable error detail for every provider failure.
8. No commit/reset was performed by this session; the tree also contains an
   external save-point commit (`c79d03f`) that predates the latest edits.
9. **Conversational Agent UI v2**: `docs/design-tokens.md` defines the
   message-first Agent layout (about 80% message area, ≥70% on small screens,
   16/4 bubbles, fixed composer, streaming/stop, folded evidence, error cards,
   grouped settings). The current P6.5 page has the conversation layout
   (bubbles/folded evidence/fixed composer), an app-scoped run controller,
   thinking-time progress, and the core v2 tokens in `app_tokens.dart`. P6.7
   history and pitch are implemented; full accessibility/200% verification,
   provider cancellation and complete v2 acceptance are still pending. Do not
   describe the remaining items as implemented.
