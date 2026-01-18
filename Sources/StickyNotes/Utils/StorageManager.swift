import Foundation

class StorageManager {
    static let shared = StorageManager()
    
    private let fileManager = FileManager.default
    private let notesFileName = "notes.json"
    
    private var storageDirectory: URL {
        // 1. 检查用户自定义路径
        if let customPath = UserDefaults.standard.string(forKey: "notesStoragePath"), !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            if (try? url.checkResourceIsReachable()) == true {
                return url
            }
        }
        
        // 2. 默认路径
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("StickyNotes", isDirectory: true)
        
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        
        return appDir
    }
    
    private var notesFileURL: URL {
        storageDirectory.appendingPathComponent(notesFileName)
    }
    
    // MARK: - Notes
    
    func saveNotes(_ notes: [Note]) {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: notesFileURL)
        } catch {
            print("Failed to save notes: \(error)")
        }
    }
    
    func loadNotes() -> [Note] {
        // 如果文件不存在，尝试从 Application Support 迁移数据? 
        // 暂时不自动迁移，遵从用户意图：选择新文件夹即读取新文件夹内容
        
        guard fileManager.fileExists(atPath: notesFileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: notesFileURL)
            return try JSONDecoder().decode([Note].self, from: data)
        } catch {
            print("Failed to load notes: \(error)")
            return []
        }
    }
}
