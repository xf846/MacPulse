import Foundation
import AppKit
import UniformTypeIdentifiers

/// 性能快照导出：复制为文本 / 保存 CSV / 保存主窗口 PNG。
/// 全部在本机完成，不上传、不联网。
@MainActor
enum SnapshotExporter {

    /// 纯文本快照（可直接粘贴到聊天 / 工单）
    static func textReport(_ m: SystemMonitor) -> String {
        let memPct = m.memory.total > 0
            ? Double(m.memory.used) / Double(m.memory.total) * 100 : 0
        let smart = m.smartDisks.map { "\($0.disk) \($0.status)" }.joined(separator: "、")
        let aiOnline = m.aiServices.filter { $0.online }.count
        let procs = m.processes.prefix(5).map { p in
            "  PID \(p.pid)  \(p.name)  CPU \(String(format: "%.1f", p.cpu))%  内存 \(String(format: "%.0f", p.memMB)) MB"
        }.joined(separator: "\n")
        let alerts = m.alertHistory.prefix(5).map { e in
            "  \(e.time.formatted(date: .omitted, time: .shortened)) \(e.isRecovery ? "恢复" : "触发") \(e.detail)"
        }.joined(separator: "\n")

        return """
        MacPulse 性能快照
        生成时间：\(m.lastUpdate.formatted(date: .abbreviated, time: .standard))
        主机：\(m.hostname) · \(m.chipName) · macOS \(m.osVersion) (\(m.buildVersion)) · 性能核 \(m.perfCores)/能效核 \(m.effCores)

        【概览】
        CPU 总使用率：\(String(format: "%.1f", m.cpu.total))%（用户 \(String(format: "%.1f", m.cpu.user))% · 系统 \(String(format: "%.1f", m.cpu.system))% · 空闲 \(String(format: "%.1f", m.cpu.idle))%）
        内存：\(String(format: "%.1f", memPct))%（已用 \(fmtBytes(Double(m.memory.used))) / 总计 \(fmtBytes(Double(m.memory.total))) · 压缩 \(fmtBytes(Double(m.memory.compressed))) · Swap \(fmtBytes(Double(m.memory.swapUsed)))）
        系统负载：\(String(format: "%.2f", m.loadOne)) / \(String(format: "%.2f", m.loadFive)) / \(String(format: "%.2f", m.loadFifteen))（1/5/15 分钟）
        磁盘：总计 \(fmtBytes(Double(m.disk.total)))，可用 \(fmtBytes(Double(m.disk.free))) · 读 \(fmtSpeed(m.disk.readBytesPerSec)) · 写 \(fmtSpeed(m.disk.writeBytesPerSec))
        网络（\(m.network.primaryInterface)）：↓ \(fmtSpeed(m.network.downBytesPerSec)) · ↑ \(fmtSpeed(m.network.upBytesPerSec)) · 累计 ↓\(fmtBytes(Double(m.network.totalDown))) ↑\(fmtBytes(Double(m.network.totalUp)))
        电池：\(m.battery.present ? "\(m.battery.percent)% · \(m.battery.charging ? "充电中" : "未充电") · \(m.battery.source)" : "台式机 / 无电池")
        已运行：\(fmtUptime(m.uptime))

        【硬件状态】
        热状态：\(m.thermals.state)（ProcessInfo.thermalState）
        GPU 利用率：\(m.gpu.utilization >= 0 ? String(format: "%.1f%%", m.gpu.utilization) : "—（当前环境不可读）")
        S.M.A.R.T.：\(smart.isEmpty ? "—（未读取到）" : smart)
        MacPulse 自身开销：\(String(format: "%.1f", m.selfCPU))% CPU · \(String(format: "%.0f", m.selfMemMB)) MB

        【媒体与本地 AI】
        正在播放：\(m.nowPlaying.isPlaying ? "\(m.nowPlaying.title) — \(m.nowPlaying.artist)（\(m.nowPlaying.app)）" : "无")
        AI 服务：\(aiOnline)/\(m.aiServices.count) 在线
        \(m.aiServices.map { "  \($0.name) \($0.port)：\($0.online ? String(format: "%.1f", $0.latencyMs) + " ms" : "离线")" }.joined(separator: "\n"))

        【进程 CPU Top 5（单核口径，与活动监视器一致）】
        \(procs.isEmpty ? "  —" : procs)

        【最近告警】
        \(alerts.isEmpty ? "  无" : alerts)

        口径说明：CPU 总使用率为全逻辑核汇总；进程 CPU 为单核等效百分比，两者不可直接相加。
        所有数据由本机 Mach / IOKit / libproc 等系统接口读取，无网络上报。
        """
    }

    /// CSV 两列表：指标, 值（UTF-8 BOM，Excel 直接打开中文不乱码）
    static func csv(_ m: SystemMonitor) -> String {
        let memPct = m.memory.total > 0
            ? Double(m.memory.used) / Double(m.memory.total) * 100 : 0
        let rows: [(String, String)] = [
            ("生成时间", m.lastUpdate.formatted(date: .abbreviated, time: .standard)),
            ("主机", m.hostname),
            ("芯片", m.chipName),
            ("macOS", "\(m.osVersion) (\(m.buildVersion))"),
            ("CPU 总使用率", String(format: "%.1f%%", m.cpu.total)),
            ("CPU 用户", String(format: "%.1f%%", m.cpu.user)),
            ("CPU 系统", String(format: "%.1f%%", m.cpu.system)),
            ("CPU 空闲", String(format: "%.1f%%", m.cpu.idle)),
            ("内存使用率", String(format: "%.1f%%", memPct)),
            ("内存已用", fmtBytes(Double(m.memory.used))),
            ("内存总计", fmtBytes(Double(m.memory.total))),
            ("内存压缩", fmtBytes(Double(m.memory.compressed))),
            ("Swap 已用", fmtBytes(Double(m.memory.swapUsed))),
            ("负载 1 分钟", String(format: "%.2f", m.loadOne)),
            ("负载 5 分钟", String(format: "%.2f", m.loadFive)),
            ("负载 15 分钟", String(format: "%.2f", m.loadFifteen)),
            ("磁盘总计", fmtBytes(Double(m.disk.total))),
            ("磁盘可用", fmtBytes(Double(m.disk.free))),
            ("磁盘读速", fmtSpeed(m.disk.readBytesPerSec)),
            ("磁盘写速", fmtSpeed(m.disk.writeBytesPerSec)),
            ("网络接口", m.network.primaryInterface),
            ("下载速率", fmtSpeed(m.network.downBytesPerSec)),
            ("上传速率", fmtSpeed(m.network.upBytesPerSec)),
            ("累计下载", fmtBytes(Double(m.network.totalDown))),
            ("累计上传", fmtBytes(Double(m.network.totalUp))),
            ("电池", m.battery.present ? "\(m.battery.percent)% \(m.battery.source)" : "无"),
            ("运行时间", fmtUptime(m.uptime)),
            ("热状态", m.thermals.state),
            ("GPU 利用率", m.gpu.utilization >= 0 ? String(format: "%.1f%%", m.gpu.utilization) : "不可读"),
            ("自身 CPU", String(format: "%.1f%%", m.selfCPU)),
            ("自身内存", String(format: "%.0f MB", m.selfMemMB)),
            ("正在播放", m.nowPlaying.isPlaying ? m.nowPlaying.title : "无"),
            ("AI 服务在线", "\(m.aiServices.filter { $0.online }.count)/\(m.aiServices.count)"),
        ]
        let header = "指标,值\n"
        let body = rows.map { "\(cell($0.0)),\(cell($0.1))\n" }.joined()
        let procRows = m.processes.map { p in
            "进程 PID \(p.pid),CPU \(String(format: "%.1f%%", p.cpu)) · 内存 \(String(format: "%.0f MB", p.memMB)) · \(cell(p.name))\n"
        }.joined()
        return "\u{FEFF}" + header + body + procRows
    }

    /// 复制到剪贴板
    static func copyText(_ m: SystemMonitor) {
        let text = textReport(m)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 另存为 CSV（NSSavePanel 由用户选位置）
    static func saveCSV(_ m: SystemMonitor) {
        let content = csv(m)
        let panel = NSSavePanel()
        panel.title = "导出性能快照（CSV）"
        panel.nameFieldStringValue = "MacPulse-\(stamp()).csv"
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .plainText]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 另存为 PNG：把完整文本快照渲染为深色长图。
    /// SDK 27 已废弃 CGWindowListCreateImage / NSWindow.snapshot，自绘更稳定且无沙箱依赖。
    static func savePNG(_ m: SystemMonitor) {
        guard let data = pngData(from: textReport(m)) else { return }
        let panel = NSSavePanel()
        panel.title = "导出性能快照（PNG）"
        panel.nameFieldStringValue = "MacPulse-\(stamp()).png"
        panel.allowedContentTypes = [UTType(filenameExtension: "png") ?? .png]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: 内部工具

    private static func pngData(from text: String) -> Data? {
        let width: CGFloat = 820
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let lineHeight = font.ascender - font.descender + font.leading + 5
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        // 预留 1.25 倍高度，避免中文/长行自动换行后被裁切
        let estimated = min(max(CGFloat(lineCount) * lineHeight * 1.25 + 48, 260), 3200)
        let image = NSImage(size: NSSize(width: width, height: estimated))
        image.lockFocus()
        NSColor(calibratedRed: 0.035, green: 0.043, blue: 0.06, alpha: 1).setFill()
        NSRect(origin: .zero, size: NSSize(width: width, height: estimated)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.99, alpha: 1),
        ]
        NSAttributedString(string: text, attributes: attrs)
            .draw(in: NSRect(x: 18, y: 14, width: width - 36, height: estimated - 28))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func cell(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
