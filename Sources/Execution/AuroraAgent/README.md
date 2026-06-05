# AuroraAgent

Tier 2 feature facade — the single import surface Application code uses
to reach the Execution layer. Composes `Config` (credentials, env
loading) and `APIClient` (HTTP + retry) into a working `Agent`.

*Public surface lives in `Public/`; implementation details in `Implementation/`; production composition in `Factory/`.*

## Public API

```swift
Agent                                            // protocol — chat + providerInfo
try await agent.chat(_ prompt: String) -> String
agent.providerInfo -> ProviderInfo

ProviderInfo(providerName:modelId:apiKeySource:) // value type for the startup banner

AgentAuth                                        // namespace for credentials
AgentAuth.Provider                               // .anthropic (today)
AgentAuth.KeyStatus                              // .env / .keychain / .envFile / .missing
try AgentAuth.setKey(_ provider: Provider, _ key: String)
AgentAuth.clearKey(_ provider: Provider)
AgentAuth.keyStatus(_ provider: Provider) -> KeyStatus

AgentAuth.setActiveProvider(_ provider: Provider)        // persist `auth use` choice
AgentAuth.activeProviderSelection() -> Provider?         // the stored choice, or nil
AgentAuthError.noProviderSelected                        // thrown when nothing selects a provider

AgentFactory.makeDefault(providerOverride:) async throws -> Agent  // production composition
```

That's the entire Application-visible surface. `DefaultAgent` (the
concrete) and `AgentFactory.make(client:)` (the test/advanced injection
seam) are `internal`.

## Why Tier 3 / Tier 4 types are hidden

`AuroraLLMProvider.APIClient`, `AuroraLLMProvider.BootInfo`,
`AuroraConfig.Config.Provider`, and `AuroraConfig.Config.KeySource` are
**not** part of Application's view. The Tier 2 facade translates each
one:

| Tier 3 / Tier 4 type | Tier 2 mirror | Translation lives in |
|---|---|---|
| `APIClient.bootInfo: BootInfo` | `Agent.providerInfo: ProviderInfo` | `DefaultAgent.providerInfo` getter |
| `Config.Provider` | `AgentAuth.Provider` | `AgentAuth.toConfig(_:)` |
| `Config.KeySource` | `AgentAuth.KeyStatus` | `AgentAuth.keyStatus(_:)` switch |
| `Message` / `ContentBlock` | (none — flattened to `String`) | `DefaultAgent.chat` |

This is what makes the architectural invariant "Application imports only
Tier 2" work: every type Application might want to name has a Tier 2
representative.

## `Agent`

Protocol so `DefaultAgent` (the concrete) can stay `internal`.
Application holds an `Agent` reference and depends only on the protocol;
the factory hides the wiring.

`chat(_:) async throws -> String` is single-shot. No conversation
history, no tools, no system prompt. The auth-flow scope doesn't need
any of those.

`providerInfo` reads on access — every banner render gets fresh values,
matching the `APIClient.bootInfo` timing dance.

## `AgentAuth`

A `public enum AgentAuth` namespace rather than methods on `Agent`
(protocols can't have static methods).

`Provider` and `KeyStatus` are local enums that mirror `Config.Provider`
and `Config.KeySource`. The mirror means Application code never sees
`AuroraConfig` types — only `AgentAuth.Provider.anthropic` and
`AgentAuth.KeyStatus.keychain`. When a new provider lands, both the
local enum AND the translator inside `setKey/clearKey/keyStatus` must
grow a case; the translator's `switch` is exhaustive so the compiler
catches a missed update.

`setKey` and `clearKey` touch the macOS keychain (via `Config`); they
prompt Touch ID on `setKey` (writing) but not on `clearKey` or
`keyStatus` (reading metadata only).

## `AgentFactory`

The Tier 2 facade factory. `makeDefault(providerOverride:)` is the production
composition path:

```swift
public static func makeDefault(providerOverride: AgentAuth.Provider? = nil) async throws -> Agent {
    Config.loadEnvironment()                       // prompt-free: .env + snapshot
    let resolved = Config.resolveActiveProvider(
        override: providerOverride.map(AgentAuth.toConfig),
        envRaw: ProcessInfo.processInfo.environment["LLM_PROVIDER"],
        storedSelection: AgentAuth.activeProviderSelection().map(AgentAuth.toConfig)
    )
    guard let provider = resolved else { throw AgentAuthError.noProviderSelected }
    await Config.loadKey(for: provider)            // authenticate ONLY the resolved provider
    return DefaultAgent(client: makeAPIClient(for: provider))
}
```

`Config.loadEnvironment()` loads `.env` and snapshots `originalKeySource`
(prompt-free), so the banner stays honest and an `LLM_PROVIDER` in `.env`
counts. The **provider-selection waterfall** — `providerOverride` (the CLI's
`--provider`) → `LLM_PROVIDER` env → the stored `auth use` selection — picks the
active provider; `nil` (nothing
selected anywhere) throws `AgentAuthError.noProviderSelected` rather than
silently defaulting. `makeAPIClient(for:)` then builds the `APIClient` against
that provider's adapter.

This factory is **not** the application composition root — it's a Tier 2 facade
factory. The application composition root lands at the CLI layer and invokes
`AgentFactory.makeDefault(providerOverride:)` alongside other module factories.

## Files

| File | Holds | Access |
|---|---|---|
| `Public/Agent.swift` | `Agent` protocol — the public Tier 2 contract (single landmark) | `public` |
| `Public/ProviderInfo.swift` | `ProviderInfo` value type returned by `Agent.providerInfo` | `public` |
| `Implementation/DefaultAgent.swift` | `DefaultAgent` final class — the single production concrete | `internal` |
| `Public/Auth.swift` | `AgentAuth` namespace + `Provider`/`KeyStatus` enums + `setKey`/`clearKey`/`keyStatus` + `setActiveProvider`/`activeProviderSelection` + `toConfig`/`fromConfig`; plus `AgentAuthError` | `public` surface, `internal` translators |
| `Factory/AgentFactory.swift` | `AgentFactory` namespace + `makeDefault(providerOverride:)` + `make(client:)` — production composition (the Tier 2 Composition Root) | `public` (`makeDefault`), `internal` (`make`) |

## Tests

`AuroraAgentTests` uses `@testable import AuroraAgent` and `@testable
import AuroraLLMProvider` to construct an `APIClient` from a stub
`LLMProvider` and inject it via `AgentFactory.make(client:)`. No HTTP,
no keychain, no `.env` — pure protocol-driven plumbing tests. Storage
round-trip for `AgentAuth` is covered at the Tier 4 layer
(`AuroraKeychainTests`, `AuroraConfigTests`); this module only verifies
the translation seams.
