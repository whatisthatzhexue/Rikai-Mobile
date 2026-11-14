# 释书糖 / LexiCandy

> 本地优先、证据可追溯、可定制的多语深读与写作工作台。
> 像吃糖一样轻松啃下原版书。

**A local-first, evidence-traceable, customizable deep-reading and writing
workbench for foreign-language books.**

## 0. 当前状态（先读）

LexiCandy 是项目转型后的产品定位；仓库里的可运行代码仍是 **Rikai 阶段**的
Android 日语阅读基线。两者不是同一件事，不能把规划写成已支持。

| 能力 | 当前状态 |
|---|---|
| 端侧 OCR（PaddleOCR 横向 / MangaOCR 纵向）、UniDic 分词、MDict 查词与词条渲染 | 已实现；Rikai 1.0 已发布，当前为 1.1 工作区 |
| 文本阅读、照片集、点击查词、词典管理、语料/历史、首次引导、设置、arm64 release 构建 | 已实现 |
| 可选词典助手（固定流水线、证据/citation、严格/宽松、历史、声调、annotation v1、受限 Markdown 预览） | 部分实现；完整 text/group DSL、发布与真机视觉验收待做 |
| LexiCandy 阅读三 Tab（知识/读音/理解）、批注、术语库、内置电子书 | 规划 |
| LexiCandy 写作页、AI 差异教练、写作引子、内置输入法 | 规划 |
| 社区、个人成长曲线、学习快照 | 规划 |
| Supabase 用户数据、Python Worker、插件系统、多语种 | 架构规划；代码尚未落地 |

当前已验证/未验证的边界见
[项目数据](docs/01-规范/项目数据.md) 与
[阶段 6 实现状态](docs/03-进度/阶段6实现状态.md)；真实 provider/API Key、
secure storage、arm64 Agent、真机视觉等仍不能写成已验证。

## 1. 产品定位

**释书糖 / LexiCandy** 致敬“物书堂”，寓意像吃糖一样轻松啃下原版书。它不是
又一个背单词或翻译 App，而是承载用户“阅读—写作—社区”闭环的深读工作台：

- **阅读（消费）**：拍下实体书或打开内置电子书，OCR、分词、词典与 Agent
  解析在同一个阅读界面里完成。
- **写作（生产）**：从阅读一键滑入写作；AI 差异教练按句分析语法与词典依据，
  让用户敢写、写得地道。
- **社区（社交）**：把批注、Agent 解答、术语库变成可分享、可复用的学习资产。
- **个人成长**：后台静默记录学习内容，按周生成词汇/语法覆盖度与成长曲线。

日语是落脚点和调研起点；工程上从一开始就为英语等其他语种预留插件接口。

## 2. 四个页面

### 2.1 阅读 Read：沉浸式解构

- 可阅读 App 内置电子书、用户实体书的 OCR 结果，以及做基本文字提取的纯文字 PDF。
- 首次启动无需配置，直接展示预存示例实体书与解析效果，引导用户拍下第一张实景照片。
- 创建书籍时选择竖排或横排；阅读中支持波浪线、高亮批注。
- 点击句子弹出该句读音（日语场景）与操作小气泡，气泡含三个 Tab：
  - **知识**：细粒度到词，优先本地词典匹配，可询问 Agent 语境义；
  - **读音**：细粒度到句/语境，从词典与分词器获取权威读音，可询问 Agent 整体读音；
  - **理解**：细粒度到句/语境，优先分词器结构分析，支持 Agent 句内/句间分析。
- 段落有显式“总结”按钮；Agent 给出若干语境相关备选项，用户点击后展开对应解答。
- 术语库：边读边标记“文化梗/专有名词”，即时生效；支持用户上传术语库，支持
  “防剧透内容折叠”，并明确内容责任与侵权风险。
- 结构三级平面图（批注式 UI）：
  1. **句**：原书照片的 OCR 重叠排版，无感翻页；
  2. **词/语法**：点击弹出本地 MDict 与分词结构，所见即所点；
  3. **知识关联**：句子关系图、音调读法表、可溯源的 Agent 解析。

### 2.2 写作 Write：无打断的生产

- 阅读页与写作页一键互相滑入；App 生命周期内各自缓存当前内容。
- “开始撰写感想”按“最近批注 → 最近的书（阅读进度 + 内容节选）→ 日常练习”
  生成写作引子；引子自动作为新文章标题，可修改。
- 支持竖排/横排、多颜色框选、波浪线、荧光笔批注。
- 内容输入支持 OCR、手写（实质也是 OCR）与手动输入；默认系统键盘，也可切换
  App 内置输入法。
- **AI 差异教练**：静默记录写作草稿，按句子闭合触发分析，用 GitHub 风格 Diff
  展示语法纠错与词典依据。
- **内置输入法**（规划）：26 键布局，支持纯日语与中日模糊语种输入；罗马音 +
  拼音混合输入，根据词典与分词器判断候选；长按出现变形/活用候选；三大支柱为
  手动分词符、模糊语种、变形输出。输入法不走 Agent，以词典 + 分词器为权威源。

### 2.3 社区 Community：语境化分享

- 发布写作批注历史、Agent 解答结果、个人书籍术语库。
- 敏感词库 + 举报后的 AI 质检（Worker + 开发者 Key）兜底内容风险。
- 主题文章分享精读批注、语法推敲轨迹。
- 社区术语表默认折叠解释，拍书即可一键加载，防止剧透。

### 2.4 个人 About Me

- **成长曲线**：后台静默记录生词与语法，按周生成词汇覆盖度报告。
- **学习快照**：一键回到上次阅读的特定页码与状态。
- 设置：高级能力放在深层设置，普通用户保持零配置前台。

## 3. 核心环绕功能

- **分词器**：日语使用 UniDic/MeCab；Token 模型字段可空，为其他语种留出空间。
- **词典**：MDict 单格式，保持词典设计一贯性；支持用户本地词典与服务端词典。
- **OCR**：端侧优先；日语重点优化竖排、弯曲、反光；云端可提供更强 OCR，
  但企业/隐私模式必须可完全本地。
- **Agent**：初期接用户自己的 LLM API Key，后期可加入端侧小模型；所有 AI 结论
  必须可点击回溯源图或原句。
- **术语库/批注/学习快照**：把阅读过程中的思考沉淀为可复用资产。

## 4. 架构

```text
Flutter App（阅读/写作/社区/个人）
  ├─ 端侧 OCR / 分词 / MDict / Agent 本地管线
  ├─ 本地 SQLite / Secure Storage / 用户文件
  └─ 可选：Supabase（鉴权、社区、术语表同步）
        │
Python Worker（轻量调度 + 云端 OCR + 配置分发）
  └─ 只回传 Action / OCR 结果 / 动态配置；不接触用户 API Key
```

- **本地优先**：核心 OCR、分词、查词在离线状态可用；有网时再增强体验。
- **端云分层**：用户 API Key 只存在本地 Secure Storage，由手机直连模型厂商；
  Worker 不代理、不接触 Key。
- **控制面/数据面分离**：Worker 下发 Prompt 模板与规则配置（本地有兜底），
  App 保持轻量；仅上报脱敏后的日活、失败率、词典未命中率等元数据。
- **插件系统**：分词器、Lookup Strategy、OCR 引擎、Agent Prompt 模板均按语言
  抽象；语言规则编码为文件，新增语种尽量只加插件 + 配置，而不是 if-else。
- **企业模式**：侧重本地处理，杜绝数据上云端 OCR，减少 Agent API，保证隐私。

## 5. 设计原则

- **所见即所点**：以 OCR 为中心，避免强迫用户查词典或手动输入句子；在图片上
  点击/滑动即可调出多窗口内容与 Agent 解析（写作模块除外）。
- **万物皆可溯**：AI 生成的结论点击即可高亮原图或原句。
- **软件变身**：学习用户习惯，提供学习快照，一键回到上次的学习场景。
- **个人成长**：离线静默记录学习内容，支持按时间段分析成长。
- **零配置前台，极客后台**：普通用户看不到配置项；高级能力放在深层设置。
- **细粒度、拒绝信息过载**：按“语境 → 句 → 词”分层展示，不一次性灌输。
- **不做翻译器**：LexiCandy 承载用户的思考，不是替代用户阅读的翻译工具。
- **不做应用外悬浮窗**：希望用户获得沉浸式深度体验。
- **PDF 只做基本文字提取**：核心叙事与竞争力在外文图书 OCR。
- **Agent 被动优先**：非必要不主动；用按钮/备选问题降低用户决策成本；
  无词典/分词依据的内容必须标注为模型推断；能用“图 + 文”表达的优先设计
  schema，而不是大段文字。

## 6. 当前实现（Rikai 基线）

当前仓库可运行的 Android 应用包含：

- 端侧 ONNX Runtime OCR：PaddleOCR PP-OCRv5 横向、MangaOCR 纵向、自动方向路由
  与 90°/270° 旋转；模型可下载、断点续传、SHA-256 校验、本地导入。
- UniDic/MeCab 原地读取、私有 `mecabrc`、29 字段 Token、注音与词性；用户自备
  UniDic。
- MDict worker isolate：原地读取、`@@@LINK` 重定向、NFKC/宽度/假名/stripkey
  候选、前缀建议、MDD 资源；离线 WebView 渲染并禁用 JS/网络。
- 文本阅读、照片集、多选、旋转、点击查词、词典管理、语料保存/历史、首次引导、
  设置、arm64 release 构建。
- 可选词典助手：用户配置 provider/API Key 后，固定流水线调用文本 LLM；图片只在
  本机 OCR，不上传视觉；严格模式必须引用真实词典结果，宽松模式标注模型补充。
- 助手已实现历史/声调、provider 测试连接、受限 Markdown 预览、annotation v1、
  富文本后处理、P6.8-lite 译文预览/证据缓存与 P7-lite 路由/遥测；完整 text/group
  DSL、发布与真机视觉验收仍未完成。

**尚未实现**：Read 三 Tab 的完整交互、批注/术语库、Write、AI 差异教练、内置
输入法、Community、成长曲线、Supabase、Python Worker、插件系统、多语种。
这些是 LexiCandy 方向，不是当前能力。

## 7. 仓库结构与快速开始

### 7.1 仓库结构

```text
app/          # Flutter 客户端；唯一 App 构建入口
supabase/     # [planned] 鉴权/社区/术语表
worker/       # [planned] Python Worker
docs/         # 跨子项目权威文档
tool/         # 仓库级编排；不实现 Flutter 逻辑
third_party/  # 来源/许可/修改记录；不参与构建
data/         # [ignored] 本地开发/用户数据
```

Flutter 命令在 `app/` 下执行；根目录不直接跑 Flutter。详细结构见
[项目结构](docs/07-维护/项目结构.md)。

### 7.2 快速开始

应用内置 **Kiyosuna Sans（KT Kiyosuna Sans Light/Bold）**，无需手动放置字体。
字体以 SIL OFL 1.1 随仓库分发，来源与许可见
[`app/assets/fonts/KiyosunaSans/README.md`](app/assets/fonts/KiyosunaSans/README.md)；
如需重新获取，可从 <https://booth.pm/zh-cn/items/5389901> 下载。

然后：

```powershell
cd C:\Projects\Rikai-Mobile\app
flutter pub get
cd ..

dart tool/verify.dart              # docs + app analyze + app test
dart tool/verify.dart --build      # 再加 app debug APK
```

环境/版本/SDK/NDK/模拟器基线见
[项目数据](docs/01-规范/项目数据.md) §1；设备测试、模拟器、adb、网络与 Gradle
排障见 [开发环境与构建](docs/05-参考/开发环境与构建.md)。UI 必须遵循
[设计规范](docs/01-规范/设计规范.md) 与 `app/lib/core/theme/app_tokens.dart`。

## 8. 文档

唯一入口：[docs/README.md](docs/README.md)。

- 当前定位（LexiCandy）：
  [释书糖 LexiCandy 概念](docs/04-历史/原始需求/LexiCandy阶段/释书糖LexiCandy概念.txt)、
  [项目成熟化处理](docs/04-历史/原始需求/LexiCandy阶段/项目成熟化处理.txt)
- 上一阶段归档（Rikai）：
  [采集重构需求](docs/04-历史/原始需求/Rikai阶段/采集重构需求.md)、
  [（旧）项目目标与简介](docs/04-历史/原始需求/Rikai阶段/（旧）项目目标与简介.txt)
- 规则/数据：[项目规则](docs/01-规范/项目规则.md)、
  [项目数据](docs/01-规范/项目数据.md)
- 当前实现：[阶段 6 实现状态](docs/03-进度/阶段6实现状态.md)、
  [设备反馈](docs/03-进度/设备反馈-2026-10-31.md)
- 设计与契约：[助手设计](docs/02-设计/助手/助手设计.md)、
  [助手契约](docs/02-设计/助手/助手契约.md)、
  [架构决策](docs/02-设计/架构决策/)
- 维护：[项目结构](docs/07-维护/项目结构.md)、
  [代码盘点](docs/07-维护/代码盘点.md)、
  [验证清单](docs/07-维护/验证清单.md)

## 9. 隐私与安全

- 图片只在设备本地 OCR，不作为 LLM 视觉输入，不上传原图。
- 用户 API Key 只存在 Android Secure Storage/Keystore，不进 SharedPreferences、
  日志、导出或 Git。
- Supabase 只承载鉴权、社区与术语表同步，不碰核心推理；Worker 只接收脱敏后的
  Action/OCR/配置数据，不接触用户 Key。
- 企业模式可完全本地处理；隐私政策必须写明端/云数据边界。
- 绑定规则见 [项目规则](docs/01-规范/项目规则.md) R-SEC/R-PROD/R-ARCH。

## 10. 许可

本项目改造自 overlay-translator（Apache-2.0），评估过 PaddleOCR4Android（MIT）。
MeCab/mecab_for_dart 为 BSD-3，ONNX Runtime 为 MIT。UniDic 与 MDict 词典由用户
自备，不随仓库分发。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、
[NOTICE](NOTICE) 与 [第三方许可](docs/05-参考/第三方许可.md)。

可选词典助手使用用户自备的 API Key 与远程文本 LLM；provider 条款与隐私政策适用。
LexiCandy 规划中的 Supabase/Python Worker 尚未落地，落地时需单独补充许可与隐私
说明。
