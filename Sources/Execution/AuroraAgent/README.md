# AuroraAgent

Tier 2 feature facade — the single import surface Application code uses
to reach the Execution layer. Composes `Config` (credentials, env
loading) and `APIClient` (HTTP + retry) into a working `Agent`.

*Public surface lives in `Public/`; implementation details in `Implementation/`.*

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

The Tier 2 facade factory. `makeDefault()` is the production composition
path:

```swift
public static func makeDefault() async -> Agent {
    await Config.load()
    return DefaultAgent(client: makeAPIClient())
}
```

`Config.load()` populates the process env from keychain + `.env` (and
snapshots `originalKeySource` so the banner stays honest). `makeAPIClient()`
constructs the `APIClient` against the Anthropic provider.

This factory is **not** the application composition root — it's a Tier
2 facade factory. The application composition root lands at the CLI
layer and invokes `AgentFactory.makeDefault()` alongside other module
factories.

## Files

| File | Holds | Access |
|---|---|---|
| `Agent.swift` | `Agent` protocol — the public Tier 2 contract (single landmark) | `public` |
| `ProviderInfo.swift` | `ProviderInfo` value type returned by `Agent.providerInfo` | `public` |
| `DefaultAgent.swift` | `DefaultAgent` final class — the single production concrete | `internal` |
| `Auth.swift` | `AgentAuth` namespace + `Provider` + `KeyStatus` enums + `setKey`/`clearKey`/`keyStatus`/`toConfig` | `public` surface, `internal` translator |
| `AgentFactory.swift` | `AgentFactory` namespace + `makeDefault(providerOverride:)` + `make(client:)` | `public` (`makeDefault`), `internal` (`make`) |

## Tests

`AuroraAgentTests` uses `@testable import AuroraAgent` and `@testable
import AuroraLLMProvider` to construct an `APIClient` from a stub
`LLMProvider` and inject it via `AgentFactory.make(client:)`. No HTTP,
no keychain, no `.env` — pure protocol-driven plumbing tests. Storage
round-trip for `AgentAuth` is covered at the Tier 4 layer
(`AuroraKeychainTests`, `AuroraConfigTests`); this module only verifies
the translation seams.
