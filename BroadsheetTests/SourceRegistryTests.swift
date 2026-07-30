import XCTest
@testable import Broadsheet

final class FeedURLNormalizerTests: XCTestCase {

    func testCasingPortAndTrailingSlashCollapse() {
        let a = FeedURLNormalizer.key(for: URL(string: "https://Feeds.Example.ORG:443/news/rss.xml/")!)
        let b = FeedURLNormalizer.key(for: URL(string: "https://feeds.example.org/news/rss.xml")!)
        XCTAssertEqual(a, b)
    }

    /// A feed's query routinely selects the edition. Dropping it would silently
    /// subscribe the reader to a different feed.
    func testQueryParametersAreKept() {
        let international = FeedURLNormalizer.key(for: URL(string: "https://feeds.bbci.co.uk/news/rss.xml?edition=int")!)
        let plain = FeedURLNormalizer.key(for: URL(string: "https://feeds.bbci.co.uk/news/rss.xml")!)
        XCTAssertNotEqual(international, plain)
        XCTAssertTrue(international.contains("edition=int"))
    }

    func testFragmentAndCredentialsAreDropped() {
        let key = FeedURLNormalizer.key(for: URL(string: "https://feeds.example.org/rss.xml#top")!)
        XCTAssertEqual(key, "https://feeds.example.org/rss.xml")
    }

    func testQueryOrderDoesNotChangeIdentity() {
        let a = FeedURLNormalizer.key(for: URL(string: "https://example.org/f?b=2&a=1")!)
        let b = FeedURLNormalizer.key(for: URL(string: "https://example.org/f?a=1&b=2")!)
        XCTAssertEqual(a, b)
    }
}

final class FeedDiscoveryTests: XCTestCase {

    private let base = URL(string: "https://example.org/news")!

    func testFindsAdvertisedRSSAtomAndJSONFeeds() {
        let html = """
        <html><head>
          <link rel="alternate" type="application/rss+xml" title="Example RSS" href="/feed.xml">
          <link rel="alternate" type="application/atom+xml" title="Example Atom" href="https://example.org/atom.xml">
          <link rel="alternate" type="application/feed+json" href="//example.org/feed.json">
          <link rel="stylesheet" href="/style.css">
          <link rel="alternate" type="text/html" hreflang="fr" href="/fr">
        </head><body></body></html>
        """

        let links = FeedDiscovery.links(inHTML: html, baseURL: base)

        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(links[0].url, URL(string: "https://example.org/feed.xml"))
        XCTAssertEqual(links[0].title, "Example RSS")
        XCTAssertEqual(links[1].url, URL(string: "https://example.org/atom.xml"))
        XCTAssertEqual(links[2].url, URL(string: "https://example.org/feed.json"))
    }

    func testIgnoresNonAlternateLinks() {
        let html = "<link rel=\"canonical\" type=\"application/rss+xml\" href=\"/nope.xml\">"
        XCTAssertTrue(FeedDiscovery.links(inHTML: html, baseURL: base).isEmpty)
    }

    func testDoesNotMatchTagsThatMerelyStartWithLink() {
        let html = "<linkedin type=\"application/rss+xml\" rel=\"alternate\" href=\"/nope.xml\"></linkedin>"
        XCTAssertTrue(FeedDiscovery.links(inHTML: html, baseURL: base).isEmpty)
    }

    func testFindsFooterAnchorsThatPlainlyPointAtAFeed() {
        let html = "<html><body><a href=\"/blog/feed\">Subscribe</a><a href=\"/about\">About</a></body></html>"
        let links = FeedDiscovery.links(inHTML: html, baseURL: base)

        XCTAssertEqual(links.map(\.url), [URL(string: "https://example.org/blog/feed")])
    }

    func testDuplicatesCollapse() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
        <link rel="alternate" type="application/rss+xml" href="https://example.org/feed.xml/">
        """
        XCTAssertEqual(FeedDiscovery.links(inHTML: html, baseURL: base).count, 1)
    }

    func testUnquotedAndSingleQuotedAttributesAreRead() {
        let html = "<link rel=alternate type='application/rss+xml' href=/feed.xml>"
        XCTAssertEqual(FeedDiscovery.links(inHTML: html, baseURL: base).map(\.url), [URL(string: "https://example.org/feed.xml")])
    }

    func testEntityEncodedHrefIsDecoded() {
        let html = "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"/feed.xml?a=1&amp;b=2\">"
        XCTAssertEqual(
            FeedDiscovery.links(inHTML: html, baseURL: base).first?.url,
            URL(string: "https://example.org/feed.xml?a=1&b=2")
        )
    }

    func testJavaScriptAndDataURLsAreRefused() {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="javascript:alert(1)">
        <link rel="alternate" type="application/rss+xml" href="data:text/xml,<rss/>">
        """
        XCTAssertTrue(FeedDiscovery.links(inHTML: html, baseURL: base).isEmpty)
    }
}

final class SourceValidatorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func validator() -> SourceValidator {
        SourceValidator(transport: URLSessionHTTPTransport.forTesting(protocolClasses: [URLProtocolStub.self]))
    }

    private let rss = """
    <?xml version="1.0"?>
    <rss version="2.0"><channel>
      <title>Example News</title><link>https://example.org</link>
      <item><title>One</title><link>https://example.org/1</link><pubDate>Mon, 27 Jul 2026 09:00:00 GMT</pubDate></item>
      <item><title>Two</title><link>https://example.org/2</link><pubDate>Mon, 27 Jul 2026 08:00:00 GMT</pubDate></item>
    </channel></rss>
    """

    // MARK: Address normalization

    func testBareHostBecomesHTTPS() throws {
        XCTAssertEqual(
            try SourceValidator.normalizedURL(from: " example.org/feed.xml "),
            URL(string: "https://example.org/feed.xml")
        )
    }

    func testFeedSchemeBecomesHTTPS() throws {
        XCTAssertEqual(
            try SourceValidator.normalizedURL(from: "feed://example.org/rss"),
            URL(string: "https://example.org/rss")
        )
    }

    /// An explicit `http://` is refused rather than silently upgraded: the reader
    /// should know the address they subscribed to.
    func testExplicitHTTPIsRefused() {
        XCTAssertThrowsError(try SourceValidator.normalizedURL(from: "http://example.org/feed")) { error in
            XCTAssertEqual(error as? SourceValidationError, .insecureAddress("http://example.org/feed"))
        }
    }

    func testEmptyAndNonsenseAddressesAreRefused() {
        XCTAssertThrowsError(try SourceValidator.normalizedURL(from: "   ")) { error in
            XCTAssertEqual(error as? SourceValidationError, .emptyAddress)
        }
        XCTAssertThrowsError(try SourceValidator.normalizedURL(from: "not a url")) { error in
            guard case SourceValidationError.invalidAddress = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    // MARK: Validation

    func testADirectFeedIsValidatedAndDescribed() async throws {
        URLProtocolStub.map(["https://example.org/feed.xml": .text(rss)])

        let candidates = try await validator().candidates(for: "example.org/feed.xml")

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].title, "Example News")
        XCTAssertEqual(candidates[0].format, .rss)
        XCTAssertEqual(candidates[0].itemCount, 2)
        XCTAssertEqual(candidates[0].siteURL, URL(string: "https://example.org"))
        XCTAssertFalse(candidates[0].carriesFullContent)
    }

    func testFullContentFeedsAreFlaggedBeforeSaving() async throws {
        let body = String(repeating: "A long paragraph of article prose. ", count: 40)
        let fullFeed = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>
          <title>Full Feed</title><link>https://example.org</link>
          <item><title>One</title><link>https://example.org/1</link>
            <content:encoded><![CDATA[<p>\(body)</p>]]></content:encoded></item>
        </channel></rss>
        """
        URLProtocolStub.map(["https://example.org/feed.xml": .text(fullFeed)])

        let candidates = try await validator().candidates(for: "https://example.org/feed.xml")
        XCTAssertTrue(candidates[0].carriesFullContent)
    }

    func testAPublisherPageYieldsItsAdvertisedFeeds() async throws {
        let page = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="Example News" href="/feed.xml">
        </head><body>Hello</body></html>
        """
        URLProtocolStub.map([
            "https://example.org": .text(page, contentType: "text/html"),
            "https://example.org/feed.xml": .text(rss)
        ])

        let candidates = try await validator().candidates(for: "example.org")

        XCTAssertEqual(candidates.map(\.feedURL.absoluteString), ["https://example.org/feed.xml"])
    }

    func testAPageWithNoFeedsIsReportedHonestly() async {
        URLProtocolStub.map(["https://example.org": .text("<html><body>nothing here</body></html>", contentType: "text/html")])

        do {
            _ = try await validator().candidates(for: "example.org")
            XCTFail("Expected a discovery failure")
        } catch let error as SourceValidationError {
            XCTAssertEqual(error, .noFeedsDiscovered(page: "example.org"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNetworkFailureIsReportedAsSuch() async {
        URLProtocolStub.respondingWith { _ in .respond(status: 500, body: Data("boom".utf8)) }

        do {
            _ = try await validator().candidates(for: "example.org/feed.xml")
            XCTFail("Expected a network failure")
        } catch let error as SourceValidationError {
            guard case .network(let underlying) = error else { return XCTFail("Wrong case: \(error)") }
            guard case .httpStatus(let code, _) = underlying else { return XCTFail("Wrong case: \(underlying)") }
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAnEmptyFeedIsNotAcceptedAsASource() async {
        let empty = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Empty</title></channel></rss>"
        URLProtocolStub.map(["https://example.org/feed.xml": .text(empty)])

        do {
            _ = try await validator().validateFeed(at: URL(string: "https://example.org/feed.xml")!)
            XCTFail("Expected a not-a-feed error")
        } catch let error as SourceValidationError {
            guard case .notAFeed(let reason) = error else { return XCTFail("Wrong case: \(error)") }
            XCTAssertEqual(reason, "The feed contained no items.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDiscoveryIsBounded() async throws {
        var responses: [String: URLProtocolStub.Outcome] = [:]
        var links = ""
        for index in 0..<20 {
            links += "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"/feed\(index).xml\">"
            responses["https://example.org/feed\(index).xml"] = .text(rss)
        }
        responses["https://example.org"] = .text("<html><head>\(links)</head></html>", contentType: "text/html")
        URLProtocolStub.map(responses)

        let candidates = try await validator().candidates(for: "example.org")

        XCTAssertEqual(candidates.count, SourceValidator.maximumDiscoveredFeeds)
    }

    func testJSONFeedIsValidated() async throws {
        let json = """
        {"version":"https://jsonfeed.org/version/1.1","title":"JSON News","home_page_url":"https://example.org",
         "items":[{"id":"1","url":"https://example.org/1","title":"One","content_text":"Body."}]}
        """
        URLProtocolStub.map(["https://example.org/feed.json": .text(json, contentType: "application/feed+json")])

        let candidates = try await validator().candidates(for: "https://example.org/feed.json")
        XCTAssertEqual(candidates[0].format, .jsonFeed)
        XCTAssertEqual(candidates[0].title, "JSON News")
    }
}
