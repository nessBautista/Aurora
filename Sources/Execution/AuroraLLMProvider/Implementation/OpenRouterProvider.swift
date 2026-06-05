/// Direct OpenRouter Chat Completions API adapter (OpenAI-compatible wire
/// format). See the module README for the model-id lookup order, retry
/// classification, and the credential/timing conventions shared by all
/// adapters.

import Foundation
import AuroraModels
import AuroraConfig

struct OpenRouterProvider: LLMProvider {
    let name = "OpenRouter"

    private let apiURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
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
        Self.describe(Config.originalKeySource(for: .openrouter))
    }

    /// Centralized model-id resolution so `modelId` (the banner property) and
    /// the `model` field in `performRequest` always agree.
    internal static func resolveModelId() -> String {
        ProcessInfo.processInfo.environment["OPENROUTER_CHEAP_MODEL_ID"]
            ?? ProcessInfo.processInfo.environment["OPENROUTER_MODEL_ID"]
            ?? ProcessInfo.processInfo.environment["MODEL_ID"]
            ?? "anthropic/claude-sonnet-4.6"
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

        // OpenAI-style messages: { role, content: "<string>" }. Multi-block
        // content (text + tool_use) needs a richer shape; the auth-flow scope
        // is single-shot text, so we flatten each message's content via
        // extractText. tool_use / tool_result round-trips are out of scope
        // for WOR-56 — see the TODO below.
        let oaMessages: [[String: Any]] = normalized.map { msg in
            ["role": msg.role, "content": extractText(msg.content)]
        }

        // System prompt — OpenAI puts it as a leading message with role
        // "system", not as a top-level field (unlike Anthropic's `system`).
        var allMessages = oaMessages
        if let systemPrompt = systemPrompt {
            allMessages.insert(["role": "system", "content": systemPrompt], at: 0)
        }

        // `max_completion_tokens` is OpenRouter's current field; `max_tokens`
        // is accepted but deprecated. (Anthropic's native adapter keeps
        // `max_tokens`.)
        let body: [String: Any] = [
            "model": modelId,
            "max_completion_tokens": 8000,
            "messages": allMessages,
        ]

        // TODO(future): map `forcedTool` to OpenRouter's
        // `response_format: { type: "json_schema", json_schema: ... }` (with
        // `provider: { require_parameters: true }` so it only routes to
        // providers that honor it). The auth-flow scope doesn't drive tools,
        // so we ignore both parameters for now; a unit test pins their
        // absence from the request body.
        _ = forcedTool
        _ = tools

        // Read API key fresh — Config.load() may have populated it after init.
        let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional OpenRouter attribution headers — dashboard rankings only,
        // NOT required for inference (requests succeed with both omitted).
        // Sent purely for attribution.
        request.setValue("https://github.com/nessBautista/aurora", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("aurora", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenRouter", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }

        if http.statusCode == 200 {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let messageJSON = firstChoice["message"] as? [String: Any],
                  let content = messageJSON["content"] as? String else {
                let preview = String(data: data, encoding: .utf8)?.prefix(500).description ?? ""
                throw BadResponse(provider: "OpenRouter",
                                  detail: "missing choices[0].message.content",
                                  bodyPreview: preview)
            }
            let finishReason = firstChoice["finish_reason"] as? String ?? "stop"
            let stopReason = mapOpenRouterFinishReason(finishReason)
            return (stopReason, [.text(content)])
        }

        let text = String(data: data, encoding: .utf8) ?? "unknown error"

        // Transient: retry-worthy. Status-code ONLY — OpenRouter has no
        // body-level "overloaded"/"insufficient_quota" marker. Retryable:
        // 408 (timeout), 429 (rate limit), 5xx (502 upstream down /
        // 503 no-provider).
        if http.statusCode == 408 || http.statusCode == 429 || (500...599).contains(http.statusCode) {
            throw TransientError(kind: "HTTP \(http.statusCode)", body: text)
        }

        // Non-transient: fail fast. 400 (incl. unknown model — OpenRouter
        // returns 400 "not a valid model ID"), 401 (bad key), 402 (out of
        // credits — TERMINAL, never retry), 403 (moderation/guardrail), 404.
        // The CLI shapes 401/402/403 into a setup hint via AgentAuth.keyStatus.
        throw NSError(domain: "OpenRouter", code: http.statusCode,
                      userInfo: [NSLocalizedDescriptionKey: text])
    }
}

/// Map OpenAI's finish-reason vocabulary to Aurora's (Anthropic-aligned)
/// stop-reason vocabulary. Adapters are contractually responsible for this
/// translation — see the `LLMProvider` protocol's stop-reason docstring.
///
/// `internal` — only `OpenRouterProvider.performRequest` calls this.
internal func mapOpenRouterFinishReason(_ openAI: String) -> String {
    switch openAI {
    case "stop":            return "end_turn"
    case "length":          return "max_tokens"
    case "tool_calls":      return "tool_use"
    case "content_filter":  return "content_filter"
    default:                return openAI   // forward unknown values verbatim
    }
}
