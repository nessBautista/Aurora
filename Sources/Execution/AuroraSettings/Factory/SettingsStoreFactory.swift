/// # SettingsStoreFactory.swift — Production composition for AuroraSettings
///
/// Returns a `SettingsStore` pointed at Aurora's production preferences
/// domain (`com.aurora.settings`).
///
/// Tests construct `SettingsStore(suiteName:)` directly with a
/// UUID-namespaced suite so they don't pollute the developer's real
/// preferences. `SettingsStore.init` has no default `suiteName:` value,
/// so a test that forgets to override is a compile error.
public func makeSettingsStore() -> SettingsStore {
    SettingsStore(suiteName: "com.aurora.settings")
}
