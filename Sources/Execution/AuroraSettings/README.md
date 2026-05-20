# AuroraSettings

UserDefaults-backed persistence for Aurora's user preferences. Holds one
field today — `selectedProvider` — and grows as new preferences land.

## Public API

```swift
Settings                                         // value struct
Settings(selectedProvider:)                      // init with optional Config.Provider

SettingsStore                                    // UserDefaults wrapper
SettingsStore(suiteName:)                        // default: "com.aurora.settings"

store.load() -> Settings                         // read; returns Settings() if nothing persisted
store.save(_ settings: Settings)                 // write; nil provider clears the key
store.reset()                                    // wipe all Aurora-namespaced keys
```

## Files

| File | Holds | Access |
|---|---|---|
| `Settings.swift` | `Settings` value struct | `public` |
| `SettingsCodec.swift` | `SettingsCodec` enum + `RawValues` — pure encode/decode | `internal` |
| `SettingsStore.swift` | `SettingsStore` — UserDefaults I/O | `public` |

Only the cross-module contract is `public`. `SettingsCodec` is `internal`;
tests reach it via `@testable import AuroraSettings`.

## Three types, three roles

| Type | Role | Semantics |
|---|---|---|
| `Settings` (struct) | Data shape | Value — passed around as snapshot copies; mutating a copy can't affect persisted state |
| `SettingsCodec` (enum) | Encode/decode between `Settings` and the `String?` raws UserDefaults persists | Pure — no I/O |
| `SettingsStore` (final class) | UserDefaults `load` / `save` / `reset` | Reference — callers share one handle to the plist |

UserDefaults can't store Swift enums directly, so the codec layer maps
`Config.Provider ↔ String` via `rawValue` / `init(rawValue:)`. Keeping that
mapping in a pure enum means every codec branch is testable without
touching UserDefaults.

## Forward compatibility

Unknown raw strings — e.g., a future Aurora wrote `"openrouter"` and an
older binary loads the plist — resolve to `nil` in `decode`, never a
crash. The store treats nil as "no preference recorded"; the user gets
re-prompted, the app stays alive. Pinned by
`SettingsCodecTests.testDecodeUnknownRawReturnsEmpty`.

## Suite names

`UserDefaults(suiteName:)` controls where the plist lands. The default
`"com.aurora.settings"` writes to
`~/Library/Preferences/com.aurora.settings.plist`.

Tests pass a UUID-namespaced suite (e.g.,
`"com.aurora.test.\(UUID().uuidString)"`) and call `removePersistentDomain`
in `tearDown`, so each test gets a throwaway plist and the developer's
real preferences are never touched.

`UserDefaults(suiteName:)` returns nil only for reserved names (e.g., the
global domain). `SettingsStore` falls back to `.standard` in that case,
but no normal app-style suite hits it.
