# AuroraAgent

Tier 2 feature facade — the single import surface Application code uses
to reach the Execution layer. Composes `Config` (credentials, env
loading) and `APIClient` (HTTP + retry) into a working `Agent`.

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

AgentFactory.makeDefault() async -> Agent        // production composition
