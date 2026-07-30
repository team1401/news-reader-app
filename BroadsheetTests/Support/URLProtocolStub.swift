import Foundation

/// A `URLProtocol` that answers from a script instead of the network.
///
/// Every networking test runs through the real ``URLSessionHTTPTransport`` — the
/// real redirect delegate, the real byte cap, the real status handling — and only
/// the bytes on the wire are stubbed. Nothing here reaches a publisher.
final class URLProtocolStub: URLProtocol {
    enum Outcome {
        case respond(status: Int, headers: [String: String] = [:], body: Data)
        case chunked(status: Int, headers: [String: String] = [:], chunks: [Data])
        case redirect(to: URL, status: Int = 302)
        case failure(NSError)

        static func text(_ body: String, status: Int = 200, contentType: String = "application/rss+xml") -> Outcome {
            .respond(status: status, headers: ["Content-Type": contentType], body: Data(body.utf8))
        }
    }

    /// Set by each test before it drives the transport. Serialized by XCTest's
    /// one-test-at-a-time execution.
    nonisolated(unsafe) static var handler: ((URLRequest) -> Outcome)?
    nonisolated(unsafe) static private(set) var requestedURLs: [URL] = []
    nonisolated(unsafe) static private(set) var requestedUserAgents: [String] = []

    static func reset() {
        handler = nil
        requestedURLs = []
        requestedUserAgents = []
    }

    static func respondingWith(_ outcome: @escaping (URLRequest) -> Outcome) {
        handler = outcome
    }

    static func map(_ responses: [String: Outcome]) {
        handler = { request in
            guard let url = request.url else { return .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL)) }
            if let exact = responses[url.absoluteString] { return exact }
            return .respond(status: 404, body: Data("not found".utf8))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        URLProtocolStub.requestedURLs.append(url)
        if let agent = request.value(forHTTPHeaderField: "User-Agent") {
            URLProtocolStub.requestedUserAgents.append(agent)
        }

        guard let outcome = URLProtocolStub.handler?(request) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL))
            return
        }

        switch outcome {
        case .respond(let status, let headers, let body):
            send(status: status, headers: headers, chunks: body.isEmpty ? [] : [body], url: url)

        case .chunked(let status, let headers, let chunks):
            send(status: status, headers: headers, chunks: chunks, url: url)

        case .redirect(let target, let status):
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString]
            )!
            var followed = URLRequest(url: target)
            followed.httpMethod = request.httpMethod
            client?.urlProtocol(self, wasRedirectedTo: followed, redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func send(status: Int, headers: [String: String], chunks: [Data], url: URL) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
