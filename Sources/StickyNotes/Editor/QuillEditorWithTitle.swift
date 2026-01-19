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
        // 1. 定义需要移除的菜单项关键词 (黑名单)
        // 移除：查询、搜索、语音、段落方向、共享、自动填充、服务、拼写和语法、转换、选择方向
        let unwantedKeywords = [
            "查询", "搜索", "语音", "段落方向", "共享", "自动填充", "服务",
            "拼写", "语法", "转换", "选择方向"
        ]
        
        // 2. 过滤现有菜单项
        var newItems: [NSMenuItem] = []
        var insertIndexForClearFormatting: Int? = nil
        
        for item in menu.items {
            if item.isSeparatorItem {
                // 智能分隔符处理：如果上一个也是分隔符，或者列表为空，则忽略当前分隔符（去重）
                if let last = newItems.last, !last.isSeparatorItem {
                    newItems.append(item)
                }
            } else {
                let title = item.title
                // 如果标题包含任意黑名单关键词，则移除
                let isUnwanted = unwantedKeywords.contains { title.contains($0) }
                if !isUnwanted {
                    // 记录"替换"项的位置，用于在其前面插入 Clear Formatting
                    if title.contains("替换") {
                        insertIndexForClearFormatting = newItems.count
                    }
                    newItems.append(item)
                }
            }
        }
        
        // 移除末尾多余的分隔符 (如果过滤后最后一个是分隔符)
        if let last = newItems.last, last.isSeparatorItem {
            newItems.removeLast()
        }
        
        // 3. 在"替换"前插入 "清除格式"
        // 2.5 进一步清理 "字体" 子菜单 (移除点不动的项)
        for item in newItems {
            if item.title.contains("字体") || item.title == "Font" {
                if let submenu = item.submenu {
                    var validSubItems: [NSMenuItem] = []
                    for subItem in submenu.items {
                        let t = subItem.title
                        // 移除: 显示字体, 空心字, 样式, 显示颜色
                        if t.contains("显示字体") || t.contains("Show Fonts") ||
                           t.contains("空心字") || t.contains("Outline") ||
                           t.contains("样式") || t.contains("Styles") ||
                           t.contains("显示颜色") || t.contains("Show Colors") ||
                           t == "字体" || t == "Font"/*有些系统包含自身标题*/ {
                            continue
                        }
                        validSubItems.append(subItem)
                    }
                    
                    submenu.removeAllItems()
                    for subItem in validSubItems {
                        submenu.addItem(subItem)
                    }
                }
            }
        }

        if let idx = insertIndexForClearFormatting {
            let clearItem = NSMenuItem(title: "清除格式", action: #selector(clearFormatting(_:)), keyEquivalent: "")
            clearItem.target = self
            clearItem.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)
            newItems.insert(clearItem, at: idx)
        }
        
        // 4. 重建菜单
        menu.removeAllItems()
        for item in newItems {
            menu.addItem(item)
        }
        
        // 5. 添加自定义项 (对齐方式和列表)
        menu.addItem(NSMenuItem.separator())
        
        // 创建"对齐方式"主菜单项
        let alignItem = NSMenuItem(title: "对齐方式", action: nil, keyEquivalent: "")
        alignItem.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        
        let subMenu = NSMenu(title: "对齐方式")
        
        let leftItem = NSMenuItem(title: "左对齐", action: #selector(alignLeft(_:)), keyEquivalent: "")
        leftItem.target = self
        leftItem.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        subMenu.addItem(leftItem)
        
        let centerItem = NSMenuItem(title: "居中对齐", action: #selector(alignCenter(_:)), keyEquivalent: "")
        centerItem.target = self
        centerItem.image = NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: nil)
        subMenu.addItem(centerItem)
        
        let rightItem = NSMenuItem(title: "右对齐", action: #selector(alignRight(_:)), keyEquivalent: "")
        rightItem.target = self
        rightItem.image = NSImage(systemSymbolName: "text.alignright", accessibilityDescription: nil)
        subMenu.addItem(rightItem)
        
        let justifyItem = NSMenuItem(title: "两端对齐", action: #selector(alignJustify(_:)), keyEquivalent: "")
        justifyItem.target = self
        justifyItem.image = NSImage(systemSymbolName: "text.justify", accessibilityDescription: nil)
        subMenu.addItem(justifyItem)
        
        alignItem.submenu = subMenu
        menu.addItem(alignItem)
        
        // 添加 "列表" 子菜单
        let listItem = NSMenuItem(title: "列表", action: nil, keyEquivalent: "")
        listItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        
        let listSubMenu = NSMenu(title: "列表")
        
        // 1. 数字编号
        let orderedItem = NSMenuItem(title: "数字列表", action: #selector(setOrderedList(_:)), keyEquivalent: "")
        orderedItem.target = self
        orderedItem.image = NSImage(systemSymbolName: "list.number", accessibilityDescription: nil)
        listSubMenu.addItem(orderedItem)
        
        // 2. 圆点编号
        let bulletItem = NSMenuItem(title: "符号列表", action: #selector(setBulletList(_:)), keyEquivalent: "")
        bulletItem.target = self
        bulletItem.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        listSubMenu.addItem(bulletItem)
        
        listItem.submenu = listSubMenu
        menu.addItem(listItem)
        
        super.willOpenMenu(menu, with: event)
    }
    
    @objc func clearFormatting(_ sender: Any) {
        self.evaluateJavaScript("window.clearFormatting && window.clearFormatting()") { _, _ in }
    }
    
    @objc func alignLeft(_ sender: Any) {
        self.evaluateJavaScript("window.setAlignment && window.setAlignment('left')") { _, _ in }
    }
    
    @objc func alignCenter(_ sender: Any) {
        self.evaluateJavaScript("window.setAlignment && window.setAlignment('center')") { _, _ in }
    }
    
    @objc func alignRight(_ sender: Any) {
        self.evaluateJavaScript("window.setAlignment && window.setAlignment('right')") { _, _ in }
    }
    
    @objc func alignJustify(_ sender: Any) {
        self.evaluateJavaScript("window.setAlignment && window.setAlignment('justify')") { _, _ in }
    }
    
    @objc func setOrderedList(_ sender: Any) {
        self.evaluateJavaScript("window.setListType && window.setListType('number')") { _, _ in }
    }
    
    @objc func setBulletList(_ sender: Any) {
        self.evaluateJavaScript("window.setListType && window.setListType('bullet')") { _, _ in }
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
    var isWindowActive: Bool = true
    var currentMode: String = "note"
    var onContentUpdate: () -> Void
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
        if currentMode != context.coordinator.lastLoadedMode && context.coordinator.isReady {
             nsView.evaluateJavaScript("window.setMode('\(currentMode)')") { _, _ in }
             context.coordinator.lastLoadedMode = currentMode
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
        var lastLoadedMode: String = "note"
        
        init(_ parent: QuillEditor) {
            self.parent = parent
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

                // 初始化模式
                webView?.evaluateJavaScript("window.setMode('\(parent.currentMode)')") { _, _ in }
                lastLoadedMode = parent.currentMode

                
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
                
            default:
                break
            }
        }
    }
}
