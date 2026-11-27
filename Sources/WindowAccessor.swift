import SwiftUI
import AppKit

/// 把 SwiftUI 窗口桥接成 NSWindow，实现位置/大小记忆。
/// 出现在视图背景里，持有弱引用不截获生命周期。
struct WindowAccessor: NSViewRepresentable {
    static let originKey = "com.macpulse.window.origin"
    static let sizeKey = "com.macpulse.window.size"

    var onTop: Bool = false

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let win = v.window else { return }
            context.coordinator.applyLevel(onTop, to: win)
            let ud = UserDefaults.standard
            if let origin = ud.array(forKey: Self.originKey) as? [CGFloat], origin.count == 2,
               let size = ud.array(forKey: Self.sizeKey) as? [CGFloat], size.count == 2 {
                let frame = NSRect(x: origin[0], y: origin[1], width: size[0], height: size[1])
                // 只在尺寸合理、且落在屏幕可视范围内时恢复，避免多显示器变化时窗口跑飞
                if frame.width >= 600 && frame.height >= 400 && frame.intersects(NSScreen.main?.frame ?? .zero) {
                    win.setFrame(frame, display: true)
                }
            }
            // 定时保存（窗口拖动/缩放过程中由 didMoveNotification 通知）
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.saveFrame(_:)),
                name: NSWindow.didMoveNotification, object: win)
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.saveFrame(_:)),
                name: NSWindow.didResizeNotification, object: win)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let win = nsView.window else { return }
        context.coordinator.applyLevel(onTop, to: win)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        /// 置顶用 .floating（高于普通窗口，低于菜单栏/系统弹层），避免盖住系统 UI
        func applyLevel(_ onTop: Bool, to win: NSWindow) {
            let target: NSWindow.Level = onTop ? .floating : .normal
            if win.level != target { win.level = target }
        }

        @objc func saveFrame(_ note: Notification) {
            guard let win = note.object as? NSWindow else { return }
            let f = win.frame
            UserDefaults.standard.set([f.origin.x, f.origin.y], forKey: WindowAccessor.originKey)
            UserDefaults.standard.set([f.size.width, f.size.height], forKey: WindowAccessor.sizeKey)
        }
    }
}
