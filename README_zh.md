# APC UPS Monitor (macOS 菜单栏监视器)

<p align="left">
  <a href="README.md"><b>English</b></a> | <a href="README_zh.md"><b>简体中文</b></a>
</p>

专为 APC Back-UPS（主要针对 Back-UPS ES 600M1 / BE600M1）设计的轻量级 macOS 原生菜单栏监控小工具。

<p align="center">
  <img src="assets/screenshot-menu.png" alt="主菜单视图" width="280" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/screenshot-diagnostics.png" alt="诊断面板视图" width="280" />
</p>

## 功能特性

- **非独占只读共享设计**：不需要运行 `apcupsd` 或 NUT 服务。仅以 `kIOHIDOptionsTypeNone` 共享只读方式打开 USB HID 设备，**绝不抢占控制权**，完整保留 macOS 原生电源管理和低电量自动关机功能。
- **实时功耗与状态显示**：在菜单栏动态展示实时估算功耗（`瓦数 = 额定功率 330W × 负载率`）、当前负载率、市电输入电压、电池电量及剩余续航时间。
- **子进程隔离与防卡死架构**：采集任务由独立的短命子进程异步执行，并配备 5 秒超时强杀看门狗，确保底层驱动调用绝不阻塞主应用界面或状态栏。
- **完善的休眠与唤醒自愈**：深度监听系统睡眠/唤醒生命周期，休眠时自动挂起，唤醒后自愈重连，杜绝死锁与陈旧句柄失效问题。
- **内置诊断面板**：支持一键切换展开诊断视图，可实时查看系统 `IOPowerSources` 原生字典及原始 USB HID 元素报告。

## 运行与安装

- **方式一（命令行一键编译与安装）**：
  ```bash
  # 仅在本地编译生成 APCUPSMonitor.app
  ./build.sh

  # 编译并直接安装到系统「应用程序」文件夹 (/Applications)
  ./build.sh install
  ```
- **方式二（Xcode）**：
  在 Xcode 中打开 `APCUPSMonitor.xcodeproj` 并点击 Run 运行。

> 注：应用已配置 `LSUIElement = true`，启动后仅常驻于顶部菜单栏，不会占用 Dock 图标。

## 安全性验证

启动本应用后，请确认 macOS「系统设置 -> 电池」或顶部原生电池菜单中仍可正常识别该 UPS 及其电量。本应用严格遵守只读共享原则，绝不会调用 `kIOHIDOptionsTypeSeizeDevice`。

如果负载率显示为 `—`，可点击 **Diagnostics → HID** 查看当前设备的原始 Usage 报告值。

## 0.1.2 架构与自愈说明

- 原生系统电源读数与 HID 读数在独立的子进程中并行执行，5 秒超时强杀，即使设备断开或驱动异常也不影响 UI。
- 系统电源数据每 2 秒轮询一次；HID 读取成功间隔 2 秒，设备不可用时自动退避至 30 秒以节省系统资源。点击刷新或展开菜单立即跳过退避。
- 定时器挂载于 RunLoop `.common` 模式，在菜单展开或鼠标交互时持续刷新。
- 可运行 `./Tests/run.sh` 执行完整的故障注入回归测试。

命令行只读诊断模式（输出 JSON，无图形界面）：
```bash
./APCUPSMonitor.app/Contents/MacOS/APCUPSMonitor --read-system
./APCUPSMonitor.app/Contents/MacOS/APCUPSMonitor --read-hid
```

## 开源协议

本项目采用 [MIT 许可证](LICENSE) 开源。

## 0.1.4 长时间运行内存优化

菜单栏文字改用 AppKit `NSStatusItem`，只在显示内容变化时更新，不再让
SwiftUI `MenuBarExtra` 常驻监听所有数据刷新。详情面板在打开时创建，关闭时
释放；读取时间改为普通格式化文本。

详情面板新增 **Show data in menu bar（在菜单栏显示数据）** 开关，默认关闭，
仅显示图标；开启后显示功率、负载或电量，重启后保留选择。新增用户级单实例
保护，防止安装版与开发版重复启动，读取子进程不受影响。

每 2 秒刷新、独立读取进程、超时恢复和
只读共享 HID 访问均保留。

故障机器的 0.1.2 版本连续运行约 17 天后，实际内存占用达到 3.9 GiB，主要是
数百万个 SwiftUI 视图、文本和闭包对象。本次移除了持续保留的菜单栏视图树。
短期压力测试不能代替数周运行，也未必覆盖原故障的所有触发条件。

内存回归测试（需要已登录的 macOS 图形桌面，测试期间会临时显示测试菜单栏项）：

```bash
./Tests/memory.sh           # 连续更新 5,000 次，检查内存增长上限
./Tests/memory.sh --panel   # 同时反复打开、关闭详情面板
./Tests/memory.sh --legacy  # 与旧 MenuBarExtra 实现对照
./Tests/memory.sh --reader  # 独立读取进程连续运行 2,000 次
```
