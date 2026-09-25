# 更新依赖并修复开发启动

## Goal

更新 Flutter 桌面应用的可维护依赖版本，并确保 Windows 上执行 `just dev` 后，完整渲染的“Codex 时区启动器”窗口自动显示在前台，而不是被终端、编辑器或浏览器遮挡。

## Background

- 当前工具链为 Flutter 3.47.5 / Dart 3.13.4，已经满足 `flutter_app/pubspec.yaml` 的 SDK 下限。
- `flutter pub outdated` 显示：
  - 直接依赖 `forui 0.27.0` 可更新到 `0.27.1`；上游变更仅修复 `FSelectMenuTile` 菜单箭头边框。
  - 直接依赖 `timezone 0.10.1` 可更新到 `0.11.1`；该版本将 `Location.offset` 从 `int` 改为 `Duration`，并将默认位置名改为 `Etc/UTC`。用户已批准接受该主版本更新，项目当前没有读取 `Location.offset`。
  - 传递依赖 `vector_math 2.4.0` 可在现有约束内更新到 `2.4.3`。
  - `cross_file`、`material_color_utilities`、`test_api` 的最新版本超出当前可解析图；不强制覆盖上游约束。
- 当前代码没有读取 timezone 包的 `Location.offset`；固定偏移设置使用应用自己的整数小时字段，地区时钟使用 `TZDateTime`。
- 已用原始 `just dev` 启动并截取真实窗口：应用 UI 完整渲染，不是空白页，也没有被 Acrylic 或 FFI 初始化卡住。
- 启动探针确认：应用 HWND 可见且正常响应，但前台 HWND 始终是启动前的浏览器/终端窗口。`flutter_app/windows/runner/flutter_window.cpp:47-49` 首帧回调只调用 `Show()`，而 `flutter_app/windows/runner/win32_window.cpp:152-154` 的 `Show()` 仅调用 `ShowWindow(SW_SHOWNORMAL)`，没有显式激活窗口。
- `pub get` 成功输出不是启动完成标志；其后仍会构建 Rust 与 Flutter Windows 应用。
- 基线工作区已有上一轮未提交的 SDK 探测修复：`scripts/flutter-windows.ps1:9` 读取用户级 `FLUTTER_ROOT`。本任务必须保留该改动。
- 后续复现中，`just dev` 的 `cargo.exe → mbx.exe → rustup.exe` 进程链曾持续等待 7 分钟以上且没有 `rustc` 子进程；直接调用当前 stable toolchain 的 Cargo 离线构建仅需 0.17 秒，结束残留进程后原始 `just dev` 约 20 秒恢复。故障所有权在 Windows 脚本调用透明 Cargo shim 的执行层，而非 Rust 源码。

## Requirements

### R1 — 更新直接依赖

- 将 `forui` 更新到 `0.27.1`。
- 将 `timezone` 更新到 `0.11.1`（用户已批准）。
- 通过 Flutter/Dart 工具刷新 `flutter_app/pubspec.lock`，不得手工编辑 lockfile。

### R2 — 更新可解析的传递依赖

- 使用依赖工具把 `vector_math` 更新到当前约束可解析的 `2.4.3`。
- 不通过 dependency override 强制采用 `cross_file 0.4.0`、`material_color_utilities 0.13.1` 或 `test_api 0.7.14`。

### R3 — Windows 开发窗口自动置前

- Windows runner 在首帧完成后显示窗口，并将该窗口激活到前台。
- 不新增窗口管理插件，不改变 Flutter 状态边界，不影响热重载。
- 保持当前窗口标题、初始尺寸、Acrylic 效果和关闭行为。

### R4 — 保持现有跨平台行为

- 不改变 macOS runner、网络、FFI、设置持久化、时区目录或启动器业务逻辑。
- `scripts/flutter-windows.ps1` 的 Scoop/用户级 Flutter SDK 探测修复继续生效。

### R5 — 避免 Cargo 透明 shim 卡死

- Windows 脚本优先通过 `rustup which cargo` 解析当前活动工具链的真实 `cargo.exe`。
- 仅在没有 rustup 或解析失败时回退到 PATH 中的 Cargo。
- `just dev` 与 `just native-test` 使用同一解析策略，不硬编码用户名或工具链路径。
- 解析失败时输出可操作的中文错误，不静默等待。

### R6 — 不强制破坏依赖图

- `cross_file`、`material_color_utilities`、`test_api` 的最新版本必须通过正常解析获得，不能用 `dependency_overrides` 掩盖上游约束。
- 如果 Flutter SDK 或 `file_selector` 平台包提供兼容版本，再单独规划升级；本任务不修改 Flutter SDK 或平台插件源代码。

## Acceptance Criteria

- [x] `forui` 锁定为 `0.27.1`；`timezone` 锁定为 `0.11.1`。
- [x] `vector_math` 锁定为 `2.4.3`，且没有新增 dependency override。
- [x] `flutter pub outdated` 不再报告两个直接依赖或 `vector_math` 可更新；剩余条目均有上游约束依据。
- [x] `just test` 全部通过：Rust 测试、`flutter analyze`、Flutter 测试。
- [x] 自动启动探针执行原始 `just dev` 后，在超时内检测到可见、正常响应且内容已渲染的 `codex_timezone.exe` 窗口。
- [x] 同一探针确认应用进程成为前台窗口，窗口标题为“Codex 时区启动器”；若前台切换被 Windows 策略拒绝，验收必须失败而不是仅检查进程存在。
- [x] 验收结束后清理本次探针启动的进程，不杀死验收前已存在的用户进程。
- [x] `git diff --check` 通过，最终差异不包含 Flutter 自动生成文件的无关改写。
- [x] Windows Cargo 解析探针返回活动 rustup 工具链中的真实 `cargo.exe`，而不是 `AppData\Local\mbx\bin\cargo.exe`。
- [x] 原始 `just dev` 在残留 shim 进程被清理后稳定启动，且不再进入无 CPU 的 Cargo 等待状态。
- [x] `just native-test` 使用同一 SDK/Cargo 解析策略并通过隔离原生验收。
- [x] `pub upgrade --major-versions --dry-run` 和临时 override 试验证明三个传递包没有安全的兼容升级路径；未保留 override。
- [x] 正常依赖状态下原始 `just dev` 连续运行 90 秒，窗口保持响应且没有设备断开。

## Out of Scope

- 安装或配置 Android SDK。
- 强行升级当前依赖图中不可解析的传递依赖。
- UI 重设计、窗口尺寸或视觉风格调整。
- 修改 Codex/ChatGPT 客户端启动、Dream Skin、网络探测或设置格式。
- 发布、签名或打包新版本。
