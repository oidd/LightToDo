import Foundation

class StorageManager {
    static let shared = StorageManager()
    
    private let fileManager = FileManager.default
    private let notesFileName = "notes.json"
    
    private var storageDirectory: URL {
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
