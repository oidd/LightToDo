import AppKit
import QuartzCore

class VisualEffectOverlayWindow: NSPanel {
    private var particleLayer: CAEmitterLayer?
    private var beamLayer: CALayer?
    private var beamMaskLayer: CAShapeLayer?
    private var dustLayer: CALayer?
    private var cleanupWorkItem: DispatchWorkItem?
    
    func logDebug(_ msg: String) {
        let str = "Effects: \(Date()): \(msg)\n"
        if let data = str.data(using: .utf8) {
             let url = URL(fileURLWithPath: "/Users/ivean/Documents/软件安装/我的扩展/轻待办/LightToDo/debug.log")
             if let handle = try? FileHandle(forWritingTo: url) {
                 handle.seekToEndOfFile()
                 handle.write(data)
                 handle.closeFile()
             } else {
                 try? data.write(to: url)
             }
        }
    }
    
    init() {
        // Start as a zero-size window but we will expand it to screen size when needed.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        // Ensure no shadow or background artifacts
        self.backgroundColor = NSColor.clear
        self.isReleasedWhenClosed = false
        
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true
        
        let contentView = NSView()
        contentView.wantsLayer = true
        self.contentView = contentView
    }
    
    // MARK: - Collapse Effect (Impact)
    
    func startCollapseEffect(edge: SnapEdge, point: CGPoint, color: NSColor) {
        // Ensure we clean up any expansion effects (beam/dust) AND schedule the window to close
        // eventually (after the dust fade time, which covers the explosion time too).
        stopExpandEffect(closeWindow: true)
        
        guard let layer = self.contentView?.layer else { return }
        
        // 1. Configure High-Intensity Color
        let intenseColor = intensifyColor(color)
        
        // 2. Create Explosion Emitter
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: 10, height: 40) // Vertical strip impact
        emitter.renderMode = .additive
        
        let cell = CAEmitterCell()
        cell.birthRate = 0 // Manual burst
        cell.lifetime = 1.5
        cell.velocity = 150
        cell.velocityRange = 50
        cell.emissionLongitude = (edge == .left) ? 0 : .pi // Shoot inward
        cell.emissionRange = .pi / 4
        cell.yAcceleration = 400 // Gravity
        cell.scale = 0.5
        cell.scaleRange = 0.2
        cell.scaleSpeed = -0.2
        cell.color = intenseColor.cgColor
        cell.alphaSpeed = -1.0
        
        // Create circular particle image
        cell.contents = createParticleImage()
        
        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
        
        // 3. Trigger Burst
        let burst = CABasicAnimation(keyPath: "emitterCells.0.birthRate")
        burst.fromValue = 100
        burst.toValue = 0
        burst.duration = 0.1
        burst.isRemovedOnCompletion = false
        burst.fillMode = .forwards
        
        emitter.add(burst, forKey: "burst")
        
        // 4. Cleanup (User Feedback: "Disappearing lag is a problem")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            emitter.removeFromSuperlayer()
        }
    }
    
    // MARK: - Expand Effect (Beam & Dust)
    
    func startExpandEffect(edge: SnapEdge, frame: NSRect, color: NSColor) {
        logDebug("startExpandEffect called")
        // Cancel any pending cleanup to prevent race conditions
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        
        guard let layer = self.contentView?.layer, let screen = NSScreen.main else { return }
        stopExpandEffect(closeWindow: false)
        
        // 1. Full Screen Setup (Eliminates coordinate math confusion)
        let screenFrame = screen.frame
        self.setFrame(screenFrame, display: true)
        
        // Convert the target window's frame (in screen coords) to our layer's coordinates
        // Since we are full screen, screen coordinates == local coordinates (mostly, watch for Cocoa Y-up)
        // Actually AppKit screens are Y-up. Layers are Y-up by default in AppKit views.
        let localTargetFrame = NSRect(x: frame.origin.x - screenFrame.origin.x,
                                     y: frame.origin.y - screenFrame.origin.y,
                                     width: frame.size.width,
                                     height: frame.size.height)
        
        let intenseColor = intensifyColor(color)
        
        // 2. Create God-Ray Beam (Refined Masked Gradient)
        // User Feedback: "Height should match strip at edge", "Flare should be soft"
        
        let beamContent = CAGradientLayer()
        beamContent.colors = [
            NSColor.white.withAlphaComponent(0.12).cgColor, // Softened from 0.18 for less "foggy" look
            NSColor.white.withAlphaComponent(0.05).cgColor, // Softened from 0.08
            NSColor.white.withAlphaComponent(0.00).cgColor  
        ]
        beamContent.locations = [0.0, 0.4, 1.0]
        
        // Geometry
        let beamLength: CGFloat = 100 
        let flareAmt: CGFloat = 60 // The "V" spread amount
        
        var beamRect: CGRect
        if edge == .left {
            beamRect = CGRect(x: localTargetFrame.minX, y: localTargetFrame.minY - flareAmt, width: beamLength, height: localTargetFrame.height + flareAmt * 2)
            beamContent.startPoint = CGPoint(x: 0, y: 0.5)
            beamContent.endPoint = CGPoint(x: 1, y: 0.5)
        } else {
            beamRect = CGRect(x: localTargetFrame.maxX - beamLength, y: localTargetFrame.minY - flareAmt, width: beamLength, height: localTargetFrame.height + flareAmt * 2)
            beamContent.startPoint = CGPoint(x: 1, y: 0.5)
            beamContent.endPoint = CGPoint(x: 0, y: 0.5)
        }
        
        beamContent.frame = beamRect
        
        // Shape Mask (Trapezoid: start exactly at strip bounds)
        let shapeMask = CAShapeLayer()
        let path = CGMutablePath()
        let br = beamContent.bounds
        
        // The flare starts from the strip edges (flareAmt offset in the frame)
        if edge == .left {
            path.move(to: CGPoint(x: 0, y: flareAmt)) // Top Left (Strip Top)
            path.addLine(to: CGPoint(x: br.width, y: 0)) // Top Right (Flare Up)
            path.addLine(to: CGPoint(x: br.width, y: br.height)) // Bottom Right (Flare Down)
            path.addLine(to: CGPoint(x: 0, y: br.height - flareAmt)) // Bottom Left (Strip Bottom)
        } else {
            path.move(to: CGPoint(x: br.width, y: flareAmt))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: br.height))
            path.addLine(to: CGPoint(x: br.width, y: br.height - flareAmt))
        }
        path.closeSubpath()
        shapeMask.path = path
        
        // Add a secondary mask to soften the top/bottom edges of the trapezoid
        let softMask = CAGradientLayer()
        softMask.frame = beamContent.bounds
        softMask.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
        softMask.locations = [0.0, 0.15, 0.85, 1.0]
        
        beamContent.mask = shapeMask
        // To combine masks, we add shapeMask to a container or nest them.
        // Let's use the alpha of the gradient to soften the vertical edges.
        beamContent.mask = softMask // Horizontal is handled by beamContent colors, vertical by softMask.
        
        // Create a reusable path for the trapezoid shape
        let trapezoidPath = path
        
        // Create container for grouping beam effects under a single mask
        let container = CALayer()
        container.frame = beamRect
        let beamShapeMask = CAShapeLayer()
        beamShapeMask.path = trapezoidPath
        container.mask = beamShapeMask
        
        // Add beam to container
        beamContent.frame = container.bounds
        container.addSublayer(beamContent)
        
        // 2.1 Window Edge Borders (User Feedback: "White diagonal borders")
        func addBorderLine(from start: CGPoint, to end: CGPoint) {
            let line = CAGradientLayer()
            line.colors = [
                NSColor.white.withAlphaComponent(0.0).cgColor,
                NSColor.white.withAlphaComponent(0.35).cgColor, // Subtle highlight
                NSColor.white.withAlphaComponent(0.0).cgColor
            ]
            line.locations = [0.0, 0.4, 0.8] // Fast falloff inward
            line.startPoint = (edge == .left) ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 1, y: 0.5)
            line.endPoint = (edge == .left) ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0, y: 0.5)
            
            let dx = end.x - start.x
            let dy = end.y - start.y
            let len = sqrt(dx*dx + dy*dy)
            let angle = atan2(dy, dx)
            
            line.bounds = CGRect(x: 0, y: 0, width: len, height: 2.0) // Slightly thicker but softer
            line.position = CGPoint(x: (start.x + end.x)/2, y: (start.y + end.y)/2)
            line.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            
            container.addSublayer(line)
        }
        
        let brBounds = container.bounds
        if edge == .left {
            // Top diagonal
            addBorderLine(from: CGPoint(x: 0, y: flareAmt), to: CGPoint(x: brBounds.width, y: 0))
            // Bottom diagonal
            addBorderLine(from: CGPoint(x: 0, y: brBounds.height - flareAmt), to: CGPoint(x: brBounds.width, y: brBounds.height))
        } else {
            addBorderLine(from: CGPoint(x: brBounds.width, y: flareAmt), to: CGPoint(x: 0, y: 0))
            addBorderLine(from: CGPoint(x: brBounds.width, y: brBounds.height - flareAmt), to: CGPoint(x: 0, y: brBounds.height))
        }
        
        // 3. Sparkle Effect (Now sibling of container to allow independent fade)
        let sparklesContainer = CALayer()
        sparklesContainer.frame = layer.bounds
        
        let sparkles = CAEmitterLayer()
        sparkles.frame = sparklesContainer.bounds
        sparkles.emitterPosition = CGPoint(x: beamRect.midX, y: beamRect.midY)
        sparkles.emitterShape = .rectangle
        sparkles.emitterSize = beamRect.size
        sparkles.renderMode = .additive // Use additive to ensure overlapping particles get brighter, not darker
        sparkles.zPosition = 200
        
        let mote = CAEmitterCell()
        mote.birthRate = 80 // Reduced saturation-heavy particles to prevent clumping
        mote.lifetime = 4.0
        mote.lifetimeRange = 2.0
        mote.velocity = 10
        mote.velocityRange = 8
        mote.emissionRange = .pi * 2
        
        mote.scale = 0.12
        mote.scaleRange = 0.08
        mote.color = intenseColor.cgColor
        mote.alphaSpeed = -0.25
        mote.contents = createParticleImage()
        
        // Add white particles for better visibility and to neutralise "blackened" look
        let whiteMote = CAEmitterCell()
        whiteMote.birthRate = 60
        whiteMote.lifetime = 4.0
        whiteMote.lifetimeRange = 2.0
        whiteMote.velocity = 10
        whiteMote.velocityRange = 8
        whiteMote.emissionRange = .pi * 2
        whiteMote.scale = 0.10
        whiteMote.scaleRange = 0.05
        whiteMote.color = NSColor.white.withAlphaComponent(0.8).cgColor
        whiteMote.alphaSpeed = -0.3
        whiteMote.contents = createParticleImage()
        
        sparkles.emitterCells = [mote, whiteMote]
        
        // Applying a very subtle fade at the very edge (95% - 100%)
        let densityMask = CAGradientLayer()
        densityMask.frame = sparklesContainer.bounds
        
        let maskSublayer = CAGradientLayer()
        maskSublayer.frame = beamRect
        maskSublayer.startPoint = (edge == .left) ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 1, y: 0.5)
        maskSublayer.endPoint = (edge == .left) ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0, y: 0.5)
        maskSublayer.colors = [
            NSColor.white.withAlphaComponent(1.0).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor  
        ]
        maskSublayer.locations = [0.0, 0.95]
        densityMask.addSublayer(maskSublayer)
        sparkles.mask = densityMask
        
        // --- ADDED: Applying the same trapezoid constraint to particles ---
        let sparklesShapeMask = CAShapeLayer()
        sparklesShapeMask.path = trapezoidPath
        // Since trapezoidPath is relative to beamRect but sparklesContainer is layer.bounds, 
        // we offset the mask or the layer. Easiest is to make the mask shape layer's frame match beamRect.
        let constraintMask = CALayer()
        constraintMask.frame = sparklesContainer.bounds
        let trapLayer = CAShapeLayer()
        trapLayer.path = trapezoidPath
        trapLayer.frame = beamRect
        constraintMask.addSublayer(trapLayer)
        
        sparklesContainer.mask = constraintMask
        sparklesContainer.addSublayer(sparkles)
        
        layer.addSublayer(sparklesContainer) 
        self.dustLayer = sparklesContainer
        
        layer.addSublayer(container)
        self.beamLayer = container
        
        // Fade in entire effect
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.5
        layer.add(fade, forKey: "fadeIn")
    }
    
    func stopExpandEffect(closeWindow: Bool = true) {
        logDebug("stopExpandEffect called. closeWindow: \(closeWindow)")
        // Fix: Cancel any existing cleanup item.
        // If stopExpandEffect is called multiple times (e.g. once by mouse exit, once by collapse animation),
        // we must ensure we don't create multiple "orphan" timers. Only the latest one should be active.
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        
        // Remove guard to ensure we ALWAYS clean up, even if layers are already nil.
        // guard let beam = beamLayer, let dust = dustLayer else { return }
        
        // Retain references for cleanup closure (if they exist)
        let beamToRemove = beamLayer
        let dustToRemove = dustLayer
        
        // Clear references so new effects can start immediately if needed
        self.beamLayer = nil
        self.dustLayer = nil
        
        // 1. Beam Fade Out (Immediate)
        if let beam = beamToRemove {
            let beamFade = CABasicAnimation(keyPath: "opacity")
            beamFade.fromValue = 1.0
            beamFade.toValue = 0.0
            beamFade.duration = 0.2 // Vanish quickly
            beamFade.fillMode = .forwards
            beamFade.isRemovedOnCompletion = false
            beam.add(beamFade, forKey: "fadeOut")
        }
        
        // 2. Dust Fade Out (Lingering Afterglow)
        if let dust = dustToRemove {
            let dustFade = CABasicAnimation(keyPath: "opacity")
            dustFade.fromValue = 1.0
            dustFade.toValue = 0.0
            dustFade.duration = 2.5 // Long linger as requested
            dustFade.fillMode = .forwards
            dustFade.isRemovedOnCompletion = false
            dust.add(dustFade, forKey: "fadeOut")
            
            // Stop emitting new particles immediately
            if let emitter = dust as? CAEmitterLayer {
                emitter.birthRate = 0
            } else if let emitter = dust.sublayers?.first(where: { $0 is CAEmitterLayer }) as? CAEmitterLayer {
                emitter.birthRate = 0
            }
        }
        
        // Independent cleanups
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            beamToRemove?.removeFromSuperlayer()
        }
        
        if closeWindow {
            // Critical: Use cancellable item for the delayed window hide.
            // STRONG CAPTURE FIX: Capture 'self' STRONGLY to keep window alive until cleanup is done.
            let item = DispatchWorkItem { 
                self.logDebug("Running cleanup item (OrderOut)")
                dustToRemove?.removeFromSuperlayer()
                // Ensure the window itself is hidden after the effects are gone
                self.orderOut(nil)
                // Break the retain cycle we created manually
                self.cleanupWorkItem = nil
            }
            
            self.cleanupWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
        } else {
             // Just schedule layer removal, don't close window
             DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                 dustToRemove?.removeFromSuperlayer()
             }
        }
    }
    
    // MARK: - Helpers
    
    func intensifyColor(_ color: NSColor) -> NSColor {
        // User Feedback: "Rich color but not black."
        // We want a more "Neon" feel - High saturation, fixed high brightness.
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        // 0.85 is softer for better blending in additive mode. 
        let newS: CGFloat = 0.85 
        // 1.0 is max brightness to ensure they always look like light sources.
        let newB: CGFloat = 1.0
        
        return NSColor(hue: h, saturation: newS, brightness: newB, alpha: 1.0)
    }
    
    private func createParticleImage() -> CGImage? {
        let size = CGSize(width: 8, height: 8)
        let img = NSImage(size: size)
        img.lockFocus()
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.setFillColor(NSColor.white.cgColor)
        ctx?.fillEllipse(in: CGRect(origin: .zero, size: size))
        img.unlockFocus()
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
