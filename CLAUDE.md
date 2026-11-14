# CLAUDE.md — LexiCandy Agent 入口

> 本文件只做 Agent 入口、命令白名单和禁令指针。业务、架构、规则、数据细节一律以
> `docs/` 为唯一权威；发现冲突时修正低权威文档，不在这里复制规则正文。

## 1. 先读

1. [`docs/README.md`](docs/README.md)：文档索引、权威层级、目录收录规则。
2. [`docs/01-规范/项目规则.md`](docs/01-规范/项目规则.md)：`R-*` 规则单一来源。
3. [`docs/01-规范/协作规范.md`](docs/01-规范/协作规范.md)：分支、提交、评审、分工。
4. [`docs/07-维护/项目结构.md`](docs/07-维护/项目结构.md)：仓库与 `app/` 结构。
5. [`docs/01-规范/项目数据.md`](docs/01-规范/项目数据.md)：测试/设备/构建/预算/固定文案。
6. [`docs/03-进度/`](docs/03-进度/)：当前实现状态、设备反馈、执行路线。
7. [`docs/04-历史/原始需求/LexiCandy阶段/`](docs/04-历史/原始需求/LexiCandy阶段/)：当前定位。

## 2. 仓库结构

- `app/`：Flutter 客户端唯一构建入口；`android/`、`assets/`、`lib/`、`test/`、
  `integration_test/`、`packages/`、`tool/` 都在这里。
- `supabase/`、`worker/`：`[planned]`，未创建；落地前先看 `docs/` 并取得人工确认。
- `docs/`、`tool/`、`third_party/`、`data/`：仓库级支撑目录。
- `third_party/` 不参与构建；`data/` 是本地开发/用户数据，不打包。
- `[active]` Agent 可改；`[planned]` 需人工确认；`[ignored]` 不入库；`[archive]` 只读。

## 3. 命令白名单

**在仓库根目录：**

```powershell
dart tool/check_docs.dart              # 文档检查
dart tool/verify.dart                  # check_docs + app analyze + app test
dart tool/verify.dart --build          # 再加 app debug APK
```

**在 `app/` 目录：**

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
dart run flutter_launcher_icons        # 修改图标后
dart tool/spike_mdict.dart             # App 专用 spike
```

- 根目录不直接跑 Flutter；Flutter 命令统一在 `app/` 下执行，或由 `tool/verify.dart`
  编排。
- 设备端测试、模拟器、`adb push`、Gradle/网络排障：见
  [`docs/05-参考/开发环境与构建.md`](docs/05-参考/开发环境与构建.md)。
- 构建前按 [`app/assets/fonts/README.md`](app/assets/fonts/README.md) 放置字体；
  模型/字体/词典/UniDic/Key 不入库。

## 4. 禁令指针

- 不修改 `[planned]`、`[ignored]`、`[archive]`；只改 `[active]`。
- 不擅自 commit/reset/push，除非用户明确要求（R-DEV-03）。
- 不把图片、base64、路径、文件名或 API Key 发给 LLM/Worker；Key 只存
  Secure Storage（R-PROD/R-SEC）。
- 不把未实现能力写成已支持；真实 provider/API Key、secure storage、arm64 Agent、
  真机视觉未验收前不得写“已验证”（R-AGENT-17）。
- 不重写已验证的 Paddle 横向 OCR、MangaOCR 基础流水线、UniDic/MDict 核心路径；
  修改前先读 [`docs/04-历史/项目历史.md`](docs/04-历史/项目历史.md)。
- `docs/04-历史/原始需求/` 只读，不回填当前值。

## 5. 身份与兼容名

- Flutter 包名：`lexicandy`；Android applicationId/namespace：
  `com.lexicandy.mobile`。
- 默认显示名 `LexiCandy`；简体中文显示 `释书糖`。
- 兼容名暂保留：`rikai_ocr`、`RikaiOcr`、`rikai.agent.*`、`rikai_agent.db`；
  改名先写 ADR/迁移方案。

## 6. 遇到问题

先查 [`docs/01-规范/误区与踩坑.md`](docs/01-规范/误区与踩坑.md) 的症状表，再按
`T-###` 阅读；不要在本文新增误区正文。
