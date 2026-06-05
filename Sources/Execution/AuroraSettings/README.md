# AuroraSettings

UserDefaults-backed persistence for Aurora's user preferences. Holds one
field today — `selectedProvider` — and grows as new preferences land.

`selectedProvider` records which LLM backend the user has chosen. The
type itself (`Config.Provider`) lives in `AuroraConfig` and enumerates
every provider Aurora knows how to talk to. Today there's exactly one
case (`.anthropic`); more land as new adapters ship. The field is
optional because "never picked yet" is a real state — that's the
trigger for the first-run prompt.

*Public surface lives in `Public/`; implementation details in `Implementation/`; production composition in `Factory/`.*

## Public API

```swift
Settings                                         // value struct
Settings(selectedProvider:)                      // init with optional Config.Provider

SettingsStore                                    // UserDefaults wrapper
SettingsStore(suiteName:)                        // required arg — no default

store.load() -> Settings                         // read; returns Settings() if nothing persisted
store.save(_ settings: Settings)                 // write; nil provider clears the key
store.reset()                                    // wipe all Aurora-namespaced keys

makeSettingsStore() -> SettingsStore             // production composition (Factory/)
```

## Files

| File | Holds | Access |
|---|---|---|
| `Public/Settings.swift` | `Settings` value struct | `public` |
| `Implementation/SettingsCodec.swift` | `SettingsCodec` enum + `RawValues` — pure encode/decode | `internal` |
| `Public/SettingsStore.swift` | `SettingsStore` (UserDefaults I/O) | `public` |
| `Factory/SettingsStoreFactory.swift` | `makeSettingsStore()` — production composition | `public` |

Only the cross-module contract is `public`. `SettingsCodec` is `internal`;
tests reach it via `@testable import AuroraSettings`.

## Three types, three roles

| Type | Role | Semantics |
|---|---|---|
| `Settings` (struct) | Data shape callers hold and pass around | Value — mutating a copy can't affect persisted state |
| `SettingsCodec` (enum) | Translation between `Settings` and the `String?` raws UserDefaults persists | Pure — no I/O |
| `SettingsStore` (final class) | UserDefaults `load` / `save` / `reset` | Reference — callers share one handle to the plist |

The split keeps each layer testable on its own: codec tests don't need
a plist, store tests use a throwaway one. Callers outside the module
only see `Settings` and `SettingsStore` — they can't stringly-type
their way into the persistence layer because the codec is `internal`.

UserDefaults can't store Swift enums directly, so the codec maps
`Config.Provider ↔ String` via `rawValue` / `init(rawValue:)`. Keeping
that mapping in a pure enum means every branch is testable without
touching UserDefaults.

## Forward compatibility

Unknown raw strings — e.g., a future Aurora wrote `"openrouter"` and an
older binary loads the plist — resolve to `nil` in `decode`, never a
crash. The store treats nil as "no preference recorded"; the user gets
re-prompted, the app stays alive. Pinned by
`SettingsCodecTests.testDecodeUnknownRawReturnsEmpty`.

## Suite names

`suiteName` is the name of the plist file UserDefaults writes to. On
macOS, `UserDefaults(suiteName: "foo")` is backed by
`~/Library/Preferences/foo.plist`. It's Foundation's API, not Aurora's
invention — Aurora just uses it to keep tests and production pointing
at different files.

Production callers go through `makeSettingsStore()`, which supplies
`"com.aurora.settings"` — written to
`~/Library/Preferences/com.aurora.settings.plist`.

Tests pass a UUID-namespaced suite (e.g.,
`"com.aurora.test.\(UUID().uuidString)"`) and call `removePersistentDomain`
in `tearDown`, so each test gets a throwaway plist and the developer's
real preferences are never touched. `SettingsStore.init` has no default
`suiteName:` value, so a test that forgets to override is a compile error
rather than a silent write to the production plist.

`UserDefaults(suiteName:)` returns nil only for reserved names (e.g., the
global domain). `SettingsStore` falls back to `.standard` in that case,
but no normal app-style suite hits it.
