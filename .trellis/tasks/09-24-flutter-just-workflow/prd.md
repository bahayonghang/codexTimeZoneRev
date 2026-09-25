# 适配 Flutter 版 just 工作流

## Goal

为 Flutter 0.2.0 架构提供可预测、跨 Windows/macOS 一致的仓库根目录 `just` 工作流，使开发者无需记脚本路径即可安装依赖、检查环境、预览、测试、开发运行和构建发布包。

## Background

- 上游 `v0.2.0` 已将界面从 Vue/Tauri 迁移为 `flutter_app/`，并将共享后端迁移到 `native/launcher_core/`；旧 `resource/` 应用已从当前分支删除。
- 当前 `justfile:4` 仍把工作目录固定为 `resource`，`install/dev/build/install-app` 配方仍调用已不存在的 npm 脚本，因此这些命令当前不可用。
- 上游现有入口是 `scripts/flutter-windows.ps1` 与 `scripts/flutter-macos.sh`。两者支持 `doctor/test/preview/run/build`；Windows 另有 `scripts/test-native-windows.ps1` 原生验收脚本。
- 本机已安装 `just 1.58.0`，但当前 PATH 中没有 Flutter；因此需要区分命令分发验证与需要 Flutter SDK 的端到端验证。

## Requirements

1. `just` 继续作为仓库根目录的统一入口，不再引用已删除的 `resource/`、npm、Tauri 或 Vue 路径。
2. 保留清晰的默认帮助行为，并让 Windows 与 macOS 使用各自已有的 Flutter 平台脚本。
3. 至少覆盖依赖安装、环境检查、开发预览、真实开发会话、测试和发布构建；命令名称应简短且与现有脚本动作一致。
4. `dev` 必须启动真实 Flutter 桌面开发会话，而不是 UI 预览；如提供 `preview`，必须明确使用固定演示数据且不触碰真实客户端或设置。
5. 移除已经失去实现基础的旧 `install-app` 配方；Flutter 0.2.0 继续采用上游脚本生成的 ZIP 分发方式，本任务不重新定义安装器契约。
6. Linux 等未支持平台必须明确失败，不能静默调用错误脚本。
7. 同步修正根目录、Flutter 子目录及代理指南中与 `just` 命令相关的说明；移除“just 只是 npm 包装器”的过期描述。
8. 不改变 Flutter UI、Rust 后端、发布工作流或产品功能；本任务只处理开发工作流和直接相关文档。
9. 验证至少覆盖 `just` 配方分发、无 `sh.exe` 的 Windows 调用、脚本参数、文档一致性及可在本机执行的 Rust 测试；Flutter 端到端验证受本机 SDK 可用性约束。

## Acceptance Criteria

- [x] `just --list` 列出迁移后的有效配方及简短说明。
- [x] `just install`、`just doctor`、`just preview`、`just dev`、`just test`、`just build` 在 Windows 上分发到 `scripts/flutter-windows.ps1` 的正确动作，并且不依赖 `sh.exe`。
- [x] 上述核心配方在 macOS 上分发到 `scripts/flutter-macos.sh` 的正确动作。
- [x] `just --list` 不再显示 `install-app`。
- [x] 未支持平台对每个平台相关配方输出明确的中文错误并返回非零状态。
- [x] `justfile` 和相关文档不再把已删除的 `resource/`、npm、Tauri/Vue 工作流描述为当前入口。
- [x] Windows 原生验收入口可由 `just` 单独调用，且不会启动真实 Codex 客户端。
- [x] `git diff --check` 与 `cargo test --manifest-path native/launcher_core/Cargo.toml --locked` 通过；若 Flutter 可用，再运行完整 Flutter 测试。
- [x] 工作区不包含旧构建缓存或生成物的意外改动。

## Out of Scope

- 修改应用功能、界面或原生后端行为。
- 修改 GitHub Release 工作流或发布签名策略。
- 升级 Flutter/Rust 依赖或改变上游固定版本。
- 自动安装 Flutter SDK、Rust 或 Visual Studio。
- 重新引入旧版当前用户安装器、快捷方式管理或安装覆盖策略。
