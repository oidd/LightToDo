import Foundation
import Combine

class NotesManager: ObservableObject {
    @Published var notes: [Note] = []
    
    enum FilterMode: String, CaseIterable {
        case all = "all"
        case today = "today"
        case recurring = "recurring"
        case completed = "completed"
        
        var title: String {
            switch self {
            case .all: return "全部"
            case .today: return "今天"
            case .recurring: return "周期"
            case .completed: return "完成"
            }
        }
    }
    
    @Published var currentFilter: FilterMode = .all
    @Published var todoCounts: [String: Int] = ["all": 0, "today": 0, "recurring": 0, "completed": 0]
    
    @Published var selectedNoteId: UUID?  // 当前活跃笔记（编辑器显示的）
    @Published var selectedNoteIds: Set<UUID> = []  // 多选集合
    @Published var isSidebarFocused: Bool = true  // 追踪侧边栏是否拥有焦点
    
    private var lastSelectedIndex: Int?  // Shift 选择的锚点
    private let storage = StorageManager.shared
    
    init() {
        loadData()
        
        // 监听存储路径变更
        NotificationCenter.default.addObserver(forName: Notification.Name("StoragePathChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.loadData()
        }
    }
    
    // MARK: - Data Loading
    
    func loadData() {
        notes = storage.loadNotes()
        
        // Ensure at least one note exists for the Todo-only app
        if notes.isEmpty {
            _ = addNote()
        }
        
        // 自动选中第一个笔记
        if let firstNote = notes.first {
            selectedNoteId = firstNote.id
            selectedNoteIds = [firstNote.id]
        }
    }
    
    // MARK: - Notes CRUD
    
    func addNote() -> Note {
        let note = Note(content: Note.createDefaultContent())
        // 插入到所有置顶文档的后面
        let insertIndex = notes.firstIndex(where: { !$0.isPinned }) ?? notes.count
        notes.insert(note, at: insertIndex)
        selectedNoteId = note.id
        selectedNoteIds = [note.id]
        lastSelectedIndex = insertIndex
        updateSortOrders()
        saveNotes()
        return note
    }
    
    func updateNote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            var updatedNote = note
            updatedNote.updatedAt = Date()
            notes[index] = updatedNote
            saveNotes()
        }
    }
    
    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        selectedNoteIds.remove(note.id)
        if selectedNoteId == note.id {
            selectedNoteId = notes.first?.id
        }
        saveNotes()
    }
    
    func deleteNote(at offsets: IndexSet) {
        let notesToDelete = offsets.map { notes[$0] }
        for note in notesToDelete {
            selectedNoteIds.remove(note.id)
            if selectedNoteId == note.id {
                selectedNoteId = nil
            }
        }
        notes.remove(atOffsets: offsets)
        if selectedNoteId == nil {
            selectedNoteId = notes.first?.id
        }
        saveNotes()
    }
    
    // MARK: - 批量删除
    
    func deleteSelectedNotes() {
        notes.removeAll { selectedNoteIds.contains($0.id) }
        if let currentId = selectedNoteId, selectedNoteIds.contains(currentId) {
            selectedNoteId = notes.first?.id
        }
        selectedNoteIds.removeAll()
        if let firstNote = notes.first {
            selectedNoteIds = [firstNote.id]
            selectedNoteId = firstNote.id
        }
        saveNotes()
    }
    
    // MARK: - 置顶
    
    func togglePin(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].isPinned.toggle()
            sortNotes()
            saveNotes()
        }
    }
    
    // MARK: - 批量置顶/取消置顶
    
    func togglePinSelectedNotes() {
        // 如果所有选中的都已置顶，则取消置顶；否则全部置顶
        let allPinned = selectedNoteIds.allSatisfy { id in
            notes.first(where: { $0.id == id })?.isPinned == true
        }
        
        for id in selectedNoteIds {
            if let index = notes.firstIndex(where: { $0.id == id }) {
                notes[index].isPinned = !allPinned
            }
        }
        sortNotes()
        saveNotes()
    }
    
    // MARK: - 拖动排序
    
    func moveNote(fromOffsets source: IndexSet, toOffset destination: Int) {
        notes.move(fromOffsets: source, toOffset: destination)
        updateSortOrders()
        saveNotes()
    }
    
    func moveNote(noteId: UUID, toIndex: Int) {
        guard let sourceIndex = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let note = notes.remove(at: sourceIndex)
        let adjustedIndex = min(toIndex, notes.count)
        notes.insert(note, at: adjustedIndex)
        updateSortOrders()
        saveNotes()
    }
    
    private func updateSortOrders() {
        for (index, _) in notes.enumerated() {
            notes[index].sortOrder = index
        }
    }
    
    private func sortNotes() {
        // 置顶的在前，然后按 sortOrder 升序
        notes.sort { (a, b) in
            if a.isPinned != b.isPinned {
                return a.isPinned
            }
            return a.sortOrder < b.sortOrder
        }
        updateSortOrders()
    }
    
    private func saveNotes() {
        storage.saveNotes(notes)
    }
    
    // MARK: - 多选逻辑
    
    /// 处理笔记选择（支持 Shift 和 Cmd 修饰键）
    func selectNote(_ noteId: UUID, shiftPressed: Bool, cmdPressed: Bool) {
        guard let clickedIndex = notes.firstIndex(where: { $0.id == noteId }) else { return }
        
        if shiftPressed, let anchor = lastSelectedIndex {
            // Shift+Click: 范围选择
            let range = min(anchor, clickedIndex)...max(anchor, clickedIndex)
            selectedNoteIds = Set(range.map { notes[$0].id })
        } else if cmdPressed {
            // Cmd+Click: 切换选择
            if selectedNoteIds.contains(noteId) {
                selectedNoteIds.remove(noteId)
                // 如果移除的是当前活跃笔记，切换到第一个选中的
                if selectedNoteId == noteId {
                    selectedNoteId = selectedNoteIds.first
                }
            } else {
                selectedNoteIds.insert(noteId)
            }
            lastSelectedIndex = clickedIndex
        } else {
            // 普通点击: 单选
            selectedNoteIds = [noteId]
            lastSelectedIndex = clickedIndex
        }
        
        // 更新活跃笔记（编辑器显示的）
        selectedNoteId = noteId
    }
    
    /// 检查笔记是否被选中（用于 UI 高亮）
    func isSelected(_ noteId: UUID) -> Bool {
        return selectedNoteIds.contains(noteId)
    }
    
    // MARK: - Selected Note
    
    var selectedNote: Note? {
        // 在新版逻辑中，由于只有一个待办笔记，我们始终返回这个笔记。
        // 如果以后有多个笔记，可以根据 selectedNoteId 返回。
        if let id = selectedNoteId {
            return notes.first { $0.id == id }
        }
        return notes.first
    }
}
