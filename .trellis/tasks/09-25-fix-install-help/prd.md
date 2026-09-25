# 修复安装命令并添加帮助

## Goal

消除仓库级 `just` 工作流中“安装依赖”和“安装桌面应用”同名歧义：`just install` 必须真实构建并安装当前用户可运行的 Codex 时区启动器，同时提供明确的 `deps`、`install-app` 兼容入口和 `help` 命令。

## Background

- 当前 `just install` 只分发到 `scripts/flutter-windows.ps1 -Action install` / `scripts/flutter-macos.sh install`，两个入口都只执行 `flutter pub get` 后退出；因此 `Got dependencies!` 只表示 Flutter 依赖解析成功，不表示桌面应用已构建或安装。
- 旧 Tauri 应用的 `install-app` 配方在 Flutter 迁移提交 `32734be` 中被删除，因为旧 npm/Tauri 安装器已失效；当前仓库没有 Flutter 版的用户目录安装能力。
- Windows/macOS 发布构建已经分别生成可安装的 Release 目录或 `.app`，但 `just build` 只生成 ZIP，不复制到用户可发现的位置。
- 旧安装契约使用 Windows `%LOCALAPPDATA%\Programs\CodexTimeZoneLauncher` 和开始菜单快捷方式，以及 macOS `~/Applications/Codex 时区启动器.app`；本任务恢复该用户可见结果，但不恢复旧 npm/Tauri 代码。
- Windows 设置保存在已安装可执行文件旁的 `data/settings.json`，升级安装必须显式保留；macOS 设置位于 `~/Library/Application Support/com.fei-away.codextimezone`，替换 `.app` 不影响设置。

## Requirements

### R1 — 明确依赖安装命令

- 新增公开 `just deps` 命令，只执行 Flutter SDK 定位与锁定依赖获取，不要求 Cargo、不构建或安装桌面应用。
- 输出必须明确说明“依赖安装完成”，避免用户将其误判为应用安装。
- `flutter-windows.ps1` 与 `flutter-macos.sh` 使用一致的 `deps` 动作语义。

### R2 — `just install` 执行真实安装

- `just install` 必须先执行当前平台的 Release 构建和发布包生成，再把完整运行产物安装到当前用户目录。
- Windows 默认安装到 `%LOCALAPPDATA%\Programs\CodexTimeZoneLauncher`，安装完整 Release 运行目录并创建/更新开始菜单快捷方式。
- macOS 默认安装到 `~/Applications/Codex 时区启动器.app`，安装前验证 `.app` 签名。
- 安装成功输出必须包含实际安装路径；仅生成 ZIP、打印“完成”但未落盘不算成功。

### R3 — 升级安全与用户数据保留

- Windows 替换旧安装目录时必须保留 `data/settings.json`，并清理不属于新 Release 的旧程序文件。
- Windows 若已安装程序正在运行，必须以可操作的中文错误失败，不得强杀用户进程或留下半安装目录。
- Windows 使用同卷暂存/备份/回滚流程；macOS 使用暂存 bundle、备份与失败回滚流程。
- 不覆盖或迁移其他不相关文件；不把本地设置、日志或开发缓存打入 ZIP。

### R4 — 兼容入口

- 新增公开 `just install-app` 命令，作为 `just install` 的兼容别名，执行完全相同的真实安装流程。
- 不恢复任何 npm、Tauri、Vue 或 `resource/` 路径。
- 不支持平台必须明确失败并返回非零状态。

### R5 — 帮助与文档

- 新增公开 `just help` 命令并显示全部有效配方；无参数执行 `just` 时继续进入帮助。
- 帮助说明必须明确区分 `deps` 与 `install`。
- 同步根 `README.md` 与 `AGENTS.md` 的命令表、直接脚本说明和验证清单。
- 保持 `justfile` 为薄分发层；Flutter/Rust 构建逻辑继续归属平台脚本，安装事务归属独立平台安装脚本。

## Acceptance Criteria

- [x] `just help` 与 `just --list` 成功，并列出 `deps`、`install`、`install-app`、`doctor`、`preview`、`dev`、`test`、`build`、`native-test`（平台支持时）和 `help`。
- [x] `just deps` 在 Windows 和 macOS 只完成依赖安装，并输出依赖安装成功的明确信息。
- [x] `just install` 与 `just install-app` 均先生成当前平台 Release 产物，再写入默认当前用户安装目录并输出真实路径。
- [x] Windows 临时目录安装测试证明完整 Release 文件可见、开始菜单快捷方式目标正确、重复安装保留 `data/settings.json` 并移除旧版额外文件。
- [x] Windows 运行中安装保护会失败且不会终止用户进程；通过可控探针验证错误路径。
- [x] macOS 安装脚本通过 Bash 语法检查；签名验证、bundle 替换和回滚在 macOS 上明确列为待平台实机验证。
- [x] `just --dry-run deps`、`just --dry-run install`、`just --dry-run install-app` 和核心既有配方分发正确，Windows 不依赖 `sh.exe`。
- [x] PowerShell 脚本 AST 检查、`bash -n scripts/flutter-macos.sh scripts/install-macos.sh`（环境可用时）及 `git diff --check` 通过。
- [x] README、AGENTS 和有效任务文档不再声称 `just install` 仅安装依赖，也不再声称 `install-app` 已被永久删除。

## Out of Scope

- Windows MSI/MSIX、签名、公证、系统级安装器、卸载器或自动更新。
- 恢复旧 Tauri/npm 安装器或任何已删除的 `resource/` 代码。
- 修改启动器 UI、Rust ABI、设置 JSON、网络、Dream Skin 或客户端启动逻辑。
- 自动安装 Flutter、Rust、Visual Studio、Xcode 或其他开发工具。
- 在本任务中修改 GitHub Release 发布触发方式。
