import Foundation
import AppKit
import UserNotifications

/// Represents a pending reminder to be triggered
struct PendingReminder: Equatable {
    let todoKey: String
    let text: String
    let deadline: Date
    let color: String
    let reminderMinutesBefore: Int = 1 // Trigger 1 minute before deadline
    
    var triggerTime: Date {
        return deadline.addingTimeInterval(-Double(reminderMinutesBefore * 60))
    }
}

/// Manages reminder scheduling and triggering
class ReminderManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderManager()
    
    @Published private(set) var activeReminders: [String] = [] // Keys of todos currently reminding
    
    private var checkTimer: Timer?
    private var pendingReminders: [PendingReminder] = []
    private var triggeredReminders: Set<String> = [] // Prevent duplicate triggers
    
    // Callbacks
    var onReminderTriggered: ((String, String) -> Void)? // (todoKey, color)
    var onStopRipple: (() -> Void)?
    
    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        startPeriodicCheck()
    }
    
    deinit {
        checkTimer?.invalidate()
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // App 处于前台时也能显示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // 用户点击通知时的响应
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 可以根据需要跳转到特定页面
        completionHandler()
    }
    
    // MARK: - Timer Management
    
    private func startPeriodicCheck() {
        // Check every 1 second for precision
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkReminders()
        }
        // Also run immediately
        checkTimer?.fire()
    }
    
    // MARK: - Public API
    
    /// Update the list of pending reminders from the editor
    func updateReminders(_ reminders: [PendingReminder]) {
        // Check for deadline changes to allow re-triggering
        for newReminder in reminders {
            if let oldReminder = self.pendingReminders.first(where: { $0.todoKey == newReminder.todoKey }) {
                // If deadline changed significantly (more than 1s), reset trigger status
                if abs(oldReminder.deadline.timeIntervalSince(newReminder.deadline)) > 1 {
                    triggeredReminders.remove(newReminder.todoKey)
                }
            } else {
                // New reminder, ensure not marked as triggered (unless it's a recycled ID? Unlikely, but safe to clear)
                triggeredReminders.remove(newReminder.todoKey)
            }
        }
        
        self.pendingReminders = reminders
        
        // Clean up triggered reminders that are no longer in the list at all
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
        
        // Handle System Notifications if enabled
        let style = UserDefaults.standard.string(forKey: "reminderStyle") ?? "glow"
        if style == "notification" {
            sendSystemNotification(
                title: "Light To Do",
                subtitle: "待办事项即将到期",
                body: reminder.text
            )
        }
        
        // Schedule auto-stop after 1 minute if not acknowledged
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.stopReminder(for: reminder.todoKey)
        }
    }
    
    // MARK: - Notification Methods
    
    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        print("✅ Notification permission granted.")
                    } else if let error = error {
                        print("❌ Notification permission error: \(error.localizedDescription)")
                    }
                }
            case .denied:
                print("⚠️ Notification permission denied. User needs to enable it in System Settings.")
            case .authorized, .provisional:
                print("✅ Notification permission already authorized.")
            @unknown default:
                break
            }
        }
    }
    
    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func sendSystemNotification(title: String, subtitle: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error adding notification request: \(error.localizedDescription)")
            }
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
                    
                    let text = dict["text"] as? String ?? ""
                    let color = dict["reminderColor"] as? String ?? "orange"
                    let deadline = Date(timeIntervalSince1970: timeMs / 1000)
                    
                    return PendingReminder(
                        todoKey: todoKey,
                        text: text,
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
