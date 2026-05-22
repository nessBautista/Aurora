import Foundation

/// URLProtocol-based HTTP stub. Tests register a handler that turns each
/// outgoing request into a synthesized (response, body) pair, and can
/// inspect captured requests afterwards.
///
/// Usage:
///   override func setUp()    { HTTPStub.reset(); session = HTTPStub.makeSession() }
///   override func tearDown() { HTTPStub.reset() }
///   HTTPStub.handler = { request in (HTTPURLResponse(...)!, Data(...)) }
///
/// Not thread-safe across parallel test classes — handler is a single static.
/// Within a single XCTestCase class, XCTest runs methods sequentially, so
/// this is fine.
final class HTTPStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?
    nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

    static func reset() {
        handler = nil
        capturedRequests = []
    }

    /// URLSession that routes every request through HTTPStub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStub.self]
        return URLSession(configuration: config)
    }

    /// URLSession converts httpBody Data into an httpBodyStream when handing
    /// the request to the URLProtocol, so tests have to read the stream to
    /// recover the body bytes.
    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) }
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capturedRequests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "HTTPStub", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "no handler set"]
            ))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
