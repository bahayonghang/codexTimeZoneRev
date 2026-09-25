# 失焦后保持玻璃背景

## Goal

窗口失去焦点后，用户仍能看到与获焦时同类的实时玻璃背景：背后的桌面被模糊采样。文字、菜单和输入控件保持不透明。获焦时的 Desktop Acrylic 外观保持不变。

## Background

- 获焦截图（19:51:08）中，壁纸透过标题栏和透明页面；失焦截图（19:52:20）中，同一窗口的标题栏和页面变为均匀深灰，壁纸采样消失。文字在两张图里都清晰。底部状态文案和「未保存修改」按钮的变化来自两次截图之间的启动操作。
- 页面骨架在亚克力主题下为 alpha 0（`flutter_app/lib/app/theme.dart`）。透明区域显示 DWM 背景。失焦路径没有把骨架改成不透明。
- `WindowMaterial.apply` 调用 `WindowEffect.acrylic`（`flutter_app/lib/services/window_material.dart`）。`flutter_acrylic` 1.1.4 在构建号 `>= 22523` 上把它写成 `DWMWA_SYSTEMBACKDROP_TYPE = DWMSBT_TRANSIENTWINDOW`（3）。本机是 Windows 11 25H2，构建号 26200.9550，透明效果注册表值为 1。
- 该 DWM 材质只在窗口活动时采样桌面。窗口失焦后，DWM 用实色填充，属性值可以仍为 3。应用只在启动和明暗主题变化时设置材质，没有 `WM_ACTIVATE` 处理。
- 本机构建号上，插件不使用 Dart 传入的 Color。获焦玻璃的明暗来自 `DWMWA_USE_IMMERSIVE_DARK_MODE`。
- 证据、插件分支和被排除的路径见 `research/unfocused-acrylic.md`。

## Requirements

### R1 — 失焦后保留实时模糊

- 窗口失焦且系统透明效果开启、高对比度关闭时，标题栏和页面继续显示背后桌面的实时模糊。
- 画面不得退回失焦截图中的均匀实色。
- 允许失焦模糊与获焦 Desktop Acrylic 在噪声纹理或轻微色调上不同。背后内容必须仍可辨认为模糊后的桌面。

### R2 — 获焦外观不变

- 获焦时继续使用当前 Desktop Acrylic：`DWMSBT_TRANSIENTWINDOW`、扩展边距 -1、标题栏颜色 `DWMWA_COLOR_NONE`、沉浸式暗色跟随应用主题。
- 不把获焦材质改成 Mica、Tabbed 或旧 Aero。

### R3 — 文字和控件保持不透明

- 正文、菜单、输入框和按钮的不透明度保持 1。
- 不使用 `WS_EX_LAYERED` 或 `SetLayeredWindowAttributes` 降低整窗透明度。

### R4 — 明暗主题在两种激活状态下生效

- 应用内的系统、浅色、深色切换继续更新原生材质。
- 窗口处于失焦时切换主题，失焦模糊使用新主题；窗口回到获焦时，Desktop Acrylic 使用新主题。
- 主题状态以应用设置为准，不改读系统 `AppsUseLightTheme` 代替应用设置。

### R5 — 实色开关保持关闭材质

- `--solid-background` 启动后，获焦和失焦都使用实色主题。
- 该模式下不设置系统背景，也不设置 Accent 模糊。

### R6 — 遵守系统对比度与透明效果策略

- `EnableTransparency` 为 0，或系统高对比度开启时，失焦路径不强制添加模糊，保留系统当前的实色结果。
- 获焦路径继续交给现有插件和 DWM。

### R7 — 依赖与所有权

- 保持 `flutter_acrylic` 1.1.4。不修改 Pub Cache 中的插件，不升级该包。
- 失焦策略写在本仓库的 Windows runner 与 `WindowMaterial`。插件继续负责获焦时的 Desktop Acrylic 设置。
- `Window.setEffect(WindowEffect.aero)` 不能作为失焦实现。插件这条路径会复位边距和暗色模式，且不会清除背景类型 3。

### R8 — 探针失败时停止

- 实现先按 `research/unfocused-acrylic.md` 的顺序做探针。
- 若 `WCA_FORCE_ACTIVEWINDOW_APPEARANCE` 与「清除瞬态背景 + `ACCENT_ENABLE_BLURBEHIND`」都不能在 build 26200 上满足 R1 和 R3，撤销失焦材质改动，保留获焦亚克力，并把阴性结果写入 research。
- 这种情况下不改用 Mica 或 Tabbed。

### R9 — 记录材质契约

- 探针和最终机制写入 `research/unfocused-acrylic.md` 的探针表。
- `WINDOWS_APPEARANCE.md` 的亚克力一节补充失焦行为和最终采用的机制。

## Acceptance Criteria

- [ ] 在 Windows 11 25H2 build 26200 上，获焦窗口仍显示当前 Desktop Acrylic，壁纸透过标题栏和页面，文字清晰。
- [ ] 同一窗口失焦后，标题栏和页面仍显示实时模糊桌面，不出现失焦截图中的均匀实色。文字、菜单和输入控件保持不透明。
- [ ] 失焦期间切换浅色和深色后，模糊色调跟随新主题；重新获焦后 Desktop Acrylic 也跟随新主题。
- [ ] `--solid-background` 在获焦和失焦时都保持实色，且不调用亚克力或 Accent 模糊。
- [ ] 系统透明效果关闭或高对比度开启时，失焦路径不强制加模糊。
- [ ] `flutter_app/test/window_material_test.dart` 覆盖实色开关、获焦效果序号 4，以及主题变化会把启用状态和明暗标志发给 runner。
- [ ] `flutter analyze` 与 `flutter test` 通过。Rust、网络、启动和 Dream Skin 代码无改动时，不把它们的失败算作本任务回归。
- [ ] research 探针表和 `WINDOWS_APPEARANCE.md` 写明最终机制。若 R8 触发，视觉行为与修复前一致，文档记录阴性结果。

## Out of Scope

- macOS 窗口材质。
- 用 Mica、Tabbed 或自绘壁纸替换获焦或失焦玻璃。
- 截取其他窗口像素来自制模糊。
- 升级 Flutter、`flutter_acrylic` 或其他依赖。
- 修改客户发现、启动、设置 JSON、网络查询、Dream Skin 或时钟暂停条件。
- 改变预览模式已经会初始化原生材质的现有行为。
- 填写 `.trellis/spec/frontend/` 占位规范。
