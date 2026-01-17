import SwiftUI

@main
struct StickyNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notesManager = NotesManager()
    @StateObject private var windowManager = WindowManager()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(notesManager)
                .environmentObject(windowManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 750, height: 500)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: EdgeSnapWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 配置窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                
                // 强制禁用背景拖拽，多次尝试确保生效
                window.isMovableByWindowBackground = false
                
                // 设置窗口背景色与应用背景一致
                window.backgroundColor = NSColor.windowBackgroundColor
                
                // 补救措施：再设一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    window.isMovableByWindowBackground = false
                }
                
                // 隐藏标准窗口按钮
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                
                // 移除标题栏的高度占用
                if let contentView = window.contentView {
                    contentView.wantsLayer = true
                }
                
                self.windowController = EdgeSnapWindowController(window: window)
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
