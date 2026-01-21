import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - 禁止窗口拖动的透明 Overlay
struct DisableWindowDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> DisableWindowDragView {
        return DisableWindowDragView()
    }
    
    func updateNSView(_ nsView: DisableWindowDragView, context: Context) {}
}

class DisableWindowDragView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 强制禁用窗口背景拖拽
        window?.isMovableByWindowBackground = false
    }
    
    // 禁止该视图区域触发窗口移动
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
}

// MARK: - 多选手势修饰符检测器
struct TapWithModifiers: ViewModifier {
    let action: (Bool, Bool) -> Void // (shiftPressed, cmdPressed)
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.shift)
                    .onEnded { _ in
                        action(true, false)
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .modifiers(.command)
                    .onEnded { _ in
                        action(false, true)
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        // 检查当前是否有修饰键按下
                        let flags = NSEvent.modifierFlags
                        if !flags.contains(.shift) && !flags.contains(.command) {
                            action(false, false)
                        }
                    }
            )
    }
}

extension View {
    func onTapWithModifiers(perform action: @escaping (Bool, Bool) -> Void) -> some View {
        self.modifier(TapWithModifiers(action: action))
    }
    
    // 禁止此区域触发窗口拖动
    func disableWindowDrag() -> some View {
        self.background(DisableWindowDrag())
    }
    
    // 隐藏 List 的选择背景
    func hideListSelectionBackground() -> some View {
        self.background(ListSelectionHider())
    }
    
    // 允许此区域拖动窗口
    func allowWindowDrag() -> some View {
        self.background(WindowDragArea())
    }
}

// MARK: - 允许窗口拖动的区域
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragAreaView {
        return WindowDragAreaView()
    }
    
    func updateNSView(_ nsView: WindowDragAreaView, context: Context) {}
}

class WindowDragAreaView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 允许这个区域触发窗口拖动
    override var mouseDownCanMoveWindow: Bool {
        return true
    }
}

// MARK: - 隐藏 List 选择背景
struct ListSelectionHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ListSelectionHiderView {
        return ListSelectionHiderView()
    }
    
    func updateNSView(_ nsView: ListSelectionHiderView, context: Context) {}
}

class ListSelectionHiderView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 延迟一点确保视图层级已完全建立
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let tableView = self.findTableView(in: self) {
                tableView.selectionHighlightStyle = .none
                tableView.allowsTypeSelect = false
                tableView.focusRingType = .none
            }
        }
    }
    
    private func findTableView(in view: NSView) -> NSTableView? {
        var currentView: NSView? = view
        while let view = currentView {
            if let tableView = view as? NSTableView {
                return tableView
            }
            currentView = view.superview
        }
        return nil
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @EnvironmentObject var notesManager: NotesManager
    @Binding var isCollapsed: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Row: All (Large Wide Button)
                StatButton(
                    mode: .all,
                    title: "全部待办事项",
                    iconName: "全部",
                    count: notesManager.todoCounts["all"] ?? 0,
                    color: Color(hex: "#087aff"), // Original Blue
                    isWide: true,
                    isSelected: notesManager.currentFilter == .all
                ) {
                    notesManager.currentFilter = .all
                }
                
                // Middle Row: Today & Important
                HStack(spacing: 12) {
                    StatButton(
                        mode: .today,
                        title: "今天",
                        iconName: "今天",
                        count: notesManager.todoCounts["today"] ?? 0,
                        color: Color(hex: "#08bcff"), // New Blue
                        isWide: false,
                        isSelected: notesManager.currentFilter == .today
                    ) {
                        notesManager.currentFilter = .today
                    }
                    
                    StatButton(
                        mode: .important,
                        title: "重要",
                        iconName: "重要",
                        count: notesManager.todoCounts["important"] ?? 0,
                        color: Color(hex: "#ff8d30"), // Orange
                        isWide: false,
                        isSelected: notesManager.currentFilter == .important
                    ) {
                        notesManager.currentFilter = .important
                    }
                }
                
                // Bottom Row: Recurring & Completed
                HStack(spacing: 12) {
                    StatButton(
                        mode: .recurring,
                        title: "周期",
                        iconName: "周期",
                        count: notesManager.todoCounts["recurring"] ?? 0,
                        color: Color(hex: "#ff3b30"), // Red
                        isWide: false,
                        isSelected: notesManager.currentFilter == .recurring
                    ) {
                        notesManager.currentFilter = .recurring
                    }
                    
                    StatButton(
                        mode: .completed,
                        title: "完成",
                        iconName: "完成",
                        count: notesManager.todoCounts["completed"] ?? 0,
                        color: Color(hex: "#8e8e93"), // Gray
                        isWide: false,
                        isSelected: notesManager.currentFilter == .completed
                    ) {
                        notesManager.currentFilter = .completed
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 10)
            
            Spacer()
        }
        .frame(width: 210)
    }
}

// MARK: - Components

struct StatButton: View {
    let mode: NotesManager.FilterMode
    let title: String
    let iconName: String
    let count: Int
    let color: Color
    let isWide: Bool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) { // Center icons with numbers
                    // Top Left: Icon
                    if mode == .today {
                        TodayIconView(iconName: iconName)
                    } else if let nsImage = loadSVG(named: iconName) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .renderingMode(.template) 
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: (mode == .recurring || mode == .important || mode == .today) ? 22 : 28,
                                height: (mode == .recurring || mode == .important || mode == .today) ? 22 : 28
                            )
                            .foregroundColor(.white)
                            .offset(y: 1.5) // Move DOWN to align with number baseline
                    }
                    
                    Spacer()
                    
                    // Top Right: Count
                    if mode != .completed {
                        Text("\(count)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 10)
                
                Spacer()
                
                // Bottom Left: Title
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(0.9)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 10)
            }
            .frame(width: isWide ? 190 : 89, height: 68)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color)
                    
                    // Subtle Gradient Overlay (Top-Left to Bottom-Right)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.15), Color.clear]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isSelected ? 0.3 : 0), lineWidth: 1.5)
            )
            .animation(.spring(response: 0.25), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct TodayIconView: View {
    let iconName: String
    
    var body: some View {
        ZStack {
            if let nsImage = loadSVG(named: iconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22) // Smaller for Today to match Recurring
                    .foregroundColor(.white)
            }
            
            // Dynamic Day Number
            Text("\(Calendar.current.component(.day, from: Date()))")
                .font(.system(size: 9, weight: .bold)) // Slightly smaller font for smaller icon
                .foregroundColor(.white)
                .offset(y: 2)
        }
        .offset(y: 1.5) // Match other icons' vertical alignment
    }
}

// 辅助函数：从 Bundle.module 加载 SVG 为 NSImage
func loadSVG(named name: String) -> NSImage? {
    // 尝试在 Resources 目录下查找 .svg 文件
    if let url = Bundle.module.url(forResource: name, withExtension: "svg") {
        return NSImage(contentsOf: url)
    }
    return nil
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// NSVisualEffectView封装
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
