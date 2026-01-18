import SwiftUI

@main
struct StickyNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notesManager = NotesManager()
    @StateObject private var windowManager = WindowManager()
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(notesManager)
                .environmentObject(windowManager)
                .preferredColorScheme(selectedScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 750, height: 500)
        
        // Settings Window
        Settings {
            SettingsView()
        }
    }
    
    var selectedScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windowController: EdgeSnapWindowController?
    var mainWindow: NSWindow?
    
    // Global shortcut monitoring
    var globalMonitor: Any?
    var localMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 配置窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                self.mainWindow = window
                window.delegate = self // Set delegate to intercrpt close
                
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                
                // 强制禁用背景拖拽，多次尝试确保生效
                window.isMovableByWindowBackground = false
                
                // 设置窗口背景为透明，允许 VisualEffectView 穿透显示壁纸
                // 这是实现"液态玻璃"红底折射的关键：必须去掉 NSWindow 默认的不透明底色
                window.isOpaque = false
                window.backgroundColor = .clear
                // window.hasShadow = false // 可选：如果不需要系统阴影
                
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
        
        setupHotKey()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay running if minimized
    }
    
    // MARK: - Window Delegate (Close Behavior)
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let action = UserDefaults.standard.string(forKey: "closeBehavior") ?? "minimize"
        if action == "quit" {
            NSApplication.shared.terminate(nil)
            return true
        } else {
            sender.miniaturize(nil)
            return false
        }
    }
    
    // MARK: - Shortcuts
    
    func setupHotKey() {
        // Set action
        HotKeyManager.shared.onHotKeyTriggered = { [weak self] in
            DispatchQueue.main.async {
                self?.toggleAppVisibility()
            }
        }
        
        // Register initial
        updateHotKeyRegistration()
        
        // Listen for changes
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    @objc func settingsChanged() {
        updateHotKeyRegistration()
    }
    
    func updateHotKeyRegistration() {
        let keyCode = UserDefaults.standard.integer(forKey: "globalShortcutKeyCode")
        let modifiers = UserDefaults.standard.integer(forKey: "globalShortcutModifiers")
        
        // Default to Option+S (Keycode 1, Mods Option) if 0
        let effectiveKeyCode = keyCode == 0 ? 1 : keyCode
        let effectiveMods = modifiers == 0 ? 524288 : modifiers
        
        HotKeyManager.shared.registerHotKey(keyCode: effectiveKeyCode, modifiers: effectiveMods)
    }
    
    func toggleAppVisibility() {
        guard let window = mainWindow else { return }
        if NSApp.isActive && !window.isMiniaturized {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
