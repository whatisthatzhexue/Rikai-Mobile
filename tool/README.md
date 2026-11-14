# 仓库级工具

> 状态：当前实现（仓库工具）｜最后同步：2026-11-14

本目录只做仓库级编排，不实现 Flutter/业务逻辑；App 脚本在 `app/tool/`。

```powershell
dart tool/check_docs.dart              # 文档链接/登记/命名/横幅/版本标签
dart tool/verify.dart                  # check_docs + app analyze + app test
dart tool/verify.dart --build           # 再加 app debug APK
```

`verify.dart` 只编排命令，Flutter 命令统一在 `app/` 工作目录执行。`check_docs.dart`
保持纯 `dart:io`，不依赖 App 包或根级 pubspec。
