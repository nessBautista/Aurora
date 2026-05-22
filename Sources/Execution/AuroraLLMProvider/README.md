# AuroraLLMProvider

The wire-format adapter layer. Adapters translate Aurora's internal
`Message` / `ContentBlock` model (defined in `AuroraModels`) to and from a
specific LLM provider's request/response shape.

## Public API

```swift
APIClient                                         // facade — owns provider + retry loop
try await client.callAPI(messages:tools:systemPrompt:forcedTool:)
    -> (String, [ContentBlock])                    // one round-trip with retry
client.bootInfo -> BootInfo                       // provider name / modelId / key source

BootInfo(providerName:modelId:apiKeySource:)     // value type for the startup banner

TransientError(kind:body:)                        // retry-worthy failure (thrown by callAPI)
BadResponse(provider:detail:bodyPreview:)         // unparseable response (thrown by callAPI)

makeAPIClient() -> APIClient                     // production composition (APIClient.swift)
```

That's the entire contract. Callers cannot name `LLMProvider`,
`AnthropicProvider`, or `makeLLMProvider()` — they're `internal`. The
protocol exists as a **module-private DI seam**, not as part of the
public surface.

## Why the provider types are internal

External callers compose through `makeAPIClient()` and read provider
identity through `BootInfo`. They never need to know which concrete
adapter is in use — that's by design. Hiding the seam means:

- Adding a new adapter (OpenRouter, etc.) is a pure internal change with
  zero impact on the module's public surface.
- Callers can't accidentally couple to `AnthropicProvider` specifics.
- The only place production code resolves a concrete is
  `makeLLMProvider()` inside the module.

## Files

| File | Holds | Access |
|---|---|---|
| `LLMProvider.swift` | `LLMProvider` protocol + `makeLLMProvider()` factory | `internal` |
| `LLMProvider+Errors.swift` | `TransientError`, `BadResponse` | `public` |
| `AnthropicProvider.swift` | `AnthropicProvider` concrete adapter | `internal` |
| `APIClient.swift` | `APIClient`, `BootInfo`, `makeAPIClient()` factory | `public` |

`make*` factories live at the bottom of the file that defines what they
build. They are the only places production code resolves a concrete
implementation; everything else takes its collaborators by injection.

## Tests

`AuroraLLMProviderTests` uses `@testable import AuroraLLMProvider` to
reach the internal symbols — stub `LLMProvider` implementations,
`APIClient(provider:...)` injection, `AnthropicProvider` HTTP-stub
plumbing. Production code outside the module never sees any of those.
