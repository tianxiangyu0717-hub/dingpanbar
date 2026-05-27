import SwiftUI
import AppKit

@main
struct DingPanBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        // 不需要主窗口；提供一个空 Settings scene 仅为满足 App 协议。
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: StatusController?

    func applicationDidFinishLaunching(_ n: Notification) {
        // 隐藏 Dock 图标 / 不出现在 Cmd-Tab。
        NSApp.setActivationPolicy(.accessory)
        status = StatusController()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关掉提醒管理窗后不要退出 app。
        return false
    }
}
