import SwiftUI
import AppKit

/// 进程详情弹窗：完整路径、线程数、TCP 监听端口。
/// 详情只在打开时读取一次（lsof 查询较重），不进入每秒刷新循环。
/// 注意：命令行 swiftc 下 SwiftUI @State 宏不可用，状态统一放 SystemMonitor。
struct ProcessDetailView: View {
    @ObservedObject var monitor: SystemMonitor

    private var killBinding: Binding<Bool> {
        Binding(get: { monitor.detailKillArmed }, set: { monitor.detailKillArmed = $0 })
    }

    var body: some View {
        let d = monitor.selectedProcessDetail
        let entry = monitor.selectedProcess
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold)).foregroundColor(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d?.name ?? "进程详情")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(entry.map { "PID \($0.pid)" } ?? "")
                        .font(.system(size: 11)).foregroundColor(Theme.faint)
                }
                Spacer()
                Button { monitor.selectProcess(nil) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundColor(Theme.faint)
                }
                .buttonStyle(.plain)
            }

            Divider().background(Theme.border)

            detailRow(label: "可执行文件路径", value: d?.path ?? "读取中…", mono: true)
            detailRow(label: "线程数", value: d.map { "\($0.threadCount) 个" } ?? "—")
            detailRow(label: "TCP 监听端口", value: portText(d?.listenPorts ?? []), mono: true)
            detailRow(label: "CPU（单核口径）", value: entry.map { String(format: "%.1f%%", $0.cpu) } ?? "—", mono: true)
            detailRow(label: "常驻内存", value: entry.map { String(format: "%.0f MB", $0.memMB) } ?? "—", mono: true)

            Text("路径与线程数来自 libproc；监听端口由 lsof 只读查询，沙箱限制时显示 —。")
                .font(.system(size: 10)).foregroundColor(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("刷新详情") { monitor.refreshProcessDetail() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("结束进程", role: .destructive) { monitor.detailKillArmed = true }
                    .buttonStyle(.borderedProminent)
                    .disabled((entry?.pid ?? 0) <= 1 || entry?.pid == Int(getpid()))
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.bg)
        .preferredColorScheme(monitor.appearanceMode == 1 ? .light :
                                monitor.appearanceMode == 2 ? .dark : nil)
        .alert("结束进程", isPresented: killBinding) {
            Button("取消", role: .cancel) {}
            Button("确认结束", role: .destructive) {
                if let e = entry { monitor.terminateProcess(e.pid) }
                monitor.selectProcess(nil)
            }
        } message: {
            Text("将向 PID \(entry?.pid ?? 0) 发送 SIGTERM。系统关键进程已做保护，但结束其他进程仍可能导致数据丢失。")
        }
    }

    private func portText(_ ports: [Int]) -> String {
        guard !ports.isEmpty else { return "—（无监听端口或沙箱不可读）" }
        return ports.map(String.init).joined(separator: "、")
    }

    private func detailRow(label: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.faint)
            Text(value)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundColor(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
