import Foundation

/// Diagnostic launches must not overwrite the player's ordinary preferences.
public enum NativePreferences {
    public static let current = applicationStore()
    public static let gamepadSupportKey = "gamepadSupport"
    public static let appSettingKeys = [
        "tankColor", "localTankColor", "serverURL", "highFrameRate", "showFPS", "soundEnabled", "soundVolume",
        "nativePresets",
        "nativeHardwareControls.v1", gamepadSupportKey,
        "callsign", "callsignAutoPending", "callsignAutoPendingName", "callsignRevision", "localCallsign",
        "localCallsignAutoPending", "localCallsignAutoPendingName", "localCallsignRevision",
        "callsignGenerationAttempt",
    ]

    public static func gamepadSupportEnabled(in defaults: UserDefaults = current) -> Bool {
        defaults.object(forKey: gamepadSupportKey) as? Bool ?? true
    }

    /// Account bearers and saved callsigns are intentionally held in Keychain.
    public static func resetAppSettings(in defaults: UserDefaults = current) {
        for key in appSettingKeys { defaults.removeObject(forKey: key) }
    }

    public static func applicationStore(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        standard: UserDefaults = .standard
    ) -> UserDefaults {
        let index = arguments.firstIndex(of: "--public-session-test-namespace")
        let namespace = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let diagnostic =
            arguments.contains("--native-performance-probe")
            || arguments.contains("--native-render-probe") || arguments.contains("--probe-direct-aim")
        guard let namespace = namespace ?? (diagnostic ? "diagnostic" : nil), !namespace.isEmpty,
            let defaults = UserDefaults(suiteName: domain(namespace))
        else { return standard }
        if arguments.contains("--reset-public-session-test-store") {
            defaults.removePersistentDomain(forName: domain(namespace))
        }
        defaults.setVolatileDomain(
            standard.volatileDomain(forName: UserDefaults.argumentDomain),
            forName: UserDefaults.argumentDomain)
        return defaults
    }

    static func domain(_ namespace: String) -> String { "com.leqra.ios.test-preferences." + namespace }
}
