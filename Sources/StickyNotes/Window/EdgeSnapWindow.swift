import AppKit
import SwiftUI

class EdgeSnapWindowController: NSObject {
    weak var window: NSWindow?
    private var indicatorWindow: EdgeIndicatorWindow?
    
    // 配置

    
    // 状态
    private(set) var state: WindowState = .floating
    private(set) var snapEdge: SnapEdge = .none
    private var hasUserInteraction = false
    private var pendingDockInteraction = false
    private var originalFrame: NSRect = .zero
    private var isDragging = false
    private var isProgrammaticMove = false // 新增：防止代码移动窗口时触发拖拽逻辑
    
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
            selector: #selector(windowWillMove),
            name: NSWindow.willMoveNotification,
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
    }
    
    private func createIndicatorWindow() {
        let indicator = EdgeIndicatorWindow()
        indicator.onMouseEntered = { [weak self] in
            // 鼠标碰到线条，立即展开
            self?.expand()
        }
        self.indicatorWindow = indicator
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
             stopMouseTrackingTimer() // 停止之前的折叠检测
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
            snapToEdge(.left)
            return
        }
        
        // 检测右边缘
        if windowFrame.maxX >= screenFrame.maxX - edgeThreshold {
            snapToEdge(.right)
            return
        }
    }
    
    // MARK: - Edge Snapping Lifecycle
    
    private func snapToEdge(_ edge: SnapEdge) {
        guard let window = window else { return }
        // 注意：这里使用 NSScreen.main 确保尽可能在这个屏幕吸附。实际逻辑可根据 window.screen
        guard let screen = window.screen ?? NSScreen.main else { return }
        
        snapEdge = edge
        originalFrame = window.frame
        
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
        
        // 2. 隐藏指示线条
        indicatorWindow?.orderOut(nil)
        
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
            self.hasUserInteraction = false
            
            // 4. 展开后，如果不操作，鼠标离开要自动缩回
            self.startMouseTrackingTimer()
        }
    }
    
    private func showIndicator(for mainWindow: NSWindow) {
        guard let indicator = indicatorWindow, let screen = mainWindow.screen else { return }
        
        let screenFrame = screen.visibleFrame
        let mainHeight = mainWindow.frame.height
        let mainY = mainWindow.frame.minY
        
        // 线条尺寸
        let indicatorWidth: CGFloat = 6
        let indicatorHeight = mainHeight
        
        var indicatorFrame = NSRect(x: 0, y: mainY, width: indicatorWidth, height: indicatorHeight)
        
        switch snapEdge {
        case .left:
            indicatorFrame.origin.x = screenFrame.minX
        case .right:
            indicatorFrame.origin.x = screenFrame.maxX - indicatorWidth
        default: break
        }
        
        indicator.setFrame(indicatorFrame, display: true)
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
}


// MARK: - Edge Indicator Window
class EdgeIndicatorWindow: NSPanel {
    var onMouseEntered: (() -> Void)?
    
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        // 创建线条视图
        let lineView = SimpleColorView()
        lineView.backgroundColor = NSColor.orange.withAlphaComponent(0.4)
        lineView.wantsLayer = true
        lineView.layer?.cornerRadius = 3
        
        self.contentView = lineView
        
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
}

class SimpleColorView: NSView {
    var backgroundColor: NSColor? {
        didSet { needsDisplay = true }
    }
    
    override func updateLayer() {
        layer?.backgroundColor = backgroundColor?.cgColor
    }
    
    override var wantsUpdateLayer: Bool {
        return true
    }
}
