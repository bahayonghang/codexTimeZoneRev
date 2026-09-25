# 执行计划：失焦后保持玻璃背景

## 实施步骤

1. **确认基线**
   - 阅读 `research/unfocused-acrylic.md`、`WINDOWS_APPEARANCE.md`、`flutter_app/lib/services/window_material.dart` 和 `flutter_acrylic` 1.1.4 的 `windows/flutter_acrylic_plugin.cpp` `SetEffect`。
   - 确认工作区没有把 Pub Cache 或生成插件注册文件算进改动。

2. **只读探针**
   - 启动当前应用并获焦，读取顶层 HWND 的 `DWMWA_SYSTEMBACKDROP_TYPE`。
   - 切到其他窗口后再读一次，同时观察画面。
   - 预期：两次都是 3，失焦画面已经是实色。若失焦属性不是 3，停止实现并更新 research，不按本设计继续改。
   - 探针程序放在临时目录，结束后删除。

3. **强制活动外观探针**
   - 在亚克力生效后设置 `WCA_FORCE_ACTIVEWINDOW_APPEARANCE`。
   - 检查获焦、失焦、再获焦三态，以及文字是否仍不透明。
   - 成功则把这一属性写入 runner 的同步函数，跳过步骤 4。
   - 失败则去掉该属性，记录失败现象。

4. **失焦 Blur-Behind**
   - 新增 runner 内的背景同步函数，按 `design.md` 的第二选择实现。
   - 在 `FlutterWindow::OnCreate` 注册 `codex_timezone/window_material`。
   - `WM_ACTIVATE` 调用同步函数；只有活动状态才 `SetFocus` 子窗口。
   - `WindowMaterial.apply` 先调用现有 `Window.setEffect`，再发送 `setPolicy`。
   - 初始化失败或 `--solid-background` 不发送 `enabled: true`。
   - `setPolicy` 失败不把已经启用的亚克力主题改回实色。

5. **控件测试**
   - 扩展 `flutter_app/test/window_material_test.dart` 的通道模拟。
   - 断言实色开关没有原生调用。
   - 断言深色主题仍发送 `effect == 4`，并且 `setPolicy` 收到 `enabled: true` 与 `dark: true`。
   - 断言页面骨架 alpha 仍为 0，卡片 alpha 小于 1，前景 alpha 为 1。

6. **视觉验收**
   - 获焦：与修复前的 Desktop Acrylic 一致。
   - Alt-Tab 失焦：标题栏和页面仍是实时模糊，不是均匀实色。
   - 再获焦：Desktop Acrylic 恢复，边框和标题按钮正常。
   - 失焦时切换浅色、深色，再获焦，两种状态都跟随主题。
   - `--solid-background` 在两种状态下都是实色。
   - 若本机可以临时关闭透明效果或打开高对比度，确认失焦时没有强制模糊，然后恢复原设置。
   - 最小化后恢复，确认没有卡住的实色或残留 Accent。

7. **文档与清理**
   - 填写 research 探针表。
   - 更新 `WINDOWS_APPEARANCE.md` 的亚克力一节。
   - 删除临时探针。若 R8 触发，撤回产品代码中的失焦策略，只保留文档中的阴性结果。

## 验证命令

```powershell
flutter test test/window_material_test.dart
flutter analyze
flutter test
```

在 `flutter_app` 目录执行。Windows runner 有 C++ 改动时，用一次 `just dev` 或现有的 Windows 运行脚本打开真实窗口做步骤 6。不启动真实 Codex 客户。

Rust 核心、安装脚本和网络代码没有改动时，不需要为它们单独跑验收。

## 风险与停止点

- 只读探针显示失焦属性不是 3：停止，先修正原因判断。
- 两个实时模糊探针都失败：执行 R8，不改用 Mica。
- `setPolicy` 在启动时找不到通道：修正注册顺序后再验收，不吞掉获焦亚克力。
- Blur-Behind 让文字变淡、边框丢失或拖动窗口明显错位：判定该探针失败，按 R8 撤回。

## 回退点

产品改动集中在：

- `flutter_app/lib/services/window_material.dart`
- `flutter_app/lib/app/application.dart`（仅当失败处理需要区分通道错误）
- `flutter_app/windows/runner/flutter_window.cpp`
- `flutter_app/windows/runner/win32_window.cpp`
- 新增的 runner 背景同步源文件
- `flutter_app/test/window_material_test.dart`
- `WINDOWS_APPEARANCE.md`

撤回时恢复这些文件即可。不改 Pub Cache。
