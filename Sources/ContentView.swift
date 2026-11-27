import SwiftUI
import AppKit

// MARK: - 配色（高对比实色，避免朦胧）
/// 由 ContentView / SettingsView 在 body 计算前同步；
/// 不用 NSColor(name:dynamicProvider:) —— 该 API 在本机渲染路径下会被错误套上色彩滤镜（实测偏青）。
/// 默认深色：背景更深、边框与次要文字对比更强，去掉低透明度色晕。
enum Theme {
    static var isDark = true

    private static func c(_ light: String, _ dark: String) -> Color {
        Color(hex: isDark ? dark : light)
    }

    static var bg: Color { c("F4F6F9", "080A0E") }
    static var bgElevated: Color { c("FFFFFF", "0E1117") }
    static var card: Color { c("FFFFFF", "141821") }
    static var cardTop: Color { c("F7F9FC", "1A1F2A") }
    static var border: Color { c("C7CFDA", "3A4352") }
    static var primary: Color { c("1F5FBF", "6FA3FF") }
    static var accent: Color { c("A85F16", "FFB063") }
    static var positive: Color { c("137A4B", "5FD9A4") }
    static var risk: Color { c("B92E39", "FF7A84") }
    static var violet: Color { c("6A46BF", "B7A0FF") }
    static var text: Color { c("11161E", "F7F9FC") }
    static var sub: Color { c("3E4856", "ADB8C8") }
    static var faint: Color { c("6B7686", "7E8A9B") }
}

extension Color {
    init(hex: String) {
        let h = hex.dropFirst().prefix(6)
        var v: UInt64 = 0
        Scanner(string: String(h)).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - 主视图
struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @Environment(\.colorScheme) private var colorScheme

    private var showAbout: Binding<Bool> {
        Binding(get: { monitor.showAbout }, set: { monitor.showAbout = $0 })
    }

    var body: some View {
        // 外观：手动深浅优先，跟随系统时用环境值；去掉半透明色晕以避免发灰朦胧
        let resolvedDark = monitor.appearanceMode == 2 ||
            (monitor.appearanceMode == 0 && colorScheme == .dark)
        Theme.isDark = resolvedDark
        return ZStack(alignment: .top) {
            // 窗口位置记忆（挂在背景层，不干扰布局）
            WindowAccessor(onTop: monitor.windowOnTop)
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    overviewGrid
                    sectionTitle("实时监控", icon: "waveform.path.ecg")
                    detailGrid
                    sectionTitle("硬件状态与告警", icon: "gauge.badge.plus")
                    healthGrid
                    sectionTitle("媒体与智能", icon: "sparkles")
                    HStack(alignment: .top, spacing: 16) {
                        musicCard
                        aiServicesCard
                    }
                    sectionTitle("进程", icon: "list.bullet")
                    Text("进程 CPU 为单核百分比（与活动监视器一致）；顶部总 CPU 为全核汇总，两者口径不同不可直接相加。点击列头排序，点击进程行看详情，右键结束进程。")
                        .font(.system(size: 11)).foregroundColor(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 16) {
                        aiProcessCard
                        processCard
                    }
                    footer
                }
                .padding(22)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .preferredColorScheme(monitor.appearanceMode == 1 ? .light :
                                monitor.appearanceMode == 2 ? .dark : nil)
        .sheet(isPresented: showAbout) { aboutView }
        .sheet(item: selectedProcessBinding) { _ in
            ProcessDetailView(monitor: monitor)
        }
    }

    private var selectedProcessBinding: Binding<ProcessEntry?> {
        Binding(get: { monitor.selectedProcess }, set: { monitor.selectedProcess = $0 })
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [Theme.primary, Theme.violet],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .shadow(color: Theme.primary.opacity(0.35), radius: 12, y: 4)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("MacPulse").font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("系统性能监视器").font(.system(size: 13, weight: .medium)).foregroundColor(Theme.sub)
                }
                Text("\(monitor.chipName)  ·  \(monitor.perfCores) 性能核 + \(monitor.effCores) 能效核  ·  macOS \(monitor.osVersion)")
                    .font(.system(size: 12)).foregroundColor(Theme.faint)
            }
            Spacer()
            HStack(spacing: 7) {
                PulsingDot(color: Theme.positive)
                Text("LIVE").font(.system(size: 11, weight: .bold)).foregroundColor(Theme.positive)
                Text(refreshLabel).font(.system(size: 11)).foregroundColor(Theme.faint)
                Rectangle().fill(Theme.border).frame(width: 1, height: 12)
                Text("自身 \(String(format: "%.1f", monitor.selfCPU))% · \(String(format: "%.0f", monitor.selfMemMB))MB")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.sub)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))

            Menu {
                Button("复制文本快照") { SnapshotExporter.copyText(monitor) }
                Button("保存 CSV…") { SnapshotExporter.saveCSV(monitor) }
                Button("保存快照 PNG…") { SnapshotExporter.savePNG(monitor) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15)).foregroundColor(Theme.sub)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("导出快照（文本 / CSV / PNG）")

            Button { SettingsWindowController.shared.show(monitor: monitor) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16)).foregroundColor(Theme.sub)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("偏好设置")

            Button { showAbout.wrappedValue = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 17)).foregroundColor(Theme.sub)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("关于")
        }
    }

    private var refreshLabel: String {
        let v = monitor.refreshInterval
        return v == v.rounded() ? "每 \(Int(v)) 秒刷新" : "每 \(String(format: "%.1f", v)) 秒刷新"
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.primary)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.sub)
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .padding(.top, 2)
    }

    // MARK: 概览卡片（第 4 张：有电池显示电池，台式机显示系统负载）
    private var overviewGrid: some View {
        HStack(spacing: 14) {
            GaugeCard(title: "CPU 使用率", value: monitor.cpu.total,
                      detail: String(format: "用户 %.0f%% · 系统 %.0f%% · 空闲 %.0f%%",
                                     monitor.cpu.user, monitor.cpu.system, monitor.cpu.idle),
                      color: monitor.cpu.total > 80 ? Theme.risk : Theme.primary,
                      icon: "cpu", unit: "%")
            GaugeCard(title: "内存占用", value: monitor.memory.total > 0 ? Double(monitor.memory.used) / Double(monitor.memory.total) * 100 : 0,
                      detail: "\(fmtBytes(Double(monitor.memory.used))) / \(fmtBytes(Double(monitor.memory.total)))",
                      color: Theme.accent, icon: "memorychip", unit: "%")
            GaugeCard(title: "磁盘占用", value: monitor.disk.total > 0 ? Double(monitor.disk.total - monitor.disk.free) / Double(monitor.disk.total) * 100 : 0,
                      detail: "已用 \(fmtBytes(Double(monitor.disk.total - monitor.disk.free))) / \(fmtBytes(Double(monitor.disk.total)))",
                      color: Theme.positive, icon: "internaldrive", unit: "%")
            if monitor.battery.present {
                GaugeCard(title: "电池", value: Double(monitor.battery.percent),
                          detail: "\(monitor.battery.percent)% · \(monitor.battery.charging ? "充电中" : monitor.battery.source)",
                          color: Theme.positive, icon: "battery.100percent", unit: "%")
            } else {
                loadCard
            }
        }
    }

    private var loadCard: some View {
        Card(title: "系统负载", icon: "speedometer", badge: String(format: "%.2f", monitor.loadOne)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.2f", monitor.loadOne))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.primary)
                        .contentTransition(.numericText(value: monitor.loadOne))
                        .animation(.easeOut(duration: 0.35), value: monitor.loadOne)
                    Text("1 分钟均值").font(.system(size: 11)).foregroundColor(Theme.sub)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Text(String(format: "5m %.2f", monitor.loadFive))
                        .font(.system(size: 11)).foregroundColor(Theme.sub)
                    Text(String(format: "15m %.2f", monitor.loadFifteen))
                        .font(.system(size: 11)).foregroundColor(Theme.sub)
                }
                Text("\(monitor.perfCores + monitor.effCores) 逻辑核 · 持续高于核数表示排队")
                    .font(.system(size: 11)).foregroundColor(Theme.faint).lineLimit(1)
            }
        }
    }

    // MARK: 实时监控
    private var detailGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Card(title: "CPU 负载历史", icon: "chart.xyaxis.line", badge: String(format: "%.0f%%", monitor.cpu.total)) {
                    Sparkline(data: monitor.cpuHistory, color: Theme.primary, maxValue: 100,
                              showAxes: true, timeSpan: "50s", unit: "%")
                    Divider().background(Theme.border)
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(Array(monitor.cpu.perCore.enumerated()), id: \.offset) { idx, v in
                            CoreCell(index: idx, value: v, isPerformance: idx < monitor.perfCores)
                        }
                    }
                }
                Card(title: "内存历史", icon: "chart.xyaxis.line",
                     badge: String(format: "%.0f%%", monitor.memory.total > 0 ? Double(monitor.memory.used) / Double(monitor.memory.total) * 100 : 0)) {
                    Sparkline(data: monitor.memHistory, color: Theme.accent, maxValue: 100,
                              showAxes: true, timeSpan: "50s", unit: "%")
                    Divider().background(Theme.border)
                    MemBreakdown(m: monitor.memory)
                }
            }
            HStack(spacing: 14) {
                Card(title: "网络流量", icon: "network", badge: monitor.network.primaryInterface) {
                    HStack(spacing: 22) {
                        MetricCell(label: "下载", systemImage: "arrow.down", value: fmtSpeed(monitor.network.downBytesPerSec), color: Theme.positive)
                        MetricCell(label: "上传", systemImage: "arrow.up", value: fmtSpeed(monitor.network.upBytesPerSec), color: Theme.accent)
                    }
                    Sparkline(data: monitor.downHistory, color: Theme.positive, maxValue: nil,
                              showAxes: true, timeSpan: "50s", unit: "B/s")
                }
                Card(title: "磁盘 I/O", icon: "arrow.up.arrow.down") {
                    HStack(spacing: 22) {
                        MetricCell(label: "读取", systemImage: "arrow.down", value: fmtSpeed(monitor.disk.readBytesPerSec), color: Theme.primary)
                        MetricCell(label: "写入", systemImage: "arrow.up", value: fmtSpeed(monitor.disk.writeBytesPerSec), color: Theme.accent)
                    }
                    Divider().background(Theme.border)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "thermometer").font(.system(size: 12)).foregroundColor(Theme.faint)
                        Text(monitor.thermals.note).font(.system(size: 11)).foregroundColor(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: 硬件状态与告警
    private var healthGrid: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Card(title: "GPU 利用率", icon: "cpu", badge: monitor.gpu.utilization >= 0 ? String(format: "%.0f%%", monitor.gpu.utilization) : "—") {
                    if monitor.gpu.utilization >= 0 {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 4) {
                                ForEach(0..<20) { i in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Double(i) < monitor.gpu.utilization / 5 ? Theme.violet : Theme.border)
                                        .frame(height: 18)
                                }
                            }
                            Text(monitor.gpu.source).font(.system(size: 11)).foregroundColor(Theme.faint)
                        }
                    } else {
                        // 不可读时用确定存在的系统事实填充，避免大片空白
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle").font(.system(size: 13)).foregroundColor(Theme.faint)
                                Text("本机无可信的公开 GPU 利用率接口（IOReport 受系统策略限制）")
                                    .font(.system(size: 11)).foregroundColor(Theme.sub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 14) {
                                Label("\(monitor.perfCores + monitor.effCores) 逻辑核", systemImage: "cpu")
                                Label(String(format: "负载 %.2f", monitor.loadOne), systemImage: "speedometer")
                            }
                            .font(.system(size: 11)).foregroundColor(Theme.faint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Card(title: "热状态", icon: "thermometer",
                     badge: monitor.thermals.state,
                     badgeColor: monitor.thermals.stateRaw == 0 ? Theme.positive
                        : monitor.thermals.stateRaw == 1 ? Theme.accent : Theme.risk) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            ForEach(0..<4) { i in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(i <= monitor.thermals.stateRaw ? thermalColor(i) : Theme.border)
                                    .frame(maxWidth: .infinity, minHeight: 14)
                            }
                        }
                        HStack(spacing: 14) {
                            Text("级别 \(monitor.thermals.stateRaw)/3 · ProcessInfo.thermalState")
                            Text("运行 \(fmtUptime(monitor.uptime))")
                        }
                        .font(.system(size: 11)).foregroundColor(Theme.faint)
                        .lineLimit(1)
                    }
                }
            }
            HStack(spacing: 14) {
                Card(title: "磁盘健康 (S.M.A.R.T.)", icon: "internaldrive",
                     badge: monitor.smartDisks.isEmpty ? "—" : "\(monitor.smartDisks.filter { $0.status.lowercased() == "verified" }.count)/\(monitor.smartDisks.count) 正常",
                     badgeColor: monitor.smartDisks.allSatisfy { $0.status.lowercased() == "verified" } ? Theme.positive : Theme.accent) {
                    VStack(alignment: .leading, spacing: 7) {
                        if monitor.smartDisks.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle").font(.system(size: 13)).foregroundColor(Theme.faint)
                                Text("未读取到 S.M.A.R.T. 信息").font(.system(size: 11)).foregroundColor(Theme.faint)
                            }
                            .frame(height: 30)
                        } else {
                            ForEach(monitor.smartDisks) { d in
                                HStack(spacing: 8) {
                                    Image(systemName: d.status.lowercased() == "verified" ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                        .font(.system(size: 14)).foregroundColor(d.status.lowercased() == "verified" ? Theme.positive : Theme.accent)
                                    Text(d.disk).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Theme.text)
                                    Text(d.status).font(.system(size: 11)).foregroundColor(Theme.sub)
                                    Spacer()
                                    Text("diskutil info · 每 5 秒").font(.system(size: 10)).foregroundColor(Theme.faint)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 30)
                }
                Card(title: "阈值告警", icon: "bell.badge") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 12) {
                            alertStepper(label: "CPU", value: Binding(
                                get: { monitor.alertConfig.cpu },
                                set: { monitor.alertConfig.cpu = $0; monitor.requestAlertPermission() }
                            ))
                            alertStepper(label: "内存", value: Binding(
                                get: { monitor.alertConfig.memory },
                                set: { monitor.alertConfig.memory = $0; monitor.requestAlertPermission() }
                            ))
                            alertStepper(label: "持续", value: Binding(
                                get: { Double(monitor.alertConfig.holdSeconds) },
                                set: { monitor.alertConfig.holdSeconds = max(1, Int($0)) }
                            ), isSeconds: true)
                        }
                        Text(monitor.alertStatus.isEmpty ? "0 = 关闭告警 · 连续超标 N 秒才通知（30 秒内不重复）" : monitor.alertStatus)
                            .font(.system(size: 11))
                            .foregroundColor(monitor.alertStatus.isEmpty ? Theme.faint : Theme.risk)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func thermalColor(_ i: Int) -> Color {
        i == 0 ? Theme.positive : i == 1 ? Theme.accent : i == 2 ? Color(hex: "E88C4A") : Theme.risk
    }

    private func alertStepper(label: String, value: Binding<Double>, isSeconds: Bool = false) -> some View {
        let step: Double = isSeconds ? 1 : 10
        let lower: Double = isSeconds ? 1 : 0
        let upper: Double = isSeconds ? 30 : 100
        return HStack(spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundColor(Theme.sub)
            Button { value.wrappedValue = max(lower, value.wrappedValue - step) } label: {
                Image(systemName: "minus.circle").foregroundColor(Theme.sub)
            }.buttonStyle(.plain)
            Text(isSeconds ? "\(Int(value.wrappedValue))s" : (value.wrappedValue == 0 ? "关" : "\(Int(value.wrappedValue))%"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(value.wrappedValue == 0 ? Theme.faint : Theme.primary)
                .frame(width: 40)
            Button { value.wrappedValue = min(upper, value.wrappedValue + step) } label: {
                Image(systemName: "plus.circle").foregroundColor(Theme.sub)
            }.buttonStyle(.plain)
        }
    }

    // MARK: 音乐
    private var musicCard: some View {
        let np = monitor.nowPlaying
        return Card(title: "正在播放", icon: "music.note", badge: np.app) {
            if np.title == "当前无媒体播放" {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Theme.border, lineWidth: 2).frame(width: 52, height: 52)
                        Circle().stroke(Theme.border, lineWidth: 2).frame(width: 34, height: 34)
                        Circle().fill(Theme.cardTop).frame(width: 14, height: 14)
                        Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(Theme.faint)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("当前无媒体播放").font(.system(size: 14, weight: .medium)).foregroundColor(Theme.sub)
                        Text("播放音乐后会显示曲目与进度").font(.system(size: 11)).foregroundColor(Theme.faint)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Theme.primary.opacity(0.28), Theme.violet.opacity(0.15)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                        Image(systemName: np.isPlaying ? "waveform" : "music.note")
                            .font(.system(size: 22)).foregroundColor(Theme.primary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(np.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("\(np.artist) · \(np.album)").font(.system(size: 11)).foregroundColor(Theme.sub).lineLimit(1)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.border)
                                Capsule().fill(LinearGradient(colors: [Theme.primary, Theme.violet], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: np.duration > 0 ? g.size.width * CGFloat(min(max(np.elapsed / np.duration, 0), 1)) : 0)
                            }
                        }.frame(height: 4)
                        HStack {
                            Text(fmtTime(np.elapsed)).font(.system(size: 10)).foregroundColor(Theme.faint)
                            Spacer()
                            Text(fmtTime(np.duration)).font(.system(size: 10)).foregroundColor(Theme.faint)
                        }
                    }
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 5) {
                            PulsingDot(color: np.isPlaying ? Theme.positive : Theme.faint)
                            Text(np.isPlaying ? "播放中" : "已暂停")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(np.isPlaying ? Theme.positive : Theme.sub)
                        }
                    }
                }
            }
        }
    }

    // MARK: AI 服务
    private var aiServicesCard: some View {
        let online = monitor.aiServices.filter { $0.online }.count
        return Card(title: "本地 AI 服务", icon: "server.rack", badge: "\(online)/\(monitor.aiServices.count) 在线") {
            VStack(spacing: 6) {
                ForEach(monitor.aiServices) { svc in
                    HStack(spacing: 7) {
                        Circle().fill(svc.online ? Theme.positive : Theme.faint.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .shadow(color: svc.online ? Theme.positive.opacity(0.6) : .clear, radius: 4)
                        Text(svc.name).font(.system(size: 12, weight: .medium))
                            .frame(width: 80, alignment: .leading)
                        Text(":" + String(svc.port)).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.faint)
                            .frame(width: 44, alignment: .leading)
                        Spacer()
                        if svc.online {
                            Text(svc.latencyMs < 0.1 ? "<0.1 ms" : String(format: "%.1f ms", svc.latencyMs))
                                .font(.system(size: 11, weight: .medium)).foregroundColor(Theme.positive)
                        } else {
                            Text("—").font(.system(size: 11)).foregroundColor(Theme.faint)
                        }
                    }
                    .frame(height: 22)
                }
            }
        }
    }

    // MARK: AI 进程
    private var aiProcessCard: some View {
        let ai = monitor.aiProcesses
        let totalMem = ai.reduce(0) { $0 + $1.memMB }
        return Card(title: "AI 进程", icon: "sparkles",
                    badge: ai.isEmpty ? "无" : "\(ai.count) 个 · \(String(format: "%.0f", totalMem)) MB") {
            if ai.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "moon.zzz").font(.title3).foregroundColor(Theme.faint)
                    Text("当前未检测到 AI 相关进程").font(.system(size: 12)).foregroundColor(Theme.sub)
                    Spacer()
                }.frame(minHeight: 44)
            } else {
                ForEach(ai) { p in
                    HStack(spacing: 8) {
                        Image(systemName: "cpu").font(.system(size: 11)).foregroundColor(Theme.violet)
                        Text(p.name).font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        MiniBar(value: p.cpu, color: p.cpu > 20 ? Theme.risk : Theme.violet).frame(width: 60)
                        Text(String(format: "%.1f%%", p.cpu)).font(.system(size: 11, design: .monospaced))
                            .foregroundColor(p.cpu > 20 ? Theme.risk : Theme.sub).frame(width: 46, alignment: .trailing)
                        Text(String(format: "%.0f MB", p.memMB)).font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.sub).frame(width: 60, alignment: .trailing)
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture { monitor.selectProcess(p) }
                }
            }
        }
    }

    // MARK: 进程表（列头排序 + 点击详情 + 右键结束进程）
    private var processCard: some View {
        Card(title: "CPU 占用 Top 8", icon: "list.bullet") {
            HStack {
                sortHeader(.pid, title: "PID", width: 56, alignment: .leading)
                sortHeader(.name, title: "进程名", width: nil, alignment: .leading)
                sortHeader(.cpu, title: "负载", width: 68, alignment: .leading)
                sortHeader(.cpu, title: "CPU", width: 50, alignment: .trailing)
                sortHeader(.memMB, title: "内存", width: 68, alignment: .trailing)
            }
            Divider().background(Theme.border)
            ForEach(Array(monitor.processes.enumerated()), id: \.offset) { idx, p in
                HStack(spacing: 8) {
                    Text(String(p.pid)).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.faint)
                        .frame(width: 56, alignment: .leading)
                    Text(p.name).font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    MiniBar(value: p.cpu, color: p.cpu > 20 ? Theme.risk : Theme.primary).frame(width: 60)
                    Text(String(format: "%.1f%%", p.cpu)).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(p.cpu > 20 ? Theme.risk : Theme.text).frame(width: 50, alignment: .trailing)
                    Text(String(format: "%.0f MB", p.memMB)).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.sub).frame(width: 68, alignment: .trailing)
                }
                .frame(height: 26)
                .background(idx % 2 == 0 ? Color.white.opacity(0.025) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { monitor.selectProcess(p) }
                .contextMenu {
                    Button("结束进程 \(p.name)（PID \(p.pid)）", role: .destructive) {
                        monitor.terminateProcess(p.pid)
                    }
                }
            }
            if !monitor.processActionMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundColor(Theme.accent)
                    Text(monitor.processActionMessage).font(.system(size: 11)).foregroundColor(Theme.sub)
                    Spacer()
                    Button("清除") { monitor.processActionMessage = "" }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundColor(Theme.primary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func sortHeader(_ key: ProcessSortKey, title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Button { monitor.setProcessSort(key) } label: {
            HStack(spacing: 2) {
                Text(title)
                if monitor.processSortKey == key {
                    Image(systemName: monitor.processSortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundColor(monitor.processSortKey == key ? Theme.primary : Theme.faint)
            .font(.system(size: 11, weight: .semibold))
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
        }
        .buttonStyle(.plain)
        .help("按 \(title) 排序")
    }

    private var footer: some View {
        HStack {
            Image(systemName: "server.rack").font(.system(size: 11)).foregroundColor(Theme.faint)
            Text("\(monitor.hostname) · macOS \(monitor.osVersion) (\(monitor.buildVersion)) · 已运行 \(fmtUptime(monitor.uptime))")
                .font(.system(size: 11)).foregroundColor(Theme.faint)
            Spacer()
            Text("更新于 \(monitor.lastUpdate.formatted(date: .omitted, time: .standard))")
                .font(.system(size: 11)).foregroundColor(Theme.faint)
        }
        .padding(.top, 4)
    }

    private var aboutView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg").font(.title2).foregroundColor(Theme.primary)
                Text("关于 MacPulse").font(.system(size: 18, weight: .bold))
            }
            Text("原生 macOS 性能监视器。所有指标通过 Mach / IOKit / libproc 等系统接口直接读取，不依赖 top、ps 等外部命令。")
                .font(.system(size: 12)).foregroundColor(Theme.sub)
            Text("数据口径").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
            Text("• CPU / 内存：host_statistics64 两次采样求差\n• 磁盘 IO：IOKit 块存储驱动累计字节求差\n• 网络：getifaddrs 链路层字节求差\n• 进程 / AI 进程：libproc taskinfo 采样 + 进程名关键词识别\n• AI 服务：仅对 127.0.0.1 端口做 TCP 连通探测（每 2 秒）\n• 正在播放：MediaRemote 读取系统 Now Playing（只读）\n• 系统负载：sysctl vm.loadavg（1/5/15 分钟均值）\n• 温度 / 风扇：Apple Silicon 无免密公开接口，故不显示估算值")
                .font(.system(size: 11)).foregroundColor(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
            Button("关闭") { showAbout.wrappedValue = false }
                .buttonStyle(.borderedProminent).tint(Theme.primary).frame(maxWidth: .infinity)
        }
        .padding(24).frame(width: 460)
    }
}

// MARK: - 通用组件

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    var badge: String? = nil
    var badgeColor: Color = Theme.primary
    let content: Content

    init(title: String, icon: String, badge: String? = nil, badgeColor: Color = Theme.primary, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.badge = badge; self.badgeColor = badgeColor; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.primary)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                if let badge = badge {
                    Text(badge).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor.opacity(0.12)))
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(LinearGradient(colors: [Theme.cardTop, Theme.card], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

private struct GaugeCard: View {
    let title: String
    let value: Double
    let detail: String
    let color: Color
    let icon: String
    var unit: String = "%"

    var body: some View {
        Card(title: title, icon: icon) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                        .contentTransition(.numericText(value: value))
                        .animation(.easeOut(duration: 0.35), value: value)
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(color.opacity(0.75))
                    Spacer()
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.border)
                        Capsule().fill(LinearGradient(colors: [color.opacity(0.65), color],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * min(max(value / 100, 0), 1))
                        Circle().fill(color)
                            .frame(width: 9, height: 9)
                            .offset(x: g.size.width * min(max(value / 100, 0), 1) - 4.5)
                            .shadow(color: color.opacity(0.8), radius: 4)
                    }
                }
                .frame(height: 7)
                Text(detail).font(.system(size: 11)).foregroundColor(Theme.sub).lineLimit(1)
            }
        }
    }
}

private struct PulsingDot: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = 0.5 + 0.5 * sin(t * 3.2)
            Circle().fill(color).frame(width: 7, height: 7)
                .scaleEffect(0.85 + 0.25 * phase)
                .opacity(0.7 + 0.3 * phase)
                .shadow(color: color.opacity(0.7), radius: 5)
        }
    }
}

private struct MetricCell: View {
    let label: String
    let systemImage: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium)).foregroundColor(color)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text).lineLimit(1)
        }
    }
}

private struct MiniBar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(color)
                    .frame(width: g.size.width * CGFloat(min(max(value / 100, 0), 1)))
            }
        }.frame(height: 4)
    }
}

// Catmull-Rom 样条转三次贝塞尔：曲线严格过每个数据点，x 方向单调（时间轴不回退）
private func appendSmoothCurve(_ path: inout Path, points pts: [CGPoint]) {
    guard pts.count > 1 else { return }
    if pts.count == 2 { path.addLine(to: pts[1]); return }
    for i in 0..<(pts.count - 1) {
        let p0 = pts[i > 0 ? i - 1 : 0]
        let p1 = pts[i]
        let p2 = pts[i + 1]
        let p3 = pts[i + 2 < pts.count ? i + 2 : pts.count - 1]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                         y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                         y: p2.y - (p3.y - p1.y) / 6)
        path.addCurve(to: p2, control1: c1, control2: c2)
    }
}

private struct Sparkline: View {
    let data: [Double]
    let color: Color
    let maxValue: Double?
    var showAxes: Bool = false
    var timeSpan: String = "50s"
    var unit: String = ""

    var body: some View {
        GeometryReader { g in
            let padL: CGFloat = showAxes ? 42 : 0
            let padB: CGFloat = showAxes ? 17 : 0
            let w = max(g.size.width - padL, 1)
            let h = max(g.size.height - padB, 1)
            let vals = data.isEmpty ? [0.0] : data
            let peak = maxValue ?? max(vals.max() ?? 1, 1)
            let dataMax = vals.max() ?? 0
            let avg = vals.reduce(0, +) / Double(vals.count)
            let pts = vals.enumerated().map { i, v -> CGPoint in
                CGPoint(x: padL + w * CGFloat(i) / CGFloat(max(vals.count - 1, 1)),
                        y: h - h * CGFloat(min(max(v / peak, 0), 1)))
            }

            ZStack(alignment: .topLeading) {
                // 网格线
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Divider().background(Theme.border.opacity(0.45))
                        Spacer(minLength: 0)
                    }
                    Divider().background(Theme.border.opacity(0.45))
                }
                .frame(height: h)
                .padding(.leading, padL)

                // Y 轴刻度
                if showAxes {
                    VStack(spacing: 0) {
                        Text(fmtAxis(peak)).frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        Text(fmtAxis(peak / 2)).frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                        Text(fmtAxis(0)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 10)).foregroundColor(Theme.faint)
                    .frame(width: padL - 6, height: h, alignment: .leading)
                }

                // 渐变填充
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    appendSmoothCurve(&p, points: pts)
                    p.addLine(to: CGPoint(x: padL + w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(gradient: Gradient(colors: [color.opacity(0.28), color.opacity(0.01)]),
                                     startPoint: .top, endPoint: .bottom))

                // 平滑曲线
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    appendSmoothCurve(&p, points: pts)
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // 统计文字
                if showAxes {
                    HStack(spacing: 10) {
                        Text("均值 \(fmtAxis(avg))")
                        Text("峰值 \(fmtAxis(dataMax))")
                    }
                    .font(.system(size: 10)).foregroundColor(Theme.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 2)
                }

                // 末端呼吸点
                if let last = pts.last {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let phase = 0.5 + 0.5 * sin(t * 4)
                        Circle().fill(color).frame(width: 6, height: 6)
                            .scaleEffect(0.9 + 0.35 * phase)
                            .opacity(0.75 + 0.25 * phase)
                            .position(last)
                            .shadow(color: color.opacity(0.9), radius: 5)
                    }
                }

                // X 轴时间
                if showAxes {
                    HStack {
                        Text("−\(timeSpan)")
                        Spacer()
                        Text("现在")
                    }
                    .font(.system(size: 10)).foregroundColor(Theme.faint)
                    .frame(width: w, height: padB, alignment: .leading)
                    .offset(x: padL, y: h)
                }
            }
        }
        .frame(height: showAxes ? 86 : 62)
    }

    private func fmtAxis(_ v: Double) -> String {
        if unit == "%" { return String(format: "%.0f%%", v) }
        if v >= 1_048_576 { return String(format: "%.1fM", v / 1_048_576) }
        if v >= 1024 { return String(format: "%.0fK", v / 1024) }
        return String(format: "%.0f", v)
    }
}

private struct CoreCell: View {
    let index: Int
    let value: Double
    let isPerformance: Bool

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.border).frame(width: 20)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isPerformance ? Theme.primary : Theme.violet.opacity(0.85))
                        .frame(width: 20, height: max(3, g.size.height * CGFloat(min(max(value / 100, 0), 1))))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 20, height: 34)
            Text("C\(index)").font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isPerformance ? Theme.primary.opacity(0.85) : Theme.violet.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MemBreakdown: View {
    let m: MemoryUsage
    var body: some View {
        VStack(spacing: 7) {
            MemRow(label: "wired 联动", bytes: m.wired, total: m.total, color: Theme.risk)
            MemRow(label: "compressed 压缩", bytes: m.compressed, total: m.total, color: Theme.accent)
            MemRow(label: "cached 缓存", bytes: m.cached, total: m.total, color: Theme.positive)
            HStack {
                Text("swap 已用").font(.system(size: 11)).foregroundColor(Theme.faint)
                Spacer()
                Text(fmtBytes(Double(m.swapUsed))).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.sub)
            }
        }
    }
}

private struct MemRow: View {
    let label: String
    let bytes: UInt64
    let total: UInt64
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.sub).frame(width: 116, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.border)
                    Capsule().fill(color)
                        .frame(width: g.size.width * (total > 0 ? CGFloat(Double(bytes) / Double(total)) : 0))
                }
            }.frame(height: 5)
            Text(fmtBytes(Double(bytes))).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.sub)
                .frame(width: 60, alignment: .trailing)
        }
    }
}
