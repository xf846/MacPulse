import SwiftUI
import AppKit

// MARK: - 偏好设置窗口

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(monitor: SystemMonitor) {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: SettingsView(monitor: monitor))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 1000),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "MacPulse 偏好设置"
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

// MARK: - 设置界面

struct SettingsView: View {
    @ObservedObject var monitor: SystemMonitor
    @Environment(\.colorScheme) private var colorScheme

    private func bind<T>(_ get: @escaping () -> T, set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }

    private var appearance: Binding<Int> {
        bind({ monitor.appearanceMode }, set: { monitor.appearanceMode = $0 })
    }
    private var interval: Binding<Double> {
        bind({ monitor.refreshInterval }, set: { monitor.refreshInterval = $0 })
    }
    private var menuVisible: Binding<Bool> {
        bind({ monitor.menuBarVisible }, set: { monitor.menuBarVisible = $0 })
    }
    private func menuMetricToggle(_ metric: MenuMetric) -> Binding<Bool> {
        bind({ monitor.menuMetrics.contains(metric) }, set: { on in
            var items = monitor.menuMetrics
            if on {
                if !items.contains(metric) { items.append(metric) }
            } else {
                items.removeAll { $0 == metric }
            }
            // 固定按枚举顺序显示，勾选顺序不影响菜单栏排列
            items.sort { MenuMetric.allCases.firstIndex(of: $0)! < MenuMetric.allCases.firstIndex(of: $1)! }
            monitor.menuMetrics = items
        })
    }
    private var onTop: Binding<Bool> {
        bind({ monitor.windowOnTop }, set: { monitor.windowOnTop = $0 })
    }
    private var cpuAlert: Binding<Double> {
        bind({ monitor.alertConfig.cpu }, set: { monitor.alertConfig.cpu = $0; monitor.requestAlertPermission() })
    }
    private var memAlert: Binding<Double> {
        bind({ monitor.alertConfig.memory }, set: { monitor.alertConfig.memory = $0; monitor.requestAlertPermission() })
    }
    private var hold: Binding<Double> {
        bind({ Double(monitor.alertConfig.holdSeconds) }, set: { monitor.alertConfig.holdSeconds = max(1, Int($0)) })
    }

    var body: some View {
        let resolvedDark = monitor.appearanceMode == 2 ||
            (monitor.appearanceMode == 0 && colorScheme == .dark)
        Theme.isDark = resolvedDark

        return ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 22, weight: .semibold)).foregroundColor(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("偏好设置").font(.system(size: 20, weight: .bold))
                    Text("所有设置立即生效并自动保存").font(.system(size: 11)).foregroundColor(Theme.sub)
                }
                Spacer()
            }
            .padding(.bottom, 4)

            SettingsGroup(title: "外观", icon: "paintbrush", note: "解决界面发灰、朦胧——深色为高对比实色配色") {
                Picker("配色", selection: appearance) {
                    Text("跟随系统").tag(0)
                    Text("浅色").tag(1)
                    Text("深色").tag(2)
                }
                .pickerStyle(.segmented)
                Text("当前：\(appearanceName(monitor.appearanceMode))")
                    .font(.system(size: 11)).foregroundColor(Theme.faint)
            }

            SettingsGroup(title: "刷新与菜单栏", icon: "gauge", note: "刷新间隔越小，CPU 占用略高") {
                Picker("刷新间隔", selection: interval) {
                    Text("0.5 秒").tag(0.5)
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }
                .pickerStyle(.segmented)
                Divider().padding(.vertical, 2)
                Toggle("显示菜单栏读数", isOn: menuVisible)
                Text("菜单栏显示项（按固定顺序拼接）")
                    .font(.system(size: 11)).foregroundColor(Theme.sub)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(MenuMetric.allCases) { metric in
                        Toggle(metric.label, isOn: menuMetricToggle(metric))
                            .font(.system(size: 11))
                            .disabled(!monitor.menuBarVisible)
                    }
                }
                Divider().padding(.vertical, 2)
                Toggle("主窗口始终在最前", isOn: onTop)
            }

            SettingsGroup(title: "阈值告警", icon: "bell.badge", note: "0 = 关闭；连续超标 N 秒才通知，30 秒内不重复") {
                VStack(alignment: .leading, spacing: 12) {
                    thresholdRow(label: "CPU", value: cpuAlert)
                    Slider(value: cpuAlert, in: 0...100, step: 5)
                    Divider().padding(.vertical, 2)
                    thresholdRow(label: "内存", value: memAlert)
                    Slider(value: memAlert, in: 0...100, step: 5)
                    Divider().padding(.vertical, 2)
                    Stepper(value: hold, in: 1...30, step: 1) {
                        Text("持续时间 \(Int(hold.wrappedValue)) 秒")
                            .font(.system(size: 12)).foregroundColor(Theme.text)
                    }
                    if !monitor.alertStatus.isEmpty {
                        Text(monitor.alertStatus)
                            .font(.system(size: 11)).foregroundColor(Theme.risk)
                    }
                    if !monitor.alertHistory.isEmpty {
                        Divider().padding(.vertical, 2)
                        HStack {
                            Text("最近告警记录").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.text)
                            Spacer()
                            Button("清空记录") { monitor.clearAlertHistory() }
                                .font(.system(size: 11)).buttonStyle(.plain).foregroundColor(Theme.primary)
                        }
                        ForEach(monitor.alertHistory.prefix(3)) { event in
                            HStack(spacing: 6) {
                                Image(systemName: event.isRecovery ? "checkmark.circle" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(event.isRecovery ? Theme.positive : Theme.risk)
                                Text(event.time.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.faint)
                                Text(event.isRecovery ? "恢复" : "触发")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(event.isRecovery ? Theme.positive : Theme.risk)
                                Text(event.detail).font(.system(size: 11)).foregroundColor(Theme.sub).lineLimit(1)
                            }
                        }
                    }
                }
            }

            SettingsGroup(title: "关于", icon: "info.circle", note: "纯本地采集，无网络上报") {
                Text("版本 1.0 · Swift 6 + SwiftUI · Mach / IOKit / libproc")
                    .font(.system(size: 11)).foregroundColor(Theme.sub)
                HStack {
                    Button("恢复默认设置") { monitor.resetPreferences() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("完成") { NSApp.keyWindow?.close() }
                        .buttonStyle(.borderedProminent).tint(Theme.primary)
                }
                .padding(.top, 6)
            }
          }
          .padding(24)
          .frame(width: 660)
        }
        .frame(width: 660, height: 1000)
        .background(Theme.bg)
        .preferredColorScheme(monitor.appearanceMode == 1 ? .light :
                                monitor.appearanceMode == 2 ? .dark : nil)
    }

    private func appearanceName(_ mode: Int) -> String {
        mode == 0 ? "跟随系统" : mode == 1 ? "浅色" : "深色"
    }

    private func thresholdRow(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.text)
            Spacer()
            Text(value.wrappedValue == 0 ? "关闭" : String(format: "%.0f%%", value.wrappedValue))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(value.wrappedValue == 0 ? Theme.faint : Theme.primary)
        }
    }
}

// MARK: - 设置分组容器

private struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let note: String
    let content: Content

    init(title: String, icon: String, note: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.note = note; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.primary)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
            }
            Text(note).font(.system(size: 11)).foregroundColor(Theme.sub)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}
