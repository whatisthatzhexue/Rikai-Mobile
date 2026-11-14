# App 专用脚本

> 状态：当前实现（App 工具）｜最后同步：2026-11-14

本目录只放 App 专用脚本，不放仓库级编排；仓库级命令在根 `tool/`。

- `spike_mdict.dart`：MDict 主机 spike，在 `app/` 下运行。
- `perf/`：[planned] 性能采集/汇总脚本；未启用前不要依赖。

Flutter/Dart 命令在本目录（`app/`）执行；根目录不直接跑 Flutter。
