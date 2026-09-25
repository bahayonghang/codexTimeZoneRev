# 执行计划：更新依赖并修复开发启动

## 实施步骤

1. **确认基线与范围**
   - 读取当前 git 状态，保留上一轮 `scripts/flutter-windows.ps1` 的 SDK 探测改动。
   - 确认没有验收探针遗留的 `just`、`dart`、`codex_timezone` 进程。
   - 记录当前 `pubspec.yaml`、lockfile 与 Windows runner 差异。

2. **更新依赖**
   - 在 `flutter_app` 通过 Flutter 工具将 `forui` 固定到 `0.27.1`、`timezone` 约束更新到 `^0.11.1`。
   - 执行依赖升级，让 `vector_math` 解析到 `2.4.3`。
   - 检查 `pubspec.yaml`、`pubspec.lock` 与 `flutter pub outdated`，确认没有新增 override，也没有强行升级不可解析包。
   - 若 timezone 产生编译错误，只在调用边界做最小兼容修复并补测试。

3. **修复 Windows 首帧显示**
   - 在 `flutter_app/windows/runner/win32_window.cpp` 的 `Win32Window::Show()` 中保留 `ShowWindow`，补齐普通窗口置顶与 `SetForegroundWindow` 激活。
   - 不改 `FlutterWindow::OnCreate` 的首帧回调时机，不添加新插件，不改窗口标题/尺寸/关闭行为。

4. **修复 Cargo 执行边界**
   - 新增 Windows Rust toolchain resolver，优先使用 `rustup which cargo` 返回的真实活动工具链 Cargo。
   - 让 `flutter-windows.ps1` 与 `test-native-windows.ps1` 复用 resolver；无 rustup 时回退 PATH，找不到时立即报中文错误。
   - 用 resolver 探针确认不会选择 `AppData\Local\mbx\bin\cargo.exe`。

5. **回归与启动验收**
   - 运行 `just test`。
   - 运行 `just --dry-run dev`、PowerShell AST 检查和 `git diff --check`。
   - 执行一次性 Win32 启动探针：运行原始 `just dev`，等待新应用窗口可见并响应，检查标题、截图/内容状态和前台 PID；记录失败日志后清理本次进程。
   - 再运行 `flutter pub outdated`，确认目标依赖已更新。

6. **清理与交付检查**
   - 删除临时截图/日志（若创建在仓库外的批准临时目录则清理）。
   - 检查最终 git diff，确保只包含依赖文件、Windows runner、必要的兼容代码及任务规划文件；不保留生成文件噪声。
   - 汇总测试结果和未覆盖风险；不自动提交，除非用户另行要求。

## 验证命令

```powershell
just test
just --dry-run dev
$null = [scriptblock]::Create((Get-Content -Raw scripts/flutter-windows.ps1))
$null = [scriptblock]::Create((Get-Content -Raw scripts/test-native-windows.ps1))
git diff --check
```

Cargo resolver 检查：

```powershell
. .\scripts\windows-rust.ps1
$cargo = Resolve-RustTool 'cargo'
$ cargo
```

依赖检查：

```powershell
Set-Location flutter_app
$flutterRoot = [Environment]::GetEnvironmentVariable('FLUTTER_ROOT', 'User')
& (Join-Path $flutterRoot 'bin\flutter.bat') pub outdated
```

启动验收必须使用原始 `just dev`，并检查：

- 新建的 `codex_timezone.exe` 窗口可见且 `Responding=True`。
- `MainWindowTitle` 为 `Codex 时区启动器`。
- `GetForegroundWindow()` 对应 PID 为该应用 PID，而不是启动前的终端/浏览器 PID。
- 探针退出时只结束本次启动的进程树。

## 风险检查点

- `timezone 0.11.1` 的 `Location.offset` 类型变化。
- Windows `SetForegroundWindow` 的前台锁策略。
- `pub get` 造成的 Flutter 生成注册文件工作区噪声。
- 上一轮未提交的 `scripts/flutter-windows.ps1` 改动不能被覆盖。

## 执行结果

- 依赖已更新：`forui 0.27.1`、`timezone 0.11.1`、`vector_math 2.4.3`；未新增 dependency override。
- Windows runner 首帧显示路径已补充普通窗口置顶与前台激活。
- Windows Cargo resolver 已绕过 PATH 中的透明 `mbx` shim，解析到活动 rustup stable toolchain；两个 Windows 入口复用该策略。
- 原始 `just dev` 探针通过：窗口可见、响应正常、内容渲染完成，应用 PID 成为前台 PID；修复后启动约 16 秒且无 `mbx` 输出。
- `just test` 通过：Rust 10 项、Flutter 31 项，Analyze 无问题。
- `just native-test` 通过隔离原生验收；PowerShell AST、全部 `just --dry-run`、`git diff --check` 通过；验收进程已清理。
- 三个传递包的最新版本经 `pub upgrade --major-versions --dry-run` 证明不可安全解析；临时 override 会破坏 `file_selector` API，已删除并未保留。
- 正常依赖状态下原始 `just dev` 连续运行 90 秒，无 `Lost connection`。
