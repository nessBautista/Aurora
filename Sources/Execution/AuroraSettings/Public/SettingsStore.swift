import Foundation

/// UserDefaults-backed persistence for `Settings`.
///
/// `suiteName` is the load-bearing knob — it controls where the plist
/// lands. Production callers go through `makeSettingsStore()` in
/// `Factory/SettingsStoreFactory.swift`, which supplies the production
/// suite (`com.aurora.settings`). Tests pass a UUID-namespaced suite name so
/// they don't pollute the real preferences domain on the developer's
/// machine.
///
/// `suiteName:` has no default — a test that forgets to override would
/// silently write to `~/Library/Preferences/com.aurora.settings.plist`,
/// so the argument is required.
public final class SettingsStore {

    private let defaults: UserDefaults
    private let suiteName: String

    public init(suiteName: String) {
        self.suiteName = suiteName
        // `UserDefaults(suiteName:)` returns nil only for reserved names
        // (e.g. the global domain); for any normal app-style suite it
        // returns a working instance.
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func load() -> Settings {
        SettingsCodec.decode(
            selectedProviderRaw: defaults.string(forKey: SettingsCodec.selectedProviderKey)
        )
    }

    public func save(_ settings: Settings) {
        let encoded = SettingsCodec.encode(settings)
        if let raw = encoded.selectedProviderRaw {
            defaults.set(raw, forKey: SettingsCodec.selectedProviderKey)
        } else {
            defaults.removeObject(forKey: SettingsCodec.selectedProviderKey)
        }
    }

    /// Wipes every Aurora-namespaced key. Tests call this in tearDown so
    /// a crashed test doesn't leak state to the next run.
    public func reset() {
        defaults.removeObject(forKey: SettingsCodec.selectedProviderKey)
    }
}
