# 技术设计：更新依赖并修复开发启动

## 设计目标

在不改变业务状态边界和跨平台业务行为的前提下：

1. 让依赖图使用 `forui 0.27.1`、`timezone 0.11.1` 和可解析的 `vector_math 2.4.3`。
2. 让 Windows runner 在首帧完成后不仅显示窗口，还把窗口置于前台。
3. 保留现有 `just` 分发、Scoop SDK 探测、Flutter 热重载和原生 FFI 链路。

## 变更边界

### 依赖层

- 修改 `flutter_app/pubspec.yaml` 中 `forui` 与 `timezone` 的版本约束。
- 通过 Flutter 工具刷新 `flutter_app/pubspec.lock`，不手动编辑 lockfile。
- 使用 `flutter pub upgrade` 更新当前约束下可解析的传递依赖；不新增 `dependency_overrides`。
- 不修改 Dart 业务 API。若 `timezone 0.11.1` 暴露编译问题，只在调用边界做最小兼容修复，并补充对应测试。

### Windows runner 层

现有首帧回调是唯一的首次显示时机：

```text
Flutter engine first frame
        -> FlutterWindow::OnCreate callback
        -> Win32Window::Show()
        -> ShowWindow(SW_SHOWNORMAL)
```

在 `Win32Window::Show()` 这一显示边界补充原生窗口激活动作，使调用方无需重复实现：

```text
ShowWindow(SW_SHOWNORMAL)
        -> SetWindowPos(HWND_TOP, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW)
        -> SetForegroundWindow(HWND)
```

选择 `SetWindowPos` + `SetForegroundWindow` 的原因：

- `ShowWindow` 保留 Flutter runner 原有行为和首帧时机。
- `HWND_TOP` 只调整普通窗口层级，不使用 `HWND_TOPMOST`，不会让应用永久置顶。
- `SetForegroundWindow` 满足“启动后立即可见”的用户意图；最终是否成功由真实 Win32 探针验收，而不是假设 API 一定成功。
- 不引入 `window_manager` 等新插件，避免新的平台边界和启动依赖。

如果 Windows 前台锁策略拒绝激活，探针必须报告失败；实现阶段再依据失败证据选择最小的原生 fallback，而不是预先加入复杂的线程输入附加逻辑。

### Windows Rust toolchain 层

Cargo 的权威来源应是 rustup 当前活动工具链，而不是 PATH 中可能存在的透明第三方 shim。两个 Windows 脚本共享一个小型 resolver：

```text
rustup which cargo
        -> active toolchain cargo.exe
        -> fallback: PATH cargo.exe
```

resolver 动态读取 `rustup which cargo` 的结果，不拼接用户名、固定 stable 版本或写死 `RUSTUP_HOME`。这样保留 `CARGO_HOME` 与 `CARGO_TARGET_DIR` 的项目缓存约定，同时避免 `mbx` 等包装器把构建变成无诊断的无限等待。`test-native-windows.ps1` 复用同一 resolver，避免两个入口再次出现不同的 Cargo 行为。

如果 rustup 不存在或解析失败，resolver 回退到 `Get-Command cargo.exe`；两者都不存在时立即抛出中文错误。该策略只改变 Windows 构建进程选择，不改变 Cargo manifest、编译产物或 ABI。

## 数据流与兼容性

- `just dev` → PowerShell 脚本 → Cargo release → Flutter Windows runner → 首帧回调 → 原生显示/激活。
- 依赖更新只影响 Dart 包解析和 UI 库内部实现，不改变 Rust ABI、JSON 字段或持久化格式。
- `timezone 0.11.1` 的 `Location.offset` 类型变化不触及当前代码；固定偏移字段和地区时区显示仍由现有服务负责。
- macOS runner、网络、FFI、Dream Skin 和设置目录不在本次变更范围。

## 验证设计

1. 依赖验证：运行 `flutter pub outdated`，确认直接依赖与 `vector_math` 已达到目标；确认没有 override。
2. 静态/单元验证：运行 `just test`，覆盖 Rust、Flutter analyze 和 Flutter tests。
3. 启动红绿回路：用一次性 PowerShell/Win32 探针执行原始 `just dev`，等待新 `codex_timezone.exe` 的可见窗口，再检查 `GetForegroundWindow()` 的 PID 是否等于应用 PID；记录启动前 PID，结束时只清理本次新增进程。
4. 内容验证：确认窗口标题为“Codex 时区启动器”、进程响应正常；需要时捕获窗口截图，避免只验证进程存在。
5. 脚本验证：执行 PowerShell AST 检查、Cargo resolver 探针、`just --dry-run dev`、`git diff --check`，并清理 Flutter 生成文件的无关工作区标记。

## 风险与回滚

- `timezone 0.11.1` 可能暴露未搜索到的 API/默认位置差异；先运行完整测试，若失败只回滚该依赖或做调用边界兼容，不回滚无关 runner 修复。
- 原生激活可能受 Windows 前台锁影响；验收失败时保留日志，基于实际错误选择最小 Win32 fallback。
- 若依赖升级导致 UI 行为变化，优先保留 `forui 0.27.1` 的安全修复和 `vector_math` 更新，逐项回滚 `timezone` 以定位回归。
- 不删除或覆盖用户已有的 `scripts/flutter-windows.ps1` SDK 探测修复。
