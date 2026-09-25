# 技术设计：Flutter 版 just 工作流

## 1. 设计目标

把 `justfile` 做成一个薄的分发层：开发者只学习稳定的仓库级命令，具体 Flutter SDK 定位、环境变量、构建目录、原生库复制和打包逻辑继续由上游平台脚本负责。避免在 `justfile` 与 PowerShell/Bash 脚本中重复实现构建流程。

## 2. 命令契约

| just 命令 | Windows 分发 | macOS 分发 | 语义 |
| --- | --- | --- | --- |
| `just install` | `flutter-windows.ps1 -Action install` | `flutter-macos.sh install` | 获取 Flutter 锁定依赖，不构建或启动 |
| `just doctor` | `flutter-windows.ps1 -Action doctor` | `flutter-macos.sh doctor` | 输出 Flutter 工具链诊断 |
| `just preview` | `flutter-windows.ps1 -Action preview` | `flutter-macos.sh preview` | 使用固定数据启动 UI，不访问真实客户端 |
| `just dev` | `flutter-windows.ps1 -Action run` | `flutter-macos.sh run` | 构建原生库并启动真实开发会话 |
| `just test` | `flutter-windows.ps1 -Action test` | `flutter-macos.sh test` | Rust 测试、Flutter analyze 与 Flutter 测试 |
| `just build` | `flutter-windows.ps1 -Action build` | `flutter-macos.sh build` | 生成并打包平台发布产物 |
| `just native-test` | `test-native-windows.ps1` | 不提供 | Windows 隔离原生验收，不启动真实 Codex |

`just install-app` 被删除。0.2.0 的公开分发契约是 `environment/artifacts/` 下的 ZIP；重新引入安装器需要另行定义覆盖、快捷方式和用户数据迁移策略。

## 3. 平台脚本边界

### Windows

- `justfile` 保留 `cmd.exe` 作为 Windows shell，确保不依赖 `sh.exe`。
- 通过 PowerShell 7 的 `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File` 调用 `scripts/flutter-windows.ps1`。现有打包脚本使用 `[IO.Path]::GetRelativePath`，Windows PowerShell 5.1 不支持该 API，不能用 `powershell.exe` 代替。
- `flutter-windows.ps1` 的 `ValidateSet` 新增 `install`；执行 `flutter pub get` 后立即返回。
- 现有 `doctor/test/preview/run/build` 分支保持原有行为。

### macOS

- `justfile` 通过 `bash scripts/flutter-macos.sh <action>` 调用现有脚本。
- `flutter-macos.sh` 在 `flutter pub get` 后识别 `install` 并立即退出。
- 新增 `doctor` 分支，执行 `flutter doctor -v` 后退出，不触发 Rust release 构建。
- 现有 `test/preview/run/build` 分支保持原有行为。

## 4. 文档同步

- 根 `README.md` 增加推荐的 `just` 命令，并保留直接脚本命令作为等价入口说明。
- `flutter_app/README.md` 在 Windows/macOS 段落中补充 just 映射，特别注明 `dev` 对应脚本的 `run`。
- `AGENTS.md` 中可由当前源码直接证明的命令、目录、构建和测试说明改为 Flutter/Rust 架构；删除旧 npm/Tauri/Vue 的现行指令，保留仍适用的仓库约束。
- 不修改 `.github/workflows/flutter-desktop.yml`；直接脚本仍作为 CI 的稳定底层入口。

## 5. 错误传播与安全边界

- PowerShell/Bash 脚本的非零退出码由 `just` 原样传播。
- Windows 脚本继续在缺少 Flutter SDK 时给出明确错误，不尝试下载或修改系统工具链。
- `dev`、`build`、原生验收产生的文件只进入已忽略的 `environment/` 或 Flutter 构建目录。
- Linux 配方不尝试执行 PowerShell/Bash 平台脚本，只输出中文“不支持”错误并返回非零状态。

## 6. 验证策略

1. `just --list` 验证配方集合和说明，且不含 `install-app`。
2. `just --dry-run <recipe>` 在 Windows 验证实际分发命令与动作参数。
3. PowerShell 解析检查验证两个 `.ps1` 文件语法；可用时运行 `bash -n` 检查 macOS 脚本。
4. 运行 `cargo test --manifest-path native/launcher_core/Cargo.toml --locked`。
5. 当前机器没有 Flutter 时，验证 `just doctor` 以明确的 SDK 缺失信息失败；若 Flutter 可用，再运行 `just test` 和可行的构建验证。
6. 搜索 `justfile` 与直接相关文档中的 `resource/`、npm、Tauri/Vue 旧入口残留。

## 7. 风险与回滚

- 最大风险是 Windows 命令行转义和当前机器缺少 Flutter SDK；通过保留 `cmd.exe` shell、使用 `--dry-run` 和脚本解析检查降低风险。
- macOS 完整执行只能在 macOS 验证；本机只做脚本静态检查，并明确记录未执行项。
- 每个层次都可通过单独恢复 `justfile`、平台脚本或文档回滚，不需要数据迁移。
