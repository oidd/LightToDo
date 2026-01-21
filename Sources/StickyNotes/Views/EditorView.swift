import SwiftUI

struct EditorView: View {
    @EnvironmentObject var notesManager: NotesManager
    @Environment(\.controlActiveState) var controlActiveState
    @Binding var editorMode: String // 从 MainView 接收
    var isSidebarCollapsed: Bool
    @State private var content: String = ""
    @State private var editorReady: Bool = false
    
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
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

