# MacPulse — macOS 系统性能监视器

原生 macOS 桌面应用（Swift 6 + SwiftUI），仪表盘实时显示 CPU / 内存 / 磁盘 / 网络 / 电池 / 系统负载 / GPU / 热状态 / S.M.A.R.T. / 进程 / AI 服务 / 媒体播放等参数，支持独立偏好设置窗口、高对比深浅主题、菜单栏读数自定义、进程详情、快照导出（文本 / CSV / PNG）、进程表交互与阈值告警历史。

## 界面设计

- **独立偏好设置窗口**：主界面右上角齿轮按钮，或菜单栏右键「偏好设置…」（⌘,）打开。包含外观、刷新间隔、菜单栏显示项勾选、主窗口置顶、告警阈值与最近告警记录、恢复默认，修改即时生效并自动保存
- **高对比实色主题**：默认深色（`#080A0E` 底 + `#141821` 卡片 + 明确边框），另可选浅色或跟随系统；移除半透明色晕，文字/边框对比度整体提升，避免发灰朦胧
- 卡片采用实色填充、清晰描边、柔和阴影的统一视觉语言
- 概览卡：大号圆体数字（带滚动过渡）+ 带发光端点的粗进度条；无内置电池时第 4 张卡替换为「系统负载」（1 分钟均值 + 5m/15m）
- 折线图：Y 轴刻度 + X 轴时间轴（−50s → 现在）+ 均值/峰值标注 + 网格参考线 + 渐变填充 + 呼吸发光端点，曲线用 Catmull-Rom 样条平滑（过点、时间轴不回退）
- 逐核柱按性能核（蓝）/ 能效核（紫）区分
- 分区标题（实时监控 / 硬件状态与告警 / 媒体与智能 / 进程）+ 呼吸状态胶囊（LIVE）
- **自身开销**：header 的 LIVE 胶囊显示 MacPulse 自身 CPU / 内存（复用进程快照，单核口径，不额外采集）
- 主窗口可设为「始终在最前」（设置里开关，`.floating` 层级，不盖系统 UI）
- **可自定义菜单栏读数**：默认 `C 42% M 76% ↓3.7M`，可在偏好设置中任意勾选 CPU / 内存 / 下载 / 上传 / 负载 / 磁盘读速（按固定顺序拼接），例：`C26% M75% ↓4K L4.3`。左键弹出 **Popover 快速视图**，右键出「显示主窗口 / 偏好设置… / 关于 / 导出快照 / 退出」菜单
- 窗口位置与大小自动记忆（UserDefaults），重启后恢复
- 进程表斑马纹 + 迷你负载条，**点击列头排序**（PID / 进程名 / CPU / 内存，再点反向），**点击进程行看详情**（完整路径 / 线程数 / TCP 监听端口，按需读取 lsof 不进入刷新循环），**右键结束进程**（SIGTERM，带结果提示；保护 PID 1 与自身）
- AI 服务卡在线/离线状态点；GPU 不可读时卡片改为展示逻辑核数与系统负载，不留大片空白
- 同行卡片等高对齐；「AI 进程」与「CPU 占用 Top 8」左右并排，媒体与 AI 服务卡并排
- **快照导出**：header 上传图标或菜单栏右键「导出快照」→ 复制完整文本报告 / 保存 CSV（带 BOM，Excel 中文不乱码）/ 保存 PNG 长图；全部本机生成、无网络上报

## 运行

```bash
open build/MacPulse.app
```

双击即可。首次运行 macOS 会弹「是否允许访问本地网络」——点**允许**（`getifaddrs` 读网络接口需要），之后不再提示。

源码构建要求：macOS 13+ 与 Xcode 命令行工具（`swiftc`，Swift 6）。不需要 Xcode 工程或第三方依赖；应用为 ad-hoc 签名，首次打开可右键「打开」放行。

## 显示的指标（默认每秒刷新，可在偏好设置改为 0.5 / 1 / 2 / 5 秒）

| 区域 | 指标 | 数据来源 |
|---|---|---|
| CPU | 总使用率（用户/系统/空闲）、历史折线、8 核逐核占用 | Mach `host_statistics64` / `host_processor_info` 两次采样求差 |
| 内存 | 已用/总量、历史折线、wired / compressed / cached / swap 细分 | Mach `host_statistics64(HOST_VM_INFO64)` + `sysctl vm.swapusage` |
| 磁盘 | 容量占用、读取/写入速率 | `FileManager.attributesOfFileSystem` + IOKit `IOBlockStorageDriver` 累计字节求差 |
| 网络 | 上传/下载速率、历史折线、主接口名 | BSD `getifaddrs` 链路层字节求差（自动跳过 lo0 / 隧道口） |
| 电池 | 电量百分比、充电状态（台式机显示"无内置电池"） | IOKit `IOPSCopyPowerSourcesInfo` |
| 进程 | CPU 占用 Top 8（PID / 进程名 / CPU / 内存），单核百分比口径，列头可排序、右键可结束 | libproc `proc_listpids` + `PROC_PIDTASKINFO` + `PROC_PIDPATHINFO` 采样求差；结束走 `kill(SIGTERM)` |
| 系统负载 | 1/5/15 分钟平均负载（台式机在概览第 4 张卡展示） | `/usr/bin/uptime` 输出解析（沙箱下 `sysctl vm.loadavg` 返回长度异常且 buffer 未填充，不可信），每 5 秒 |
| GPU | GPU 利用率（不可读时显示 —，不编数字） | IOReport 私有接口动态加载（`libIOReport.dylib`），每 5 秒 |
| 热状态 | nominal / fair / serious / critical 四档 | `ProcessInfo.processInfo.thermalState`（Apple 公开接口，免 root） |
| 磁盘健康 | 枚举所有物理磁盘（本机 disk0 + disk4）分别读 S.M.A.R.T. 状态 | `diskutil list physical` + `diskutil info -plist <disk>`，每 5 秒 |
| 阈值告警 | CPU / 内存阈值（0=关闭）+ 连续超标秒数（默认 3s，防抖动），超阈值发系统通知，30 秒不重复；最近 30 条触发/恢复事件在偏好设置里查看（仅内存，不落盘） | `UNUserNotificationCenter`，用户首次调阈值时请求授权 |
| AI 进程 | 识别 WorkBuddy / Claude / Codex / Ollama / Python 等 6 个，按内存排序 | 同一份 libproc 快照 + 进程名关键词匹配 |
| 本地 AI 服务 | CC Switch :15721、Ollama :11434、LM Studio :1234、llama.cpp :8080、vLLM :8000 的在线状态与回环延迟（每 2 秒） | POSIX `connect()` 到 127.0.0.1，不收发数据 |
| 正在播放 | 曲名 / 艺人 / 专辑 / 播放进度 / 来源 App（Apple Music、Spotify、MyGo 等） | MediaRemote 私有框架 `MRMediaRemoteGetNowPlayingInfo`（只读） |
| 系统 | 芯片型号、性能核/能效核、macOS 版本、主机名、运行时长 | `sysctl` + `ProcessInfo` |
| 菜单栏 | 可勾选读数（CPU/内存/下载/上传/负载/磁盘读速）+ Popover 快速视图 | 复用同一份 SystemMonitor 数据，1 秒刷新 |
| 进程详情 | 完整可执行文件路径、线程数、TCP 监听端口 | `PROC_PIDPATHINFO` / `PROC_PIDTASKINFO` + `lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN`（点击时读取一次） |
| 快照导出 | 文本报告 / CSV / PNG 长图，含全部指标与最近告警 | `SnapshotExporter`：本机 `NSPasteboard` / `NSSavePanel` / `NSAttributedString` 渲染，无网络 |

**温度 / 热状态**：CPU 绝对温度（摄氏度）在本机无法可靠读取——已实测排除：① SMC 私有调用 `IOConnectCallStructMethod` 返回 `kIOReturnUnsupported`；② `hw.temperature` 等 sysctl 键不存在；③ IOKit AppleARMIO / IOHIDSystem 属性无温度字段；④ IOReport 的 `PMP/Volt-Temp HM` 通道虽能订阅（含 E0_V_T / P0_V_T / G0_V_T），但走 `RawElements` 自定义二进制结构（`IOReportSimpleGetIntegerValue` 返回 `Int64.min`），无公开解析口径。为避免编造数字，应用改用 Apple 公开的 `ProcessInfo.thermalState` 给出四档热状态（正常 / 轻度受热 / 明显受热 / 严重受热）。

**进程 CPU 口径**：进程 CPU 是**单核百分比**（单核满载 = 100%，与「活动监视器」一致）；顶部总 CPU 是**全核汇总**（8 核相加，最高 800%→归一到 100%）。两者口径不同，Top8 之和小于总 CPU 是正常的，不可直接相加对比。

**GPU 利用率**：走 IOReport 私有接口（Stats 项目同款方案），动态加载避免启动崩溃。在受限沙箱 / 系统策略下通道被清空，界面如实显示"—（该环境不可读）"；正常双击运行可读到真实值。

**媒体播放说明**：走 macOS 系统级 Now Playing 机制（MediaRemote），任何向系统注册播放信息的 App 都能读到。无播放时显示"当前无媒体播放"。在受限沙箱内 MediaRemote 的跨进程信息被隔离，只能验证到降级态；正常双击运行时可读取真实播放信息。

## 源码结构

```
MacPulse/
  Sources/
    MacPulseApp.swift    # @main 入口（单例持有 Monitor）
    SystemMonitor.swift  # 采集层：Mach / IOKit / libproc 封装 + 数据模型 + 格式化
    ContentView.swift    # SwiftUI 高对比仪表盘（卡片、自绘折线图、进度条、告警状态）
    SettingsView.swift   # 独立偏好设置窗口（外观 / 刷新 / 菜单栏读数 / 置顶 / 告警历史 / 恢复默认）
    SnapshotExporter.swift # 快照导出：文本报告 / CSV / PNG 长图（本机生成）
    ProcessDetailView.swift # 进程详情弹窗（路径 / 线程数 / 监听端口，避开 @State 宏）
    MenuBarController.swift # 菜单栏常驻（NSStatusItem + NSPopover 快速视图 + 右键菜单）
    WindowAccessor.swift  # NSWindow 桥接：窗口位置/大小记忆（UserDefaults）
  tools/make_icon.py     # 图标绘制脚本（Pillow，输出母图与 iconset）
  icons/
    macpulse_1024.png    # 图标母图（1024×1024）
    MacPulse.icns        # 应用图标（多尺寸）
    MacPulse.iconset/    # 图标源尺寸集合
  build/MacPulse.app     # 编译产物（运行 ./build.sh 后生成，未纳入版本控制）
```

图标为「深蓝渐变圆角方形 + 发光脉冲波形」（已去掉白色描边与同心圆网格），呼应应用主题；绘制脚本见 `tools/make_icon.py`。

## 重新编译

```bash
cd <仓库目录>
./build.sh
```

脚本会自动安装图标、编译并签名（若需重绘图标，先运行 `python3 tools/make_icon.py` 再 `iconutil -c icns icons/MacPulse.iconset -o icons/MacPulse.icns`）。

> 注意：本机 Xcode 27.2 SDK 的 SwiftUI 编译器宏插件（`@State` / `@StateObject`）与命令行 swiftc 不兼容，源码刻意避开这些宏（用单例 + `@ObservedObject` + 显式 Binding），保证 `swiftc` 直接可编。

## 已知限制

- 进程 CPU% 基于 libproc taskinfo 的纳秒累计差，短采样间隔下读数偏保守（趋势准确）。
- 磁盘读写速率是两台块存储驱动累计字节的差值，代表该采样周期内所有磁盘的总吞吐。
- 应用为纯本地监控，无网络通信、无数据上报。
- PNG 导出是「文本快照渲染的深色长图」，不是窗口像素截图——SDK 27 已废弃 `CGWindowListCreateImage` / `NSWindow.snapshot`，自绘更稳定且信息完整。
- 进程监听端口依赖 `lsof`，受限沙箱下可能返回空（界面显示 —），不影响其他指标。

## 许可

MIT License，详见 [LICENSE](LICENSE)。
