# Local entry for Codex 时区启动器.
# These recipes call the npm scripts in resource/. They do not call Tauri or Cargo directly.

set working-directory := "resource"

# 列出可用命令
[private]
default:
    @just --list

# 在 resource 安装锁定的 npm 依赖
install:
    npm ci --cache ../environment/npm-cache

# 启动当前系统的桌面开发会话
[windows]
dev:
    npm run dev:win

# 启动当前系统的桌面开发会话
[macos]
dev:
    npm run dev:mac

# 仅支持 Windows 与 macOS
[linux]
dev:
    @echo '仅支持 Windows 与 macOS。' >&2
    @exit 1

# 构建当前系统的发布产物
[windows]
build:
    npm run build:win

# 构建当前系统的发布产物
[macos]
build:
    npm run build:mac

# 仅支持 Windows 与 macOS
[linux]
build:
    @echo '仅支持 Windows 与 macOS。' >&2
    @exit 1
