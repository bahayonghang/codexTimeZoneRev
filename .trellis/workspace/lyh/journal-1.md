# Journal - lyh (Part 1)

> AI development session journal
> Started: 2026-09-24

---



## Session 1: 适配 Flutter 版 just 工作流
<!-- trellis-session: v=2 fp=bc507cccf4e71f52 -->

**Date**: 2026-09-25
**Task**: 适配 Flutter 版 just 工作流
**Branch**: `dev`

### Summary

将根目录 just 配方迁移到 Flutter 0.2.0 平台脚本，补齐 install/doctor 动作，删除旧 install-app，并同步 README 与 AGENTS；完成 just 分发、脚本语法和 Rust 测试验证。

### Git Commits

| Hash | Message |
|------|---------|
| `32734be` | fix(just): 🐛 适配 Flutter 开发命令 |

### Status

[OK] **Completed**


## Session 2: 记录失焦亚克力并提交安装命令
<!-- trellis-session: v=2 fp=49d494b044e8ad29 -->

**Date**: 2026-09-25
**Task**: 记录失焦亚克力并提交安装命令
**Branch**: `dev`

### Summary

确认 Windows 11 25H2 失焦 Desktop Acrylic 无法用强制活动外观或 Blur-Behind 恢复，并拆分提交安装命令、文档和任务记录。

### Main Changes

- 记录 build 26200 失焦亚克力探针，并归档 09-25-keep-unfocused-glass。
- 提交 just deps 与当前用户安装命令，以及对应文档和安装任务。

### Git Commits

| Hash | Message |
|------|---------|
| `1e07007` | feat(just): ✨ 区分依赖安装与桌面应用安装 |
| `380ec0e` | docs(agents): 📝 说明依赖安装与应用安装命令 |
| `70579e9` | docs(windows): 📝 记录失焦亚克力变为实色 |
| `7890961` | chore(trellis): 🔧 记录安装命令任务 |

### Testing

- [OK] Win32 标题栏像素探针；安装事务本次未重新执行。

### Status

[OK] **Completed**
