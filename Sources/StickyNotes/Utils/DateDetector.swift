import Foundation

struct DateDetectionResult: Codable {
    let matchedText: String
    let date: TimeInterval
    let range: [Int] // [location, length]
    let repeatType: String // "none", "daily", "weekly", "monthly", "yearly", "weekdays"
    let suggestedLabel: String // e.g. "明天 03:00"
}

class DateDetector {
    static let shared = DateDetector()
    private var detector: NSDataDetector?
    
    private init() {
        try? detector = NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }
    
    func detect(in text: String) -> DateDetectionResult? {
        guard let detector = detector else { return nil }
        
        // Find the first date match
        // We iterate to find the most "relevant" one, or just the first valid one.
        // For simple usage, first match is usually what we want (e.g. "Tomorrow 3pm")
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        
        guard let match = matches.first, let date = match.date else {
            return nil
        }
        
        let matchedString = (text as NSString).substring(with: match.range)
        
        // Infer repetition from the context (surrounding text or the match itself if it contains keywords)
        // NSDataDetector usually captures "Every Monday" as a date (next monday), but doesn't tell us it's recurring.
        // We'll peek at the matched text using simple heuristics for Chinese/English.
        let repeatType = inferRepeateType(from: text, range: match.range)
        
        // Format the suggested label
        let formatter = DateFormatter()
        // Smart format: if within this year, hide year. If today/tomorrow, use relative.
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'今天' HH:mm"
        } else if Calendar.current.isDateInTomorrow(date) {
            formatter.dateFormat = "'明天' HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        let label = formatter.string(from: date)
        
        return DateDetectionResult(
            matchedText: matchedString,
            date: date.timeIntervalSince1970 * 1000, // JS expects ms
            range: [match.range.location, match.range.length],
            repeatType: repeatType,
            suggestedLabel: label
        )
    }
    
    private func inferRepeateType(from text: String, range: NSRange) -> String {
        // Look at the matched text specifically, or a slightly wider window?
        // Usually "Every day" is part of the time phrase or immediately adjacent.
        // Let's check the matched string + 2 chars before/after if possible, or just the full text?
        // Checking full text might be risky ("I go to gym Every day but next Monday I can't").
        // Let's stick to the matched string first, and if not found, check if immediate prefix has "Every"/"每".
        
        let nsString = text as NSString
        // Expand range slightly to catch "每" before "周一" if detector only caught "周一"
        let start = max(0, range.location - 2)
        let end = min(nsString.length, range.location + range.length + 2)
        let extendedRange = NSRange(location: start, length: end - start)
        let snippet = nsString.substring(with: extendedRange).lowercased()
        
        if snippet.contains("每天") || snippet.contains("每日") || snippet.contains("every day") || snippet.contains("daily") {
            return "daily"
        }
        if snippet.contains("每周") || snippet.contains("every week") || snippet.contains("weekly") {
            return "weekly"
        }
        if snippet.contains("每月") || snippet.contains("every month") || snippet.contains("monthly") {
            return "monthly"
        }
        if snippet.contains("每年") || snippet.contains("every year") || snippet.contains("yearly") {
            return "yearly"
        }
        // "Weekday" logic could be added: "工作日" -> weekdays
        if snippet.contains("工作日") || snippet.contains("weekdays") {
            return "weekdays"
        }
        
        return "none"
    }
}
