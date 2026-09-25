# 技术设计：修复安装命令并添加帮助

## 1. 目标与边界

根目录 `justfile` 只负责稳定命令名、平台分发和帮助展示。平台构建脚本继续负责 Flutter/Rust 构建与 ZIP，独立的平台安装脚本负责“构建产物 → 当前用户可运行安装”的事务。这样不会在 `justfile` 复制构建逻辑，也不会让安装事务散落在构建命令中。

## 2. 命令契约

| 命令 | 语义 | Windows | macOS |
| --- | --- | --- | --- |
| `just help` | 显示有效配方 | `just --list` | `just --list` |
| `just deps` | 只获取锁定依赖 | `flutter-windows.ps1 deps` | `flutter-macos.sh deps` |
| `just build` | 构建并打包 Release | `flutter-windows.ps1 build` | `flutter-macos.sh build` |
| `just install` | 构建、打包并安装当前用户应用 | `build` 后调用 Windows 安装脚本 | `build` 后调用 macOS 安装脚本 |
| `just install-app` | `install` 的兼容别名 | 依赖 `install` | 依赖 `install` |
| 其他既有命令 | 保持当前行为 | 当前 Windows 脚本 | 当前 macOS 脚本 |

`default` 调用 `help`。安装不再复用名称含混的“只装依赖”动作；依赖安装统一使用 `deps`。

## 3. Windows 安装事务

### 3.1 输入与默认值

`scripts/install-windows.ps1` 接受可覆盖的 `Source`、`InstallRoot` 和 `ShortcutPath` 参数，以便在批准临时目录执行无用户副作用的验收。默认值为：

- Source：`flutter_app/build/windows/x64/runner/Release`
- InstallRoot：`%LOCALAPPDATA%\Programs\CodexTimeZoneLauncher`
- ShortcutPath：`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Codex 时区启动器.lnk`

脚本验证 Source 中至少存在 `codex_timezone.exe`、`codex_timezone_core.dll`、`data/flutter_assets` 和 `data/icudtl.dat`，防止把不完整构建报告为安装成功。

### 3.2 更新流程

1. 枚举目标目录范围内的 `codex_timezone` 进程；发现运行实例时立即失败。
2. 在安装根目录同级创建 GUID 暂存目录，复制完整 Source。
3. 若旧安装存在 `data/settings.json`，复制到暂存目录。
4. 将旧安装目录重命名为 GUID 备份，再将暂存目录重命名为正式目录。
5. 新目录就位后创建开始菜单快捷方式；任一步失败时尽量恢复旧目录和旧快捷方式。
6. 成功后删除备份并输出 `已安装：<path>` 与开始菜单路径。

目录整体替换保证旧 DLL/资源不会残留，同时只显式迁移已知用户设置。运行中保护避免 Windows 文件锁导致不可预测的半更新。

## 4. macOS 安装事务

`scripts/install-macos.sh` 默认把 `flutter_app/build/macos/Build/Products/Release/Codex 时区启动器.app` 安装到 `~/Applications/Codex 时区启动器.app`：

1. 检查源 `.app` 存在。
2. 使用 `codesign --verify --deep --strict` 验证源 bundle。
3. 通过 `/usr/bin/ditto` 复制到 `~/Applications` 下的 GUID 暂存目录。
4. 将现有 bundle 改名为备份，再将暂存 bundle 改名为正式路径；失败时恢复备份。
5. 验证最终 bundle 签名，清理备份并输出安装路径。

用户设置位于 `~/Library/Application Support`，不随 `.app` 替换。

## 5. 错误与兼容策略

- 所有用户可见错误使用中文句子，并指出下一步（例如先退出已安装应用）。
- 安装脚本不终止应用进程，不修改系统 PATH，不要求管理员权限。
- Windows/macOS 都不恢复旧安装器实现；只复用其公开安装目标和开始菜单行为。
- `install-app` 作为别名保留，降低用户既有命令记忆和脚本调用中断风险。
- 平台脚本对未知动作应在执行昂贵构建前失败；Windows 继续由 `ValidateSet` 保证，macOS 增加早期动作校验。

## 6. 验证与回滚

- 结构：`just --list`、`just help`、`just --dry-run ...`。
- Windows 安装：在批准临时目录构造/使用完整 Release，连续安装两次并放置不同 `settings.json` 与旧额外文件，验证保留、清理和快捷方式目标；用运行中路径探针验证拒绝路径。
- 脚本：PowerShell AST、`bash -n`。
- 构建：运行真实 `just install` 验证默认用户目录与输出；这会直接产生用户可见安装，属于用户已批准的目标结果。
- 回归：`just deps`、`just test`、`git diff --check`。
- macOS 完整签名/替换/回滚只能在 macOS 实机验证，Windows 不冒充该证据。
- 代码回滚只需恢复 `justfile`、平台动作、安装脚本与文档；用户目录中的已安装应用不随源码回滚自动删除。
