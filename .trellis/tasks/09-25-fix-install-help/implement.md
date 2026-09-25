# 执行计划：修复安装命令并添加帮助

## 实施步骤

1. **建立基线**
   - 确认工作区状态与当前 Trellis 任务。
   - 记录 `just install` 当前仅调用 `flutter pub get`、`install-app` 不存在的旧行为。
   - 搜索所有 `just install`、`install-app` 和平台 action 文档引用。

2. **重构命令分发**
   - 在 `justfile` 新增公开 `help`、`deps`、`install-app`。
   - 将 `install` 定义为“先 build，再调用当前平台安装脚本”。
   - 保持 `default` 进入帮助，Windows shell 继续使用 `cmd.exe`。
   - 为 Linux 和无 macOS 原生验收能力的目标输出明确非零错误。

3. **调整平台构建动作**
   - Windows `ValidateSet` 与分支改为 `deps`，成功后输出依赖安装完成。
   - macOS 在执行 `pub get`/Cargo 前校验 action，并将 `deps` 作为只装依赖的早退分支。
   - 保证 `build` 的 Release、Rust 原生库注入和 ZIP 契约不变。

4. **实现 Windows 安装器**
   - 新增 `scripts/install-windows.ps1`，提供 Source/InstallRoot/ShortcutPath 可覆盖参数。
   - 实现输入完整性校验、运行中保护、暂存复制、设置保留、目录替换、失败回滚和开始菜单快捷方式。
   - 错误信息使用中文，不强杀用户进程。

5. **实现 macOS 安装器**
   - 新增 `scripts/install-macos.sh`，实现源 bundle 验证、ditto 暂存、备份替换、最终验签和失败回滚。
   - 保持 `~/Applications/Codex 时区启动器.app` 目标与 Application Support 设置边界。

6. **同步文档**
   - 更新 `README.md`：帮助、依赖、构建、安装的顺序和语义。
   - 更新 `AGENTS.md`：命令表、直接脚本边界、dry-run 验证与安装目录/数据保留规则。
   - 不修改已归档任务对历史决策的记录。

7. **分层验证**
   - 运行 `just --fmt --check`、`just help`、`just --list` 和全部 dry-run。
   - 运行 PowerShell AST 与 Bash `bash -n`。
   - 运行 `just deps`。
   - 在批准临时目录执行 Windows 安装、覆盖安装、设置保留、陈旧文件清理、快捷方式和运行中拒绝验证。
   - 运行真实 `just install`，检查默认用户目录和快捷方式；如目标程序正在运行，保留错误证据且不终止它。
   - 运行 `just test` 与 `git diff --check`。

## 验证命令

```powershell
just --fmt --check
just help
just --list
just --dry-run deps
just --dry-run install
just --dry-run install-app
just --dry-run doctor
just --dry-run preview
just --dry-run dev
just --dry-run test
just --dry-run build
just --dry-run native-test
$null = [scriptblock]::Create((Get-Content -Raw scripts/flutter-windows.ps1))
$null = [scriptblock]::Create((Get-Content -Raw scripts/install-windows.ps1))
bash -n scripts/flutter-macos.sh scripts/install-macos.sh
just deps
just install
just test
git diff --check
```

## 风险检查点

- Windows 目录替换与运行中 exe 文件锁。
- Windows `data/settings.json` 保留以及旧文件清理。
- 快捷方式创建失败后的应用/快捷方式一致性。
- macOS `.app` 原子替换与 ad-hoc 签名验证只能在 macOS 实机确认。
- `install` 语义变化对 README、AGENTS 和用户既有命令认知的影响。

## 执行结果

- `justfile` 已新增 `help`、`deps`、`install-app`；`install` 现在依赖 Release 构建并分发到平台安装器。
- Windows/macOS 依赖动作已统一为 `deps`，并输出“依赖安装完成”提示；Windows 仅在需要 Rust 的 test/run/build 动作中解析 Cargo。
- Windows 临时目录验证通过：首次安装、重复安装、`data/settings.json` 保留、旧文件清理、源 settings 隔离、快捷方式目标正确；运行中安装返回非零且未终止测试进程。
- 真实 `just install` 与 `just install-app` 均在 Windows 构建并安装到 `%LOCALAPPDATA%\Programs\CodexTimeZoneLauncher`，开始菜单快捷方式指向安装后的 exe。
- `just test`、`just native-test`、全部 Windows dry-run、PowerShell AST、`bash -n` 和 `git diff --check` 通过。
- macOS 安装器已通过 Bash 语法检查；`.app` 签名、替换和回滚仍需在 macOS 实机执行，Windows 不将该项标记为实机通过。

## 回滚点

- 源码变更可在单个提交中恢复 `justfile`、两个平台构建脚本、新安装脚本和文档。
- 已写入用户目录的安装结果不由 Git 回滚；失败安装必须由脚本自身回滚，用户也可删除默认安装目录。
- 不触碰 Rust/Dart/FFI/设置格式，因此产品数据迁移回滚风险仅限 Windows 安装目录事务。
