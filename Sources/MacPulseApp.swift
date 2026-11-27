import SwiftUI
import AppKit

@main
struct MacPulseApp: App {
    // SystemMonitor.shared 为单例，生命周期随 App；避开 @StateObject 编译器宏（本机 Xcode 插件服务不兼容）
    private let monitor = SystemMonitor.shared
    // 菜单栏控制器必须强引用持有，否则会被立即释放
    private let menuBar = MenuBarController(monitor: SystemMonitor.shared)

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
        }
        .defaultSize(width: 1000, height: 720)
        .windowStyle(.titleBar)
    }
}
