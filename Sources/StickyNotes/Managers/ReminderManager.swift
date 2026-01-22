import Foundation
import AppKit

/// Represents a pending reminder to be triggered
struct PendingReminder: Equatable {
    let todoKey: String
    let deadline: Date
    let color: String
    let reminderMinutesBefore: Int = 1 // Trigger 1 minute before deadline
    
    var triggerTime: Date {
        return deadline.addingTimeInterval(-Double(reminderMinutesBefore * 60))
    }
}

/// Manages reminder scheduling and triggering
class ReminderManager: ObservableObject {
    static let shared = ReminderManager()
    
    @Published private(set) var activeReminders: [String] = [] // Keys of todos currently reminding
    
    private var checkTimer: Timer?
    private var pendingReminders: [PendingReminder] = []
    private var triggeredReminders: Set<String> = [] // Prevent duplicate triggers
    
    // Callbacks
    var onReminderTriggered: ((String, String) -> Void)? // (todoKey, color)
    var onStopRipple: (() -> Void)?
    
    private init() {
        startPeriodicCheck()
    }
    
    deinit {
        checkTimer?.invalidate()
    }
    
    // MARK: - Timer Management
    
    private func startPeriodicCheck() {
        // Check every 30 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkReminders()
        }
        // Also run immediately
        checkTimer?.fire()
    }
    
    // MARK: - Public API
    
    /// Update the list of pending reminders from the editor
    func updateReminders(_ reminders: [PendingReminder]) {
        self.pendingReminders = reminders
        // Clean up triggered reminders that are no longer in the list
        let currentKeys = Set(reminders.map { $0.todoKey })
        triggeredReminders = triggeredReminders.intersection(currentKeys)
    }
    
    /// Mark a reminder as stopped (user checked the todo or acknowledged it)
    func stopReminder(for todoKey: String) {
        activeReminders.removeAll { $0 == todoKey }
        // If no more active reminders, stop ripple
        if activeReminders.isEmpty {
            onStopRipple?()
        }
    }
    
    /// Called when the window expands - triggers bell animations for active reminders
    func onWindowExpanded() {
        // Bell animations are triggered via JavaScript through the editor
        // This is handled by the notification sent to WebView
    }
    
    // MARK: - Reminder Checking
    
    private func checkReminders() {
        let now = Date()
        
        for reminder in pendingReminders {
            // Skip if already triggered
            guard !triggeredReminders.contains(reminder.todoKey) else { continue }
            
            // Check if it's time to trigger (within 1 minute before deadline)
            let triggerTime = reminder.triggerTime
            let deadline = reminder.deadline
            
            // Trigger if: triggerTime <= now <= deadline
            if now >= triggerTime && now <= deadline {
                triggerReminder(reminder)
            }
        }
    }
    
    private func triggerReminder(_ reminder: PendingReminder) {
        // Mark as triggered to prevent duplicates
        triggeredReminders.insert(reminder.todoKey)
        
        // Add to active reminders
        if !activeReminders.contains(reminder.todoKey) {
            activeReminders.append(reminder.todoKey)
        }
        
        // Notify the callback (this will trigger ripple animation on edge bar)
        onReminderTriggered?(reminder.todoKey, reminder.color)
        
        // Schedule auto-stop after 1 minute if not acknowledged
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.stopReminder(for: reminder.todoKey)
        }
    }
    
    /// Parse reminder data from JSON received from editor
    func parseRemindersFromJSON(_ jsonString: String) -> [PendingReminder] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return json.compactMap { dict -> PendingReminder? in
                    guard let todoKey = dict["key"] as? String,
                          let timeMs = dict["time"] as? Double,
                          let hasReminder = dict["hasReminder"] as? Bool,
                          hasReminder,
                          timeMs > 0 else { return nil }
                    
                    let color = dict["reminderColor"] as? String ?? "orange"
                    let deadline = Date(timeIntervalSince1970: timeMs / 1000)
                    
                    return PendingReminder(
                        todoKey: todoKey,
                        deadline: deadline,
                        color: color
                    )
                }
            }
        } catch {
            print("Failed to parse reminder JSON: \(error)")
        }
        
        return []
    }
}
