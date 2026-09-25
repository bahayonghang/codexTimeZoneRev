# 启动与依赖调查证据

## 环境

- Flutter 3.47.5 / Dart 3.13.4（Scoop `extras/flutter`）。
- Windows 11，Visual Studio Enterprise 2026，C++ desktop workload 可用。
- `just dev` 通过 `scripts/flutter-windows.ps1 -Action run` 构建 Rust release 库后运行 Flutter Windows debug 应用。

## 依赖调查

在 `flutter_app` 执行 `flutter pub outdated` 的结果：

| 类型 | 包 | 当前 | 目标/结论 |
| --- | --- | --- | --- |
| direct | `forui` | 0.27.0 | 0.27.1；上游为菜单箭头边框修复 |
| direct | `timezone` | 0.10.1 | 0.11.1；用户批准主版本更新 |
| transitive | `vector_math` | 2.4.0 | 2.4.3；现有约束可升级 |
| transitive | `cross_file` | 0.3.5+5 | 最新 0.4.0 不在当前可解析图，不强制覆盖 |
| transitive | `material_color_utilities` | 0.13.0 | 最新 0.13.1 不在当前可解析图，不强制覆盖 |
| transitive dev | `test_api` | 0.7.12 | 最新 0.7.14 不在当前可解析图，不强制覆盖 |

`timezone 0.11.x` 的变更包括 `Location.offset` 从 `int` 改为 `Duration`，默认位置名使用 `Etc/UTC`。代码搜索没有发现对 `Location.offset` 或 timezone 默认 `UTC` 位置的直接依赖；应用自己的 `LauncherSettings.offset` 仍是整数小时，地区时钟使用 `TZDateTime`。

## 启动复现

### 窗口存在但不是前台

使用原始 `just dev` 启动后等待 `codex_timezone.exe`，探针记录：

- 应用 HWND 可见：`visible=True`。
- 应用进程正常响应：`responding=True`。
- 窗口标题：`Codex 时区启动器`。
- 启动前前台进程是 `floorp`；启动后前台进程仍是 `floorp`。

因此用户看到“没有启动界面”的最可能原因是窗口已创建但被其他窗口遮挡，而不是 Dart/Flutter 首帧失败。

### 窗口内容已渲染

在同一启动探针中捕获窗口截图，显示完整的启动设置、时区选择、客户端路径和时钟面板。`main.dart` 在 `runApp` 前等待 `WindowMaterial.initialize()`，但本次运行未出现空白窗口或初始化挂起。

## 代码定位

- `flutter_app/windows/runner/flutter_window.cpp:47-49`：首个 Flutter frame 回调调用 `this->Show()`。
- `flutter_app/windows/runner/win32_window.cpp:152-154`：`Show()` 只调用 `ShowWindow(window_handle_, SW_SHOWNORMAL)`。
- 当前实现没有 `SetForegroundWindow`、`SetWindowPos(HWND_TOP)` 或等价激活调用。

## Cargo 包装层调查

用户第二次报告 `just dev` 停在依赖解析后。现场进程链为：

```text
just → pwsh → C:\Users\lyh\AppData\Local\mbx\bin\cargo.exe
     → C:\Users\lyh\.cargo\bin\mbx.exe
     → rustup proxy
```

从 03:34:53 到 03:42:21，Cargo/mbx 进程没有 `rustc` 子进程，CPU 几乎为零，线程处于等待状态；release 产物时间戳没有推进。直接使用 `C:\Users\lyh\.rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\cargo.exe`、`CARGO_HOME=environment/cargo` 执行离线构建，0.17 秒完成。结束残留进程后再次执行原始 `just dev`，约 20.4 秒出现完整应用窗口。

`mbx doctor` 随后报告 0 failures，但其透明 Cargo shim 仍是可卡住的执行边界。`rustup which cargo` 能稳定返回活动 stable 工具链的真实路径，因此 Windows 脚本应优先解析该路径并保留 PATH fallback。

## 最新传递依赖试验

`flutter pub upgrade --major-versions --dry-run` 返回 `No dependencies would change`。临时 `pubspec_overrides.yaml` 将 `cross_file` 强制到 0.4.0、`material_color_utilities` 强制到 0.13.1、`test_api` 强制到 0.7.14 后，解析虽然成功，但 Windows 构建在 `file_selector_*` 和应用代码处失败：`XFile` 变成抽象类、缺少 `path`/`fromData`。试验结束后已删除 override 并恢复正常 lockfile。

因此三者不能通过安全的依赖升级满足“最新版本”：
- `cross_file 0.4.0` 与当前 `file_selector_*` 的 `^0.3.x` 约束不兼容；
- `material_color_utilities` 由 Flutter SDK/`material_ui` 约束；
- `test_api 0.7.12` 被 Flutter 3.47.5 的 `flutter_test` 明确固定。

## 启动连接验证

恢复正常依赖后串行执行原始 `just dev`，应用窗口持续响应 90 秒，没有 `Lost connection` 或异常退出。Flutter 输出该提示只表示设备连接结束，需结合应用是否被关闭、终端是否中断或构建是否失败判断，不能把依赖 outdated 提示当作启动错误。

## 依赖与构建注意事项

- 依赖更新必须通过 `flutter pub add`/`flutter pub upgrade` 完成，不手改 `pubspec.lock`。
- `just dev` 的 `pub get` 成功输出早于 Rust/Flutter Windows 构建和窗口启动，不能把依赖解析完成误判为 UI 已启动。
- Flutter 生成插件注册文件可能在 `pub get` 后出现无语义差异的工作区标记；最终只保留有意修改的文件。
