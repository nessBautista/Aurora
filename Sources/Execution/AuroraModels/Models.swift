import Foundation

/// One conversational turn — role plus its content blocks.
/// Role values track the Anthropic vocabulary: `"user"`, `"assistant"`.
public struct Message {
    public let role: String
    public let content: [ContentBlock]

    public init(role: String, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }
}

/// Aurora's internal representation of one block within a message.
/// The three cases mirror Anthropic's `content` array; OpenRouter (Phase 6)
/// will map to the same set via its OpenAI-compatible adapter.
public enum ContentBlock {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
    case toolResult(toolUseId: String, content: String)
}

// MARK: - JSON encoding

/// Encode one block to the dictionary shape Anthropic's request body expects.
public func encodeBlock(_ block: ContentBlock) -> [String: Any] {
    switch block {
    case .text(let text):
        return ["type": "text", "text": text]
    case .toolUse(let id, let name, let input):
        return ["type": "tool_use", "id": id, "name": name, "input": input]
    case .toolResult(let toolUseId, let content):
        return ["type": "tool_result", "tool_use_id": toolUseId, "content": content]
    }
}

/// Encode the messages array for the `messages` field of a Messages-API request.
public func encodeMessages(_ messages: [Message]) -> [[String: Any]] {
    messages.map { msg in
        ["role": msg.role, "content": msg.content.map(encodeBlock)]
    }
}

/// Parse the `content` array from a 200 response back into Aurora's
/// `ContentBlock` enum. Unknown block types are dropped — forward-compatible
/// with future Anthropic features.
public func parseContentBlocks(_ raw: [[String: Any]]) -> [ContentBlock] {
    raw.compactMap { dict in
        guard let type = dict["type"] as? String else { return nil }
        switch type {
        case "text":
            guard let text = dict["text"] as? String else { return nil }
            return .text(text)
        case "tool_use":
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let input = dict["input"] as? [String: Any] else { return nil }
            return .toolUse(id: id, name: name, input: input)
        default:
            return nil
        }
    }
}

/// Concatenate every `.text` block's payload with newlines. Convenience for
/// callers that only care about the assistant's prose response (the auth-flow
/// `Agent.chat(String) -> String` path).
public func extractText(_ content: [ContentBlock]) -> String {
    content.compactMap { block in
        if case .text(let t) = block { return t }
        return nil
    }.joined(separator: "\n")
}
