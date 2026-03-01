import AppKit
import Carbon.HIToolbox

// C callback for Carbon hot key event
private func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        GlobalShortcut.shared.onTrigger?()
    }
    return noErr
}

final class GlobalShortcut {
    static let shared = GlobalShortcut()

    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    var keyCode: Int {
        get { UserDefaults.standard.object(forKey: "shortcutKeyCode") as? Int ?? kVK_ANSI_B }
        set { UserDefaults.standard.set(newValue, forKey: "shortcutKeyCode") }
    }

    var modifierFlags: NSEvent.ModifierFlags {
        get {
            let raw = UserDefaults.standard.object(forKey: "shortcutModifiers") as? UInt
                ?? NSEvent.ModifierFlags([.command, .shift]).rawValue
            return NSEvent.ModifierFlags(rawValue: raw)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "shortcutModifiers") }
    }

    var shortcutDescription: String {
        var parts: [String] = []
        if modifierFlags.contains(.command) { parts.append("Cmd") }
        if modifierFlags.contains(.shift) { parts.append("Shift") }
        if modifierFlags.contains(.option) { parts.append("Opt") }
        if modifierFlags.contains(.control) { parts.append("Ctrl") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    func start() {
        stop()

        // Install Carbon event handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status1 = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        print("InstallEventHandler: \(status1 == noErr ? "OK" : "failed (\(status1))")")

        // Register the hot key (system-wide)
        let carbonMods = carbonModifiers(from: modifierFlags)
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x434C_424C),  // "CLBL"
            id: 1
        )

        let status2 = RegisterEventHotKey(
            UInt32(keyCode),
            carbonMods,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        print("RegisterEventHotKey(\(shortcutDescription)): \(status2 == noErr ? "OK" : "failed (\(status2))")")
    }

    func stop() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    func restart() {
        stop()
        start()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    private func keyName(for code: Int) -> String {
        switch code {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        default: return "Key(\(code))"
        }
    }
}
