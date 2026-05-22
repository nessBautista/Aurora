import Foundation

/// Namespace for pre-send message cleanup. Caseless enum — pure
/// static functions, never instantiated.
public enum MessageNormalizer {

    /// Cleans up the message list before sending to the API.
    ///
    /// Three jobs:
    ///  1. **Orphaned tool_use** — if an assistant message has a `tool_use`
    ///     with no matching `tool_result` anywhere, insert a placeholder
    ///     `"(cancelled)"` result. The Anthropic API requires every
    ///     `tool_use` to have a corresponding result, or it rejects the
    ///     request.
    ///  2. **Consecutive same-role messages** — the API requires strict
    ///     user/assistant alternation. Merge adjacent same-role messages by
    ///     concatenating their content arrays.
    ///  3. **Returns a new array** — does not mutate the input.
    ///
    /// `LLMProvider` conformances MUST call `MessageNormalizer.normalize`
    /// as the first step of `performRequest` — see the protocol contract
    /// in `LLMProvider.swift`.
    public static func normalize(_ messages: [Message]) -> [Message] {
        var result = messages

        // 1. Find all existing tool_result IDs
        var existingResultIds = Set<String>()
        for msg in result {
            for block in msg.content {
                if case .toolResult(let toolUseId, _) = block {
                    existingResultIds.insert(toolUseId)
                }
            }
        }

        // Insert placeholder results for orphaned tool_use blocks
        for msg in result {
            guard msg.role == "assistant" else { continue }
            for block in msg.content {
                if case .toolUse(let id, _, _) = block, !existingResultIds.contains(id) {
                    result.append(Message(
                        role: "user",
                        content: [.toolResult(toolUseId: id, content: "(cancelled)")]
                    ))
                    existingResultIds.insert(id)
                }
            }
        }

        // 2. Merge consecutive same-role messages
        guard !result.isEmpty else { return result }
        var merged = [result[0]]
        for msg in result.dropFirst() {
            if msg.role == merged[merged.count - 1].role {
                let combined = merged[merged.count - 1].content + msg.content
                merged[merged.count - 1] = Message(role: msg.role, content: combined)
            } else {
                merged.append(msg)
            }
        }

        return merged
    }
}
