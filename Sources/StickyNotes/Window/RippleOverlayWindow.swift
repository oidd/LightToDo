import AppKit
import SwiftUI

/// Full-screen transparent window for wave/ripple animation
class RippleOverlayWindow: NSPanel {
    private var rippleLayer: CALayer?
    private var rippleLayers: [CAShapeLayer] = []
    private var animationTimer: Timer?
    private var isAnimating = false
    
    private var edgePosition: SnapEdge = .left
    private var indicatorFrame: NSRect = .zero
    private var rippleColor: NSColor = NSColor.orange
    
    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .screenSaver // Above most windows
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true // Click-through
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        
        // Setup content view with layer
        let hostView = NSView(frame: self.frame)
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = hostView
    }
    
    // MARK: - Public API
    
    /// Start ripple animation from the edge indicator
    func startRipple(edge: SnapEdge, indicatorFrame: NSRect, color: NSColor) {
        guard !isAnimating else { return }
        
        self.edgePosition = edge
        self.indicatorFrame = indicatorFrame
        self.rippleColor = color
        self.isAnimating = true
        
        // Update frame to cover the screen
        if let screen = NSScreen.main {
            self.setFrame(screen.frame, display: true)
        }
        
        self.orderFront(nil)
        
        // Start generating ripples with organic timing
        startRippleGeneration()
    }
    
    /// Stop generating new ripples (existing ones will complete naturally)
    func stopRipple() {
        animationTimer?.invalidate()
        animationTimer = nil
        isAnimating = false
        
        // Let existing ripples fade out naturally, then close window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.isAnimating == false && self?.rippleLayers.isEmpty == true {
                self?.orderOut(nil)
            }
        }
    }
    
    // MARK: - Animation
    
    private func startRippleGeneration() {
        // Generate ripples at variable intervals (0.8-1.5s) for organic feel
        scheduleNextRipple()
    }
    
    private func scheduleNextRipple() {
        guard isAnimating else { return }
        
        // Random interval between 0.6 and 1.2 seconds
        let interval = Double.random(in: 0.6...1.2)
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.generateSingleRipple()
            self?.scheduleNextRipple()
        }
    }
    
    private func generateSingleRipple() {
        guard let contentView = self.contentView, let layer = contentView.layer else { return }
        
        let rippleLayer = CAShapeLayer()
        
        // Calculate ripple origin based on edge
        let originX: CGFloat
        let originY = indicatorFrame.midY
        
        switch edgePosition {
        case .left:
            originX = indicatorFrame.maxX
        case .right:
            originX = indicatorFrame.minX
        default:
            return
        }
        
        // Create arc path (semi-circle expanding from edge)
        let startRadius: CGFloat = 5
        let startAngle: CGFloat
        let endAngle: CGFloat
        
        if edgePosition == .left {
            // Expand to the right
            startAngle = -.pi / 2
            endAngle = .pi / 2
        } else {
            // Expand to the left
            startAngle = .pi / 2
            endAngle = 3 * .pi / 2
        }
        
        let startPath = NSBezierPath()
        startPath.appendArc(
            withCenter: NSPoint(x: originX, y: originY),
            radius: startRadius,
            startAngle: startAngle * 180 / .pi,
            endAngle: endAngle * 180 / .pi
        )
        
        rippleLayer.path = startPath.cgPath
        rippleLayer.strokeColor = rippleColor.withAlphaComponent(0.6).cgColor
        rippleLayer.fillColor = nil
        rippleLayer.lineWidth = 3
        rippleLayer.lineCap = .round
        
        layer.addSublayer(rippleLayer)
        rippleLayers.append(rippleLayer)
        
        // Animate expansion with slight randomness
        let maxRadius: CGFloat = CGFloat.random(in: 1500...2500)
        let duration: CFTimeInterval = Double.random(in: 4.0...6.0)
        
        // Create end path
        let endPath = NSBezierPath()
        endPath.appendArc(
            withCenter: NSPoint(x: originX, y: originY),
            radius: maxRadius,
            startAngle: startAngle * 180 / .pi,
            endAngle: endAngle * 180 / .pi
        )
        
        // Path animation
        let pathAnimation = CABasicAnimation(keyPath: "path")
        pathAnimation.fromValue = startPath.cgPath
        pathAnimation.toValue = endPath.cgPath
        pathAnimation.duration = duration
        pathAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        // Opacity animation (fade as it expands)
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.8
        opacityAnimation.toValue = 0.0
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        
        // Line width animation (thinner as it expands)
        let lineWidthAnimation = CABasicAnimation(keyPath: "lineWidth")
        lineWidthAnimation.fromValue = 4
        lineWidthAnimation.toValue = 1
        lineWidthAnimation.duration = duration
        
        // Group animations
        let group = CAAnimationGroup()
        group.animations = [pathAnimation, opacityAnimation, lineWidthAnimation]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak rippleLayer] in
            rippleLayer?.removeFromSuperlayer()
            if let layer = rippleLayer {
                self?.rippleLayers.removeAll { $0 === layer }
            }
            // Check if we should close the window
            if self?.isAnimating == false && self?.rippleLayers.isEmpty == true {
                self?.orderOut(nil)
            }
        }
        
        rippleLayer.add(group, forKey: "rippleExpand")
        
        CATransaction.commit()
    }
}

// MARK: - NSBezierPath Extension

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0..<self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        
        return path
    }
}
