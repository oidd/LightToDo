import AppKit
import SwiftUI

class EdgeSnapWindowController: NSObject {
    weak var window: NSWindow?
    private var trackingView: MouseTrackingView?
    
    // 配置
    private let edgeThreshold: CGFloat = 30        // 靠近边缘触发吸附的距离
    private let tabWidth: CGFloat = 40             // 可见标签宽度
    private let animationDuration: TimeInterval = 0.25
    private let collapseBufferDistance: CGFloat = 80  // 鼠标离开窗口后需要移动的距离才折叠
    
    // 状态
    private var state: WindowState = .floating
    private var snapEdge: SnapEdge = .none
    private var hasUserInteraction = false
    private var originalFrame: NSRect = .zero
    private var isDragging = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var mouseTrackingTimer: Timer?
    
    init(window: NSWindow) {
        self.window = window
        super.init()
        
        setupWindow()
        setupMouseTracking()
    }
    
    deinit {
        removeMouseMonitors()
        mouseTrackingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        // 配置窗口样式
        window.level = .floating
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
            selector: #selector(windowWillStartDragging),
            name: NSWindow.willMoveNotification,
            object: window
        )
    }
    
    private func setupMouseTracking() {
        guard let window = window, let contentView = window.contentView else { return }
        
        // 创建透明的鼠标追踪视图
        let trackingView = MouseTrackingView(frame: contentView.bounds)
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onMouseEntered = { [weak self] in
            self?.handleMouseEntered()
        }
        trackingView.onMouseExited = { [weak self] in
            self?.handleMouseExited()
        }
        contentView.addSubview(trackingView, positioned: .above, relativeTo: nil)
        self.trackingView = trackingView
        
        // 全局鼠标监听（用于检测点击窗口外部）
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleGlobalClick(event)
        }
        
        // 本地鼠标监听（用于检测窗口内操作）
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.handleLocalInteraction(event)
            return event
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
    
    // MARK: - Window Movement
    
    @objc private func windowWillStartDragging(_ notification: Notification) {
        isDragging = true
        
        // 如果从边缘拖动，解除吸附状态
        if state != .floating {
            state = .floating
            snapEdge = .none
            hasUserInteraction = false
        }
    }
    
    @objc private func windowDidMove(_ notification: Notification) {
        guard window != nil else { return }
        
        // 延迟检测，等拖动结束
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            // 检查是否还在拖动
            if NSEvent.pressedMouseButtons == 0 {
                self.isDragging = false
                self.checkEdgeSnap()
            }
        }
    }
    
    private func checkEdgeSnap() {
        guard let window = window, state == .floating else { return }
        // 使用主屏幕，因为窗口可能已经超出当前屏幕
        guard let screen = NSScreen.main else { return }
        
        let windowFrame = window.frame
        let screenFrame = screen.visibleFrame
        
        // 检测左边缘 - 窗口左边缘接近或超出屏幕左边缘
        // 条件：窗口左边缘 <= 屏幕左边缘 + 阈值（包括超出屏幕的情况）
        if windowFrame.minX <= screenFrame.minX + edgeThreshold {
            snapToEdge(.left)
            return
        }
        
        // 检测右边缘 - 窗口右边缘接近或超出屏幕右边缘
        // 条件：窗口右边缘 >= 屏幕右边缘 - 阈值（包括超出屏幕的情况）
        if windowFrame.maxX >= screenFrame.maxX - edgeThreshold {
            snapToEdge(.right)
            return
        }
    }
    
    // MARK: - Edge Snapping
    
    private func snapToEdge(_ edge: SnapEdge) {
        guard let window = window else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        snapEdge = edge
        originalFrame = window.frame
        
        let screenFrame = screen.visibleFrame
        var newFrame = window.frame
        
        // 对齐到边缘
        switch edge {
        case .left:
            newFrame.origin.x = screenFrame.minX
        case .right:
            newFrame.origin.x = screenFrame.maxX - newFrame.width
        case .none:
            return
        }
        
        // 动画移动到边缘
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            self?.state = .snapped
            // 吸附后立即收起
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.collapse()
            }
        }
    }
    
    private func collapse() {
        guard let window = window, snapEdge != .none else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        var newFrame = window.frame
        
        switch snapEdge {
        case .left:
            newFrame.origin.x = screenFrame.minX - newFrame.width + tabWidth
        case .right:
            newFrame.origin.x = screenFrame.maxX - tabWidth
        case .none:
            return
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            self?.state = .collapsed
        }
    }
    
    private func expand() {
        guard let window = window, state == .collapsed else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        var newFrame = window.frame
        
        switch snapEdge {
        case .left:
            newFrame.origin.x = screenFrame.minX
        case .right:
            newFrame.origin.x = screenFrame.maxX - newFrame.width
        case .none:
            return
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            self?.state = .expanded
            self?.hasUserInteraction = false
        }
    }
    
    // MARK: - Mouse Tracking
    
    private func handleMouseEntered() {
        // 停止折叠监测
        stopMouseTrackingTimer()
        
        if state == .collapsed {
            expand()
        }
    }
    
    private func handleMouseExited() {
        if state == .expanded && !hasUserInteraction {
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
        
        // 如果状态改变，停止监测
        if state != .expanded || hasUserInteraction {
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
        if !extendedFrame.contains(mouseLocation) && state == .expanded && !hasUserInteraction {
            collapse()
        }
    }
    
    private func handleLocalInteraction(_ event: NSEvent) {
        // 记录用户在窗口内的操作
        if state == .expanded || state == .locked {
            hasUserInteraction = true
            state = .locked
        }
    }
    
    private func handleGlobalClick(_ event: NSEvent) {
        guard let window = window else { return }
        
        let windowFrame = window.frame
        let screenLocation = NSEvent.mouseLocation
        
        // 如果点击在窗口外部且处于锁定状态
        if !windowFrame.contains(screenLocation) && state == .locked {
            hasUserInteraction = false
            collapse()
        }
    }
}

// MARK: - Mouse Tracking View

class MouseTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }
    
    private func setupTrackingArea() {
        // 透明，不影响点击
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }
        
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }
    
    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }
    
    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
    
    // 让点击事件穿透到下面的视图
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
