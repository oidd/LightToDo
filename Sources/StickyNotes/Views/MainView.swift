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
            .toolbar(.hidden, for: .windowToolbar) // Hide native toggle
        }
        .overlay(
            // Window Control Buttons - on top-left of sidebar panel
            NativeWindowControlButtons(isActive: isWindowActive)
                .frame(width: 70, height: 24)
                .padding(Edge.Set.leading, 18) 
                .padding(Edge.Set.top, 15)
            , alignment: .topLeading
        )
        .overlay(
            // Combined Toggle + Mode Switcher - moves together based on sidebar state
            HStack(spacing: 12) {
                // Sidebar Toggle Button
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Mode Switcher
                modeSwitcher
            }
            .padding(.leading, isSidebarCollapsed ? 100 : 250)
            .padding(.top, 12)
            // Animation modifier removed to sync with global transaction
            , alignment: .topLeading
        )
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
    
    private var modeSwitcher: some View {
        ZStack {
            Capsule()
                .fill(Color(nsColor: .controlColor).opacity(0.5))
                .frame(width: 104, height: 28)
                .overlay(
                    Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5)
                )
            
            HStack(spacing: 0) {
                if editorMode == "todo" { Spacer() }
                Capsule()
                    .fill(colorScheme == .dark ? Color(nsColor: .controlAccentColor).opacity(0.15) : Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                    .frame(width: 50, height: 24)
                    .padding(.horizontal, 2)
                if editorMode == "note" { Spacer() }
            }
            .frame(width: 104, height: 28)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: editorMode)
            
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        editorMode = "note"
                    }
                    updateMode("note")
                    notifyInteraction()
                }) {
                    Text("笔记")
                        .font(.system(size: 13, weight: editorMode == "note" ? .semibold : .medium))
                        .foregroundColor(editorMode == "note" ? .accentColor : .primary.opacity(0.6))
                        .frame(width: 50, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        editorMode = "todo"
                    }
                    updateMode("todo")
                    notifyInteraction()
                }) {
                    Text("待办")
                        .font(.system(size: 13, weight: editorMode == "todo" ? .semibold : .medium))
                        .foregroundColor(editorMode == "todo" ? .accentColor : .primary.opacity(0.6))
                        .frame(width: 50, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 104, height: 28)
        }
        .contentShape(Rectangle())
        .onHover { hover in
            if hover { notifyInteraction() }
        }
    }
}
