import Foundation

public enum NativeControlAction: String, Codable, CaseIterable, Hashable, Sendable {
    case forward, reverse, left, right, fire, fireAlt
    public var label: String {
        switch self {
        case .forward: return "Forward"
        case .reverse: return "Reverse"
        case .left: return "Turn left"
        case .right: return "Turn right"
        case .fire: return "Fire"
        case .fireAlt: return "Fire (alternate)"
        }
    }
}

public struct NativeKeyboardLayout: Codable, Equatable, Sendable {
    public var forward: Int
    public var reverse: Int
    public var left: Int
    public var right: Int
    public var fire: Int
    public var fireAlt: Int

    public subscript(action: NativeControlAction) -> Int {
        get {
            switch action {
            case .forward: return forward
            case .reverse: return reverse
            case .left: return left
            case .right: return right
            case .fire: return fire
            case .fireAlt: return fireAlt
            }
        }
        set {
            switch action {
            case .forward: forward = newValue
            case .reverse: reverse = newValue
            case .left: left = newValue
            case .right: right = newValue
            case .fire: fire = newValue
            case .fireAlt: fireAlt = newValue
            }
        }
    }
}

public enum NativeBindingError: LocalizedError, Equatable {
    case reserved, duplicate, invalidLayout
    public var errorDescription: String? {
        switch self {
        case .reserved:
            return "That key is reserved. Escape, P, M, F, Tab and system shortcuts cannot be assigned."
        case .duplicate: return "That key is already assigned. Change the other binding first."
        case .invalidLayout: return "Choose keyboard layout 1 or 2."
        }
    }
}

/// Physical USB HID codes match UIKey.keyCode and do not change with keyboard
/// language. Both layouts can share a pilot, or be assigned to separate desktop pilots.
public struct NativeControlBindings: Codable, Equatable, Sendable {
    public var layouts: [NativeKeyboardLayout]
    public init(layouts: [NativeKeyboardLayout]) { self.layouts = layouts }
    public static let defaults = NativeControlBindings(layouts: [
        NativeKeyboardLayout(forward: 26, reverse: 22, left: 4, right: 7, fire: 20, fireAlt: 6),
        NativeKeyboardLayout(forward: 82, reverse: 81, left: 80, right: 79, fire: 44, fireAlt: 40),
    ])
    public var isValid: Bool {
        guard layouts.count == 2 else { return false }
        var seen = Set<Int>()
        for layout in layouts {
            for action in NativeControlAction.allCases {
                let code = layout[action]
                guard Self.validKey(code), seen.insert(code).inserted else { return false }
            }
        }
        return true
    }
    public static func validKey(_ code: Int) -> Bool {
        // Letters, numbers, punctuation, arrows, keypad, and either Shift.
        // Control/Option/Command are reserved for platform shortcuts.
        guard ![9, 16, 19].contains(code) else { return false }  // F, M, P
        return (4...39).contains(code) || code == 40 || (44...49).contains(code)
            || [51, 52, 54, 55, 56].contains(code) || (79...82).contains(code)
            || (84...98).contains(code) || code == 225 || code == 229
    }
    public func assigning(_ code: Int, layout index: Int, action: NativeControlAction) throws
        -> NativeControlBindings
    {
        guard layouts.indices.contains(index) else { throw NativeBindingError.invalidLayout }
        guard Self.validKey(code) else { throw NativeBindingError.reserved }
        for (otherIndex, layout) in layouts.enumerated() {
            for other in NativeControlAction.allCases {
                if otherIndex != index || other != action, layout[other] == code {
                    throw NativeBindingError.duplicate
                }
            }
        }
        var next = self
        next.layouts[index][action] = code
        return next
    }
    public func contains(_ code: Int) -> Bool {
        layouts.contains { layout in NativeControlAction.allCases.contains { layout[$0] == code } }
    }
    public func input(pressed: Set<Int>, layout index: Int? = nil) -> GameInput {
        let selected = index.map { layouts.indices.contains($0) ? [layouts[$0]] : [] } ?? layouts
        func held(_ action: NativeControlAction) -> Bool {
            selected.contains { pressed.contains($0[action]) }
        }
        return GameInput(
            forward: held(.forward), reverse: held(.reverse), left: held(.left), right: held(.right),
            fire: held(.fire) || held(.fireAlt))
    }
    public static func keyLabel(_ code: Int) -> String {
        if (4...29).contains(code) { return String(UnicodeScalar(code - 4 + 65)!) }
        if (30...38).contains(code) { return String(code - 29) }
        if (89...97).contains(code) { return "NUM \(code - 88)" }
        return [
            39: "0", 40: "ENTER", 44: "SPACE", 45: "-", 46: "=", 47: "[", 48: "]", 49: "\\", 51: ";", 52: "'",
            53: "`", 54: ",", 55: ".", 56: "/", 79: "→", 80: "←", 81: "↓", 82: "↑", 83: "NUM LOCK",
            84: "NUM /", 85: "NUM *", 86: "NUM -", 87: "NUM +", 88: "NUM ENTER", 98: "NUM 0", 99: "NUM .",
            103: "NUM =", 225: "SHIFT L", 229: "SHIFT R",
        ][code] ?? "KEY \(code)"
    }
}

public struct NativeControlPreferences: Codable, Equatable, Sendable {
    public var bindings: NativeControlBindings = .defaults
    public var mouseAim = true
    public var mouseFire = true
    public init() {}
    public static let storageKey = "nativeHardwareControls.v1"
    public static func load(from defaults: UserDefaults) -> NativeControlPreferences {
        guard let data = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode(Self.self, from: data), saved.bindings.isValid
        else { return Self() }
        return saved
    }
    public func save(to defaults: UserDefaults) {
        guard bindings.isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
