import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("appTheme") private var appTheme: String = "system" // system, light, dark
    @AppStorage("closeBehavior") private var closeAction: String = "minimize" // minimize, quit
    @AppStorage("notesStoragePath") private var notesStoragePath: String = ""
    @AppStorage("globalShortcutKey") private var globalShortcutKey: String = "s" // default s
    @AppStorage("globalShortcutModifiers") private var globalShortcutModifiers: Int = 524288 // default Option (Alt)
    @AppStorage("globalShortcutKeyCode") private var globalShortcutKeyCode: Int = 1 // default s keycode
    @AppStorage("todoSortMode") private var todoSortMode: String = "byDeadline" // byDeadline, none
    
    @State private var isRecordingShortcut = false
    
    var body: some View {
        Form {
            // MARK: - General Settings
            Section {
                // 1. 开机自启
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }
                
                // 2. 将此 APP 保持在最前 (Optional, standard needed?)
                // Toggle("Keep Window on Top", isOn: ...)
                
                // 3. 关闭主面板时的操作
                Picker("点击窗口关闭按钮 (x) 时:", selection: $closeAction) {
                    Text("最小化到程序坞").tag("minimize")
                    Text("退出应用").tag("quit")
                }
                .pickerStyle(.menu)
                
                // 4. 待办事项排序
                Picker("待办事项排序:", selection: $todoSortMode) {
                    Text("按截止时间").tag("byDeadline")
                    Text("不排序").tag("none")
                }
                .pickerStyle(.menu)
                
            } header: {
                Text("常规")
            }
            
            // MARK: - Appearance
            Section {
                // 4. 外观主题
                Picker("外观主题", selection: $appTheme) {
                    Text("跟随系统").tag("system")
                    Text("浅色模式").tag("light")
                    Text("深色模式").tag("dark")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("外观")
            }
            
            // MARK: - Storage
            Section {
                // 5. 笔记保存位置
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前位置: \(currentStoragePath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Button("更改保存位置...") {
                        selectStorageFolder()
                    }
                }
            } header: {
                Text("存储")
            }
            
            // MARK: - Shortcuts
            Section {
                // 6. 快捷键
                HStack {
                    Text("显示/隐藏主面板")
                    Spacer()
                    Button(action: {
                        isRecordingShortcut = true
                    }) {
                        if isRecordingShortcut {
                            Text("按下快捷键...")
                                .foregroundColor(.accentColor)
                        } else {
                            Text(shortcutDescription)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent("s"), modifiers: .option) // Just for display simulation
                    .background(ShortcutRecorder(isRecording: $isRecordingShortcut,
                                                 key: $globalShortcutKey,
                                                 modifiers: $globalShortcutModifiers,
                                                 keyCode: $globalShortcutKeyCode))
                }
                .help("推荐使用 Option + S")
                
            } header: {
                Text("快捷键")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }
    
    // MARK: - Helpers
    
    private var currentStoragePath: String {
        if notesStoragePath.isEmpty {
            return "默认 (Application Support)"
        }
        return notesStoragePath
    }
    
    private var shortcutDescription: String {
        // Simple formatter
        var parts: [String] = []
        let rawMods = UInt(globalShortcutModifiers)
        if (rawMods & NSEvent.ModifierFlags.command.rawValue) != 0 { parts.append("⌘") }
        if (rawMods & NSEvent.ModifierFlags.control.rawValue) != 0 { parts.append("⌃") }
        if (rawMods & NSEvent.ModifierFlags.option.rawValue) != 0 { parts.append("⌥") }
        if (rawMods & NSEvent.ModifierFlags.shift.rawValue) != 0 { parts.append("⇧") }
        parts.append(globalShortcutKey.uppercased())
        return parts.joined(separator: "")
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        // macOS 13+
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
    
    private func selectStorageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                notesStoragePath = url.path
                // Trigger reload via Notification or Singleton
                NotificationCenter.default.post(name: Notification.Name("StoragePathChanged"), object: nil)
            }
        }
    }
}

// 隐藏的 View 用于捕获按键 (简单实现)
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var key: String
    @Binding var modifiers: Int
    @Binding var keyCode: Int
    
    func makeNSView(context: Context) -> NSView {
        let view = ShortcutListenView()
        view.onEvent = { event in
            guard isRecording else { return }
            
            // Ignore modifiers only
            if event.type == .flagsChanged { return }
            
            // Save settings
            if let chars = event.charactersIgnoringModifiers {
                self.key = chars
                self.modifiers = Int(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
                self.keyCode = Int(event.keyCode)
                self.isRecording = false
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 
    }
}

class ShortcutListenView: NSView {
    var onEvent: ((NSEvent) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        onEvent?(event)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Hack to grab focus when recording? 
        // Better implementation requires a dedicated focus loop
        // For now relying on window scope
    }
}
