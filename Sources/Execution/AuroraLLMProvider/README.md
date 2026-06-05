# AuroraLLMProvider

The wire-format adapter layer. Adapters translate Aurora's internal
`Message` / `ContentBlock` model (defined in `AuroraModels`) to and from a
specific LLM provider's request/response shape.

*Public surface lives in `Public/`; implementation details in `Implementation/`; production composition in `Factory/`.*

## Public API

```swift
APIClient                                         // facade — owns provider + retry loop
try await client.callAPI(messages:tools:systemPrompt:forcedTool:)
    -> (String, [ContentBlock])                    // one round-trip with retry
client.bootInfo -> BootInfo                       // provider name / modelId / key source

BootInfo(providerName:modelId:apiKeySource:)     // value type for the startup banner

TransientError(kind:body:)                        // retry-worthy failure (thrown by callAPI)
BadResponse(provider:detail:bodyPreview:)         // unparseable response (thrown by callAPI)

makeAPIClient(for: Config.Provider) -> APIClient // production composition (Factory/)
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
  `makeLLMProvider(for:)` inside the module.

## Adapters

Each adapter is an `internal struct` conforming to `LLMProvider`. They share
the same shape and credential/timing conventions; only the wire format
differs. Adding one is a pure internal change (see the section above).

### Shared conventions

- **`modelId` is computed on every access**, not captured at init — it reads
  the environment each time, so model overrides loaded from `.env` (via
  `Config.loadEnvironment()`) take effect for requests issued after load.
- **`apiKeySource` is computed** from `Config.originalKeySource(for:)`, a
  snapshot taken *before* `Config.loadKey(for:)` copies a keychain value into the
  environment. This keeps the boot banner honest — it still reports
  "keychain (Touch ID)" rather than "env var" after load.
- **`apiKey` is read fresh inside `performRequest`**, never captured at init,
  for the same post-load reason.
- **No `fatalError` on a missing key.** `performRequest` sends an empty
  credential and lets the provider's `401` surface; the CLI shapes that into
  a setup hint via `AgentAuth.keyStatus`.
- **`performRequest` normalizes first** (`MessageNormalizer.normalize`) per
  the `LLMProvider` contract, then encodes to the provider's wire format.

### AnthropicProvider

Direct Anthropic Messages API — `POST https://api.anthropic.com/v1/messages`.
The request/response shape is what `ContentBlock` was designed around, so the
translation is mostly identity (`encodeMessages` / `parseContentBlocks`).

**Model-id lookup order:**

```
ANTHROPIC_CHEAP_MODEL_ID → ANTHROPIC_MODEL_ID → MODEL_ID → "claude-sonnet-4-6"
```

`ANTHROPIC_CHEAP_MODEL_ID` is a deliberate "use the cheap model" toggle for
expensive workflows (live integration tests, long agent loops); when set it
always wins.

Structured output (`forcedTool`) uses tool-use coercion: a synthetic tool
with `strict: true` plus `tool_choice: {type: "tool", name: ...}`
(`synthesizeForcedToolSchema`).

### OpenRouterProvider

Direct OpenRouter Chat Completions API —
`POST https://openrouter.ai/api/v1/chat/completions`. The wire format is
**OpenAI-compatible**, so it differs from Anthropic's in several ways:

- **Auth:** `Authorization: Bearer <key>` (not `x-api-key`).
- **Messages:** `content` is a plain **string**, not an array of blocks —
  Aurora's `[ContentBlock]` is flattened via `extractText`.
- **System prompt:** a leading message with `role: "system"`, **not** a
  top-level `system` field.
- **Response:** read from `choices[0].message.content`; the stop signal is
  `choices[0].finish_reason`, mapped to Aurora's (Anthropic-aligned)
  stop-reason vocabulary by `mapOpenRouterFinishReason`.
- **Token limit:** `max_completion_tokens` (OpenRouter's current field;
  `max_tokens` is accepted but deprecated — Anthropic's adapter still uses
  `max_tokens`).
- **Attribution headers:** `HTTP-Referer` / `X-Title` are sent but are
  **optional** — dashboard rankings only, not required for inference.

**Model-id lookup order:**

```
OPENROUTER_CHEAP_MODEL_ID → OPENROUTER_MODEL_ID → MODEL_ID → "anthropic/claude-sonnet-4.6"
```

OpenRouter identifiers are namespaced (`<provider>/<model>`) and use **dots**
in the version (`claude-sonnet-4.6`), unlike Anthropic's native **dashes**
(`claude-sonnet-4-6`). A bare `claude-sonnet-4-6` won't route — it needs both
the `anthropic/` prefix and the dot form. (`anthropic/claude-sonnet-4` exists
but is a drifting family alias that advances with each release — don't pin to
it.)

**Retry classification (status-code only).** OpenRouter has no body-level
"overloaded"/"insufficient_quota" marker, so classification is purely by HTTP
status:

| Status | Meaning | Handling |
|---|---|---|
| 408 / 429 / 5xx | timeout / rate limit / upstream down / no provider | **transient** → `TransientError` (retried by `APIClient`) |
| 400 | bad request (incl. unknown model: "not a valid model ID") | terminal |
| 401 | invalid / missing key | terminal |
| 402 | out of credits | terminal (never retried) |
| 403 | moderation / guardrail | terminal |
| 404 | not found | terminal |

**Structured output is not yet driven.** `tools` and `forcedTool` are accepted
but ignored for now (the current scope is single-shot text). The future
mapping is `response_format: { type: "json_schema", json_schema: ... }` with
`provider: { require_parameters: true }`, so the request only routes to
providers that honor the schema.

## Files

| File | Holds | Access |
|---|---|---|
| `Implementation/LLMProvider.swift` | `LLMProvider` protocol (module-private DI seam) | `internal` |
| `Public/LLMProvider+Errors.swift` | `TransientError`, `BadResponse` | `public` |
| `Implementation/AnthropicProvider.swift` | `AnthropicProvider` concrete adapter | `internal` |
| `Implementation/OpenRouterProvider.swift` | `OpenRouterProvider` concrete adapter — OpenAI-compatible | `internal` |
| `Public/APIClient.swift` | `APIClient`, `BootInfo` | `public` |
| `Factory/APIClientFactory.swift` | `makeAPIClient()` (public) + `makeLLMProvider()` (internal) — production composition | mixed |

Production composition lives in `Factory/`: `makeAPIClient()` wires the
public client, and the internal `makeLLMProvider()` it calls is the only
place production code resolves a `Config.Provider` to a concrete adapter.
Everything else takes its collaborators by injection; tests construct
`APIClient(provider:backoffSeconds:)` directly with a stub.

## Tests

`AuroraLLMProviderTests` uses `@testable import AuroraLLMProvider` to
reach the internal symbols — stub `LLMProvider` implementations,
`APIClient(provider:...)` injection, `AnthropicProvider` HTTP-stub
plumbing. Production code outside the module never sees any of those.
