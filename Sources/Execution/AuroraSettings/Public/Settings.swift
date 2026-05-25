import Foundation
import AuroraConfig

/// A snapshot of Aurora's persisted user preferences. Value type — pass it
/// around freely; mutations don't leak. Persist a change by handing the
/// updated value to `SettingsStore.save(_:)`.
public struct Settings: Equatable {
    
    public var selectedProvider: Config.Provider?
    
    public init(selectedProvider: Config.Provider? = nil) {
        self.selectedProvider = selectedProvider
    }
}
