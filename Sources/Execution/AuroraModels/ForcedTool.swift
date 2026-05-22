import Foundation

/// Request modifier: coerce the model into emitting structured output
/// matching `schema` by forcing it to call the synthetic tool `name`. The
/// returned `tool_use` block's input dict is the structured output the
/// caller wants.
///
/// Provider-neutral — each `LLMProvider` adapter translates this into the
/// equivalent on its wire format. The Anthropic path uses tool-use coercion
/// (synthetic tool with `strict: true` + `tool_choice: {type: "tool", name:
/// ...}`); OpenAI-family providers map to `response_format: json_schema`.
/// Providers without a structured-output mechanism may ignore the parameter
/// and rely on caller-side free-text JSON extraction.
///
/// `description` defaults to a generic submit-state description; callers
/// can override for tool-specific guidance the model sees as part of the
/// schema context.
public struct ForcedTool {
    public let name: String
    public let schema: [String: Any]
    public let description: String

    public init(
        name: String,
        schema: [String: Any],
        description: String = "Submit the final structured state extracted from this conversation."
    ) {
        self.name = name
        self.schema = schema
        self.description = description
    }
}
