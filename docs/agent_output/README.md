# Agent 输出质检样本（docs/agent_output）

本目录保存 Agent 一次运行的实际输出，供后续质检、回归对比和 prompt/管线评审使用。
它不是模型原始响应，也不是 provider 请求日志。

## 文件命名

```text
YYYY-MM-DD-HH-mm.txt
```

- 年 4 位、月/日/时/分各 2 位，使用本机本地时间；例如
  `2026-11-02-19-53.txt`。
- 每个文件是结果区“复制结果为 Markdown”得到的 Markdown 文本（与
  `buildAgentResultMarkdown` 同源）。
- 不放入图片、图片路径、base64、API Key、请求体或 provider 原始响应。
- 一次运行一个文件；新增样本时不要改写已有文件，以便后续对比。

## 使用方式

- 人工检查译文、逐句理解、可能的理解、未解决项、词典依据和 citation 顺序。
- 发现管线问题时，先按 `docs/project_tips.md` 的 `T-###` 定位管线/解析器原因，
  不要直接把展示要求写进 prompt；只有确认管线无法表达该语义时才改 prompt。
- 样本文件不参与构建；目录本身不作为运行时资源。
