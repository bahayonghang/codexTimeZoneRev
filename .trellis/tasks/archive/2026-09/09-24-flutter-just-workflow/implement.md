# 实施计划：Flutter 版 just 工作流

## 1. 实施步骤

- [x] 加载 `trellis-before-dev`，确认当前 Flutter 目录和相关规范约束。
- [x] 修改 `scripts/flutter-windows.ps1`：增加 `install` 动作，只执行依赖获取后返回。
- [x] 修改 `scripts/flutter-macos.sh`：增加 `install` 与 `doctor` 的提前返回分支。
- [x] 重写 `justfile`：移除 `resource` 工作目录和 npm 配方，接入 Windows/macOS 平台脚本；保留 Windows `cmd.exe` shell；删除 `install-app`；增加 Windows `native-test`。
- [x] 更新根 `README.md` 与 `flutter_app/README.md`，记录推荐 just 命令及 `dev → run` 映射。
- [x] 更新 `AGENTS.md` 中已经失效的 Tauri/Vue/npm 命令、目录和测试说明，使其与 0.2.0 源码一致。
- [x] 检查所有直接相关文件不存在未解决冲突、过期命令或意外生成物。

## 2. 验证命令

```powershell
just --list
just --dry-run install
just --dry-run doctor
just --dry-run preview
just --dry-run dev
just --dry-run test
just --dry-run build
just --dry-run native-test
$null = [scriptblock]::Create((Get-Content -Raw scripts/flutter-windows.ps1))
$null = [scriptblock]::Create((Get-Content -Raw scripts/test-native-windows.ps1))
cargo test --manifest-path native/launcher_core/Cargo.toml --locked
git diff --check
```

如果本机存在 Bash：

```bash
bash -n scripts/flutter-macos.sh
```

如果本机存在 Flutter SDK，再运行：

```powershell
just doctor
just test
```

`just build` 会执行完整平台构建，只有工具链与依赖齐备时才运行；否则保留 dry-run 与明确的环境阻塞说明。

## 3. 审查门

- [x] PRD、设计和实施计划与用户确认的“移除 install-app”决策一致。
- [x] `justfile` 只负责分发，不复制平台脚本的业务逻辑。
- [x] `dev` 与 `preview` 语义没有混淆。
- [x] Windows 路径不依赖 Git Bash 或 `sh.exe`。
- [x] 文档不再把已删除的 `resource/` 应用描述为当前入口。
- [x] 未把本机缺少 Flutter 误报为代码验证通过。

## 4. 验证结果

- `just --fmt --check`、`just --list` 与所有 Windows dry-run 分发通过；列表中无 `install-app`。
- 在不包含 `sh.exe` 的受限 PATH 下，`just doctor` 成功调用 PowerShell 7，并按预期报告缺少 Flutter SDK。
- 使用临时 Flutter SDK 替身验证 Windows `install` 只执行 `flutter pub get` 后退出。
- 使用 LF 归一化后的 macOS 脚本及临时 Flutter 替身验证 `install` 与 `doctor` 分支；WSL 直接读取 Windows CRLF checkout 的失败不视为脚本语法缺陷。
- 两个 PowerShell 脚本通过 AST 语法解析。
- Rust 测试通过：10 passed。
- `git diff --check`、Markdown 围栏与冲突标记检查通过。
- 当前机器没有 Flutter SDK，因此未执行真实 `just test`、`just dev`、`just build` 或 Flutter analyze；完整 Flutter/macOS 验证明确延期到具备对应 SDK 和平台的机器。

## 5. 回滚点

- 平台脚本改动与 `justfile` 改动必须保持可独立回滚。
- 文档改动不与产品代码混合重构；若验证发现上游脚本行为不适合包装，应回到规划阶段而不是在 `justfile` 中复制补偿逻辑。
