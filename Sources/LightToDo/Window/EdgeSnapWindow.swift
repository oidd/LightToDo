import AppKit
import SwiftUI

class EdgeSnapWindowController: NSObject {
    weak var window: NSWindow?
    private var indicatorWindow: EdgeIndicatorWindow?
    private var rippleOverlay: RippleOverlayWindow? // Keep existing for reminder ripples if needed, or deprecate? Let's keep for now.
    private var visualEffectOverlay: VisualEffectOverlayWindow?
    
    // 配置

    
    // 状态
    private(set) var state: WindowState = .floating
    private(set) var snapEdge: SnapEdge = .none
    
    // Default to right if not set
    private var preferredEdge: SnapEdge {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "preferredSnapEdge") ?? "right"
            return SnapEdge(rawValue: rawValue) ?? .right
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "preferredSnapEdge")
        }
    }
    private var hasUserInteraction = false
    private var pendingDockInteraction = false
    private var originalFrame: NSRect = .zero
    private var isDragging = false
    private var isProgrammaticMove = false // 新增：防止代码移动窗口时触发拖拽逻辑
    private var lastUserSize: CGSize? // 记录用户手动调整的最后大小
    
    // 鼠标监听器
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    
    // 拖拽专用监听器 (用于检测释放)
    private var dragGlobalMonitor: Any?
    private var dragLocalMonitor: Any?
    
    private var mouseTrackingTimer: Timer?
    
    // 配置
    private let edgeThreshold: CGFloat = 30        // 增加吸附阈值，提升手感
    private let animationDuration: TimeInterval = 0.25
    private let collapseBufferDistance: CGFloat = 80
    
    init(window: NSWindow) {
        self.window = window
        super.init()
        
        setupWindow()
    }
    
    deinit {
        removeMouseMonitors()
        stopDragMonitoring()
        mouseTrackingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // 记录初始大小
        self.lastUserSize = window.frame.size
        
        // 配置窗口样式
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        
        // 监听窗口移动
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: window
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillMove),
            name: NSWindow.willMoveNotification,
            object: window
        )
        
        // 监听用户手动调整大小结束 (更新 lastUserSize)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEndLiveResize),
            name: NSWindow.didEndLiveResizeNotification,
            object: window
        )
        
        // 初始化辅助线条窗口
        createIndicatorWindow()
        
        // 全局鼠标监听（用于检测点击窗口外部）
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleGlobalClick(event)
        }
        
        // 本地鼠标监听（用于检测窗口内操作）
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.handleLocalInteraction(event)
            return event
        }
        
        // 监听颜色变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColorChange),
            name: Notification.Name("EdgeBarColorChanged"),
            object: nil
        )
        
        // 监听应用活跃状态 (用于后台召唤/自动收起)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = window, let screen = window.screen else { return }
        
        // Improve Logic: Don't save size if it looks like a system snap/maximize
        // If window covers > 90% of screen, or is exactly half-screen width/height, skip saving.
        // Simple heuristic: Only save if it's "floating-like"
        
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        
        let isMaximized = windowFrame.width >= screenFrame.width * 0.95 && windowFrame.height >= screenFrame.height * 0.95
        
        // Also Filter default half-split views? Maybe too aggressive.
        // Let's stick to the "Big Enlarge" the user mentioned.
        
        if !isMaximized {
            self.lastUserSize = window.frame.size
        }
    }
    
    private func createIndicatorWindow() {
        let indicator = EdgeIndicatorWindow()
        
        // 初始化颜色
        let colorName = UserDefaults.standard.string(forKey: "reminderColor") ?? "orange"
        indicator.updateColor(colorFromString(colorName))
        
        indicator.onMouseEntered = { [weak self] in
            guard let self = self else { return }
            self.stopRippleAnimation()
            
            if self.state == .floating {
                // Summon Mode: Bring window to front
                self.summonWindow()
            } else {
                // Expand Mode: Slide out
                self.expand()
            }
        }
        self.indicatorWindow = indicator
        
        // Create ripple overlay
        rippleOverlay = RippleOverlayWindow()
        
        // Create new visual effect overlay
        visualEffectOverlay = VisualEffectOverlayWindow()
        
    }
    
    @objc private func handleColorChange(_ notification: Notification) {
        let colorName = notification.object as? String ?? "orange"
        indicatorWindow?.updateColor(colorFromString(colorName))
    }
    
    private func colorFromString(_ colorName: String) -> NSColor {
        switch colorName {
        case "blue": return NSColor(red: 0.565, green: 0.792, blue: 0.976, alpha: 1)
        case "green": return NSColor(red: 0.647, green: 0.839, blue: 0.655, alpha: 1)
        case "red": return NSColor(red: 0.937, green: 0.604, blue: 0.604, alpha: 1)
        case "yellow": return NSColor(red: 1, green: 0.961, blue: 0.616, alpha: 1)
        case "purple": return NSColor(red: 0.808, green: 0.576, blue: 0.847, alpha: 1)
        case "pink": return NSColor(red: 0.957, green: 0.561, blue: 0.694, alpha: 1)
        case "gray": return NSColor(red: 0.690, green: 0.745, blue: 0.773, alpha: 1)
        default: return NSColor(red: 1, green: 0.8, blue: 0.502, alpha: 1)
        }
    }
    
    private func removeMouseMonitors() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }
    
    // MARK: - Drag Detection
    
    private func startDragMonitoring() {
        // 防止重复添加
        if dragGlobalMonitor != nil || dragLocalMonitor != nil { return }
        
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.handleDragEnd()
        }
        
        // 监听鼠标抬起，作为拖拽结束的信号
        dragGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: handler)
        dragLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            handler(event)
            return event
        }
    }
    
    private func stopDragMonitoring() {
        if let monitor = dragGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            dragGlobalMonitor = nil
        }
        if let monitor = dragLocalMonitor {
            NSEvent.removeMonitor(monitor)
            dragLocalMonitor = nil
        }
    }
    
    private func handleDragEnd() {
        stopDragMonitoring()
        
        if isDragging {
            isDragging = false
            // 只有当真正的拖拽结束时才检查吸附
            checkEdgeSnap()
        }
    }
    
    // MARK: - Window Movement
    
    @objc private func windowWillMove(_ notification: Notification) {
        // 如果是代码控制的移动，或者是我们在吸附/隐藏动画中，不要重置状态
        if isProgrammaticMove { return }
        
        guard let window = window else { return }
        
        // 1. 检查是否需要恢复原始大小 (针对 macOS 系统级吸附/缩放后的恢复)
        // 只有当窗口明显被改变大小时才尝试恢复 (避免微小抖动触发)
        if let savedSize = lastUserSize {
            let currentArea = window.frame.width * window.frame.height
            let savedArea = savedSize.width * savedSize.height
            
            // 如果当前面积明显大于用户保存的面积 (说明被系统放大了)，则恢复
            // 使用 > 1.1 作为容差
            if currentArea > savedArea * 1.05 || currentArea < savedArea * 0.95 {
                 // 保持窗口顶部和中心相对位置，防止跳变
                 let oldMaxY = window.frame.maxY
                 let oldMidX = window.frame.midX
                 
                 var newFrame = window.frame
                 newFrame.size = savedSize
                 newFrame.origin.y = oldMaxY - savedSize.height
                 newFrame.origin.x = oldMidX - savedSize.width / 2
                 
                 window.setFrame(newFrame, display: true)
            }
        }
        
         // 开始拖动
         if !isDragging {
             isDragging = true
             startDragMonitoring()
         }
        
         // 拖动开始：如果已经吸附，立即解除状态并隐藏线条
         if state != .floating {
             state = .floating
             snapEdge = .none
             hasUserInteraction = false
             pendingDockInteraction = false
             indicatorWindow?.orderOut(nil)
             visualEffectOverlay?.stopExpandEffect() // Fix: Remove beam when dragging
             stopMouseTrackingTimer()
             
             // Restore interaction
             window.alphaValue = 1
             window.ignoresMouseEvents = false
         }
    }
    
    @objc private func windowDidMove(_ notification: Notification) {
        // 仅仅是标记，实际逻辑在 windowWillMove 和 handleDragEnd 中处理
        // 这里不需要做耗时的检查，也不需要那个不可靠的 timer Hack
    }
    
    private func checkEdgeSnap() {
        // 如果正在代码动画中，也不要吸附
        guard !isProgrammaticMove else { return }
        guard let window = window, state == .floating else { return }
        guard let screen = NSScreen.main else { return }
        
        let windowFrame = window.frame
        let screenFrame = screen.visibleFrame
        
        // 检测左边缘
        if windowFrame.minX <= screenFrame.minX + edgeThreshold {
            // Smart Logic: If window is already partially off-screen (minX < screenFrame.minX), collapse immediately
            let immediate = windowFrame.minX < screenFrame.minX
            snapToEdge(.left, collapseImmediately: immediate)
            return
        }
        
        // 检测右边缘
        if windowFrame.maxX >= screenFrame.maxX - edgeThreshold {
            // Smart Logic: If window is already partially off-screen (maxX > screenFrame.maxX), collapse immediately
            let immediate = windowFrame.maxX > screenFrame.maxX
            snapToEdge(.right, collapseImmediately: immediate)
            return
        }
    }
    
    // MARK: - Edge Snapping Lifecycle
    
    private func snapToEdge(_ edge: SnapEdge, collapseImmediately: Bool = false) {
        guard let window = window else { return }
        // 注意：这里使用 NSScreen.main 确保尽可能在这个屏幕吸附。实际逻辑可根据 window.screen
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        snapEdge = edge
        preferredEdge = edge // Save preference
        originalFrame = window.frame
        
        if collapseImmediately {
            // Direct Collapse: Skip the snap-to-edge animation and go straight to hidden
            // We set state to .snapped temporarily so collapse() knows where to go
            state = .snapped
            collapse()
            return
        }
        
        let screenFrame = screen.visibleFrame
        var newFrame = window.frame
        
        // 1. 先对齐到边缘（吸附态）
        switch edge {
        case .left:
            newFrame.origin.x = screenFrame.minX
        case .right:
            newFrame.origin.x = screenFrame.maxX - newFrame.width
        case .none: return
        }
        
        isProgrammaticMove = true
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isProgrammaticMove = false
            
            // 吸附动画结束，状态变为 snapped
            self.state = .snapped
            // 延迟一点点后自动折叠隐藏
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.collapse()
            }
        }
    }
    
    private func collapse() {
        guard let window = window, snapEdge != .none else { return }
        // 防止重复折叠
        if state == .collapsed { return }
        
        guard let screen = window.screen ?? NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        var newFrame = window.frame
        
        let hideOffset: CGFloat = 50 
        
        // 2. 完全移出屏幕
        switch snapEdge {
        case .left:
            newFrame.origin.x = screenFrame.minX - newFrame.width - hideOffset
        case .right:
            newFrame.origin.x = screenFrame.maxX + hideOffset
        case .none: return
        }
        
        isProgrammaticMove = true
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isProgrammaticMove = false
            
            self.state = .collapsed
            self.pendingDockInteraction = false
            
            // 3. 幽灵模式：完全透明且不响应鼠标，解决遮挡 Bug
            self.window?.alphaValue = 0
            self.window?.ignoresMouseEvents = true
            
            // 4. 显示指示线条
            self.showIndicator(for: self.window!)
            
            // 5. Trigger Collapse Animation (Squash & Particles)
            let colorName = UserDefaults.standard.string(forKey: "reminderColor") ?? "orange"
            let color = self.colorFromString(colorName)
            
            // Determine impact point (center of strip vertically)
            let midY = self.window!.frame.midY - (self.window!.screen?.frame.minY ?? 0)
            // But we need screen coordinates for the overlay? No, overlay is usually fullscreen or large.
            // VisualEffectOverlayWindow handles coordinates relative to itself.
            // Let's pass the point relative to the Overlay's future frame?
            // Actually, we'll position the overlay to cover the impact area.
            
            // Just pass the strip center point in screen coordinates?
            // The overlay will be placed to cover the area.
            let stripX = (self.snapEdge == .left) ? (screenFrame.minX) : (screenFrame.maxX)
            let impactPoint = CGPoint(x: stripX, y: midY) 
            
            // For now, let's just use the strip's frame for calculations inside.
            // We need to map coordinates.
            // Let's simplify: pass edge and let overlay handle mapping if it fills screen?
            // VisualEffectOverlay logic expects `startCollapseEffect(edge:point:color:)`. 
            
            // Let's position overlay first?
            let overlayRect = screenFrame
            self.visualEffectOverlay?.setFrame(overlayRect, display: true)
            self.visualEffectOverlay?.orderFront(nil)
            
            // Convert stripX to overlay local
            let localPoint = CGPoint(x: (self.snapEdge == .left) ? 0 : overlayRect.width, y: midY - overlayRect.minY)
            
            self.visualEffectOverlay?.startCollapseEffect(edge: self.snapEdge, point: localPoint, color: color)
            
            // Trigger Strip Squash Animation (Only for impact, no color revert)
            self.indicatorWindow?.animateSquashAndStretch()
        }
    }
    
    // 公开给 AppDelegate 调用
    func forceExpand() {
        // 无论当前状态如何（除了已经是常规浮动），都强制展开
        if state != .floating {
            pendingDockInteraction = true // 标记：这是 Dock 唤醒的，等待鼠标
            
            // 确保窗口立即可见可点
            window?.alphaValue = 1
            window?.ignoresMouseEvents = false
            
            expand()
        }
    }
    
    private func expand() {
        guard let window = window, snapEdge != .none else { return }
        // 防止重复展开
        if state == .expanded { return }
        
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        // 1. 解除幽灵模式：恢复不透明度，恢复鼠标响应
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        
        // 2. Set Intensity IMMEDIATELY (User feedback: sync color)
        // This ensures the color is bold BEFORE the window starts moving.
        self.showIndicator(for: window, isIntense: true)
        indicatorWindow?.level = .screenSaver
        
        let screenFrame = screen.visibleFrame
        var newFrame = window.frame
        
        // 3. 移回屏幕边缘
        switch snapEdge {
        case .left:
            newFrame.origin.x = screenFrame.minX
        case .right:
            newFrame.origin.x = screenFrame.maxX - newFrame.width
        case .none: return
        }
        
        // 确保窗口在最前
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        isProgrammaticMove = true
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self = self else { return }
            self.isProgrammaticMove = false
            
            self.state = .expanded
            // 4. Maintenance / Force position update
            self.showIndicator(for: window, isIntense: true)
            self.startMouseTrackingTimer() 
            
            // 5. Trigger Beam
            let colorName = UserDefaults.standard.string(forKey: "reminderColor") ?? "orange"
            let color = self.colorFromString(colorName)
            
            self.visualEffectOverlay?.orderFront(nil) 
            self.visualEffectOverlay?.startExpandEffect(edge: self.snapEdge, frame: self.window!.frame, color: color)
        }
    }
    
    private func showIndicator(for mainWindow: NSWindow, isIntense: Bool = false) {
        guard let indicator = indicatorWindow, let screen = mainWindow.screen else { return }
        
        // 每次显示时刷新颜色（确保使用最新的用户设置）
        let colorName = UserDefaults.standard.string(forKey: "reminderColor") ?? "orange"
        var color = colorFromString(colorName)
        
        if isIntense {
            // NOTE: We no longer override the base 'color' here.
            // We pass the standard color to the indicator, and it handles 
            // the intensification for the center pulse internally.
        }
        
        indicator.snapEdge = self.snapEdge
        indicator.updateColor(color, isIntense: isIntense)
        
        let screenFrame = screen.visibleFrame
        let mainHeight = mainWindow.frame.height
        let mainY = mainWindow.frame.minY
        
        // 线条尺寸 - Fix: Increase window height significantly (2.0x) to allow for stretch animation
        // "Rectangular clipping" happens when the 1.4x stretch exceeds the window bounds.
        let indicatorWidth: CGFloat = 6
        let contentHeight = mainHeight
        let windowPadding = mainHeight // Extra vertical padding (0.5x on top, 0.5x on bottom)
        let indicatorWindowHeight = contentHeight + windowPadding
        
        var indicatorFrame = NSRect(x: 0, y: mainY - (windowPadding / 2), width: indicatorWidth, height: indicatorWindowHeight)
        
        // Ensure we don't go off-screen vertically if possible, or just let it clip screen bounds 
        // (usually fine for transparent windows, but safer to clamp if needed). 
        // For now, let's trust the padding logic.
        
        switch snapEdge {
        case .left:
            indicatorFrame.origin.x = screenFrame.minX
        case .right:
            indicatorFrame.origin.x = screenFrame.maxX - indicatorWidth
        default: break
        }
        
        indicator.setFrame(indicatorFrame, display: true)
        
        // Update the internal view to be centered within this large window
        if let lineView = indicator.contentView as? SimpleColorView {
            // Layout logic handles centering, but we need to ensure the view knows its "target" size
            // For SimpleColorView, it fills the window. We need to shrink it?
            // Actually, SimpleColorView IS the contentView. If we resize the window, the view resizes.
            // We need a sublayer or a different layout strategy.
            // Strategy: Make SimpleColorView have a `stripLayer` that performs the animation, 
            // instead of animating the whole view's layer.
            // OR: Let SimpleColorView frame be the full window, but draw the strip in the center.
            // Let's go with Strategy B: Update SimpleColorView to manage a `containerLayer` sized correctly.
            
            // Pass the intended strip height to the view so it can center its content
            lineView.updateLayout(fullHeight: indicatorWindowHeight, stripHeight: contentHeight)
        }
        
        indicator.orderFront(nil) // 显示
    }
    
    // MARK: - Mouse Tracking
    
    private func handleMouseEntered() {
        // 停止折叠监测
        stopMouseTrackingTimer()
        
        // 如果是 Dock 唤醒的等候状态，鼠标一旦进入，就视为用户接管，清除标记
        if pendingDockInteraction {
            pendingDockInteraction = false
        }
        
        if state == .collapsed {
            expand()
        }
    }
    
    private func handleMouseExited() {
        if state == .expanded && !hasUserInteraction && !pendingDockInteraction {
            // 启动定时器持续监测鼠标位置
            startMouseTrackingTimer()
        }
    }
    
    private func startMouseTrackingTimer() {
        stopMouseTrackingTimer()
        mouseTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkMousePositionForCollapse()
        }
    }
    
    private func stopMouseTrackingTimer() {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
    }
    
    private func checkMousePositionForCollapse() {
        guard let window = window else { return }
        
        // 如果不再是展开状态，或者是用户正在交互（如打字），则不自动收起
        // 注意：hasUserInteraction 只有在用户点击内容后置为 true。
        // 如果只是想看一眼，没点击，鼠标移走就收起。
        // 新增：如果是 Dock 唤醒的等待状态，也不收起
        if state != .expanded || hasUserInteraction || pendingDockInteraction {
            stopMouseTrackingTimer()
            return
        }
        
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        
        // 给窗口边界增加缓冲区域
        let extendedFrame = windowFrame.insetBy(dx: -collapseBufferDistance, dy: -collapseBufferDistance)
        
        // 如果鼠标在扩展区域外才折叠
        if !extendedFrame.contains(mouseLocation) {
            stopMouseTrackingTimer()
            visualEffectOverlay?.stopExpandEffect() // Stop beam immediately on mouse exit logic
            collapse()
        }
    }
    
    private func checkMouseAndCollapse() {
        guard let window = window else { return }
        
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        
        // 给窗口边界增加缓冲区域，鼠标需要移动到更远的位置才触发折叠
        let extendedFrame = windowFrame.insetBy(dx: -collapseBufferDistance, dy: -collapseBufferDistance)
        
        // 如果鼠标在扩展区域外才折叠
        if !extendedFrame.contains(mouseLocation) && state == .expanded && !hasUserInteraction && !pendingDockInteraction {
            collapse()
        }
    }
    
    // MARK: - Interaction Handling
    
    // 供外部 UI 调用，告知用户正在与窗口交互，防止自动收起
    func notifyUserInteraction() {
        if state == .expanded {
            hasUserInteraction = true
            state = .locked
            // 如果我们已经判定交互了，Dock 的等待标识就不需要了
            pendingDockInteraction = false
        }
    }
    
    private func handleLocalInteraction(_ event: NSEvent) {
        // 用户在窗口内点击或打字，视为锁定状态，不自动收起
        if state == .expanded || state == .locked {
            hasUserInteraction = true
            state = .locked
            // pendingDockInteraction 也就失效了，因为用户已经交互了
            pendingDockInteraction = false
        }
    }
    
    private func handleGlobalClick(_ event: NSEvent) {
        guard let window = window else { return }
        
        let windowFrame = window.frame
        let screenLocation = NSEvent.mouseLocation
        
        // 如果点击在窗口外部
        // 1. 如果处于锁定状态 (locked)，立即收起
        // 2. 如果处于 Dock 唤醒等待状态 (pendingDockInteraction)，用户点别处了，说明不需要了，收起
        let shouldCollapse = (state == .locked) || (state == .expanded && pendingDockInteraction)
        
        if !windowFrame.contains(screenLocation) && shouldCollapse {
             hasUserInteraction = false
             pendingDockInteraction = false
             // 立即收起
             collapse()
        }
    }
    
    // MARK: - Background / Summon Logic
    
    @objc private func handleAppResignedActive(_ notification: Notification) {
        // App goes to background
        
        if state == .floating {
             // Show summon strip at preferred edge
             // But we need to fake a 'snapEdge' for the indicator logic to work, OR pass it explicitly.
             // Let's modify showIndicator to accept an optional edge override.
             // Or sets a temporary var.
             showIndicatorForSummon()
        } else if state == .expanded {
             // Auto collapse if expanded and lost focus
             collapse()
        }
    }
    
    @objc private func handleAppBecameActive(_ notification: Notification) {
        // App comes to foreground
        
        if state == .floating {
            // Hide summon strip
            indicatorWindow?.orderOut(nil)
        }
    }
    
    private func summonWindow() {
        guard let window = window else { return }
        
        // 1. Activate App
        NSApp.activate(ignoringOtherApps: true)
        
        // 2. Bring window to front
        window.makeKeyAndOrderFront(nil)
        
        // 3. Hide indicator
        indicatorWindow?.orderOut(nil)
    }
    
    private func showIndicatorForSummon() {
        guard let window = window else { return }
        // Use preferred edge
        let edge = preferredEdge
        
        // Reuse showIndicator logic but force the edge
        // Note: showIndicator uses self.snapEdge. We need to override or temporarily set it?
        // Better: refactor showIndicator to take an argument, or use a temp trick.
        // Let's create a specific helper to avoid messing with 'snapEdge' state.
        
        guard let indicator = indicatorWindow, let screen = window.screen ?? NSScreen.main else { return }
        
        let colorName = UserDefaults.standard.string(forKey: "reminderColor") ?? "orange"
        indicator.updateColor(colorFromString(colorName))
        
        let screenFrame = screen.visibleFrame
        let mainHeight = window.frame.height
        // If floating, use window's current centerY? Or preferredY?
        // User requested: "persistent vertical position... if never used default center".
        // For now let's use the window's current Y if possible, or center if that feels disconnected?
        // Actually user said: "instructions... keep persisted position".
        // Simplification: Just match window Y for now if floating.
        let mainY = window.frame.minY
        
        let indicatorWidth: CGFloat = 6
        let indicatorHeight = mainHeight
        
        var indicatorFrame = NSRect(x: 0, y: mainY, width: indicatorWidth, height: indicatorHeight)
        
        switch edge {
        case .left:
            indicatorFrame.origin.x = screenFrame.minX
        case .right:
            indicatorFrame.origin.x = screenFrame.maxX - indicatorWidth
        default: break
        }
        
        // Ensure indicator is visible
        indicator.setFrame(indicatorFrame, display: true)
        indicator.orderFront(self)
    }
    
    // MARK: - Reminder Animation
    
    /// Start ripple animation with the specified color (called when a reminder triggers)
    func startRippleAnimation(color: NSColor, isPreview: Bool = false) {
        // If it's a preview, we might need to "fake" the sticker bar if it's not there
        let targetEdge = snapEdge != .none ? snapEdge : .right
        
        if isPreview && state != .collapsed {
            // Preview mode: temp show indicator even if window is open
            showTemporaryIndicator(for: targetEdge, color: color)
            return
        }
        
        guard state == .collapsed, let indicator = indicatorWindow else { return }
        
        // Start breathing animation (Deep Blue Stretch)
        indicator.startBreathing()
        
        // Start ripple overlay (now handles light rays WebGL)
        rippleOverlay?.startRipple(edge: snapEdge, indicatorFrame: indicator.frame, color: color)
    }
    
    private func showTemporaryIndicator(for edge: SnapEdge, color: NSColor) {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let indicatorWidth: CGFloat = 6
        let indicatorHeight: CGFloat = window.frame.height
        let indicatorY = window.frame.minY
        
        var indicatorFrame = NSRect(x: 0, y: indicatorY, width: indicatorWidth, height: indicatorHeight)
        
        switch edge {
        case .left:
            indicatorFrame.origin.x = screenFrame.minX
        case .right:
            indicatorFrame.origin.x = screenFrame.maxX - indicatorWidth
        default: return
        }
        
        // Create a temporary indicator for preview
        let tempIndicator = EdgeIndicatorWindow()
        tempIndicator.setFrame(indicatorFrame, display: true)
        // tempIndicator.updateColor(color) // Don't use passed color, force Deep Blue
        tempIndicator.orderFront(self)
        tempIndicator.startBreathing()
        
        // Start ripple
        rippleOverlay?.startRipple(edge: edge, indicatorFrame: indicatorFrame, color: color)
        
        // Clean up after 8 seconds (extended for better preview)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            tempIndicator.stopBreathing(with: color)
            tempIndicator.orderOut(nil)
            self?.rippleOverlay?.stopRipple()
        }
    }
    
    /// Stop ripple animation (called when user hovers or expands)
    func stopRippleAnimation() {
        rippleOverlay?.stopRipple()
        let colorName = UserDefaults.standard.string(forKey: "reminderColor") ?? "orange"
        let color = colorFromString(colorName)
        indicatorWindow?.stopBreathing(with: color)
    }
    
    /// Check if the window is in collapsed (hidden) state
    var isCollapsed: Bool {
        return state == .collapsed
    }
    
    /// Public API for minimizing (intercepted from AppDelegate)
    func snapToPreferredEdge() {
        snapToEdge(preferredEdge, collapseImmediately: true)
    }
}


// MARK: - Edge Indicator Window
class EdgeIndicatorWindow: NSPanel {
    var onMouseEntered: (() -> Void)?
    private var isShaking = false
    private var shakeAnimation: CAKeyframeAnimation?
    private var beamLayer: CAGradientLayer?
    private var backgroundLayer: CALayer?
    var snapEdge: SnapEdge = .none
    
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        // 创建线条视图
        let lineView = SimpleColorView()
        // Start transparent, will be updated immediately
        lineView.backgroundColor = .clear
        lineView.wantsLayer = true
        
        self.contentView = lineView
        
        // Setup persistent central highlight (Slit)
        setupCentralHighlight()
        
        // 追踪区域
        let trackingArea = NSTrackingArea(
            rect: .zero, // 将在 layout 时更新，或者全覆盖
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        lineView.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }
    
    // MARK: - Breathing Animation (Deep Blue Stretch Pulse)
    
    // MARK: - Breathing Animation (Deep Blue Stretch Pulse)
    
    func startBreathing() {
        guard !isShaking, let contentView = self.contentView, let layer = contentView.layer else { return }
        isShaking = true
        
        // 0. Prepare Root Layer
        // We stop using the view's main background color because we need independent layer control.
        if let lineView = contentView as? SimpleColorView {
            // Store original if needed? Actually we just reset to transparent here.
            lineView.backgroundColor = .clear 
        }
        
        let bounds = layer.bounds
        
        // 1. Create Background Layer (The Blue Bar)
        // This layer will handle the Stretch Animation independently.
        let bg = CALayer()
        bg.frame = bounds
        bg.backgroundColor = NSColor(red: 0.0, green: 0.3, blue: 1.0, alpha: 0.9).cgColor // Deep Klein Blue
        bg.cornerRadius = 3
        
        layer.addSublayer(bg)
        self.backgroundLayer = bg
        
        // 2. Animate Background: Vertical Stretch (Scale Y)
        let stretch = CABasicAnimation(keyPath: "transform.scale.y")
        stretch.fromValue = 1.0
        stretch.toValue = 1.4 // Stretch 40%
        stretch.duration = 0.8
        stretch.autoreverses = true
        stretch.repeatCount = .infinity
        stretch.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        bg.add(stretch, forKey: "breathingStretch")
        
        // 3. Animate Background: Opacity Pulse
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.6
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        bg.add(pulse, forKey: "breathingPulse")
        
        // 4. Add Vertical Beam (White Light Streak)
        // This layer is added to ROOT 'layer', NOT 'bg'. 
        // So it stays static (no stretch) and perfectly centered.
        let beam = CAGradientLayer()
        // Strict Gradient: Only center 30% has visible white.
        beam.colors = [
            NSColor(white: 1, alpha: 0).cgColor,    // 0.0
            NSColor(white: 1, alpha: 0).cgColor,    // 0.35
            NSColor(white: 1, alpha: 1).cgColor,    // 0.50
            NSColor(white: 1, alpha: 0).cgColor,    // 0.65
            NSColor(white: 1, alpha: 0).cgColor     // 1.0
        ]
        beam.locations = [0, 0.35, 0.5, 0.65, 1]
        beam.startPoint = CGPoint(x: 0.5, y: 0)
        beam.endPoint = CGPoint(x: 0.5, y: 1)
        
        let beamWidth: CGFloat = 3.0
        beam.frame = CGRect(x: (bounds.width - beamWidth) / 2, y: 0, width: beamWidth, height: bounds.height)
        beam.compositingFilter = "screenBlendMode"
        
        // Diamond Mask
        let maskShape = CAShapeLayer()
        let path = CGMutablePath()
        let w = beamWidth
        let h = bounds.height
        
        path.move(to: CGPoint(x: w/2, y: 0))
        path.addLine(to: CGPoint(x: w, y: h/2))
        path.addLine(to: CGPoint(x: w/2, y: h))
        path.addLine(to: CGPoint(x: 0, y: h/2))
        path.closeSubpath()
        
        maskShape.path = path
        beam.mask = maskShape
        
        layer.addSublayer(beam)
        self.beamLayer = beam
        
        // Animate Beam Opacity Only (No Jump/Stretch)
        let beamPulse = CABasicAnimation(keyPath: "opacity")
        beamPulse.fromValue = 0.5
        beamPulse.toValue = 1.0
        beamPulse.duration = 0.8
        beamPulse.autoreverses = true
        beamPulse.repeatCount = .infinity
        beamPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        beam.add(beamPulse, forKey: "beamPulse")
    }
    
    func stopBreathing(with color: NSColor) {
        guard isShaking, let contentView = self.contentView else { return }
        isShaking = false
        
        // Remove manual layers
        backgroundLayer?.removeFromSuperlayer()
        backgroundLayer = nil
        
        beamLayer?.removeFromSuperlayer()
        beamLayer = nil
        
        // Restore correct user color
        let lineView = contentView as? SimpleColorView
        lineView?.backgroundColor = color
    }
    
    func animateSquashAndStretch() {
        guard let lineView = self.contentView as? SimpleColorView, 
              let stripLayer = lineView.getStripLayer() else { return }
        
        // 1. Setup Pivot & Shape
        // Since stripLayer is now centered in a larger view, we can animate it directly
        // The anchor point handling depends on how stripLayer is framed.
        // In layout(), we set frame center. Let's ensure anchorPoint is center (default 0.5,0.5).
        
        stripLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        // Position isn't changing, just scale.
        
        // 2. Scale Animation (Elastic Bounce)
        stripLayer.removeAnimation(forKey: "squash")
        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale.y")
        // User Feedback: "Stretch is too exaggerated, 1.1x is enough"
        scaleAnim.values = [1.0, 1.1, 0.96, 1.02, 0.99, 1.0]
        scaleAnim.keyTimes = [0, 0.15, 0.35, 0.55, 0.8, 1.0]
        scaleAnim.duration = 0.6
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        stripLayer.add(scaleAnim, forKey: "squash")
        
        // Ensure central highlight scales with the strip
        // shineLayer is a sublayer of stripLayer, so it inherits the transform automatically!
    }
    
    private func setupCentralHighlight() {
        // No-op: Removed in favor of gradient background
    }
    
    func updateColor(_ color: NSColor, isIntense: Bool = false) {
        if let lineView = self.contentView as? SimpleColorView {
            lineView.updateState(color: color, edge: self.snapEdge, isIntense: isIntense)
        }
    }
    
    // Removed old transient highlight method
}

class SimpleColorView: NSView {
    var backgroundColor: NSColor? {
        didSet { updateLayer() }
    }
    
    // The "Strip" is now a sublayer, not the root layer
    private var stripLayer = CALayer()
    private var shineLayer = CALayer()
    private var isIntense = false
    private var currentColor: NSColor?
    
    // Layout Metrics
    private var stripHeight: CGFloat = 100
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor // Root is transparent padding
        
        // Strip Layer (The actual visible capsule)
        stripLayer.cornerRadius = 3
        stripLayer.masksToBounds = true
        layer?.addSublayer(stripLayer)
        
        // Shine Layer (Inside the strip)
        shineLayer.backgroundColor = NSColor.white.cgColor
        shineLayer.opacity = 0
        
        let linearMask = CAGradientLayer()
        linearMask.type = .axial // Linear gradient covers full width horizontally
        linearMask.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.8).cgColor,
            NSColor.white.withAlphaComponent(0.8).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        linearMask.locations = [0.0, 0.4, 0.6, 1.0]
        linearMask.startPoint = CGPoint(x: 0.5, y: 0.0)
        linearMask.endPoint = CGPoint(x: 0.5, y: 1.0)
        
        shineLayer.mask = linearMask
        stripLayer.addSublayer(shineLayer)
    }
    
    func updateLayout(fullHeight: CGFloat, stripHeight: CGFloat) {
        self.stripHeight = stripHeight
        self.needsLayout = true
    }
    
    func getStripLayer() -> CALayer? {
        return stripLayer
    }
    
    func updateState(color: NSColor, edge: SnapEdge, isIntense: Bool) {
        self.backgroundColor = color
        self.isIntense = isIntense
        updateLayer()
    }
    
    override func layout() {
        super.layout()
        
        // Center the strip vertically within the padded view
        let yPos = (bounds.height - stripHeight) / 2
        
        // Important: Disable implicit animations for frame updates
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stripLayer.frame = CGRect(x: 0, y: yPos, width: bounds.width, height: stripHeight)
        stripLayer.cornerRadius = bounds.width / 2
        
        shineLayer.frame = stripLayer.bounds
        shineLayer.mask?.frame = shineLayer.bounds
        CATransaction.commit()
    }
    
    override func updateLayer() {
        guard let _ = layer, let color = backgroundColor else { return }
        
        if isIntense {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            
            // "Neon" algorithm: Max brightness (1.0) and high saturation (0.9)
            // This prevents the "blackened" look and ensures it looks like a light source.
            let intenseColor = NSColor(hue: h, saturation: 0.9, brightness: 1.0, alpha: 1.0)
            
            stripLayer.backgroundColor = color.cgColor // Standard color for the ends
            shineLayer.backgroundColor = intenseColor.cgColor // Vibrant neon for the center
            shineLayer.opacity = 1.0
            
            if let mask = shineLayer.mask as? CAGradientLayer {
                // Pulse the neon color in the center section
                mask.colors = [
                    NSColor.white.withAlphaComponent(0.0).cgColor,
                    NSColor.white.withAlphaComponent(1.0).cgColor,
                    NSColor.white.withAlphaComponent(1.0).cgColor,
                    NSColor.white.withAlphaComponent(0.0).cgColor 
                ]
                mask.locations = [0.0, 0.4, 0.6, 1.0]
            }
        } else {
            stripLayer.backgroundColor = color.cgColor
            shineLayer.opacity = 0.0
        }
    }
    
    override var wantsUpdateLayer: Bool {
        return true
    }
}
