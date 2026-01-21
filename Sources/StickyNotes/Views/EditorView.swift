import SwiftUI

struct EditorView: View {
    @EnvironmentObject var notesManager: NotesManager
    @Environment(\.controlActiveState) var controlActiveState
    @Binding var editorMode: String // 从 MainView 接收
    var isSidebarCollapsed: Bool
    @State private var content: String = ""
    @State private var editorReady: Bool = false
    
    // Top Bar State
    @State private var searchText: String = ""
    @State private var addTrigger: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if let selectedId = notesManager.selectedNoteId,
               let _ = notesManager.notes.first(where: { $0.id == selectedId }) {
                
                // Quill 富文本编辑器（仅正文）
                QuillEditor(
                    content: $content,
                    filterMode: Binding(
                        get: { notesManager.currentFilter.rawValue },
                        set: { if let mode = NotesManager.FilterMode(rawValue: $0) { notesManager.currentFilter = mode } }
                    ),
                    searchText: $searchText,
                    addTrigger: $addTrigger,
                    isWindowActive: controlActiveState == .key,
                    onContentUpdate: {
                        saveContent()
                    },
                    onCountsUpdate: { counts in
                        notesManager.todoCounts = counts
                    },
                    onReady: {
                        editorReady = true
                    },
                    onNewNote: {
                        withAnimation {
                            _ = notesManager.addNote()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: notesManager.selectedNoteId) { _ in
                    loadSelectedNote()
                }
                .onAppear {
                    loadSelectedNote()
                }
                .onTapGesture {
                    notesManager.isSidebarFocused = false
                }
                .disableWindowDrag()
            } else {
                // 无选中文档时的占位视图 - 仅显示新建按钮
                VStack {
                    Button(action: {
                        withAnimation {
                            _ = notesManager.addNote()
                        }
                    }) {
                        Label("新建笔记", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ZStack(alignment: .leading) {
                    if searchText.isEmpty {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("搜索")
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                        .allowsHitTesting(false)
                    }
                    
                    TextField("", text: $searchText)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .frame(width: 150) // Adjust width as needed
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(8)
            }
            
            ToolbarItem(placement: .primaryAction) {
                if notesManager.currentFilter != .completed {
                    Button(action: {
                        addTrigger += 1
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold)) // Slightly larger icon
                            .foregroundColor(.primary)
                            .frame(width: 14, height: 14) // Icon size
                            .padding(8) // Padding for circle
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1) // Native-like shadow
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5) // Subtle border
                            )
                    }
                    .buttonStyle(.plain)
                    .help("新建待办事项")
                }
            }
        }
    }
    
    private func loadSelectedNote() {
        guard let selectedId = notesManager.selectedNoteId,
              let note = notesManager.notes.first(where: { $0.id == selectedId }) else {
            content = ""
            return
        }
        
        content = note.content.isEmpty ? "<p><br></p>" : note.content
        print("📝 加载笔记: \(note.id), 内容长度: \(content.count)")
    }
    
    private func saveContent() {
        guard let selectedId = notesManager.selectedNoteId,
              var note = notesManager.notes.first(where: { $0.id == selectedId }) else { return }
        
        if note.content != content {
            note.content = content
            // 注意：Note 模型现在会自动根据 content 计算名为 displayTitle 的属性
            notesManager.updateNote(note)
            print("💾 保存内容，长度：\(content.count)")
        }
    }
}

