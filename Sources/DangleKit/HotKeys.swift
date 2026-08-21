import Carbon.HIToolbox

/// Global hotkeys via Carbon's RegisterEventHotKey — no accessibility
/// permission needed, unlike NSEvent global monitors.
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var installed = false
    private var refs: [EventHotKeyRef?] = []

    public struct Modifiers: OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: UInt32(cmdKey))
        public static let shift = Modifiers(rawValue: UInt32(shiftKey))
        public static let option = Modifiers(rawValue: UInt32(optionKey))
        public static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    fileprivate func handle(id: UInt32) {
        handlers[id]?()
    }

    @discardableResult
    public func register(keyCode: Int, modifiers: Modifiers,
                         handler: @escaping () -> Void) -> Bool {
        installIfNeeded()
        let id = nextID
        nextID += 1
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x444E_474C), id: id) // 'DNGL'
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers.rawValue, hkID,
                                         GetEventDispatcherTarget(), 0, &ref)
        refs.append(ref)
        return status == noErr
    }

    /// Parses "ctrl+opt+D"-style specs from packs. Supported modifier names:
    /// ctrl/control, opt/option/alt, cmd/command, shift.
    public static func parse(_ spec: String) -> (keyCode: Int, modifiers: Modifiers)? {
        var mods: Modifiers = []
        var key: String?
        for raw in spec.lowercased().split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "ctrl", "control": mods.insert(.control)
            case "opt", "option", "alt": mods.insert(.option)
            case "cmd", "command": mods.insert(.command)
            case "shift": mods.insert(.shift)
            default: key = part
            }
        }
        guard let key, let code = Self.keyCodes[key], !mods.isEmpty else { return nil }
        return (code, mods)
    }

    private static let keyCodes: [String: Int] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12,
        "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22,
        "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
    ]

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotKeyCenter.shared.handle(id: hkID.id)
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
