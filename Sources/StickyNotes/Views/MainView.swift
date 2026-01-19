import SwiftUI

struct MainView: View {
    @EnvironmentObject var notesManager: NotesManager
    @EnvironmentObject var windowManager: WindowManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.controlActiveState) var controlActiveState
    
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editorMode: String = "note" 
    
    private var isSidebarCollapsed: Bool {
        columnVisibility == .detailOnly
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Main Content
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(isCollapsed: Binding(
                    get: { columnVisibility == .detailOnly },
                    set: { columnVisibility = $0 ? .detailOnly : .all }
                ))
                    .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 210)
            } detail: {
            EditorView(editorMode: $editorMode, isSidebarCollapsed: isSidebarCollapsed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .ignoresSafeArea()
            }
            .navigationSplitViewStyle(.balanced)
            // 移除 Toolbar，使用 Overlay 以彻底解决背景拉伸问题
            .toolbar { }
        }
        .overlay(alignment: .topLeading) {
            modeSwitcher
                // 动态调整位置：
                // 折叠: 165 (用户指定)
                // 展开: 245 (用户指定)
                .padding(.leading, isSidebarCollapsed ? 165 : 245)
                .padding(.top, 11) 
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSidebarCollapsed)
        }



        // Removed old Overlay block
        .frame(minWidth: 700, minHeight: 450)
        .background(Color.black.opacity(0.001))
        .ignoresSafeArea()
        .onAppear {
            syncModeWithSelection()
        }
        .onChange(of: notesManager.selectedNoteId) { _ in
            syncModeWithSelection()
        }
    }

    // Helper to notify window controller
    private func notifyInteraction() {
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            delegate.windowController?.notifyUserInteraction()
        }
    }
    
    private func syncModeWithSelection() {
        if let id = notesManager.selectedNoteId,
           let note = notesManager.notes.first(where: { $0.id == id }) {
            if editorMode != note.mode {
                editorMode = note.mode
            }
        }
    }

    private func updateMode(_ mode: String) {
        if let id = notesManager.selectedNoteId,
           let index = notesManager.notes.firstIndex(where: { $0.id == id }) {
            var note = notesManager.notes[index]
            if note.mode != mode {
                note.mode = mode
                notesManager.updateNote(note)
            }
        }
    }
    
    private var isWindowActive: Bool {
        controlActiveState == .key || controlActiveState == .active
    }
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
        }
    }
    
    private func addNewNote() {
        withAnimation {
            _ = notesManager.addNote()
        }
    }
    
    // MARK: - Liquid Glass Components
    

    
    private var modeSwitcher: some View {
        GlassySegmentedControl(
            selection: $editorMode,
            options: [
                ("笔记", "note"),
                ("待办", "todo")
            ],
            onSelect: { mode in
                updateMode(mode)
                notifyInteraction()
            }
        )
    }
}

// MARK: - Reusable Liquid Glass Components

struct GlassySegmentedControl: View {
    @Binding var selection: String
    let options: [(title: String, id: String)]
    var onSelect: ((String) -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    
    private var selectedIndex: Int {
        options.firstIndex(where: { $0.id == selection }) ?? 0
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.id) { option in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = option.id
                    }
                    onSelect?(option.id)
                }) {
                    Text(option.title)
                        .font(.system(size: 13, weight: selection == option.id ? .medium : .regular))
                        .foregroundColor(.primary)
                        .frame(width: 55, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize() // 强制容器只包裹内容，防止在 Toolbar 中被拉长
        .background(alignment: .leading) {
            // Active Indicator Pill
            if options.contains(where: { $0.id == selection }) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 55, height: 28)
                    .offset(x: CGFloat(selectedIndex) * 55)
            }
        }
        .padding(2)
        // 独立的胶囊玻璃底座
        .background {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .light ? 0.6 : 0.2))
            }
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
    }
}

extension View {
    @ViewBuilder
    func hideSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            self.toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
