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
    @AppStorage("reminderColor") private var reminderColor: String = "orange"
    @AppStorage("reminderStyle") private var reminderStyle: String = "glow" // glow, notification
    
    @State private var isRecordingShortcut = false
    
    private let availableColors = [
        ("orange", "橙色", Color(red: 1, green: 0.8, blue: 0.502)),
        ("blue", "蓝色", Color(red: 0.565, green: 0.792, blue: 0.976)),
        ("green", "绿色", Color(red: 0.647, green: 0.839, blue: 0.655)),
        ("red", "红色", Color(red: 0.937, green: 0.604, blue: 0.604)),
        ("yellow", "黄色", Color(red: 1, green: 0.961, blue: 0.616)),
        ("purple", "紫色", Color(red: 0.808, green: 0.576, blue: 0.847)),
        ("pink", "粉色", Color(red: 0.957, green: 0.561, blue: 0.694)),
        ("gray", "灰色", Color(red: 0.690, green: 0.745, blue: 0.773))
    ]
    
    var body: some View {
        Form {
            // MARK: - General Settings
            Section {
                // 1. 开机自启
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }
                
                // 3. 关闭主面板时的操作
                Picker("点击窗口关闭按钮 (x) 时", selection: $closeAction) {
                    Text("最小化到程序坞").tag("minimize")
                    Text("退出应用").tag("quit")
                }
                .pickerStyle(.menu)
                
                // 4. 待办事项排序
                Picker("待办事项排序", selection: $todoSortMode) {
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
                .pickerStyle(.menu)
                
                // 5. 贴边长条颜色
                Picker("贴边长条颜色", selection: $reminderColor) {
                    ForEach(availableColors, id: \.0) { colorInfo in
                        Label {
                            Text(colorInfo.1)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(colorInfo.2)
                        }
                        .tag(colorInfo.0)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: reminderColor) { newValue in
                    NotificationCenter.default.post(name: Notification.Name("EdgeBarColorChanged"), object: newValue)
                }
                .padding(.vertical, 4)
                
                // 6. 提醒样式
                VStack(alignment: .leading, spacing: 10) {
                    Text("提醒样式")
                        .font(.body)
                    
                    HStack(spacing: 16) {
                        ReminderStyleOption(
                            id: "glow",
                            title: "呼吸光晕",
                            imageName: "呼吸光晕",
                            isSelected: reminderStyle == "glow"
                        ) {
                            reminderStyle = "glow"
                        }
                        
                        ReminderStyleOption(
                            id: "notification",
                            title: "系统通知",
                            imageName: "系统通知",
                            isSelected: reminderStyle == "notification"
                        ) {
                            reminderStyle = "notification"
                        }
                    }
                    
                    if reminderStyle == "notification" {
                        Text("请在系统“通知”中找到本软件，开启“持续”通知功能")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 8)
                
            } header: {
                Text("外观")
            }
            
            // MARK: - Storage
            Section {
                // 5. 笔记保存位置 (Simplified single row)
                HStack(spacing: 8) {
                    Text(currentStoragePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
                        )
                    
                    Button("更改") {
                        selectStorageFolder()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
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
        .frame(width: 450, height: 550)
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

struct ReminderStyleOption: View {
    let id: String
    let title: String
    let imageName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .center, spacing: 8) {
                // Image Container
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.05))
                        )
                    
                    if let imageURL = Bundle.module.url(forResource: imageName, withExtension: "png"),
                       let image = NSImage(contentsOf: imageURL) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 140, height: 70)
                            .cornerRadius(8)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 140, height: 70)
                            .cornerRadius(8)
                    }
                }
                .frame(width: 140, height: 70)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
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
