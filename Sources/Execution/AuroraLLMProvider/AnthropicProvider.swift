/// # AnthropicProvider.swift — Direct Anthropic Messages API
///
/// Talks to `https://api.anthropic.com/v1/messages` directly. The
/// request/response shape is what Aurora's internal `ContentBlock` model is
/// designed around, so the translation is mostly identity.
///
/// ## Model lookup order
///
///   `ANTHROPIC_CHEAP_MODEL_ID` → `ANTHROPIC_MODEL_ID` → `MODEL_ID` (legacy)
///   → `"claude-sonnet-4-6"` (default).
///
/// `ANTHROPIC_CHEAP_MODEL_ID` is a deliberate "use cheap model" toggle for
/// expensive workflows (live integration tests, long agent loops); when set,
/// it always wins.
///
/// ## Timing dance
///
///   - `modelId` is **computed**, not captured at init — reads the env on
///     every access. `Config.load()` populates env from `.env` before any
///     `performRequest` runs, so model overrides in `.env` work.
///   - `apiKeySource` is **also computed**, but reads
///     `Config.originalKeySource(for: .anthropic)` which serves a snapshot
///     from BEFORE `Config.load()` mutated env. So the banner still shows
///     "keychain (Touch ID)" after the keychain value got copied into env.
///   - `apiKey` is read fresh in `performRequest`, not captured in init.
///   - No `fatalError` on missing key — `performRequest` sends an empty key
///     and lets Anthropic's 401 surface. Phase 5's CLI shapes that into a
///     setup hint.

import Foundation
import AuroraModels
import AuroraConfig

struct AnthropicProvider: LLMProvider {
    let name = "Anthropic"

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    internal let urlSession: URLSession

    init() {
        self.init(urlSession: .shared)
    }

    /// Test seam — production callers use the no-arg `init()` which routes
    /// to `URLSession.shared`. Tests inject a session backed by a URLProtocol
    /// stub to capture requests and synthesize responses.
    internal init(urlSession: URLSession) {
        self.urlSession = urlSession
    }

    var modelId: String {
        Self.resolveModelId()
    }

    var apiKeySource: String {
        Self.describe(Config.originalKeySource(for: .anthropic))
    }

    /// Centralized model-id resolution so `modelId` (the property the banner
    /// reads) and the `model` field in `performRequest` always agree.
    internal static func resolveModelId() -> String {
        ProcessInfo.processInfo.environment["ANTHROPIC_CHEAP_MODEL_ID"]
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_MODEL_ID"]
            ?? ProcessInfo.processInfo.environment["MODEL_ID"]
            ?? "claude-sonnet-4-6"
    }

    private static func describe(_ source: Config.KeySource) -> String {
        switch source {
        case .env:      return "env var"
        case .keychain: return "keychain (Touch ID)"
        case .envFile:  return ".env file"
        case .missing:  return "missing"
        }
    }

    func performRequest(
        messages: [Message],
        tools: [[String: Any]]?,
        systemPrompt: String?,
        forcedTool: ForcedTool? = nil
    ) async throws -> (stopReason: String, content: [ContentBlock]) {
        // Step 1 of the protocol contract: normalize first.
        let normalized = MessageNormalizer.normalize(messages)

        var body: [String: Any] = [
            "model": modelId,
            "max_tokens": 8000,
            "messages": encodeMessages(normalized),
        ]
        // Effective tools = caller's tools (regular tool loop) + the
        // synthetic submit_state tool when coercing. Anthropic requires
        // the forced tool be present in the `tools` array, otherwise the
        // request 400s.
        var effectiveTools = tools ?? []
        if let forced = forcedTool {
            effectiveTools.append(synthesizeForcedToolSchema(forced))
            // tool_choice is a per-request option, so earlier turns of the
            // agent loop can keep `tool_choice: auto` and only the
            // coercion turn flips to forcing the named tool.
            body["tool_choice"] = [
                "type": "tool",
                "name": forced.name,
                "disable_parallel_tool_use": true,
            ] as [String: Any]
        }
        if !effectiveTools.isEmpty { body["tools"] = effectiveTools }
        if let systemPrompt = systemPrompt { body["system"] = systemPrompt }

        // Read API key fresh — Config.load() may have populated it after init.
        let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Anthropic", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }

        if http.statusCode == 200 {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stopReason = json["stop_reason"] as? String,
                  let rawContent = json["content"] as? [[String: Any]] else {
                let preview = String(data: data, encoding: .utf8)?.prefix(500).description ?? ""
                throw BadResponse(provider: "Anthropic",
                                  detail: "missing stop_reason or content",
                                  bodyPreview: preview)
            }
            return (stopReason, parseContentBlocks(rawContent))
        }

        let text = String(data: data, encoding: .utf8) ?? "unknown error"

        // Transient: retry-worthy.
        if http.statusCode == 429 || (500...599).contains(http.statusCode) {
            throw TransientError(kind: "HTTP \(http.statusCode)", body: text)
        }
        if text.contains("overloaded_error") {
            throw TransientError(kind: "overloaded", body: text)
        }

        // Non-transient: fail fast.
        throw NSError(domain: "Anthropic", code: http.statusCode,
                      userInfo: [NSLocalizedDescriptionKey: text])
    }
}

/// Translate a `ForcedTool` into Anthropic's tool-definition shape with
/// `strict: true` engaged. Strict mode constrains the model's emitted JSON
/// to the schema at sampling time — missing required fields, wrong types,
/// and malformed JSON are eliminated by the API. The schema dialect
/// Anthropic accepts under strict mode is the documented subset (no
/// recursive `$ref`, no `if`/`then`/`else`, `additionalProperties: false`
/// required on every object); callers stay inside it.
///
/// `internal` — only `AnthropicProvider.performRequest` calls this.
internal func synthesizeForcedToolSchema(_ forced: ForcedTool) -> [String: Any] {
    [
        "name": forced.name,
        "description": forced.description,
        "strict": true,
        "input_schema": forced.schema,
    ]
}
