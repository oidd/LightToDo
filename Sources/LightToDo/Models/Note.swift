import Foundation
import UniformTypeIdentifiers
import CoreTransferable

// 定义自定义 UTType 用于拖放
extension UTType {
    static var note: UTType {
        UTType(exportedAs: "com.lighttodo.note")
    }
}

struct Note: Identifiable, Codable, Equatable, Transferable {
    var id: UUID
    var content: String  // HTML 格式的字符串
    var mode: String = "note" // 笔记模式 ("note" or "todo")
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool = false  // 置顶状态
    var sortOrder: Int = 0  // 手动排序顺序
    
    // Transferable 协议实现
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .note)
    }
    
    init(id: UUID = UUID(), content: String = "", mode: String = "note", isPinned: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.content = content
        self.mode = mode
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isPinned = isPinned
        self.sortOrder = sortOrder
    }

    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case id, content, mode, createdAt, updatedAt, isPinned, sortOrder
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        // 兼容旧数据：如果缺少 mode 字段，默认为 "note"
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "note"
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        // 兼容旧数据
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(mode, forKey: .mode)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    
    // 从内容自动提取标题（第一行文本）
    var displayTitle: String {
        // 1. 将块级元素结束标签和 br 替换为换行符，防止文本粘连
        var text = content
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "</div>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "</h1>", with: "\n")
            .replacingOccurrences(of: "</h2>", with: "\n")
            .replacingOccurrences(of: "</h3>", with: "\n")
            .replacingOccurrences(of: "</li>", with: "\n")
        
        // 2. 去除所有剩余 HTML 标签
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // 3. 处理常见的 HTML 实体
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        
        // 4. 按换行符分割，查找第一个非空行
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(50))
            }
        }
        
        return "新笔记"
    }
    
    // 创建默认的空 HTML 内容
    static func createDefaultContent() -> String {
        return "<p></p>"
    }
}
