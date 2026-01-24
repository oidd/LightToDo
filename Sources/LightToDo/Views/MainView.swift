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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(isCollapsed: Binding(
                get: { columnVisibility == .detailOnly },
                set: { columnVisibility = $0 ? .detailOnly : .all }
            ))
                .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 210)
        } detail: {
            EditorView(editorMode: .constant("todo"), isSidebarCollapsed: isSidebarCollapsed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 250, minHeight: 450)
    }

    // Helper to notify window controller
    private func notifyInteraction() {
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            delegate.windowController?.notifyUserInteraction()
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
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 6, x: 0, y: 2)
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
