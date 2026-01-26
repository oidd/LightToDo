import AppKit
import QuartzCore

class VisualEffectOverlayWindow: NSPanel {
    private var particleLayer: CAEmitterLayer?
    private var beamLayer: CALayer?
    private var beamMaskLayer: CAShapeLayer?
    private var dustLayer: CAEmitterLayer?
    
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
        
        // 4. Cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            emitter.removeFromSuperlayer()
        }
    }
    
    // MARK: - Expand Effect (Beam & Dust)
    
    func startExpandEffect(edge: SnapEdge, frame: NSRect, color: NSColor) {
        guard let layer = self.contentView?.layer, let screen = NSScreen.main else { return }
        stopExpandEffect()
        
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
            NSColor.white.withAlphaComponent(0.18).cgColor, // Lighter source
            NSColor.white.withAlphaComponent(0.08).cgColor, 
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
        // But we need the trapezoid shape!
        // We'll apply the shapeMask to the beamContent and the softMask to a container.
        
        // Create container for grouping effects under a single mask
        let container = CALayer()
        container.frame = beamRect
        container.mask = shapeMask
        
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
        
        // 3. Sparkle Effect (Now inside container to share mask and coordinates)
        let sparkles = CAEmitterLayer()
        sparkles.emitterPosition = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        sparkles.emitterShape = .rectangle
        sparkles.emitterSize = container.bounds.size
        sparkles.renderMode = .unordered
        
        let mote = CAEmitterCell()
        mote.birthRate = 180 
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
        
        sparkles.emitterCells = [mote]
        
        // User Feedback: "Decrease particle density further from the strip"
        // Applying a very subtle fade at the very edge (95% - 100%)
        let densityMask = CAGradientLayer()
        densityMask.frame = container.bounds
        densityMask.startPoint = (edge == .left) ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 1, y: 0.5)
        densityMask.endPoint = (edge == .left) ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0, y: 0.5)
        densityMask.colors = [
            NSColor.white.withAlphaComponent(1.0).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor  
        ]
        densityMask.locations = [0.0, 0.95] 
        sparkles.mask = densityMask
        
        container.addSublayer(sparkles) 
        self.dustLayer = sparkles
        
        layer.addSublayer(container)
        self.beamLayer = container
        
        // Fade in entire effect
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.5
        layer.add(fade, forKey: "fadeIn")
    }
    
    func stopExpandEffect() {
        guard let beam = beamLayer, let dust = dustLayer else { return }
        
        // Retain references for cleanup closure
        let beamToRemove = beam
        let dustToRemove = dust
        
        // Clear references so new effects can start immediately if needed
        self.beamLayer = nil
        self.dustLayer = nil
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            beamToRemove.removeFromSuperlayer()
            dustToRemove.removeFromSuperlayer()
        }
        
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = 0.6 // Slow fade for "residual light" effect
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        
        beamToRemove.add(fadeOut, forKey: "fadeOut")
        dustToRemove.add(fadeOut, forKey: "fadeOut")
        
        // Stop emitting new particles immediately, let existing ones fade
        if let emitter = dustToRemove as? CAEmitterLayer {
            emitter.birthRate = 0
        }
        
        CATransaction.commit()
    }
    
    // MARK: - Helpers
    
    func intensifyColor(_ color: NSColor) -> NSColor {
        // User Feedback: "Rich color but not black."
        // We want a more "Neon" feel - High saturation, fixed high brightness.
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        // Drive saturation to max for punchy color
        let newS: CGFloat = 1.0 
        // Keep brightness in a range that is colorful but NEVER dark.
        // 0.9 is very bright, 0.7 is rich. Let's aim for 0.85.
        let newB: CGFloat = 0.85
        
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
