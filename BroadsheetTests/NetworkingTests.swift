import XCTest
@testable import Broadsheet

final class HTTPTransportTests: XCTestCase {

    private var transport: URLSessionHTTPTransport!

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
        transport = URLSessionHTTPTransport.forTesting(protocolClasses: [URLProtocolStub.self])
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func url(_ string: String = "https://feeds.example.org/feed.xml") -> URL {
        URL(string: string)!
    }

    // MARK: HTTPS

    func testPlainHTTPIsRefusedBeforeAnyRequestIsMade() async {
        do {
            _ = try await transport.fetch(url("http://feeds.example.org/feed.xml"), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected an insecure-scheme error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .insecureScheme(scheme: "http"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(URLProtocolStub.requestedURLs.isEmpty, "Nothing should have been sent")
    }

    func testNonHTTPSchemeIsRefused() async {
        do {
            _ = try await transport.fetch(url("ftp://example.org/feed.xml"), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected an insecure-scheme error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .insecureScheme(scheme: "ftp"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Success

    func testSuccessfulFetchReturnsBodyAndMetadata() async throws {
        URLProtocolStub.respondingWith { _ in .text("<rss></rss>") }

        let result = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)

        XCTAssertEqual(result.statusCode, 200)
        XCTAssertEqual(result.text, "<rss></rss>")
        XCTAssertEqual(result.finalURL, url())
        XCTAssertEqual(result.redirectCount, 0)
    }

    func testRequestCarriesADescriptiveUserAgent() async throws {
        URLProtocolStub.respondingWith { _ in .text("<rss></rss>") }

        _ = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)

        let agent = try XCTUnwrap(URLProtocolStub.requestedUserAgents.first)
        XCTAssertTrue(agent.hasPrefix("Broadsheet/"), "Got \(agent)")
        XCTAssertTrue(agent.localizedCaseInsensitiveContains("news reader"))
    }

    func testDeclaredCharsetIsHonoured() async throws {
        let latin1 = "café".data(using: .isoLatin1)!
        URLProtocolStub.respondingWith { _ in
            .respond(status: 200, headers: ["Content-Type": "text/xml; charset=iso-8859-1"], body: latin1)
        }

        let result = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)
        XCTAssertEqual(result.text, "café")
    }

    // MARK: Status

    func testHTTPErrorStatusIsTyped() async {
        URLProtocolStub.respondingWith { _ in .respond(status: 503, body: Data("busy".utf8)) }

        do {
            _ = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected a status error")
        } catch let error as HTTPFetchError {
            guard case .httpStatus(let code, _) = error else { return XCTFail("Wrong case: \(error)") }
            XCTAssertEqual(code, 503)
            XCTAssertTrue(error.isTransient, "A 503 should be retried later, not treated as permanent")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testForbiddenIsNotTreatedAsTransient() async {
        URLProtocolStub.respondingWith { _ in .respond(status: 403, body: Data("no".utf8)) }

        do {
            _ = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected a status error")
        } catch let error as HTTPFetchError {
            XCTAssertFalse(error.isTransient)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmptyBodyIsAnError() async {
        URLProtocolStub.respondingWith { _ in .respond(status: 200, body: Data()) }

        do {
            _ = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected an empty-response error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .emptyResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Redirects

    func testRedirectIsFollowedAndCounted() async throws {
        let start = url("https://example.org/feed")
        let target = url("https://cdn.example.org/feed.xml")
        URLProtocolStub.respondingWith { request in
            request.url == start ? .redirect(to: target) : .text("<rss></rss>")
        }

        let result = try await transport.fetch(start, accept: HTTPAccept.feed, limits: .feed)

        XCTAssertEqual(result.finalURL, target)
        XCTAssertEqual(result.redirectCount, 1)
    }

    func testRedirectChainIsBounded() async {
        URLProtocolStub.respondingWith { request in
            let next = URL(string: (request.url?.absoluteString ?? "https://example.org/") + "x")!
            return .redirect(to: next)
        }

        do {
            _ = try await transport.fetch(
                url("https://example.org/"),
                accept: HTTPAccept.feed,
                limits: HTTPFetchLimits(maximumBytes: 1_000_000, timeout: 10, maximumRedirects: 3)
            )
            XCTFail("Expected a redirect-limit error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .tooManyRedirects(limit: 3))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRedirectToPlainHTTPIsRefused() async {
        let start = url("https://example.org/feed")
        URLProtocolStub.respondingWith { request in
            request.url == start ? .redirect(to: URL(string: "http://example.org/feed.xml")!) : .text("<rss/>")
        }

        do {
            _ = try await transport.fetch(start, accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected an insecure-redirect error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .insecureRedirect(to: "http://example.org/feed.xml"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Size

    func testDeclaredOversizeBodyIsRefusedWithoutReadingIt() async {
        let big = String(repeating: "a", count: 4096)
        URLProtocolStub.respondingWith { _ in
            .respond(status: 200, headers: ["Content-Length": "999999999"], body: Data(big.utf8))
        }

        do {
            _ = try await transport.fetch(
                url(),
                accept: HTTPAccept.feed,
                limits: HTTPFetchLimits(maximumBytes: 8_192, timeout: 10, maximumRedirects: 3)
            )
            XCTFail("Expected a size error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .responseTooLarge(limit: 8_192))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamedBodyIsAbandonedOnceItExceedsTheLimit() async {
        // No Content-Length, so the cap can only be enforced mid-stream.
        let chunk = Data(String(repeating: "b", count: 2_048).utf8)
        URLProtocolStub.respondingWith { _ in .chunked(status: 200, chunks: Array(repeating: chunk, count: 20)) }

        do {
            _ = try await transport.fetch(
                url(),
                accept: HTTPAccept.feed,
                limits: HTTPFetchLimits(maximumBytes: 4_096, timeout: 10, maximumRedirects: 3)
            )
            XCTFail("Expected a size error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .responseTooLarge(limit: 4_096))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: Transport failures

    func testTimeoutIsTyped() async {
        URLProtocolStub.respondingWith { _ in
            .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        }

        do {
            _ = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected a timeout")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .timedOut)
            XCTAssertTrue(error.isTransient)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOfflineIsTyped() async {
        URLProtocolStub.respondingWith { _ in
            .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        }

        do {
            _ = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected an offline error")
        } catch let error as HTTPFetchError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnknownTransportFailureKeepsItsMessage() async {
        URLProtocolStub.respondingWith { _ in
            .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed))
        }

        do {
            _ = try await transport.fetch(url(), accept: HTTPAccept.feed, limits: .feed)
            XCTFail("Expected a transport failure")
        } catch let error as HTTPFetchError {
            guard case .transportFailure(let message) = error else { return XCTFail("Wrong case: \(error)") }
            XCTAssertFalse(message.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class RobotsRulesTests: XCTestCase {

    func testWildcardGroupApplies() {
        let rules = RobotsRules.parse("""
        User-agent: *
        Disallow: /private/
        Allow: /private/public-note
        """, userAgentToken: "Broadsheet")

        XCTAssertTrue(rules.allows(path: "/news/story"))
        XCTAssertFalse(rules.allows(path: "/private/secret"))
        XCTAssertTrue(rules.allows(path: "/private/public-note"))
    }

    func testNamedGroupWinsOverWildcard() {
        let rules = RobotsRules.parse("""
        User-agent: *
        Disallow: /

        User-agent: Broadsheet
        Disallow: /admin
        """, userAgentToken: "Broadsheet")

        XCTAssertTrue(rules.allows(path: "/news/story"))
        XCTAssertFalse(rules.allows(path: "/admin/panel"))
    }

    func testEmptyDisallowPermitsEverything() {
        let rules = RobotsRules.parse("User-agent: *\nDisallow:", userAgentToken: "Broadsheet")
        XCTAssertTrue(rules.allows(path: "/anything"))
    }

    func testCommentsAndBlankLinesAreIgnored() {
        let rules = RobotsRules.parse("""
        # a comment
        User-agent: *

        Disallow: /x   # trailing comment
        """, userAgentToken: "Broadsheet")

        XCTAssertFalse(rules.allows(path: "/x/y"))
        XCTAssertTrue(rules.allows(path: "/y"))
    }

    func testWildcardAndEndAnchorPatterns() {
        let rules = RobotsRules.parse("""
        User-agent: *
        Disallow: /*.pdf$
        """, userAgentToken: "Broadsheet")

        XCTAssertFalse(rules.allows(path: "/docs/report.pdf"))
        XCTAssertTrue(rules.allows(path: "/docs/report.pdf.html"))
    }

    func testNoRobotsFileMeansUnrestricted() {
        XCTAssertTrue(RobotsRules.parse("", userAgentToken: "Broadsheet").allows(path: "/anything"))
    }
}

final class RobotsPolicyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    private func policy() -> RobotsPolicy {
        RobotsPolicy(transport: URLSessionHTTPTransport.forTesting(protocolClasses: [URLProtocolStub.self]))
    }

    func testDisallowedPathIsNotFetched() async {
        URLProtocolStub.map([
            "https://example.org/robots.txt": .text("User-agent: *\nDisallow: /premium/", contentType: "text/plain")
        ])

        let policy = policy()
        let allowed = await policy.isFetchAllowed(URL(string: "https://example.org/premium/story")!)
        XCTAssertFalse(allowed)
    }

    func testAllowedPathIsFetched() async {
        URLProtocolStub.map([
            "https://example.org/robots.txt": .text("User-agent: *\nDisallow: /premium/", contentType: "text/plain")
        ])

        let policy = policy()
        let allowed = await policy.isFetchAllowed(URL(string: "https://example.org/news/story")!)
        XCTAssertTrue(allowed)
    }

    func testMissingRobotsFileMeansAllowed() async {
        URLProtocolStub.respondingWith { _ in .respond(status: 404, body: Data("nope".utf8)) }

        let policy = policy()
        let allowed = await policy.isFetchAllowed(URL(string: "https://example.org/news/story")!)
        XCTAssertTrue(allowed)
    }

    /// An unreadable robots.txt is not permission. Broadsheet declines and the
    /// reader still gets the feed excerpt plus a link to the publisher.
    func testUnreadableRobotsFileMeansNotAllowed() async {
        URLProtocolStub.respondingWith { _ in .respond(status: 500, body: Data("boom".utf8)) }

        let policy = policy()
        let allowed = await policy.isFetchAllowed(URL(string: "https://example.org/news/story")!)
        XCTAssertFalse(allowed)
    }

    func testRulesAreFetchedOncePerHost() async {
        URLProtocolStub.map([
            "https://example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain")
        ])

        let policy = policy()
        _ = await policy.isFetchAllowed(URL(string: "https://example.org/a")!)
        _ = await policy.isFetchAllowed(URL(string: "https://example.org/b")!)

        let robotsRequests = URLProtocolStub.requestedURLs.filter { $0.path == "/robots.txt" }
        XCTAssertEqual(robotsRequests.count, 1)
    }
}
