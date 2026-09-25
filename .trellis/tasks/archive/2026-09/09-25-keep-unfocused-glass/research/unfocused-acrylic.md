# 失焦后玻璃背景消失：证据

规划日期：2026-09-25。本文件只记录已核对的代码、SDK 和截图。实现时的探针结果追加在文末，不覆盖本节。

## 用户可见现象

两张截图是同一主窗口，间隔约一分钟。

| 状态 | 时钟 | 背景 |
| --- | --- | --- |
| 窗口获焦 | 19:51:08，2026-09-25 星期五 | 桌面紫色壁纸透过标题栏和页面；卡片为更深的半透明层；文字清晰 |
| 窗口失焦 | 19:52:20，同一日期 | 标题栏和页面变成均匀深灰；壁纸采样消失；卡片仍与页面有轻微色差；文字仍清晰 |

两张图的外观菜单都是「跟随系统」，客户路径都指向 `ChatGPT.exe`。失焦图底部状态从「Dream Skin 已启动」变为启动结果文案，这是两次截图之间执行了启动，不解释背景变化。

规划时用 `DwmGetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)` 枚举可见窗口，没有找到标题含「时区启动器」的窗口。属性读数要在实现探针里补。

## 本机环境

| 项 | 值 |
| --- | --- |
| `DisplayVersion` | 25H2 |
| `CurrentBuild.UBR` | 26200.9550 |
| 注册表 `ProductName` | Windows 10 Pro（Windows 11 上常见的旧字符串，不以它判断版本） |
| `EnableTransparency` | 1 |
| `AppsUseLightTheme` | 0 |
| 已安装 SDK | `10.0.26100.0` |
| `flutter_acrylic` | 1.1.4，锁定在 `flutter_app/pubspec.yaml` |

透明效果注册表值为 1，获焦时玻璃正常。失焦实色发生在透明效果仍然开启时。

## 应用当前怎么铺玻璃

`WindowMaterial.apply` 只在启动和明暗主题变化时调用一次插件：

```23:27:flutter_app/lib/services/window_material.dart
  static Future<void> apply(bool dark) => Window.setEffect(
    effect: WindowEffect.acrylic,
    dark: dark,
    color: dark ? const Color(0xb8202024) : const Color(0xb8f5f5f7),
  );
```

`LauncherApplication._syncMaterial` 在 `materialDark == dark` 时直接返回，没有窗口激活监听。`flutter_app/lib/app/launcher_page.dart` 的 `didChangeAppLifecycleState` 只在 `hidden` / `paused` / `detached` 时停时钟，不修改材质。

亚克力主题把页面骨架背景设为 alpha 0，卡片保留半透明，文字和控件保持不透明：

```26:34:flutter_app/lib/app/theme.dart
  // Only the page backdrop is transparent. Menus and input surfaces retain
  // their opaque fill so desktop content cannot reduce their readability.
  return acrylic
      ? theme.copyWith(
          scaffoldStyle: theme.scaffoldStyle.copyWith(
            backgroundColor: base.background.withValues(alpha: 0),
          ),
        )
      : theme;
```

因此失焦后如果 DWM 在窗口后面铺上实色，透明骨架会把实色直接显示出来，文字仍由 Flutter 不透明像素绘制。这与失焦截图一致。

`WINDOWS_APPEARANCE.md` 记录当前契约：Windows 11 使用 DWM Desktop Acrylic，原生读数 `DWMWA_SYSTEMBACKDROP_TYPE=3`，并且「没有降低整个窗口的透明度」。

## 插件在本机版本上的实际调用

`WindowEffect` 序号：`disabled=0`，`solid=1`，`transparent=2`，`aero=3`，`acrylic=4`，`mica=5`，`tabbed=6`。控件测试断言 `SetEffect` 的 `effect` 为 4（`flutter_app/test/window_material_test.dart`）。

插件源码在 Pub Cache：`flutter_acrylic-1.1.4/windows/flutter_acrylic_plugin.cpp`。构建号 `>= 22523` 且 `effect > 3` 时走系统背景，不走旧 Accent：

- 先把 Accent 设为 `ACCENT_DISABLED`。
- `DwmExtendFrameIntoClientArea` 边距为 -1。
- `DWMWA_USE_IMMERSIVE_DARK_MODE` 使用参数 `dark`。
- `DWMWA_CAPTION_COLOR = 0xFFFFFFFE`（`DWMWA_COLOR_NONE`）。
- `effect == 4` 时 `DWMWA_SYSTEMBACKDROP_TYPE = 3`。

SDK `um/dwmapi.h`（10.0.26100.0，约第 100–108 行）对应该值：

| 值 | 枚举 | 插件中的效果 |
| --- | --- | --- |
| 0 | `DWMSBT_AUTO` | 未使用 |
| 1 | `DWMSBT_NONE` | 未使用 |
| 2 | `DWMSBT_MAINWINDOW` | `mica` |
| 3 | `DWMSBT_TRANSIENTWINDOW` | `acrylic` |
| 4 | `DWMSBT_TABBEDWINDOW` | `tabbed` |

该头文件没有「非活动窗口继续采样亚克力」的枚举或属性。`DWMWA_SYSTEMBACKDROP_TYPE` 在这份 SDK 里是最后一个背景相关属性。

同一分支解析了 `color`，随后没有读取它。构建号 `>= 22523` 时，Dart 传入的 `0xb8202024` / `0xb8f5f5f7` 不到达 DWM。获焦时的深色玻璃来自系统暗色 Desktop Acrylic。

构建号低于 22523 的旧路径才会把 Color 编成 Accent 的 ABGR：`A<<24 | B<<16 | G<<8 | R`。深色 `0xB8202024` 对应 `0xB8242020`，浅色 `0xB8F5F5F7` 对应 `0xB8F7F5F5`。

## 失焦机制

`DWMSBT_TRANSIENTWINDOW` 是瞬态窗口材质。窗口不再是活动窗口时，DWM 停止采样背后桌面，并用实色填充原先的透明区域。属性可以保持为 3。重新调用 `Window.setEffect(WindowEffect.acrylic)` 只是再写一次同一个属性，不能让非活动窗口恢复采样。

Flutter 引擎会在视图 `WM_KILLFOCUS` 后于下一轮任务把生命周期改成 `inactive`（本机 SDK `windows_lifecycle_manager.cc` 的 `UpdateState`，`flutter_window.cc` 的 `WM_KILLFOCUS`）。这个信号比 DWM 换底色晚一帧，而且 `Window.setEffect` 本身不能覆盖该策略。DWM 切换必须在顶层窗口的 `WM_ACTIVATE` 里同步完成。

现有 runner 对 `WM_ACTIVATE` 不区分 `wParam`，活动和非活动都 `SetFocus(child_content_)`（`flutter_app/windows/runner/win32_window.cpp` 第 216–219 行）。失焦截图中窗口能够停留在非活动状态，这行 `SetFocus` 不产生实色底。非活动分支若再调用 `SetFocus`，可能把窗口重新激活。

## 不能直接改用插件的 Aero

`WindowEffect.aero` 的序号是 3，不满足 `effect > 3`，会走旧 Accent。从上一次的亚克力（`window_effect_last_ > 3`）切过去时，插件会：

- 把扩展边距改回 `{0, 0, 1, 0}`。
- 关闭沉浸式暗色。
- 关闭旧的 `MICA_EFFECT`（属性 1029）。
- 不把 `DWMWA_SYSTEMBACKDROP_TYPE` 设回 `DWMSBT_NONE`。

因此 `Window.setEffect(WindowEffect.aero)` 不能当作失焦实现。系统背景类型 3 会留下，边距和暗色模式还会被清掉。

## 候选机制

按优先顺序。前一个探针达到验收，就不做下一个。

1. `WCA_FORCE_ACTIVEWINDOW_APPEARANCE`（插件头文件中的 composition 属性 15）。在亚克力已经设好后写入 `BOOL TRUE`。若失焦时 Desktop Acrylic 仍在采样、文字仍不透明、获焦外观不变，就采用它。属性的数据布局不在 SDK 文档里，探针失败则放弃，不把它写成既定 API。
2. 失焦时把背景类型设为 `DWMSBT_NONE`，再设置 `ACCENT_ENABLE_BLURBEHIND`（Accent 状态 3，flags 沿用插件的 2），渐变色从现有 Color 常量换算。保持边距 -1、沉浸式暗色和 `DWMWA_COLOR_NONE`。获焦时按插件 1.1.4 的 Windows 11 序列恢复 `DWMSBT_TRANSIENTWINDOW`。这是实时模糊，没有亚克力噪声纹理，允许和获焦画面有轻微差异。
3. 两者都不能在 build 26200 上保持实时模糊时，撤销失焦材质改动，保留获焦亚克力，把阴性结果写回本文件。

Mica（类型 2）和 Tabbed（类型 4）失焦后仍保留壁纸主题色。它们采样的是壁纸主题，画面与当前实时玻璃不同，获焦外观也会改变。本任务不使用这两种材质。

不采用 `SetLayeredWindowAttributes` 或 `WS_EX_LAYERED`。那会降低文字和控件的不透明度，违反 `WINDOWS_APPEARANCE.md`。

## 实现探针记录

2026-09-25，在本机 build 26200.9550 上用临时 Win32 窗口测量。洋红色不透明窗口铺在受试窗口后面。受试窗口使用与 `flutter_acrylic` 1.1.4 相同的扩展边距 -1、沉浸式暗色和 `DWMWA_CAPTION_COLOR = 0xFFFFFFFE`。GDI 客户区是不透明白色，不能代表 Flutter 的透明交换链；标题栏像素能露出系统背景，作为实时采样的传感器。洋红分数是 `(R+B)/2-G`。分数 223 表示采到了背后的洋红窗口，分数 0 表示中性实色。

| 探针 | backdrop | 标题栏 | 洋红分数 | 前景 |
| --- | --- | --- | --- | --- |
| Desktop Acrylic 获焦 | 3 | 223,0,223 | 223 | 是 |
| Desktop Acrylic 失焦 | 3 | 84,84,84 | 0 | 否 |
| 失焦后写 `WCA_FORCE_ACTIVEWINDOW_APPEARANCE=TRUE` | 3 | 84,84,84 | 0 | 否 |
| 去掉该标志并重新获焦 | 3 | 223,0,223 | 223 | 是 |
| `DWMSBT_NONE` 后 `ACCENT_ENABLE_BLURBEHIND`，flags 0 或 2，alpha `0x01`，获焦 | 1 | 0,0,0 | 0 | 是 |
| 同上，失焦 | 1 | 43,43,43 | 0 | 否 |
| 旧 Accent Acrylic（状态 4）获焦 | 1 | 0,0,0 | 0 | 是 |
| 旧 Accent Acrylic 失焦 | 1 | 43,43,43 | 0 | 否 |

`WS_EX_NOREDIRECTIONBITMAP` 整窗亚克力的客户区读数是获焦 `146,146,146`、失焦 `84,84,84`，强制活动外观后仍是 `84,84,84`。这条路径没有透出洋红窗口。

## 结论

R8 已触发。两个候选机制都没有在失焦时保留实时采样。强制活动外观不改变已失焦的 Desktop Acrylic。切到 Blur-Behind 或旧 Accent Acrylic 后，获焦标题栏也不再采样背后的窗口。产品代码保持「只在启动和主题变化时设置 Desktop Acrylic」。没有改用 Mica 或 Tabbed。临时探针已删除。
