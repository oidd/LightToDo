import Carbon
import AppKit

class HotKeyManager {
    static let shared = HotKeyManager()
    
    // Store reference to keep it alive
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHotKeyID = EventHotKeyID(signature: 0x534E4F54, id: 1) // 'SNOT', 1
    
    var onHotKeyTriggered: (() -> Void)?
    
    init() {
        // Install Event Handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            // Forward to Swift handler
            HotKeyManager.shared.onHotKeyTriggered?()
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
    }
    
    func registerHotKey(keyCode: Int, modifiers: Int) {
        // Unregister old if any
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        
        // Convert NSEvent modifiers to Carbon modifiers
        let carbonModifiers = convertToCarbonModifiers(modifiers)
        
        // Register
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         carbonModifiers,
                                         eventHotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
        } else {
            print("Hotkey registered: code \(keyCode), mods \(carbonModifiers)")
        }
    }
    
    private func convertToCarbonModifiers(_ startModifiers: Int) -> UInt32 {
        var mods: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: UInt(startModifiers))
        
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        
        return mods
    }
}
