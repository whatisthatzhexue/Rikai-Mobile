# third_party

> 状态：当前参考（第三方来源）｜最后同步：2026-11-14

本目录**不参与构建**，只记录第三方来源、许可与修改说明。

- `overlay-translator/`：LICENSE / NOTICE / MODIFICATIONS。
- `paddleocr4android/`：LICENSE / README。
- `upstream/`：[ignored] 上游参考克隆，不编译、不提交。

可构建的 vendored 代码必须放到 `app/packages/`（Dart/Flutter）或
`worker/src/_vendor/`（Python）；不要在本目录放构建入口。
