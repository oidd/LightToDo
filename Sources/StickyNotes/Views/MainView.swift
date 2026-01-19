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
            },
            isActive: isWindowActive
        )
    }
}

// MARK: - Reusable Liquid Glass Components

struct GlassySegmentedControl: View {
    @Binding var selection: String
    let options: [(title: String, id: String)]
    var onSelect: ((String) -> Void)?
    var isActive: Bool = true
    
    @Environment(\.colorScheme) var colorScheme
    
    private var selectedIndex: Int {
        options.firstIndex(where: { $0.id == selection }) ?? 0
    }
    
    private var sliderColor: Color {
        if colorScheme == .dark {
            // Dark Mode: Active #333333, Idle #252525
            return isActive ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color(red: 0.145, green: 0.145, blue: 0.145)
        } else {
            return isActive ? Color.black.opacity(0.08) : Color(red: 0.949, green: 0.949, blue: 0.949)
        }
    }
    
    private var baseColor: Color {
        if colorScheme == .dark {
            // Dark Mode: Active #1b1b1b, Idle #1d1d1d
            return isActive ? Color(red: 0.106, green: 0.106, blue: 0.106) : Color(red: 0.114, green: 0.114, blue: 0.114)
        } else {
            return isActive ? Color.white : Color(red: 0.976, green: 0.976, blue: 0.976)
        }
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
                        .foregroundColor(selection == option.id ? .blue : .primary)
                        .frame(width: 55, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize() // 强制容器只包裹内容，防止在 Toolbar 中被拉长
        .padding(2)
        .background(alignment: .leading) {
            // Active Indicator Pill
            if options.contains(where: { $0.id == selection }) {
                Capsule()
                    .fill(sliderColor)
                    .frame(width: 55, height: 28)
                    .offset(x: CGFloat(selectedIndex) * 55)
            }
        }
        .padding(2)
        // 独立的胶囊玻璃底座
        .background {
            Capsule()
                .fill(baseColor)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 6, x: 0, y: 2) // Deepen black shadow in dark mode
                .shadow(color: (colorScheme == .dark) ? Color.white.opacity(0.1) : .clear, radius: 1, x: 0, y: 0) // Dark Mode Rim Light
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
