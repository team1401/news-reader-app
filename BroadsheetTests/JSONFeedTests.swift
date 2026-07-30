import XCTest
@testable import Broadsheet

final class JSONFeedParserTests: XCTestCase {

    private let feedURL = URL(string: "https://example.org/feed.json")!

    private func parse(_ json: String) throws -> ParsedFeed {
        try JSONFeedParser.parse(Data(json.utf8), feedURL: feedURL)
    }

    private let minimal = """
    {
      "version": "https://jsonfeed.org/version/1.1",
      "title": "Example Feed",
      "home_page_url": "https://example.org/",
      "feed_url": "https://example.org/feed.json",
      "description": "A feed for tests",
      "items": [
        {
          "id": "https://example.org/1",
          "url": "https://example.org/1",
          "title": "First item",
          "content_html": "<p>First body paragraph.</p><p>Second body paragraph.</p>",
          "summary": "A summary of the first item.",
          "date_published": "2026-07-27T10:30:00Z",
          "authors": [{ "name": "Ada Writer" }],
          "image": "https://example.org/1.jpg"
        }
      ]
    }
    """

    func testParsesChannelIdentity() throws {
        let feed = try parse(minimal)

        XCTAssertEqual(feed.format, .jsonFeed)
        XCTAssertEqual(feed.channelTitle, "Example Feed")
        XCTAssertEqual(feed.channelLink, URL(string: "https://example.org/"))
        XCTAssertEqual(feed.channelDescription, "A feed for tests")
    }

    func testParsesItemFields() throws {
        let item = try XCTUnwrap(parse(minimal).items.first)

        XCTAssertEqual(item.title, "First item")
        XCTAssertEqual(item.link, URL(string: "https://example.org/1"))
        XCTAssertEqual(item.guid, "https://example.org/1")
        XCTAssertEqual(item.summary, "A summary of the first item.")
        XCTAssertEqual(item.contentHTML, "<p>First body paragraph.</p><p>Second body paragraph.</p>")
        XCTAssertEqual(item.author, "Ada Writer")
        XCTAssertEqual(item.imageURL, URL(string: "https://example.org/1.jpg"))
        XCTAssertEqual(item.publishedAt, ISO8601DateFormatter().date(from: "2026-07-27T10:30:00Z"))
    }

    func testAcceptsJSONFeedVersionOne() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1","title":"Old","items":[
          {"id":"1","url":"https://example.org/a","title":"A","content_text":"Body."}]}
        """)
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].title, "A")
    }

    func testVersionOneSingularAuthorIsRead() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1","title":"Old","author":{"name":"Feed Author"},
         "items":[{"id":"1","url":"https://example.org/a","title":"A","content_text":"Body."}]}
        """)
        XCTAssertEqual(feed.items[0].author, "Feed Author")
    }

    func testItemAuthorWinsOverFeedAuthor() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1.1","title":"F","authors":[{"name":"Feed Author"}],
         "items":[{"id":"1","url":"https://example.org/a","title":"A","content_text":"Body.",
                   "authors":[{"name":"Item Author"}]}]}
        """)
        XCTAssertEqual(feed.items[0].author, "Item Author")
    }

    func testMultipleAuthorsAreJoined() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1.1","title":"F",
         "items":[{"id":"1","url":"https://example.org/a","title":"A","content_text":"Body.",
                   "authors":[{"name":"One"},{"name":"Two"}]}]}
        """)
        XCTAssertEqual(feed.items[0].author, "One, Two")
    }

    func testUntitledMicroblogItemBorrowsItsOpeningText() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1.1","title":"Microblog",
         "items":[{"id":"1","url":"https://example.org/a",
                   "content_html":"<p>An untitled note about the harbour.</p>"}]}
        """)
        XCTAssertEqual(feed.items[0].title, "An untitled note about the harbour.")
    }

    func testExternalURLIsNotUsedAsTheCanonicalLink() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1.1","title":"F",
         "items":[{"id":"https://example.org/a","external_url":"https://elsewhere.example/x",
                   "title":"A","content_text":"Body."}]}
        """)
        XCTAssertEqual(feed.items[0].link, URL(string: "https://example.org/a"))
    }

    func testUnparseableDateStaysNilRatherThanBecomingNow() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1.1","title":"F",
         "items":[{"id":"1","url":"https://example.org/a","title":"A","content_text":"Body.",
                   "date_published":"sometime last week"}]}
        """)
        XCTAssertNil(feed.items[0].publishedAt)
    }

    func testHTMLInSummaryIsNormalisedToPlainText() throws {
        let feed = try parse("""
        {"version":"https://jsonfeed.org/version/1.1","title":"F",
         "items":[{"id":"1","url":"https://example.org/a","title":"A",
                   "summary":"<p>Plain &amp; simple</p>","content_text":"Body."}]}
        """)
        XCTAssertEqual(feed.items[0].summary, "Plain & simple")
    }

    // MARK: Errors

    func testMalformedJSONIsTyped() {
        XCTAssertThrowsError(try parse("{ not json")) { error in
            guard case FeedParsingError.malformedJSON = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testJSONThatIsNotAFeedIsTyped() {
        XCTAssertThrowsError(try parse("{\"hello\":\"world\"}")) { error in
            XCTAssertEqual(error as? FeedParsingError, .notAJSONFeed)
        }
    }

    func testUnsupportedVersionIsTyped() {
        XCTAssertThrowsError(try parse("{\"version\":\"https://jsonfeed.org/version/9\",\"items\":[]}")) { error in
            XCTAssertEqual(error as? FeedParsingError, .unsupportedJSONFeedVersion("https://jsonfeed.org/version/9"))
        }
    }

    func testEmptyDocumentIsTyped() {
        XCTAssertThrowsError(try JSONFeedParser.parse(Data())) { error in
            XCTAssertEqual(error as? FeedParsingError, .emptyDocument)
        }
    }
}

final class FeedDocumentParserTests: XCTestCase {

    func testJSONIsDetectedFromTheBodyEvenWithAWrongContentType() throws {
        let json = """
        {"version":"https://jsonfeed.org/version/1.1","title":"F",
         "items":[{"id":"1","url":"https://example.org/a","title":"A","content_text":"Body."}]}
        """
        let feed = try FeedDocumentParser.parse(Data(json.utf8), contentType: "text/plain")
        XCTAssertEqual(feed.format, .jsonFeed)
    }

    func testXMLIsRoutedToTheXMLParser() throws {
        let rss = """
        <?xml version="1.0"?><rss version="2.0"><channel><title>T</title>
        <item><title>I</title><link>https://example.org/i</link></item></channel></rss>
        """
        let feed = try FeedDocumentParser.parse(Data(rss.utf8), contentType: "application/rss+xml")
        XCTAssertEqual(feed.format, .rss)
        XCTAssertEqual(feed.items.count, 1)
    }

    func testAtomIsRoutedToTheXMLParser() throws {
        let atom = """
        <?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>T</title>
        <entry><title>E</title><link rel="alternate" href="https://example.org/e"/></entry></feed>
        """
        let feed = try FeedDocumentParser.parse(Data(atom.utf8), contentType: nil)
        XCTAssertEqual(feed.format, .atom)
    }

    func testLeadingWhitespaceAndBOMDoNotConfuseDetection() throws {
        let json = "\u{FEFF}  {\"version\":\"https://jsonfeed.org/version/1.1\",\"title\":\"F\",\"items\":[]}"
        let feed = try FeedDocumentParser.parse(Data(json.utf8), contentType: nil)
        XCTAssertEqual(feed.format, .jsonFeed)
    }

    func testEmptyBodyIsTyped() {
        XCTAssertThrowsError(try FeedDocumentParser.parse(Data(), contentType: "application/json")) { error in
            XCTAssertEqual(error as? FeedParsingError, .emptyDocument)
        }
    }

    func testAnHTMLPageIsNotAFeed() {
        XCTAssertThrowsError(try FeedDocumentParser.parse(Data("<html><body>hi</body></html>".utf8), contentType: "text/html")) { error in
            guard case FeedParsingError.unsupportedFormat = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
    }
}
