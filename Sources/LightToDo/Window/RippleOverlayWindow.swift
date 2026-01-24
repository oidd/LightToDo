import AppKit
import SwiftUI

/// Full-screen transparent window for breathing glow with dome effect and expanding rings
class RippleOverlayWindow: NSPanel {
    private var baseGlowLayer: CAGradientLayer?
    private var coreLayer: CAGradientLayer?
    
    private var cycleTimer: Timer?
    private var ringTimer: Timer?
    private var isAnimating = false
    private var currentEdge: SnapEdge = .right
    
    // Settings
    private let coreRadius: CGFloat = 65
    private let baseGlowRadius: CGFloat = 130
    
    private var indicatorFrame: NSRect = .zero

    private var screenWidth: CGFloat { self.frame.width }
    private var screenHeight: CGFloat { self.frame.height }
    private var centerY: CGFloat {
        // If indicatorFrame is set (non-zero height), use its center. Otherwise default to screen center.
        if indicatorFrame.height > 0 {
            // Adjust for screen origin if needed, but usually main screen starts at 0.
            // Assuming window covers the screen exactly.
            return indicatorFrame.midY
        }
        return screenHeight / 2
    }
    
    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        
        setupContentView()
    }
    
    private func setupContentView() {
        let hostView = NSView(frame: self.frame)
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.clear.cgColor
        self.contentView = hostView
    }
    
    // MARK: - Public API
    
    func startRipple(edge: SnapEdge, indicatorFrame: NSRect, color: NSColor) {
        guard !isAnimating else { return }
        
        self.currentEdge = edge
        self.indicatorFrame = indicatorFrame
        self.isAnimating = true
        
        if let screen = NSScreen.main {
            self.setFrame(screen.frame, display: true)
        }
        
        self.alphaValue = 1.0
        self.makeKeyAndOrderFront(nil)
        
        // 1. Create Persistent Layers (Base Glow + Core)
        createBaseGlow()
        createCore()
        
        // 2. Start Expanding Ring Cycle
        performWaveCycle()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard self?.isAnimating == true else { return }
            self?.performWaveCycle()
        }
        
        // 3. Start Comet Tail Rings
        ringTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard self?.isAnimating == true else { return }
            if Double.random(in: 0...1) > 0.3 {
                self?.generateBrightRing(speedMultiplier: 1.0)
                if Double.random(in: 0...1) > 0.5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.generateBrightRing(speedMultiplier: 1.4)
                    }
                }
            }
        }
    }
    
    func stopRipple() {
        isAnimating = false
        cycleTimer?.invalidate()
        cycleTimer = nil
        ringTimer?.invalidate()
        ringTimer = nil
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            self?.baseGlowLayer = nil
            self?.coreLayer = nil
            self?.orderOut(nil)
            self?.alphaValue = 1.0
        })
    }
    
    // MARK: - Persistent Base Glow (More Transparent Deep Blue)
    
    private func createBaseGlow() {
        guard let contentView = self.contentView, let parentLayer = contentView.layer else { return }
        
        let layerSize = baseGlowRadius * 2
        
        let glow = CAGradientLayer()
        glow.type = .radial
        // Deep Klein Blue backing - REDUCED ALPHA
        glow.colors = [
            NSColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 0.25).cgColor, // drastically reduced from 0.6
            NSColor(red: 0.05, green: 0.1, blue: 0.7, alpha: 0.15).cgColor, // drastically reduced from 0.4
            NSColor(red: 0.0, green: 0.05, blue: 0.6, alpha: 0.0).cgColor
        ]
        glow.locations = [0, 0.5, 1]
        
        let originX: CGFloat = currentEdge == .right ? screenWidth - baseGlowRadius : -baseGlowRadius
        glow.frame = CGRect(x: originX, y: centerY - baseGlowRadius, width: layerSize, height: layerSize)
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1.0, y: 1.0)
        glow.cornerRadius = baseGlowRadius
        glow.opacity = 0
        
        let maskLayer = CAShapeLayer()
        let maskRect: CGRect = currentEdge == .right
            ? CGRect(x: 0, y: 0, width: baseGlowRadius, height: layerSize)
            : CGRect(x: baseGlowRadius, y: 0, width: baseGlowRadius, height: layerSize)
        maskLayer.path = CGPath(rect: maskRect, transform: nil)
        glow.mask = maskLayer
        
        // Insert very back
        parentLayer.insertSublayer(glow, at: 0)
        self.baseGlowLayer = glow
        
        // Appear and stay
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1.0
        fadeIn.duration = 1.0
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        glow.add(fadeIn, forKey: "baseIn")
        
        // Gentle pulse for base
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.7
        pulse.duration = 3.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(pulse, forKey: "basePulse")
    }
    
    // MARK: - Persistent Core (Softer Blue Tint)
    
    private func createCore() {
        guard let contentView = self.contentView, let parentLayer = contentView.layer else { return }
        
        let layerSize = coreRadius * 2
        
        let core = CAGradientLayer()
        core.type = .radial
        core.colors = [
            NSColor.white.cgColor,
            NSColor(red: 0.6, green: 0.7, blue: 1.0, alpha: 0.6).cgColor, // Reduced from 0.9
            NSColor(red: 0.2, green: 0.3, blue: 0.95, alpha: 0.3).cgColor, // Reduced from 0.6
            NSColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 0.0).cgColor
        ]
        core.locations = [0, 0.2, 0.5, 1]
        
        let originX: CGFloat = currentEdge == .right ? screenWidth - coreRadius : -coreRadius
        core.frame = CGRect(x: originX, y: centerY - coreRadius, width: layerSize, height: layerSize)
        core.startPoint = CGPoint(x: 0.5, y: 0.5)
        core.endPoint = CGPoint(x: 1.0, y: 1.0)
        core.cornerRadius = coreRadius
        core.opacity = 0
        
        let maskLayer = CAShapeLayer()
        let maskRect: CGRect = currentEdge == .right
            ? CGRect(x: 0, y: 0, width: coreRadius * 0.9, height: layerSize)
            : CGRect(x: coreRadius * 1.1, y: 0, width: coreRadius * 0.9, height: layerSize)
        maskLayer.path = CGPath(rect: maskRect, transform: nil)
        core.mask = maskLayer
        
        parentLayer.addSublayer(core)
        self.coreLayer = core
        
        // Fade In
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1.0
        fadeIn.duration = 1.0
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        core.add(fadeIn, forKey: "coreIn")
        
        // Continuous Breathing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, let c = self.coreLayer else { return }
            
            let opAnim = CABasicAnimation(keyPath: "opacity")
            opAnim.fromValue = 1.0
            opAnim.toValue = 0.5
            opAnim.duration = 1.5
            opAnim.autoreverses = true
            opAnim.repeatCount = .infinity
            opAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            c.add(opAnim, forKey: "breatheOp")
            
            let scAnim = CABasicAnimation(keyPath: "transform.scale")
            scAnim.fromValue = 1.0
            scAnim.toValue = 1.2
            scAnim.duration = 1.5
            scAnim.autoreverses = true
            scAnim.repeatCount = .infinity
            scAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            c.add(scAnim, forKey: "breatheSc")
        }
    }
    
    // MARK: - Thick Hollow Ring Wave (More Transparent)
    
    private func performWaveCycle() {
        guard let contentView = self.contentView, let parentLayer = contentView.layer else { return }
        
        let startRadius: CGFloat = 80
        let layerSize = startRadius * 2
        
        let wave = CAGradientLayer()
        wave.type = .radial
        
        // Deep Klein Blue Hollow Ring - REDUCED ALPHA
        wave.colors = [
            NSColor(red: 0.0, green: 0.1, blue: 0.6, alpha: 0.0).cgColor,
            NSColor(red: 0.0, green: 0.2, blue: 0.8, alpha: 0.05).cgColor, // Very faint inner
            NSColor(red: 0.05, green: 0.3, blue: 1.0, alpha: 0.4).cgColor, // Peak reduced from 0.9 to 0.4
            NSColor(red: 0.1, green: 0.4, blue: 1.0, alpha: 0.0).cgColor
        ]
        wave.locations = [0.0, 0.4, 0.9, 1.0]
        
        let originX: CGFloat = currentEdge == .right ? screenWidth - startRadius : -startRadius
        wave.frame = CGRect(x: originX, y: centerY - startRadius, width: layerSize, height: layerSize)
        wave.cornerRadius = startRadius
        wave.startPoint = CGPoint(x: 0.5, y: 0.5)
        wave.endPoint = CGPoint(x: 1.0, y: 1.0)
        wave.opacity = 0
        
        let maskLayer = CAShapeLayer()
        let maskRect: CGRect = currentEdge == .right
            ? CGRect(x: 0, y: 0, width: startRadius, height: layerSize)
            : CGRect(x: startRadius, y: 0, width: startRadius, height: layerSize)
        maskLayer.path = CGPath(rect: maskRect, transform: nil)
        wave.mask = maskLayer
        
        // Insert behind core
        if let base = baseGlowLayer {
            parentLayer.insertSublayer(wave, above: base)
        } else {
            parentLayer.insertSublayer(wave, at: 0)
        }
        
        let duration: CFTimeInterval = 4.0
        let endRadius: CGFloat = 550
        let endSize = endRadius * 2
        let endOriginX: CGFloat = currentEdge == .right ? screenWidth - endRadius : -endRadius
        
        let endMaskRect: CGRect = currentEdge == .right
            ? CGRect(x: 0, y: 0, width: endRadius, height: endSize)
            : CGRect(x: endRadius, y: 0, width: endRadius, height: endSize)
        
        // Animation
        let boundsAnim = CABasicAnimation(keyPath: "bounds")
        boundsAnim.toValue = CGRect(x: 0, y: 0, width: endSize, height: endSize)
        
        let posAnim = CABasicAnimation(keyPath: "position")
        posAnim.toValue = CGPoint(x: endOriginX + endRadius, y: centerY)
        
        let cornerAnim = CABasicAnimation(keyPath: "cornerRadius")
        cornerAnim.toValue = endRadius
        
        // Opacity
        let fadeAnim = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnim.values = [0.0, 1.0, 0.7, 0.0]
        fadeAnim.keyTimes = [0, 0.1, 0.6, 1.0]
        
        let group = CAAnimationGroup()
        group.animations = [boundsAnim, posAnim, cornerAnim, fadeAnim]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        
        if let mask = wave.mask as? CAShapeLayer {
            let maskAnim = CABasicAnimation(keyPath: "path")
            maskAnim.toValue = CGPath(rect: endMaskRect, transform: nil)
            maskAnim.duration = duration
            maskAnim.fillMode = .forwards
            maskAnim.isRemovedOnCompletion = false
            mask.add(maskAnim, forKey: "mexpand")
        }
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak wave] in
            wave?.removeFromSuperlayer()
        }
        wave.add(group, forKey: "wexpand")
        CATransaction.commit()
    }
    
    // MARK: - Comet Tail Ring (Bright but clean)
    
    private func generateBrightRing(speedMultiplier: Double) {
        guard let contentView = self.contentView, let parentLayer = contentView.layer else { return }
        
        let initialRadius: CGFloat = 50
        let layerSize = initialRadius * 2
        
        let ring = CALayer()
        let originX: CGFloat = currentEdge == .right ? screenWidth - initialRadius : -initialRadius
        ring.frame = CGRect(x: originX, y: centerY - initialRadius, width: layerSize, height: layerSize)
        ring.cornerRadius = initialRadius
        
        ring.borderWidth = 1.8
        // Deep blue but slightly softer alpha
        ring.borderColor = NSColor(red: 0.6, green: 0.7, blue: 1.0, alpha: 0.9).cgColor
        ring.backgroundColor = NSColor.clear.cgColor
        ring.shadowColor = NSColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 0.9).cgColor
        ring.shadowRadius = 8
        ring.shadowOpacity = 1.0
        ring.opacity = 0
        
        let maskLayer = CAShapeLayer()
        let maskRect: CGRect = currentEdge == .right
            ? CGRect(x: 0, y: 0, width: initialRadius, height: layerSize)
            : CGRect(x: initialRadius, y: 0, width: initialRadius, height: layerSize)
        maskLayer.path = CGPath(rect: maskRect, transform: nil)
        ring.mask = maskLayer
        
        if let core = coreLayer {
            parentLayer.insertSublayer(ring, below: core)
        } else {
            parentLayer.addSublayer(ring)
        }
        
        let duration: CFTimeInterval = 2.4 / speedMultiplier
        let endRadius: CGFloat = 380
        let endSize = endRadius * 2
        let endOriginX: CGFloat = currentEdge == .right ? screenWidth - endRadius : -endRadius
        let endMaskRect: CGRect = currentEdge == .right
            ? CGRect(x: 0, y: 0, width: endRadius, height: endSize)
            : CGRect(x: endRadius, y: 0, width: endRadius, height: endSize)
        
        let boundsAnim = CABasicAnimation(keyPath: "bounds")
        boundsAnim.toValue = CGRect(x: 0, y: 0, width: endSize, height: endSize)
        
        let posAnim = CABasicAnimation(keyPath: "position")
        posAnim.toValue = CGPoint(x: endOriginX + endRadius, y: centerY)
        
        let cornerAnim = CABasicAnimation(keyPath: "cornerRadius")
        cornerAnim.toValue = endRadius
        
        let borderAnim = CABasicAnimation(keyPath: "borderWidth")
        borderAnim.toValue = 0.5
        
        let fadeAnim = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnim.values = [0.0, 1.0, 1.0, 0.0]
        fadeAnim.keyTimes = [0, 0.1, 0.6, 1.0]
        
        let group = CAAnimationGroup()
        group.animations = [boundsAnim, posAnim, cornerAnim, borderAnim, fadeAnim]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        
        if let mask = ring.mask as? CAShapeLayer {
            let maskAnim = CABasicAnimation(keyPath: "path")
            maskAnim.toValue = CGPath(rect: endMaskRect, transform: nil)
            maskAnim.duration = duration
            maskAnim.fillMode = .forwards
            maskAnim.isRemovedOnCompletion = false
            mask.add(maskAnim, forKey: "rmexpand")
        }
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak ring] in
            ring?.removeFromSuperlayer()
        }
        ring.add(group, forKey: "rexpand")
        CATransaction.commit()
    }
}
