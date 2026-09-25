# Flutter 桌面应用的仓库级统一入口。
# 具体 SDK 定位、依赖获取、原生构建与打包逻辑由 scripts/ 下的平台脚本负责。

# Windows 常见 PATH 不包含 sh.exe；just 配方只调用 PowerShell 7。
[windows]
set shell := ["cmd.exe", "/c"]

# 列出可用命令
[private]
default:
    @just --list

[private]
[windows]
_flutter action:
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/flutter-windows.ps1 -Action {{ action }}

[macos]
[private]
_flutter action:
    bash scripts/flutter-macos.sh {{ action }}

[linux]
[private]
_flutter action:
    @echo '仅支持 Windows 与 macOS。' >&2
    @exit 1

# 获取 Flutter 锁定依赖
install: (_flutter "install")

# 检查 Flutter 与平台开发工具链
doctor: (_flutter "doctor")

# 使用固定演示数据启动 UI 预览
preview: (_flutter "preview")

# 构建原生库并启动真实开发会话
dev: (_flutter "run")

# 运行 Rust、静态分析和 Flutter 测试
test: (_flutter "test")

# 构建并打包当前平台的发布产物
build: (_flutter "build")

# 运行 Windows 隔离原生验收，不启动真实 Codex
[windows]
native-test:
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/test-native-windows.ps1

# Windows 隔离原生验收目前没有 macOS 等价脚本
[macos]
native-test:
    @echo '原生隔离验收脚本目前仅支持 Windows。' >&2
    @exit 1

# 仅支持 Windows 与 macOS
[linux]
native-test:
    @echo '仅支持 Windows 与 macOS。' >&2
    @exit 1
