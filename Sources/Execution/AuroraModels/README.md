# AuroraModels

Wire-format value types and pure helpers shared between `AuroraLLMProvider`
(Tier 3) and the forthcoming `AuroraAgent` (Tier 2). One module so both
can depend on the same `Message` / `ContentBlock` types without an upward
edge.

The vocabulary tracks the Anthropic Messages API (`"user"` /
`"assistant"` roles; `text` / `tool_use` / `tool_result` blocks); other
providers' adapters translate to and from these types.

*Every file in this module is part of the public surface (`Public/`).*

## `Message`

One conversational turn — a role plus its content blocks.

```swift
public struct Message {
    public let role: String
    public let content: [ContentBlock]
}

let userTurn = Message(role: "user", content: [.text("hello")])

let assistantTurn = Message(role: "assistant", content: [
    .text("Let me check that."),
    .toolUse(id: "tu_1", name: "read_file", input: ["path": "/etc/hosts"]),
])
```

`role` is a string, not an enum, so adapters can round-trip
provider-specific role names verbatim.

## `ContentBlock`

The three-case enum that mirrors Anthropic's `content` array. Every block
in a message is exactly one of these.

```swift
public enum ContentBlock {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
    case toolResult(toolUseId: String, content: String)
}
```

| Case | When | Carries |
|---|---|---|
| `.text` | Plain prose, either direction | The string |
| `.toolUse` | Assistant requested a tool call | Synthetic id, tool name, arg dict |
| `.toolResult` | User reply with a tool's output | The id of the matching `.toolUse` + output string |

## `encodeBlock` / `encodeMessages`

Encode Aurora types into the dictionary shape the Messages API expects on
the request body. Pure — no I/O, no global state.

```swift
public func encodeBlock(_ block: ContentBlock) -> [String: Any]
public func encodeMessages(_ messages: [Message]) -> [[String: Any]]

let body: [String: Any] = [
    "model": "claude-sonnet-4-6",
    "messages": encodeMessages(history),
]
```

## `parseContentBlocks`

Decode a 200-response's `content` array back into `[ContentBlock]`.
Unknown block types are silently dropped — forward-compatible with future
provider features.

```swift
public func parseContentBlocks(_ raw: [[String: Any]]) -> [ContentBlock]

let raw = responseJSON["content"] as? [[String: Any]] ?? []
let blocks = parseContentBlocks(raw)
```

## `extractText`

Flatten a content array to a single string — every `.text` block joined
with newlines. Convenience for callers that only want the assistant's
prose (e.g., the auth-flow `Agent.chat(String) -> String` path).

```swift
public func extractText(_ content: [ContentBlock]) -> String

// "Hello there\nFollow-up question?"
extractText([.text("Hello there"), .text("Follow-up question?")])
```

## `MessageNormalizer`

Caseless-enum namespace for one pure pre-send cleanup pass. `LLMProvider`
conformances MUST call this as the first step of `performRequest`.

```swift
public enum MessageNormalizer {
    public static func normalize(_ messages: [Message]) -> [Message]
}

let clean = MessageNormalizer.normalize(history)
```

Three jobs:

1. **Orphaned `tool_use` → placeholder result.** If an assistant message
   has a `.toolUse` with no matching `.toolResult` anywhere in the list,
   append `.toolResult(toolUseId: …, content: "(cancelled)")` so the API
   doesn't reject the request.
2. **Merge same-role neighbors.** Anthropic requires strict
   user/assistant alternation; adjacent same-role messages get their
   `content` arrays concatenated.
3. **Pure.** Returns a new array; never mutates input.

## `ForcedTool`

Request modifier: coerce the model into emitting structured output by
making it call a synthetic tool whose schema describes the desired shape.
Provider-neutral — adapters translate.

```swift
public struct ForcedTool {
    public let name: String
    public let schema: [String: Any]
    public let description: String
}

let forced = ForcedTool(
    name: "submit_state",
    schema: [
        "type": "object",
        "properties": [
            "step": ["type": "string"],
            "done": ["type": "boolean"],
        ],
        "required": ["step", "done"],
    ]
)

let (_, blocks) = try await client.callAPI(
    messages: history,
    tools: nil,
    systemPrompt: prompt,
    forcedTool: forced
)
// The resulting .toolUse block's `input` dict is the structured output.
```

Anthropic adapters translate to tool-use coercion (`tool_choice` +
`strict: true`); OpenAI-family adapters translate to
`response_format: json_schema`.
