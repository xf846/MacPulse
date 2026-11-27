import Foundation
import AppKit
import SwiftUI

/// macOS 菜单栏常驻控制器（iStat Menus 风格）。
/// 左键点击状态项弹出快速视图 Popover；右键显示菜单（显示主窗口 / 关于 / 退出）。
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let item: NSStatusItem
    private let monitor: SystemMonitor
    private let popover = NSPopover()
    private var timer: Timer?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        updateTitle()
    }

    private func configure() {
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "MacPulse")
        button.image?.size = NSSize(width: 15, height: 15)
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // 不用 item.menu：左键交给 Popover；右键自己在 action 里弹菜单
        item.menu = nil

        popover.contentViewController = NSHostingController(rootView: MenuPopoverView(monitor: monitor, controller: self))
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 290, height: 370)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = buildMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
            return
        }
        if popover.isShown { popover.performClose(sender) }
        else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let show = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let settings = NSMenuItem(title: "偏好设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "关于 MacPulse", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem.separator())

        let exportItem = NSMenuItem(title: "导出快照", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let copy = NSMenuItem(title: "复制文本快照", action: #selector(exportText), keyEquivalent: "")
        copy.target = self
        let csv = NSMenuItem(title: "保存 CSV…", action: #selector(exportCSV), keyEquivalent: "")
        csv.target = self
        let png = NSMenuItem(title: "保存快照 PNG…", action: #selector(exportPNG), keyEquivalent: "")
        png.target = self
        sub.addItem(copy); sub.addItem(csv); sub.addItem(png)
        exportItem.submenu = sub
        menu.addItem(exportItem)
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出 MacPulse", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func updateTitle() {
        item.isVisible = monitor.menuBarVisible
        guard monitor.menuBarVisible, let button = item.button else { return }
        let mem = monitor.memory.total > 0 ? Int((Double(monitor.memory.used) / Double(monitor.memory.total) * 100).rounded()) : 0
        var parts: [String] = []
        for metric in monitor.menuMetrics {
            switch metric {
            case .cpu:   parts.append("C\(Int(monitor.cpu.total.rounded()))%")
            case .memory: parts.append("M\(mem)%")
            case .down:  parts.append("↓\(Self.compactSpeed(monitor.network.downBytesPerSec))")
            case .up:    parts.append("↑\(Self.compactSpeed(monitor.network.upBytesPerSec))")
            case .load:  parts.append("L\(String(format: "%.1f", monitor.loadOne))")
            case .disk:  parts.append("D\(Self.compactSpeed(monitor.disk.readBytesPerSec))")
            }
        }
        button.title = parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    static func compactSpeed(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1fM", bps / 1_048_576) }
        if bps >= 1024 { return String(format: "%.0fK", bps / 1024) }
        return String(format: "%.0fB", bps)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc func showMainWindow() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.isVisible && $0.frame.size.width > 500 }) {
            win.makeKeyAndOrderFront(nil)
        }
    }

    @objc func showSettings() {
        closePopover()
        SettingsWindowController.shared.show(monitor: monitor)
    }

    @objc func showAbout() {
        closePopover()
        monitor.showAbout = true
        showMainWindow()
    }

    @objc private func exportText() { SnapshotExporter.copyText(monitor) }
    @objc private func exportCSV() { SnapshotExporter.saveCSV(monitor) }
    @objc private func exportPNG() { SnapshotExporter.savePNG(monitor) }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {}

    deinit { timer?.invalidate() }
}

// MARK: - Popover 快速视图（SwiftUI）

private struct MenuPopoverView: View {
    @ObservedObject var monitor: SystemMonitor
    let controller: MenuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg").foregroundColor(.blue)
                Text("MacPulse").font(.system(size: 14, weight: .bold))
                Spacer()
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("实时").font(.system(size: 10)).foregroundColor(.secondary)
            }

            // 两个核心环
            HStack(spacing: 14) {
                miniGauge(label: "CPU", value: monitor.cpu.total, color: .blue)
                miniGauge(label: "内存", value: monitor.memory.total > 0 ? Double(monitor.memory.used)/Double(monitor.memory.total)*100 : 0, color: .orange)
            }

            Divider()

            VStack(spacing: 7) {
                row(icon: "arrow.down", label: "下载", value: MenuBarController.compactSpeed(monitor.network.downBytesPerSec) + "/s", color: .green)
                row(icon: "arrow.up", label: "上传", value: MenuBarController.compactSpeed(monitor.network.upBytesPerSec) + "/s", color: .orange)
                row(icon: "arrow.up.arrow.down", label: "磁盘读", value: fmt(monitor.disk.readBytesPerSec) + "/s", color: .blue)
                row(icon: "thermometer", label: "热状态", value: monitor.thermals.state, color: monitor.thermals.stateRaw == 0 ? .green : .orange)
                let gpu = monitor.gpu.utilization
                row(icon: "cpu", label: "GPU", value: gpu >= 0 ? String(format: "%.0f%%", gpu) : "—", color: .purple)
                let online = monitor.aiServices.filter { $0.online }.count
                row(icon: "sparkles", label: "AI 服务", value: "\(online)/\(monitor.aiServices.count) 在线", color: .green)
            }

            Divider()
            if !monitor.alertStatus.isEmpty {
                Text(monitor.alertStatus).font(.system(size: 10)).foregroundColor(.red).lineLimit(2)
            }
            HStack(spacing: 8) {
                Button { controller.showMainWindow() } label: {
                    Label("打开主窗口", systemImage: "macwindow")
                        .font(.system(size: 11)).frame(maxWidth: .infinity)
                }
                Button { controller.quitApp() } label: {
                    Image(systemName: "power").font(.system(size: 11))
                }
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private func miniGauge(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                Circle().trim(to: min(1, value/100))
                    .stroke(color, lineWidth: 6)
                Text("\(Int(value))%").font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .frame(width: 56, height: 56)
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color).frame(width: 18)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    private func fmt(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1fM", bps/1_048_576) }
        if bps >= 1024 { return String(format: "%.0fK", bps/1024) }
        return String(format: "%.0fB", bps)
    }
}
