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
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.controlActiveState) var controlActiveState
    @Binding var isCollapsed: Bool
    
    // 是否为活动窗口
    private var isActive: Bool {
        controlActiveState == .key || controlActiveState == .active
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部占位区域（为红黄绿和功能按钮留空间）
            Color.clear
                .frame(height: 44)
            
            // 文档列表
            if !isCollapsed {
                noteListView
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                Spacer()
            }
        }
        .frame(width: isCollapsed ? 1 : 230)
        .background(sidebarBackground)
        .shadow(color: Color.black.opacity(isCollapsed || !isActive ? 0 : (colorScheme == .dark ? 0.4 : 0.12)), 
               radius: 12, x: 3, y: 3)
        .padding(.leading, 12)
        .padding(.vertical, 12)
    }
    
    // MARK: - Subviews
    
    private var noteListView: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(notesManager.notes.enumerated()), id: \.element.id) { index, note in
                    let isLastPinned = note.isPinned && (index + 1 >= notesManager.notes.count || !notesManager.notes[index + 1].isPinned)
                    
                    NoteRowView(note: note, 
                               isSelected: notesManager.isSelected(note.id),
                               isWindowActive: isActive,
                               isLastPinned: isLastPinned)
                        .padding(.horizontal, 10)
                        // 1. 设置拖动数据 (使用 ID 字符串更稳定)
                        .draggable(note.id.uuidString)
                        // 2. 设置放置目标
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedIdString = items.first,
                                  let draggedId = UUID(uuidString: draggedIdString),
                                  draggedId != note.id else { return false }
                            
                            if let toIndex = notesManager.notes.firstIndex(where: { $0.id == note.id }) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    notesManager.moveNote(noteId: draggedId, toIndex: toIndex)
                                }
                                return true
                            }
                            return false
                        }
                        // 使用 simultaneousGesture 检测修饰键
                        .onTapWithModifiers { shiftPressed, cmdPressed in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                notesManager.selectNote(note.id, shiftPressed: shiftPressed, cmdPressed: cmdPressed)
                            }
                        }
                        .contextMenu {
                            contextMenuContent(for: note)
                        }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private func contextMenuContent(for note: Note) -> some View {
        if notesManager.selectedNoteIds.count > 1 && notesManager.isSelected(note.id) {
            batchContextMenu
        } else {
            singleContextMenu(for: note)
        }
    }
    
    private var batchContextMenu: some View {
        Group {
            Button {
                withAnimation {
                    notesManager.togglePinSelectedNotes()
                }
            } label: {
                let allPinned = notesManager.selectedNoteIds.allSatisfy { id in
                    notesManager.notes.first(where: { $0.id == id })?.isPinned == true
                }
                Label(allPinned ? "取消置顶 \(notesManager.selectedNoteIds.count) 项" : "置顶 \(notesManager.selectedNoteIds.count) 项", 
                      systemImage: allPinned ? "pin.slash" : "pin")
            }
            
            Divider()
            
            Button(role: .destructive) {
                withAnimation {
                    notesManager.deleteSelectedNotes()
                }
            } label: {
                Label("删除 \(notesManager.selectedNoteIds.count) 项", systemImage: "trash")
            }
        }
    }
    
    private func singleContextMenu(for note: Note) -> some View {
        Group {
            Button {
                notesManager.selectNote(note.id, shiftPressed: false, cmdPressed: false)
                withAnimation {
                    notesManager.togglePin(note)
                }
            } label: {
                Label(note.isPinned ? "取消置顶" : "置顶", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            
            Divider()
            
            Button(role: .destructive) {
                notesManager.selectNote(note.id, shiftPressed: false, cmdPressed: false)
                withAnimation {
                    notesManager.deleteNote(note)
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
    
    private var sidebarBackground: some View {
        ZStack {
            // LAYER 1: 高折射背景 (The Refractive Base)
            // 基础物理层：捕捉壁纸颜色
            VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            
            // 叠加层：白色渐变 + 叠加模式，制造"凝胶感" (Gel-like thickness)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.15),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.overlay)
            
            // 基础底色：适度降低，让上面的凝胶层和下面的折射层发挥作用
            (colorScheme == .dark ? Color.black : Color.white)
                .opacity(0.4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        
        // LAYER 3: 表面光泽 (Surface & Noise) - 模拟内发光
        // 通过模糊的白色描边模拟内部的光线散射
        // 调整：大幅降低暗色模式下的亮度 (0.5 -> 0.1)，避免刺眼
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 2)
                .blur(radius: 3)
                .mask(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .padding(1) //稍微内缩，确保只在边缘发光
        )
        
        // LAYER 2: 边缘流动高光 (The Fluid Rims)
        // 关键：从左上到右下的渐变，模拟物理光源 (暗色模式下大幅降低亮度)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(colorScheme == .dark ? 0.2 : 0.85), location: 0),   // 高亮受光面
                            .init(color: .white.opacity(colorScheme == .dark ? 0.1 : 0.3), location: 0.3),  // 过渡区
                            .init(color: .white.opacity(0.05), location: 1)    // 阴影面
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1 // 1px 精致切割感
                )
        )        // 增加柔和投影，增强悬浮感
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        .opacity(isCollapsed ? 0 : 1)
    }
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isCollapsed.toggle()
        }
    }
}


// 自定义窗口控制按钮
struct WindowControlButtons: View {
    let isActive: Bool
    @Environment(\.colorScheme) var colorScheme
    @State private var isHoveringClose = false
    @State private var isHoveringMinimize = false
    @State private var isHoveringZoom = false
    @State private var isGroupHovered = false
    
    // 非活动状态下的灰色
    private var inactiveColor: Color {
        if colorScheme == .dark {
            return Color(red: 71/255, green: 73/255, blue: 77/255) // #47494d
        } else {
            return Color(red: 211/255, green: 211/255, blue: 211/255) // #d3d3d3
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // 关闭按钮
            WindowButton(color: isActive ? Color(red: 1, green: 0.38, blue: 0.35) : inactiveColor,
                        icon: "xmark",
                        isHovered: $isHoveringClose,
                        isGroupHovered: isGroupHovered && isActive) {
                NSApplication.shared.keyWindow?.close()
            }
            
            // 最小化按钮
            WindowButton(color: isActive ? Color(red: 1, green: 0.75, blue: 0.28) : inactiveColor,
                        icon: "minus",
                        isHovered: $isHoveringMinimize,
                        isGroupHovered: isGroupHovered && isActive) {
                NSApplication.shared.keyWindow?.miniaturize(nil)
            }
            
            // 最大化按钮
            WindowButton(color: isActive ? Color(red: 0.15, green: 0.8, blue: 0.25) : inactiveColor,
                        icon: "plus",
                        isHovered: $isHoveringZoom,
                        isGroupHovered: isGroupHovered && isActive) {
                NSApplication.shared.keyWindow?.zoom(nil)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isGroupHovered = hovering
            }
        }
    }
}

struct WindowButton: View {
    let color: Color
    let icon: String
    @Binding var isHovered: Bool
    let isGroupHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                
                if isGroupHovered {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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

struct NoteRowView: View {
    let note: Note
    let isSelected: Bool
    let isWindowActive: Bool
    let isLastPinned: Bool
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var notesManager: NotesManager
    
    private var bgColor: Color {
        if isSelected {
            if isWindowActive {
                return Color.accentColor
            } else {
                return colorScheme == .dark ? Color(white: 0.25) : Color(red: 242/255, green: 242/255, blue: 242/255)
            }
        }
        return Color.clear
    }
    
    private var titleColor: Color {
        if isSelected {
            return isWindowActive ? .white : .accentColor
        }
        return .primary
    }
    
    private var dateColor: Color {
        if isSelected {
            return isWindowActive ? .white.opacity(0.75) : .accentColor.opacity(0.75)
        }
        return .secondary
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                noteIcon
                noteContent
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bgColor)
            )
            .disableWindowDrag() // 核心：确保这个区域绝对不移动窗口，只响应重排序
            
            if isLastPinned {
                Divider()
                    .background(Color.gray.opacity(0.15))
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
        }
        .contentShape(Rectangle())
    }
    
    private var noteIcon: some View {
        Group {
            if note.isPinned {
                PinnedDocIcon(
                    color: isSelected ? (isWindowActive ? .white : .accentColor) : .secondary,
                    size: 17
                )
                .frame(width: 20)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? (isWindowActive ? .white : .accentColor) : .secondary)
                    .frame(width: 20)
            }
        }
    }
    
    private var noteContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(titleColor)
                .lineLimit(1)
            
            Text(formattedDate)
                .font(.system(size: 11))
                .foregroundColor(dateColor)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: note.updatedAt)
    }
}
