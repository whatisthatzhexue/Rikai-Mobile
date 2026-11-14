# Fonts

LexiCandy 内置 **Kiyosuna Sans（KT Kiyosuna Sans）** 作为界面默认字体。两个
字重文件随仓库提交，位于：

```text
app/assets/fonts/KiyosunaSans/KiyosunaSans-L-1.0.1.otf   # Light，默认正文（Flutter 400）
app/assets/fonts/KiyosunaSans/KiyosunaSans-B-1.0.1.otf   # Bold，标题/强调（Flutter 700）
```

Light 文件以 400 注册，因此默认正文直接使用细版；Bold 以 700 注册。字体家族名在
`pubspec.yaml` 中为 `KT Kiyosuna Sans`。

## 来源

- 下载页：<https://booth.pm/zh-cn/items/5389901>
- 设计：WATANABE Reiya
- 衍生自 Zen Kaku Gothic（Yoshimichi Ohira）
- 版本：1.0.1（2024-01-03）

## 许可

Kiyosuna Sans 使用 **SIL Open Font License 1.1**，Copyright (c) 2024
WATANABE Reiya，保留字体名称 `KT Kiyosuna Sans` / `KTきよすなゴシック`。
完整许可文本、署名与再分发说明见
[`KiyosunaSans/README.md`](KiyosunaSans/README.md)。

字体文件随 LexiCandy 一起分发，不单独售卖；修改版本不得使用保留字体名称。

## 构建行为

`app/pubspec.yaml` 声明 `KT Kiyosuna Sans` 的两个字重。字体已入库，不需要手动
下载；构建前只需在 `app/` 下运行 `flutter pub get`。如果替换字体文件，必须同步
更新 `KiyosunaSans/README.md` 并保留 OFL 许可与署名。

如确需重新获取字体，可从上面的 Booth 下载页下载；仓库内的两个字体文件为
v1.0.1，未修改。
