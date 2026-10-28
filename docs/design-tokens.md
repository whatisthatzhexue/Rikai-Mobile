# Rikai-Mobile 设计 Token 规范

> 版本 1.0 · 2026-10-27
> 状态：**强制规范**。所有现有与后续 UI（含 Phase 2+）必须遵循本文件；
> 功能设计与 UI 设计同步进行时以此为准。
>
> 实现：`lib/core/theme/app_tokens.dart`（token）与 `AppTheme.light()`
> （Material 3 主题）。页面中不得硬编码颜色、字号、间距、圆角。

## 1. 视觉方向

- **蓝 / 白**：白色内容面 + 浅灰蓝页面底色 + 品牌蓝交互色。
- **紧凑直观**：4pt 间距体系，常规控件高 40dp，列表与卡片低留白。
- **阅读优先**：正文清晰、层级克制；不使用的装饰性阴影和大面积渐变。
- **平面分层**：1px 边框代替阴影；卡片白底、圆角 12。
- **单一光源**：每屏一个主操作（品牌蓝实心按钮），其余操作用描边/文字按钮。
- 当前版本**只提供浅色主题**；深色主题不属于 v1 规范，后续如需加入必须先扩展
  token 表，不得在页面里临时反色。

## 2. 色彩 Token

| Token | 值 | 用途 |
|---|---|---|
| `AppColors.blue50` | `#E8F1FF` | 选中背景、浅色标签、注音词背景 |
| `AppColors.blue100` | `#D4E4FF` | 悬浮/选中态、进度轨道 |
| `AppColors.blue500` / `primary` | `#0052D9` | 主操作、链接、焦点、Tab 指示器 |
| `AppColors.blue600` / `primaryPressed` | `#0046B8` | 主按钮按下态 |
| `AppColors.blue700` / `onPrimaryContainer` | `#003A99` | 蓝底浅色容器上的文字 |
| `AppColors.surface` | `#FFFFFF` | 卡片、AppBar、输入框、底部弹层 |
| `AppColors.background` | `#F5F7FA` | 页面底色 |
| `AppColors.surfaceMuted` | `#F0F4F9` | 未选中标签、次级容器 |
| `AppColors.header` | `#003A99` | 主页品牌顶栏、抽屉顶部 |
| `AppColors.onHeader` | `#FFFFFF` | 品牌顶栏上的文字/图标 |
| `AppColors.textPrimary` | `#181818` | 正文、标题 |
| `AppColors.textSecondary` | `#5C6470` | 说明、列表副标题、图标 |
| `AppColors.textTertiary` | `#8A929E` | 占位符、辅助提示 |
| `AppColors.border` | `#DCE3EC` | 卡片/输入框边框 |
| `AppColors.divider` | `#EDF1F6` | 分割线 |
| `AppColors.error` | `#D54941` | 错误、删除 |
| `AppColors.warning` | `#E37318` | 警告 |
| `AppColors.success` | `#2BA471` | 成功、已授权 |

规则：

- 品牌蓝只用于**可交互/重点**元素，不用于大面积正文背景。
- 正文与背景对比度 ≥ 4.5:1；次要文字 ≥ 3:1。
- 不使用 Material 默认紫色、绿色系 seed 色；不使用随机的 `Colors.*`。
- 错误/成功同时配合图标或文字，不能只靠颜色表达。

## 3. 字体与字号

- 字体家族：**HarmonyOS Sans SC**，Regular（400）。
- 资源路径：`assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`。
- **字体文件不入库**：由使用者自行从华为 HarmonyOS 设计资源下载，说明见
  `assets/fonts/README.md`。构建前必须放置到上述路径，否则 Flutter 构建失败。
- 当前仅提供 Regular。层级通过**字号 + 颜色 + 留白**建立，不依赖多种字重；
  后续若加入 Medium/Bold，必须同步更新 `pubspec.yaml`、`app_tokens.dart` 和本表。
- 用户可在左侧抽屉的“自定义字体”中切换 **HarmonyOS Sans（内置）** 与
  **系统默认**；默认是 HarmonyOS Sans。字体文件不入库，见第 9 节。

### 3.1 字号组合（72 / 48 / 36）

设计稿按 **3x** 标注；Flutter 逻辑字号为设计 px ÷ 3：

| Token | 设计稿 | Flutter | 行高 | 用途 |
|---|---:|---:|---:|---|
| `AppTypography.display` | 72px | **24sp** | 1.25 | 首页主标题、空状态标题、词条页大标题 |
| `AppTypography.headline` | 48px | **16sp** | 1.5 | 正文、列表标题、按钮、输入文字、Tab |
| `AppTypography.title` | 36px | **12sp** | 1.5 | 辅助说明、标签、时间、路径、错误详情 |

> 注意：72/48/36 是 3x 设计稿标注，不是 Flutter 直接使用的 sp。移动端直接使用
> 72sp/48sp/36sp 会破坏布局，禁止。

- 标题/按钮使用 16sp 与语义色；24sp 只用于页面级重点，不用于列表项。
- 12sp 仅用于辅助信息，正文不得低于 16sp。
- 默认 `letterSpacing: 0`；中文标签不使用负字距。

### 3.2 阅读区字号（内容例外）

阅读区正文是用户可调内容，不属于 UI chrome：

- 范围 14–30sp，默认 **20sp**（`AppTypography.readerDefault`）。
- 行高 1.6；振假名字号为主字号的 **55%**（`furiganaRatio`）。
- 标点/空白不显示注音；内容词高亮，功能词弱化。

### 3.3 词典 WebView

- 词条正文：白色背景、`font-size: 16px`、`line-height: 1.7`、页面内边距 16px。
- 保留词典自带 CSS；图片 `max-width: 100%`。
- 应用外壳（AppBar、Tab）使用本 token；WebView 内容保持词典原貌。

## 4. 间距、尺寸、圆角、边框

### 4.1 间距（4pt 基线）

| Token | 值 | 用途 |
|---|---:|---|
| `AppSpacing.xxs` | 2 | 图标与文字微调 |
| `AppSpacing.xs` | 4 | 标签内边距、行内间隔 |
| `AppSpacing.sm` | 8 | 组件内间距、列表元素间隔 |
| `AppSpacing.md` | 12 | 输入框内边距、按钮间距 |
| `AppSpacing.lg` | 16 | 页面左右边距、卡片内边距 |
| `AppSpacing.xl` | 24 | 章节间距、页面上下留白 |
| `AppSpacing.xxl` | 32 | 空状态上下留白 |

页面默认 `padding: 16`；卡片内 `padding: 12–16`；同组控件间距 8；章节间距 24。

### 4.2 组件尺寸

| Token | 值 | 说明 |
|---|---:|---|
| `AppSizes.appBar` | 52 | 紧凑 AppBar 高度 |
| `AppSizes.control` | 40 | 按钮、图标按钮最小高度/触控区 |
| `AppSizes.field` | 44 | 输入框目标高度 |
| `AppSizes.chip` | 28 | 标签/Chip 高度 |
| `AppSizes.iconSmall` | 16 | 行内小图标 |
| `AppSizes.icon` | 20 | 常规图标 |
| `AppSizes.iconLarge` | 24 | 重点图标 |
| `AppSizes.emptyIcon` | 40 | 空/错误状态图标 |
| `AppSizes.heroIcon` | 48 | 页面级空状态图标 |
| `AppSizes.homeActionHeight` | 72 | 主页功能按钮高度 |
| `AppSizes.homeActionIcon` | 28 | 主页功能按钮图标 |
| `AppSizes.pageMaxWidth` | 720 | 平板/横屏内容最大宽度 |

触控目标不小于 40×40dp；列表行最小高度 56dp。

### 4.3 圆角与边框

| Token | 值 | 用途 |
|---|---:|---|
| `AppRadius.sm` | 6 | 标签、TokenChip |
| `AppRadius.md` | 8 | 按钮、输入框、菜单 |
| `AppRadius.lg` | 12 | 卡片、对话框 |
| `AppRadius.xl` | 16 | 底部弹层顶部 |
| `AppRadius.pill` | 999 | 胶囊标签（少用） |
| `AppSizes.borderWidth` | 1 | 统一边框 |

- 卡片：白底 + `#DCE3EC` 1px 边框 + 12 圆角，**无阴影**。
- 浮层/菜单：白底 + 1px 边框 + 8 圆角；不使用重投影。

## 5. 组件规范

### AppBar
- 高 52，白底，底部 1px 分割线，标题 16sp 主文字色，左对齐。
- 图标 20，颜色 `textSecondary`；主操作可改品牌蓝。
- 不使用 elevation/滚动阴影。
- **主页品牌顶栏**是唯一例外：深蓝 `#003A99` 背景，白色菜单图标（左）、
  居中白色“主页”（16sp/600）、白色设置图标（右），无底部分割线。
  抽屉顶部同样使用深蓝背景、应用图标与白色文字。

### 主页功能按钮
- 四个全宽实心品牌蓝按钮：拍照识别、输入文本、查词、语料。
- 高度 72，圆角 12，白图标 28 + 白色文字。
- 文字 40sp、行高 1.35（行盒 54 ≈ 按钮高度的 75%），600 字重。
- 不使用副标题；按钮之间的间距为 12。

### 按钮
- 主按钮：品牌蓝底、白字、16sp、高 40、圆角 8、水平内边距 16。
- 次按钮：白底、1px 边框、品牌蓝字、同尺寸。
- 文字按钮：品牌蓝字，无底色，最小 40 高。
- 禁用：主色 35% 透明度；不要仅靠灰色文字表达禁用。
- 一屏最多一个主按钮；危险操作使用错误色描边/文字。

### 输入框
- 白底、1px `border`、圆角 8、内容内边距 12。
- 聚焦：品牌蓝 1.5px；错误：错误色 1.5px。
- 标签 12sp `textSecondary`；占位符 16sp `textTertiary`。
- 多行输入保持 16sp；不使用 12sp 正文。

### 卡片
- 白底、12 圆角、1px 边框、无阴影；内边距 12–16。
- 卡片内标题 16sp；说明 12sp；标题与说明间距 8。
- 卡片可点击时使用 `InkWell`，水波纹颜色品牌蓝低透明度。

### 标签 / Chip
- 高 28，圆角 6，12sp；默认浅灰蓝底，选中蓝50底 + 蓝700字。
- 过滤类 Chip 同时提供文字/勾选状态，不只靠颜色。
- 标签文字超过一行时截断，不换行撑高。

### 列表
- 行最小高度 56，水平边距 16，垂直内边距 4–8。
- 主文字 16sp，副文字 12sp；尾部图标 20。
- 分组标题 12sp、`textSecondary`、可加大写/字距（仅英文）。

### 底部弹层 / 对话框
- 底部弹层：白底、顶部 16 圆角、拖动条 4×32、内容内边距 16。
- 对话框：白底、12 圆角、无阴影、标题 16sp、正文 16sp、按钮右对齐。
- 弹层默认高度不超过屏幕 80%；内容可滚动。

### Tab
- 标签 16sp；选中品牌蓝 + 2px 指示器；未选中 `textSecondary`。
- 多于 4 个 Tab 时允许横向滚动。

### 进度 / 开关 / 滑块
- 进度色品牌蓝，轨道蓝100（或浅灰蓝）。
- 开关选中品牌蓝；滑块激活品牌蓝。
- 加载状态必须有文字说明（例如“正在加载 UniDic…”），不能只有转圈。

### 阅读器 TokenChip
- 内容词：蓝50背景、蓝700文字、6 圆角、内边距 4×2。
- 功能词：透明背景、`textSecondary`。
- 标点/空白：无背景、无点击、无注音。
- 振假名 12sp 以下（主字号 55%），`textSecondary`。
- 点击目标至少 40 高；Wrap 间距 2/8。

### 空状态 / 错误状态
- 居中；图标 40–48，标题 24sp（页面级）或 16sp（局部），说明 12sp。
- 必须给出下一步操作（重试 / 打开设置 / 添加词典），不能只有错误文字。

### 查词结果
- 点击单条结果只进入该词条页面，不混合显示其他搜索结果。
- 同一词典结果 ≥2 条时，在该词典结果列表最前面显示“查看全部（N 条）”；
  点击后只显示该词典下该词的全部词条。
- 多词典默认每本最多显示的词条数由“阅读显示 → 每词典词条上限”控制，
  默认无限制。

## 6. 组件库与 TDesign

- 允许使用 **TDesign Flutter** 作为组件库；当前实现使用 Material 3 +
  本 token 主题，**同一页面不得混用两套组件库**。
- 若后续接入 `tdesign_flutter`，按下表映射，且以本文件为准：

| 本规范 | TDesign 变量 / 组件 |
|---|---|
| `primary #0052D9` | `--td-brand-color` |
| `error #D54941` | `--td-error-color` |
| `success #2BA471` | `--td-success-color` |
| `background #F5F7FA` | `--td-bg-color-page` |
| `surface #FFFFFF` | `--td-bg-color-container` |
| `textPrimary/Secondary/Tertiary` | `--td-text-color-primary/secondary/placeholder` |
| 24 / 16 / 12sp | `--td-font-size-*`（24/16/12 映射） |
| 40 高按钮 | `TButton` medium |
| 44 高输入框 | `TInput` medium |
| 28 高标签 | `TTag` medium |
| 12 圆角卡片 | `TCell`/容器样式 |

- 接入 TDesign 时，必须同时调整 `AppTheme` 与本文档，避免两套 token 漂移。

## 7. 已完成的 UI 适配

Phase 1 及之前的页面（首页、文本阅读、设置、TokenChip、底部详情）已通过
`AppTheme.light()` 与 token 统一：

- 首页：深蓝品牌顶栏 + 白色图标、左侧抽屉、四个大号蓝色功能按钮、
  “使用前须知”卡片；移除了冗长的介绍文字。
- 阅读页：白色阅读面、蓝色内容词、紧凑工具栏；正文按用户字号；
  输入草稿在应用存活期内保留。
- 设置页：MDict → 阅读显示 → UniDic → 存储权限；卡片化、12 圆角、
  1px 边框、紧凑列表；路径可用系统文件管理器选择。
- 词条页：单结果只显示该词条；多词条时“查看全部”。
- 底部弹层/对话框：白底、16 圆角、无阴影。
- 启动页：居中应用图标 + 实际加载阶段文字（主界面/已安装词典/分词）。

新增 Phase 2+ 页面（搜索、词条、词典管理）必须直接使用：
`AppColors` / `AppTypography` / `AppSpacing` / `AppRadius` / `AppSizes` 与
`Theme.of(context)` 的文本样式，不得复制数值。

## 8. 自查清单（每个 UI PR）

- [ ] 没有硬编码 `Color(0x...)` 或 `Colors.xxx`（除透明/白色数据占位）。
- [ ] 字号仅来自 token；阅读正文除外（用户设置）。
- [ ] 间距为 4 的倍数；页面边距 16；卡片圆角 12。
- [ ] 主按钮不超过一个；危险操作使用错误色语义。
- [ ] 触控目标 ≥ 40×40；无只靠颜色传达的状态。
- [ ] 加载态有文字；空/错误态提供下一步操作。
- [ ] 中文字体使用 HarmonyOS Sans SC；字体文件未被提交。
- [ ] 与 `app_tokens.dart` 一致；若新增 token，先更新本文件与实现。

## 9. 字体获取

字体不在仓库中。构建前：

1. 从华为 HarmonyOS 设计资源下载 HarmonyOS Sans（SC Regular）。
2. 放置为 `assets/fonts/HarmonyOS_Sans_SC_Regular.ttf`。
3. 运行 `flutter pub get` 与构建；缺失时构建会报 asset 错误。

详见 `assets/fonts/README.md`。字体由使用者自行下载，项目不再分发。
