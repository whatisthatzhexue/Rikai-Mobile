# App（Flutter 客户端）

> 状态：当前实现（App 子项目）｜最后同步：2026-11-14

## 职责

Android 单端 Flutter 客户端：阅读、写作、社区、个人四页；本地 OCR、UniDic 分词、
MDict 查词、Agent 编排与语言插件宿主。核心阅读/查词必须离线可用；云端能力是可选项。

## 构建

在本目录执行（根目录不直接跑 Flutter）：

```powershell
flutter pub get
flutter analyze
flutter build apk --debug
```

构建前按 `assets/fonts/README.md` 放置 HarmonyOS Sans SC Regular 字体。修改
`assets/LexiCandy_Icon.jpg` 后运行：

```powershell
dart run flutter_launcher_icons
```

## 测试

```powershell
flutter test
flutter test integration_test
```

单元/widget 测试在 `test/`；设备/模拟器集成测试在 `integration_test/`。性能场景归
`integration_test/performance/`（[planned]，未启用前不要依赖）；采集/汇总脚本归
`tool/perf/`（[planned]）。

## 目录

- `android/`：Android 宿主、Kotlin、Manifest、资源。
- `assets/`：打包资源；`models/manifest.json` 是唯一打包模型清单。
- `lib/`：`core/`、`services/`、`state/`、`features/`。
- `packages/`：本地基础设施包与契约；`rikai_ocr`、`mecab_for_dart` 已启用。
- `plugins/`：语言插件实现（[planned]，未启用）。
- `test/`、`integration_test/`：测试。
- `tool/`：App 专用脚本；仓库级编排在根 `tool/`。

## 边界

- 不 import `supabase/` 或 `worker/` 源码；只通过 HTTP/契约通信。
- `app/packages/` 只放契约与基础设施；`app/plugins/<lang>/` 只放语言插件实现。
- 不把图片、路径、API Key 发给模型；Key 只存 Secure Storage。
- 具体规则、数据、设计 token 以 `docs/` 为唯一权威，不在本文件复述。

## 文档

- [文档索引](../docs/README.md)
- [项目规则](../docs/01-规范/项目规则.md)
- [项目数据](../docs/01-规范/项目数据.md)
- [设计规范](../docs/01-规范/设计规范.md)
- [项目结构](../docs/07-维护/项目结构.md)
- [开发环境与构建](../docs/05-参考/开发环境与构建.md)
