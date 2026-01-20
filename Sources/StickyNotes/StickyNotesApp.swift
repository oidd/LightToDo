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
        // 寻找并配置初始窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                if self.isMainWindow(window) {
                    self.setupMainWindow(window)
                    break
                }
            }
        }
        
        setupHotKey()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay running if minimized
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        if let window = mainWindow {
            hideStandardButtons(for: window)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            
            // 关键：如果是贴边隐藏状态，强制展开
            windowController?.forceExpand()
            
            hideStandardButtons(for: window)
            return false // 关键：告知系统我们已经手动处理了恢复逻辑，不要新建 WindowGroup 窗口
        }
        return true
    }
    
    // MARK: - Window Configuration
    
    private func isMainWindow(_ window: NSWindow) -> Bool {
        // 排除设置窗口（根据尺寸或标题）
        if window.frame.size.width == 450 && window.frame.size.height == 400 { return false }
        if window.title == "Settings" || window.identifier?.rawValue == "com_apple_SwiftUI_Settings" { return false }
        return true
    }
    
    private func setupMainWindow(_ window: NSWindow) {
        guard mainWindow == nil else { return }
        self.mainWindow = window
        window.delegate = self
        
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        
        // 核心配置
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        
        // 实际限制最小窗口尺寸（SwiftUI minWidth=250 是为了利用规律解决卡顿）
        window.minSize = CGSize(width: 500, height: 450)
        
        hideStandardButtons(for: window)
        
        // 延迟修复：确保在各种状态切换后按钮依然隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.isMovableByWindowBackground = false
            self.hideStandardButtons(for: window)
        }
        
        // 移除标题栏的高度占用
        if let contentView = window.contentView {
            contentView.wantsLayer = true
        }
        
        self.windowController = EdgeSnapWindowController(window: window)
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
    
    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            hideStandardButtons(for: window)
        }
    }
    
    // 强制限制窗口最小尺寸（SwiftUI minWidth=250 是为了解决卡顿，但实际限制为 500）
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minWidth: CGFloat = 500
        let minHeight: CGFloat = 450
        return NSSize(
            width: max(frameSize.width, minWidth),
            height: max(frameSize.height, minHeight)
        )
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            // 如果是在运行时意外产生的新窗口，补救初始化
            if mainWindow == nil && isMainWindow(window) {
                setupMainWindow(window)
            }
            hideStandardButtons(for: window)
        }
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            hideStandardButtons(for: window)
        }
    }

    private func hideStandardButtons(for window: NSWindow) {
        // Disabled to allow native traffic lights
    }
    
    func toggleAppVisibility() {
        guard let window = mainWindow else { return }
        if NSApp.isActive && !window.isMiniaturized {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            hideStandardButtons(for: window)
        }
    }
}
