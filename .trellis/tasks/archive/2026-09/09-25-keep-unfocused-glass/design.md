# 技术设计：失焦后保持玻璃背景

## 设计目标

在 Windows runner 的窗口激活边界上维持实时背景采样。获焦时的 Desktop Acrylic 仍由已锁定的 `flutter_acrylic` 1.1.4 设置。失焦时只替换 DWM 正在使用的采样策略。

## 所有权

```text
WindowMaterial.apply(dark)
    -> Window.setEffect(acrylic)          // 插件：获焦 Desktop Acrylic
    -> runner setPolicy(enabled, dark)    // 记录策略并按当前激活状态同步

WM_ACTIVATE
    -> WindowBackdrop::OnActivate
    -> 非活动：不 SetFocus
    -> 活动：SetFocus 到 Flutter 子窗口
```

`WindowMaterial` 仍是 Dart 侧唯一入口。runner 持有最新的 `enabled` 与 `dark`，因为应用主题可以和系统 `AppsUseLightTheme` 不同。

方法通道名称为 `codex_timezone/window_material`，与 macOS runner 的 `codex_timezone/network` 一样由 runner 注册，不新增 Flutter 插件。

`setPolicy` 参数：

| 字段 | 含义 |
| --- | --- |
| `enabled` | 亚克力初始化成功且用户没有传 `--solid-background` |
| `dark` | 当前应用主题是否为深色 |

调用顺序是契约：先 `Window.setEffect`，再 `setPolicy`。相反顺序会让插件在失焦时把背景类型写回 3，窗口又变成实色。

通道在 `FlutterWindow::OnCreate` 里、`RegisterPlugins` 之后注册，并保存顶层 HWND。现有插件通道能在 `main` 里调用成功，说明注册发生在 Dart 调用之前；`setPolicy` 使用同一时机。若实机出现 `MissingPluginException`，先修正注册时机，不把亚克力整体关掉。`setPolicy` 失败只记录诊断，获焦亚克力保持可用。

## 激活状态

DWM 以顶层窗口是否活动为准。同步点是 runner 的 `WM_ACTIVATE`，不使用 `AppLifecycleState.inactive`。引擎把 `WM_KILLFOCUS` 延后到下一轮任务才变成 `inactive`，晚于 DWM 铺实色。

`Win32Window::MessageHandler` 的 `WM_ACTIVATE`：

1. 调用 `WindowBackdrop::OnActivate(hwnd, wparam)`。
2. 仅当 `LOWORD(wparam) != WA_INACTIVE` 时 `SetFocus(child_content_)`。

在收到第一次 `WM_ACTIVATE` 之前，`setPolicy` 只保存策略，不改写插件刚设好的亚克力。

## 策略选择

实现时按这个顺序，前一项满足 R1 与 R3 就停止。

### 第一选择：强制活动外观

亚克力设置完成后，用插件已经加载的 `SetWindowCompositionAttribute` 写入 `WCA_FORCE_ACTIVEWINDOW_APPEARANCE`（属性 15）和 `BOOL TRUE`。每次 `setPolicy` 与每次进入非活动状态都重写一次，避免 DWM 清掉该标志。

满足以下全部条件才采用：

- 失焦时壁纸模糊仍在，标题栏和页面都不是实色。
- 获焦外观与修复前一致。
- 文字和控件不透明。
- 重新获焦后没有边框、圆角或标题按钮残留异常。

探针失败则移除这个属性，不保留半生效代码。

### 第二选择：失焦改用 Blur-Behind

仅在第一选择失败后使用。非活动且允许模糊时：

1. `DWMWA_SYSTEMBACKDROP_TYPE = DWMSBT_NONE`（1）。构建号低于 22523 时跳过这一步。
2. Accent 状态设为 `ACCENT_ENABLE_BLURBEHIND`（3），`AccentFlags` 为 2。
3. `GradientColor` 使用现有 Dart 颜色的 ABGR：深色 `0xB8242020`，浅色 `0xB8F7F5F5`。若与获焦亚克力的明暗差距明显，只调整这个 alpha，不新增主题色系统。
4. 保持边距 -1、沉浸式暗色和 `DWMWA_CAPTION_COLOR = 0xFFFFFFFE`。

活动时恢复插件 1.1.4 在构建号 `>= 22523` 上的序列：Accent `ACCENT_DISABLED`，边距 -1，沉浸式暗色，标题栏 `DWMWA_COLOR_NONE`，背景类型 `DWMSBT_TRANSIENTWINDOW`。构建号更低时恢复 `ACCENT_ENABLE_ACRYLICBLURBEHIND`，并带上同一个 ABGR 色值。版本判断使用 `ntdll!RtlGetVersion`，不用会受清单影响的 `VersionHelpers`。

这段恢复序列与插件重复，是因为失焦路径会覆盖插件写入的属性。注释标明它对应 `flutter_acrylic` 1.1.4 的 `SetEffect` Windows 11 分支。本任务不升级该包。

透明效果关闭或高对比度开启时，非活动分支不做上述两步，留下 DWM 自己的实色回退。这两项在每次进入非活动状态时读取。

## 主题同步

`WindowMaterial.apply(dark)` 在两种激活状态下都执行：

1. `Window.setEffect(effect: acrylic, dark: dark, color: 现有常量)`。
2. `setPolicy(enabled: true, dark: dark)`。runner 按当前是否活动选择第一或第二策略。

`--solid-background` 不调用 `apply`，也不发送 `enabled: true`。runner 默认 `enabled = false`，`WM_ACTIVATE` 不改 DWM。

## 测试边界

控件测试可以断言方法通道参数，不能断言 DWM 像素。`window_material_test.dart` 同时模拟 `com.alexmercerind/flutter_acrylic` 和 `codex_timezone/window_material`。

视觉验收只在 Windows 11 25H2 build 26200 的真实窗口上做。Windows 10 保留代码分支，本任务不把它列为通过条件。

## 回退

R8 触发时删除失焦策略和对应通道调用，恢复「只调用 `Window.setEffect(acrylic)`」。`WINDOWS_APPEARANCE.md` 记录两个探针都失败。不引入 Mica。

## 不改动的行为

- 预览模式仍会走 `WindowMaterial.initialize`。本任务不改变这一点。
- 时钟在 `inactive` 时继续运行。
- 插件 Pub Cache 源码保持不动。
