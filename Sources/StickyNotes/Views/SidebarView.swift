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
        VStack(spacing: 0) {
            // Empty space
            Spacer()
        }
        .frame(width: 210)
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
