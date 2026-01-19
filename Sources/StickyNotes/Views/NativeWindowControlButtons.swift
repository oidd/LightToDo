import SwiftUI
import AppKit

struct NativeWindowControlButtons: NSViewRepresentable {
    typealias NSViewType = TrafficLightContainerView
    let isActive: Bool
    
    func makeNSView(context: Context) -> TrafficLightContainerView {
        return TrafficLightContainerView()
    }
    
    func updateNSView(_ nsView: TrafficLightContainerView, context: Context) {
        nsView.updateActiveState(isActive)
    }
}

class TrafficLightContainerView: NSView {
    private var closeButton: TrafficLightButton!
    private var minimizeButton: TrafficLightButton!
    private var zoomButton: TrafficLightButton!
    private var isActive: Bool = true
    private var isGroupHovered: Bool = false
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 70, height: 24))
        setupButtons()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupButtons() {
        let buttonSize: CGFloat = 14
        let spacing: CGFloat = 8
        
        closeButton = TrafficLightButton(
            frame: NSRect(x: 0, y: 5, width: buttonSize, height: buttonSize),
            type: .close
        )
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        addSubview(closeButton)
        
        minimizeButton = TrafficLightButton(
            frame: NSRect(x: buttonSize + spacing, y: 5, width: buttonSize, height: buttonSize),
            type: .minimize
        )
        minimizeButton.target = self
        minimizeButton.action = #selector(minimizeWindow)
        addSubview(minimizeButton)
        
        zoomButton = TrafficLightButton(
            frame: NSRect(x: (buttonSize + spacing) * 2, y: 5, width: buttonSize, height: buttonSize),
            type: .zoom
        )
        zoomButton.target = self
        zoomButton.action = #selector(zoomWindow)
        addSubview(zoomButton)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isGroupHovered = true
        updateButtonStates()
    }
    
    override func mouseExited(with event: NSEvent) {
        isGroupHovered = false
        updateButtonStates()
    }
    
    func updateActiveState(_ active: Bool) {
        isActive = active
        updateButtonStates()
    }
    
    private func updateButtonStates() {
        closeButton.updateState(isActive: isActive, isGroupHovered: isGroupHovered)
        minimizeButton.updateState(isActive: isActive, isGroupHovered: isGroupHovered)
        zoomButton.updateState(isActive: isActive, isGroupHovered: isGroupHovered)
    }
    
    @objc private func closeWindow() {
        window?.close()
    }
    
    @objc private func minimizeWindow() {
        window?.miniaturize(nil)
    }
    
    @objc private func zoomWindow() {
        window?.zoom(nil)
    }
}

class TrafficLightButton: NSButton {
    enum ButtonType {
        case close, minimize, zoom
    }
    
    private let buttonType: ButtonType
    private var isActive: Bool = true
    private var isGroupHovered: Bool = false
    
    private var activeColor: NSColor {
        switch buttonType {
        case .close: return NSColor(red: 1, green: 0.38, blue: 0.35, alpha: 1)
        case .minimize: return NSColor(red: 1, green: 0.75, blue: 0.28, alpha: 1)
        case .zoom: return NSColor(red: 0.15, green: 0.8, blue: 0.25, alpha: 1)
        }
    }
    
    private var inactiveColor: NSColor {
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(white: 0.28, alpha: 1)
        } else {
            return NSColor(white: 0.83, alpha: 1)
        }
    }
    
    private var iconName: String {
        switch buttonType {
        case .close: return "xmark"
        case .minimize: return "minus"
        case .zoom: return "plus"
        }
    }
    
    init(frame: NSRect, type: ButtonType) {
        self.buttonType = type
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupButton() {
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = bounds.width / 2
        updateAppearance()
    }
    
    func updateState(isActive: Bool, isGroupHovered: Bool) {
        self.isActive = isActive
        self.isGroupHovered = isGroupHovered
        updateAppearance()
    }
    
    private func updateAppearance() {
        layer?.backgroundColor = (isActive ? activeColor : inactiveColor).cgColor
        
        if isGroupHovered && isActive {
            let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            if let symbolImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                image = symbolImage
                contentTintColor = NSColor.black.withAlphaComponent(0.5)
            }
        } else {
            image = nil
        }
        
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds)
        (isActive ? activeColor : inactiveColor).setFill()
        path.fill()
        
        if isGroupHovered && isActive, let img = image {
            let imgSize = img.size
            let imgRect = NSRect(
                x: (bounds.width - imgSize.width) / 2,
                y: (bounds.height - imgSize.height) / 2,
                width: imgSize.width,
                height: imgSize.height
            )
            img.draw(in: imgRect)
        }
    }
}
