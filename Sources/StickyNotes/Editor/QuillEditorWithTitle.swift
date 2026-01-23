import SwiftUI
import WebKit

class ClickableWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { 
        super.becomeFirstResponder() 
    }
    
    // 禁止此区域触发窗口拖动  
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // 移除 window?.makeFirstResponder(self)
        // 这会抢走 HTML 输入框的焦点，导致待办模式无法打字
    }
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // 1. 定义需要移除的菜单项关键词
        // 移除：浏览器导航、拼写语法、替换、转换、字体、语音、方向等
        let unwantedKeywords = [
            "重新载入", "返回", "前进", "停止", "在", "在新窗口中打开",
            "拼写", "语法", "替换", "转换", "字体", "语音", "段落方向", "选择方向"
        ]
        
        // 2. 过滤现有菜单项
        var newItems: [NSMenuItem] = []
        
        for item in menu.items {
            if item.isSeparatorItem {
                if let last = newItems.last, !last.isSeparatorItem {
                    newItems.append(item)
                }
            } else {
                let title = item.title
                // 仅移除浏览器导航相关项
                let isUnwanted = unwantedKeywords.contains { title.contains($0) }
                if !isUnwanted {
                    newItems.append(item)
                }
            }
        }
        
        // 移除末尾多余的分隔符
        if let last = newItems.last, last.isSeparatorItem {
            newItems.removeLast()
        }
        
        // 3. 添加"删除"菜单项
        let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteFocusedTodo(_:)), keyEquivalent: "")
        deleteItem.target = self
        if let trashImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除") {
            trashImage.isTemplate = true
            deleteItem.image = trashImage
        }
        
        // 添加分隔符然后添加删除
        if !newItems.isEmpty {
            newItems.append(NSMenuItem.separator())
        }
        newItems.append(deleteItem)
        
        // 4. 重建菜单
        menu.removeAllItems()
        for item in newItems {
            menu.addItem(item)
        }
        
        super.willOpenMenu(menu, with: event)
    }
    
    @objc func deleteFocusedTodo(_ sender: Any) {
        // 调用 JavaScript 删除当前聚焦的待办事项
        self.evaluateJavaScript("window.deleteFocusedTodo && window.deleteFocusedTodo()") { _, _ in }
    }

    
    @objc func toggleInlineCode(_ sender: Any) {
        self.evaluateJavaScript("window.toggleInlineCode && window.toggleInlineCode()") { _, _ in }
    }
}

struct QuillEditorWithTitle: NSViewRepresentable {
    @Binding var title: String
    @Binding var content: String
    var onTitleUpdate: () -> Void
    var onContentUpdate: () -> Void
    var onReady: () -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "editor")
        config.userContentController = controller
        
        let webView = ClickableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true // 启用 Safari 调试
        }
        
        context.coordinator.webView = webView
        
        // 查找资源文件
        var htmlURL: URL?
        if let url = Bundle.main.url(forResource: "lexical-editor", withExtension: "html") {
            htmlURL = url
        } else if let url = Bundle.module.url(forResource: "lexical-editor", withExtension: "html") {
            htmlURL = url
        }
        
        if let url = htmlURL {
            print("✅ 正在从路径加载编辑器: \(url.path)")
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if title != context.coordinator.lastLoadedTitle && context.coordinator.isReady {
            let escaped = title.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "'", with: "\\'")
            nsView.evaluateJavaScript("window.setTitle('\(escaped)')") { _, _ in }
            context.coordinator.lastLoadedTitle = title
        }
        
        if content != context.coordinator.lastLoadedContent && context.coordinator.isReady {
            let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "'", with: "\\'")
                             .replacingOccurrences(of: "\n", with: "\\n")
            nsView.evaluateJavaScript("window.setContent('\(escaped)')") { _, _ in }
            context.coordinator.lastLoadedContent = content
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: QuillEditorWithTitle
        weak var webView: WKWebView?
        var lastLoadedTitle: String = ""
        var lastLoadedContent: String = ""
        var isReady: Bool = false
        
        init(_ parent: QuillEditorWithTitle) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let data = message.body as? [String: Any],
                  let type = data["type"] as? String else { return }
            
            switch type {
            case "ready":
                print("✅ Quill 编辑器已就绪")
                isReady = true
                
                // 初始化标题和内容
                if !parent.title.isEmpty {
                    let escaped = parent.title.replacingOccurrences(of: "\\", with: "\\\\")
                                             .replacingOccurrences(of: "'", with: "\\'")
                    webView?.evaluateJavaScript("window.setTitle('\(escaped)')") { _, _ in }
                }
                lastLoadedTitle = parent.title
                
                if !parent.content.isEmpty {
                    let escaped = parent.content.replacingOccurrences(of: "\\", with: "\\\\")
                                                .replacingOccurrences(of: "'", with: "\\'")
                                                .replacingOccurrences(of: "\n", with: "\\n")
                    webView?.evaluateJavaScript("window.setContent('\(escaped)')") { _, _ in }
                }
                lastLoadedContent = parent.content
                
                DispatchQueue.main.async {
                    self.parent.onReady()
                }
                
            case "titleUpdate":
                if let title = data["title"] as? String {
                    DispatchQueue.main.async {
                        self.lastLoadedTitle = title
                        self.parent.title = title
                        self.parent.onTitleUpdate()
                    }
                }
                
            case "update":
                if let html = data["html"] as? String {
                    DispatchQueue.main.async {
                        self.lastLoadedContent = html
                        self.parent.content = html
                        self.parent.onContentUpdate()
                    }
                }
                
            default:
                break
            }
        }
    }
}

// MARK: - 简化版 QuillEditor（不包含标题，标题由 SwiftUI 处理）
struct QuillEditor: NSViewRepresentable {
    @Binding var content: String
    @Binding var filterMode: String
    @Binding var searchText: String
    @Binding var addTrigger: Int
    @Binding var sortMode: String
    var isWindowActive: Bool = true
    var onContentUpdate: () -> Void
    var onCountsUpdate: ([String: Int]) -> Void
    var onReady: () -> Void
    var onNewNote: (() -> Void)? = nil
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "editor")
        config.userContentController = controller
        
        let webView = ClickableWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true // 启用 Safari 调试
        }
        
        context.coordinator.webView = webView
        
        // 查找资源文件
        var htmlURL: URL?
        if let url = Bundle.main.url(forResource: "lexical-editor", withExtension: "html") {
            htmlURL = url
        } else if let url = Bundle.module.url(forResource: "lexical-editor", withExtension: "html") {
            htmlURL = url
        }
        
        if let url = htmlURL {
            print("✅ 正在从路径加载编辑器: \(url.path)")
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if content != context.coordinator.lastLoadedContent && context.coordinator.isReady {
            let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "'", with: "\\'")
                             .replacingOccurrences(of: "\n", with: "\\n")
            nsView.evaluateJavaScript("window.setContent('\(escaped)')") { _, _ in }
            context.coordinator.lastLoadedContent = content
        }
        
        // 只有当活跃状态改变且编辑器就绪时才调用 JS
        if isWindowActive != context.coordinator.lastIsWindowActive && context.coordinator.isReady {
             nsView.evaluateJavaScript("window.setWindowActive(\(isWindowActive))") { _, _ in }
             context.coordinator.lastIsWindowActive = isWindowActive
        }

        // 检查模式变化
        if filterMode != context.coordinator.lastLoadedFilterMode && context.coordinator.isReady {
             nsView.evaluateJavaScript("window.setFilterMode && window.setFilterMode('\(filterMode)')") { _, _ in }
             context.coordinator.lastLoadedFilterMode = filterMode
        }
        
        // 检查搜索文本变化
        if searchText != context.coordinator.lastSearchText && context.coordinator.isReady {
             let escaped = searchText.replacingOccurrences(of: "'", with: "\\'")
             nsView.evaluateJavaScript("window.setSearchQuery && window.setSearchQuery('\(escaped)')") { _, _ in }
             context.coordinator.lastSearchText = searchText
        }
        
        // 检查新增触发器
        if addTrigger != context.coordinator.lastAddTrigger && context.coordinator.isReady {
             nsView.evaluateJavaScript("window.addNewTodo && window.addNewTodo()") { _, _ in }
             context.coordinator.lastAddTrigger = addTrigger
        }
        
        // 检查排序模式变化
        if sortMode != context.coordinator.lastSortMode && context.coordinator.isReady {
             nsView.evaluateJavaScript("window.setTodoSortMode && window.setTodoSortMode('\(sortMode)')") { _, _ in }
             context.coordinator.lastSortMode = sortMode
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: QuillEditor
        weak var webView: WKWebView?
        var lastLoadedContent: String = ""
        var isReady: Bool = false
        var lastIsWindowActive: Bool = true
        var lastLoadedFilterMode: String = "all"
        var lastSearchText: String = ""
        var lastAddTrigger: Int = 0
        var lastSortMode: String = "byDeadline"
        
        init(_ parent: QuillEditor) {
            self.parent = parent
            super.init()
            setupBellNotification()
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let data = message.body as? [String: Any],
                  let type = data["type"] as? String else { return }
            
            switch type {
            case "newNote":
                DispatchQueue.main.async {
                    self.parent.onNewNote?()
                }
                
            case "ready":
                print("✅ Quill 编辑器已就绪")
                isReady = true
                
                // 初始化窗口状态
                webView?.evaluateJavaScript("window.setWindowActive(\(parent.isWindowActive))") { _, _ in }
                lastIsWindowActive = parent.isWindowActive

                // 初始化过滤模式
                webView?.evaluateJavaScript("window.setFilterMode('\(parent.filterMode)')") { _, _ in }
                lastLoadedFilterMode = parent.filterMode
                
                // 初始化排序模式
                webView?.evaluateJavaScript("window.setTodoSortMode && window.setTodoSortMode('\(parent.sortMode)')") { _, _ in }
                lastSortMode = parent.sortMode

                
                // 初始化内容
                if !parent.content.isEmpty {
                    let escaped = parent.content.replacingOccurrences(of: "\\", with: "\\\\")
                                                .replacingOccurrences(of: "'", with: "\\'")
                                                .replacingOccurrences(of: "\n", with: "\\n")
                    webView?.evaluateJavaScript("window.setContent('\(escaped)')") { _, _ in }
                }
                lastLoadedContent = parent.content
                
                DispatchQueue.main.async {
                    self.parent.onReady()
                }
                
            case "update":
                if let html = data["html"] as? String {
                    DispatchQueue.main.async {
                        self.lastLoadedContent = html
                        self.parent.content = html
                        self.parent.onContentUpdate()
                    }
                }
            
            case "reminders":
                if let remindersData = data["data"] as? [[String: Any]] {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: remindersData)
                        if let jsonString = String(data: jsonData, encoding: .utf8) {
                            let reminders = ReminderManager.shared.parseRemindersFromJSON(jsonString)
                            ReminderManager.shared.updateReminders(reminders)
                        }
                    } catch {
                        print("Failed to encode reminders data: \(error)")
                    }
                }
                
            case "counts":
                if let countsDict = data["data"] as? [String: Any] {
                    var counts: [String: Int] = [:]
                    for (key, value) in countsDict {
                        if let val = value as? Int {
                            counts[key] = val
                        } else if let val = value as? Double {
                            counts[key] = Int(val)
                        } else if let val = value as? NSNumber {
                            counts[key] = val.intValue
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.parent.onCountsUpdate(counts)
                    }
                }
                
            case "previewReminder":
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerReminderPreview"), object: nil)
                }
                
            default:
                break
            }
        }
        
        // Listen for bell animation requests
        func setupBellNotification() {
            NotificationCenter.default.addObserver(forName: NSNotification.Name("TriggerBellAnimation"), object: nil, queue: .main) { [weak self] notification in
                guard let self = self, let todoKey = notification.object as? String else { return }
                self.webView?.evaluateJavaScript("window.triggerBellAnimation && window.triggerBellAnimation('\(todoKey)')") { _, _ in }
            }
            
            NotificationCenter.default.addObserver(forName: NSNotification.Name("ShowReminderRays"), object: nil, queue: .main) { [weak self] notification in
                guard let self = self, let dict = notification.object as? [String: String],
                      let edge = dict["edge"], let color = dict["color"] else { return }
                self.webView?.evaluateJavaScript("window.showReminderRays && window.showReminderRays('\(edge)', '\(color)')") { _, _ in }
            }
            
            NotificationCenter.default.addObserver(forName: NSNotification.Name("HideReminderRays"), object: nil, queue: .main) { [weak self] _ in
                self?.webView?.evaluateJavaScript("window.hideReminderRays && window.hideReminderRays()") { _, _ in }
            }
        }
    }
}
