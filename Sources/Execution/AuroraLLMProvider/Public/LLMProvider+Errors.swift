import Foundation

/// Retry-worthy failure (HTTP 429, 5xx, `overloaded_error`, embedded
/// mid-response error). The retry loop in `APIClient.swift` catches this
/// specifically — other errors propagate immediately.
public struct TransientError: LocalizedError {
    public let kind: String
    public let body: String

    public init(kind: String, body: String) {
        self.kind = kind
        self.body = body
    }

    public var errorDescription: String? {
        "API \(kind) — all retries exhausted. The service may be overloaded; try again in a minute."
    }
}

/// Provider returned a response we couldn't parse defensively. Not
/// retry-worthy — usually means a translation bug or schema mismatch.
public struct BadResponse: LocalizedError {
    public let provider: String
    public let detail: String
    public let bodyPreview: String

    public init(provider: String, detail: String, bodyPreview: String) {
        self.provider = provider
        self.detail = detail
        self.bodyPreview = bodyPreview
    }

    public var errorDescription: String? {
        "\(provider): \(detail). Body preview: \(bodyPreview)"
    }
}
