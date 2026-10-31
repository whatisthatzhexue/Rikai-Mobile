> ⚠️ 历史快照：本文档记录特定历史时期的审查结论。当前修复状态请以 docs/phase6-status.md 和各 phase 状态文件为准。

# 非 Agent 功能回归检查

- 日期：2026-10-30
- 状态：**快照评审**。另一个 session 正在修改 Agent 代码/文档；行号与结论以当前
  工作区快照为准，合并/继续改造后需复核。
- 范围：Agent 以外的现有功能——OCR/拍照/照片集/语料、UniDic/MeCab、MDict 查词/
  渲染/搜索、读者页、主页/导航/主题/引导/设置/帮助、HistoryStore、共享模型/工具。
- 方法：只读 `git diff`、调用链、共享服务与测试；没有修改任何文件。`flutter
  analyze` 在当前快照为 **No issues found**；未运行 `flutter test`/`flutter
  build apk`，避免与另一个 session 的构建/测试互相干扰。

## 结论

- **未发现非 Agent 运行时逻辑回归**：OCR/拍照/语料、MeCab/UniDic、MDict 查词/
  渲染、读者页、主题/导航/引导/设置都没有改变行为的 diff。
- **确认有 2 个非 Agent 设备测试仍使用旧主页文案**，会直接失败；另有 1 个帮助页
  文案指向已改名的主页入口。
- 剩余风险主要是构建/提交边界（非 Agent 代码依赖尚未提交的 Agent 文件、
  `flutter_secure_storage` 未做 Gradle 构建验证）以及 MDict worker 的新命令与
  交互查词共用队列。

## 1. 已确认问题

| ID | 问题 | 证据 | 影响 / 修复 |
|---|---|---|---|
| R1 | MeCab 设备测试仍点旧主页「输入文本」 | `integration_test/mecab_android_test.dart:195` 使用 `find.text('输入文本')`；主页按钮已改为「查句子」 | 该测试 seed 了 UniDic 路径，会直接落到主页，tap 找不到 widget，后续阅读器/注音 E2E 中断。改为 `查句子`。 |
| R2 | MDict 设备测试仍点旧主页「查词」 | `integration_test/mdict_android_test.dart:290` 使用 `find.text('查词')`；主页按钮已改为「查单词」 | 主页→搜索→词条渲染的设备断言无法运行。改为 `查单词`。 |
| R3 | 帮助页文案指向不存在的主页入口 | `lib/features/settings/help_page.dart:67` 写“可在主页「语料」中查看” | 主页入口现为「历史记录」；语料页标题仍为「语料」。用户按帮助找不到入口。改为“主页「历史记录」”。 |

> `test/widget_test.dart` 与 `test/reader_save_test.dart` 已同步新文案；上述两个
> `integration_test/` 与帮助页遗漏。

## 2. 行为变化 / 需要验证的风险

| ID | 变化 | 风险 | 建议 |
|---|---|---|---|
| R4 | `lookup_actions.dart:21` 先等待 `mdictServiceProvider.future`，再让 `LookupGateway` 校验可用词典 | 旧代码先校验再启动 MDict；零可用词典时现在可能先启动/等待 worker，极端情况下 30s 超时错误替代友好提示。主要影响 `entry://` 路径 | 低风险；可在 `performLookup` 先做 selection 校验，或接受现状。 |
| R5 | `mdict_worker.dart` 新增 `sample`/`suggest` 命令，与交互查词共用同一 worker FIFO | 词典熟悉期采样可能让搜索短暂排队；单测不可见 | 设备上验证大词典 Familiarization 与搜索并发时的延迟。 |
| R6 | `mdict_worker.dart` 新增 `package:html`（worker isolate 内解析样本） | 少量启动/内存开销 | 设备冷启动/内存观察；样本有界（≤12 条）。 |
| R7 | 非 Agent 代码硬依赖未提交的 Agent 文件：`lib/app.dart`、`settings_store.dart`、`mdict_worker.dart` | 若 Agent 文件未一起提交/编辑中断，整个应用无法编译 | 提交时把 Agent 依赖作为同一变更集；不要把非 Agent 文件单独回滚。 |
| R8 | `flutter_secure_storage ^11.2.0` 新增 | 仅 Agent 使用；minSdk 26/AGP 8.11.1 看起来兼容，但未跑 Gradle build | 在另一 session 完成后跑 `flutter build apk --debug`，确认插件注册/启动。 |
| R9 | 主页 `ListView` → `SingleChildScrollView + Column` | 7 个 children 全部 eager 构建（可忽略）；滚动/导航测试已更新 | 小屏/横屏手工确认五按钮和两张卡片可滚动。 |

## 3. 未发现回归 / 安全区域

- OCR/拍照/照片集/多选/语料、`HistoryStore`：无 tracked diff。
- `MdictService.lookup` worker 分支、`EntryRenderer`、`EntryPage`、搜索页、
  词典管理：查词处理路径未改；`MdictService` 只是实现 `LookupBackend` 并新增
  命令分支。
- MeCab/UniDic 服务：未改。
- 读者页：未改；`reader_save_test` 仅同步主页文案。
- 主题：`app_tokens.dart` 变更严格为新增（`AgentTokens`），未删除/修改既有值。
- 导航/引导/设置：既有路由与 onboarding 未改；设置页只新增「词典助手」分区。
- 共享工具：`htmlToPlainText` 未改；新增的 `cleanDictionaryText` 仅 Agent 使用，
  正则只清理 C0/C1 控制字符、PUA U+E000–U+F8FF 与 U+FFFD，不涉及 CJK。
- `LookupGateway` 保留词典顺序、候选默认值与 `enabled && isAvailable` 过滤。

## 4. 验证状态与后续动作

- 已验证：`flutter analyze` → **No issues found**；`dart format --output=none`
  解析改动过的非 Agent 文件通过（AgentPage 有格式漂移，属于 Agent）。
- **未验证**：完整 `flutter test`、`flutter build apk --debug`、设备
  `integration_test`。原因是另一个 session 正在工作；完成后必须补跑。
- 建议修复顺序：
  1. 修 `integration_test/mecab_android_test.dart:195` 与
     `integration_test/mdict_android_test.dart:290` 的主页文案；
  2. 修 `help_page.dart:67` 的「语料」→「历史记录」；
  3. 另一 session 完成后跑完整 analyze/test/debug build；
  4. 设备上验证 MDict 查词与 `sample`/`suggest` 并发、OCR/语料回归。

## 5. 状态更新（2026-10-31）

| ID | 状态 | 说明 |
|---|---|---|
| R1 | fixed + device verified | `integration_test/mecab_android_test.dart` 已改为「查句子」；x86_64 设备 4/4 通过 |
| R2 | fixed (label) | `integration_test/mdict_android_test.dart` 已改为「查单词」并补 onboarding 种子；设备 5/6 通过，最后一个搜索页断言未找到 `とうきょう【東京】`，与 R2 文案无关，未改非 Agent 搜索逻辑 |
| R3 | fixed | `lib/features/settings/help_page.dart` 已改为「历史记录」 |
| R4–R9 | open | 等待完整 analyze/test/debug build 与设备回归；本表只记录状态，不改上述评审结论 |

## 6. 2026-10-31 实机反馈中的非 Agent 项

以下两项来自用户实机反馈，已在
[device-feedback-2026-10-31.md](device-feedback-2026-10-31.md) 的 Wave 1 中安排；
本文件只登记，不改变 R1–R9 的原始评审结论。

| ID | 问题 | 状态 / 修复方向 |
|---|---|---|
| F15 | 词条内容页的 `entry://` 跳转使用全局词典选择与全局匹配模式，而不是当前词条所在词典 | fixed (unit)：`entryLinkLookupRequest` 限定当前词典 + exact；`EntryPage` 传当前 tab 的词典；设备词条跳转待验 |
| F16 | OCR 模型后台下载时离开模型页，返回后无进度提示 | fixed (controller unit)：应用级 `ocrModelDownloadControllerProvider` 保存进度/取消/完成；`ModelPage` 订阅；设备下载页返回待验；未改下载校验/镜像/`.part` |

> 这两项会修改非 Agent 代码，但属于用户明确要求；实施时仍要跑 MDict 查词/词条
> 渲染和 OCR 模型下载回归，不得顺手改变查词选择全局偏好或模型下载语义。
