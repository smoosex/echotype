# AGENTS.md

本文件定义本仓库内所有 AI Agent 的协作规则。

## 1. 任务来源与状态管理

任务清单见 [docs/development_process.json](docs/development_process.json)。

每次开始任务前必须：

- 选择一个任务 `id`
- 将该任务 `status` 从 `pending` 改为 `in_progress`

每次完成任务后必须：

- 将该任务 `status` 改为 `completed`
- 若出现新增工作，补充新任务（保持字段：`id/title/description/status`）

允许的状态值只有：

- `pending`
- `in_progress`
- `completed`

## 2. 执行顺序约束

- 必须优先完成 P0 技术验证相关任务，再进入后续 Sprint。
- 涉及文本注入时，必须先保证 L1（复制到剪贴板）稳定，再做 L2（自动粘贴）。
- 任何功能实现都需要包含错误路径处理，不允许只实现成功路径。

## 3. 代码与架构约束

- 使用 Swift + SwiftUI 作为主栈。
- 模块边界固定为：`AppShell/UI`、`HotkeyService`、`AudioService`、`STTService`、`TextInjectionService`。
- 禁止上传音频或转写文本到外部服务（除非用户明确提出并修改计划）。
- 默认不持久化原始录音文件。

## 4. 提交与文档同步

每次交付需同步以下内容：

- 改动说明（做了什么、为什么）
- 对应任务 `id`
- 验证方式（命令、结果、已知限制）

如果改动影响计划或范围，必须同步更新：

- `docs/development_process.json`

## 6. 完成定义（DoD）

一个任务可标记为 `completed` 的最低标准：

- 功能可运行或文档可用
- 至少有一次实际验证记录
- 错误处理路径已考虑
- 相关文档已更新
