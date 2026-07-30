import XCTest
@testable import Broadsheet

final class FeedParserTests: XCTestCase {

    // MARK: Fixtures

    private let rssFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>Meridian Wire — Energy</title>
        <link>https://meridianwire.example/energy</link>
        <description>Energy coverage from Meridian Wire.</description>
        <item>
          <title>Grid Operators Warn Reserve Margins Are Thin</title>
          <link>https://meridianwire.example/energy/reserve-margins?utm_source=rss&amp;utm_medium=feed</link>
          <guid isPermaLink="false">meridian-2026-07-29-001</guid>
          <description>&lt;p&gt;Three operators told regulators that August reserves fall &lt;em&gt;below&lt;/em&gt; target.&lt;/p&gt;&lt;p&gt;A hearing is scheduled.&lt;/p&gt;</description>
          <content:encoded><![CDATA[<p>Three operators told regulators that August reserves fall below target.</p><p>A hearing is scheduled for 21 August.</p>]]></content:encoded>
          <pubDate>Wed, 29 Jul 2026 14:05:00 GMT</pubDate>
          <dc:creator>Adaeze Okonjo</dc:creator>
          <enclosure url="https://meridianwire.example/img/pylons.jpg" type="image/jpeg" length="10241"/>
        </item>
        <item>
          <title>Second Story With A Broken Link</title>
          <link>not a valid url</link>
          <description>Short summary.</description>
          <pubDate>Tue, 28 Jul 2026 09:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """

    private let atomFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>The Delta Review</title>
      <link rel="self" href="https://deltareview.example/feed.atom"/>
      <link href="https://deltareview.example/"/>
      <subtitle>Basin reporting</subtitle>
      <entry>
        <title>Basin Towns Lose the Certainty They Argued For</title>
        <link rel="alternate" href="https://deltareview.example/basin/certainty-lost"/>
        <link rel="edit" href="https://deltareview.example/edit/991"/>
        <id>tag:deltareview.example,2026:991</id>
        <summary type="html">&lt;p&gt;The remand hands another season of uncertainty to the lower basin.&lt;/p&gt;</summary>
        <published>2026-07-29T11:30:00Z</published>
        <updated>2026-07-29T12:00:00Z</updated>
        <author><name>Lucía Ferreira</name></author>
      </entry>
    </feed>
    """

    // MARK: RSS

    func testParsesRSSChannelIdentityFromTheDocument() throws {
        let feed = try FeedParser().parse(Data(rssFixture.utf8))

        XCTAssertEqual(feed.format, .rss)
        XCTAssertEqual(feed.channelTitle, "Meridian Wire — Energy")
        XCTAssertEqual(feed.channelLink?.absoluteString, "https://meridianwire.example/energy")
        XCTAssertEqual(feed.channelDescription, "Energy coverage from Meridian Wire.")
        XCTAssertEqual(feed.items.count, 2)
    }

    func testParsesRSSItemFields() throws {
        let feed = try FeedParser().parse(Data(rssFixture.utf8))
        let item = try XCTUnwrap(feed.items.first)

        XCTAssertEqual(item.title, "Grid Operators Warn Reserve Margins Are Thin")
        XCTAssertEqual(item.link?.host, "meridianwire.example")
        XCTAssertEqual(item.guid, "meridian-2026-07-29-001")
        XCTAssertEqual(item.author, "Adaeze Okonjo")
        XCTAssertEqual(item.imageURL?.absoluteString, "https://meridianwire.example/img/pylons.jpg")
        XCTAssertNotNil(item.contentHTML)
    }

    func testRSSPublishedDateIsParsedRatherThanIgnored() throws {
        let feed = try FeedParser().parse(Data(rssFixture.utf8))
        let published = try XCTUnwrap(feed.items.first?.publishedAt)

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 29
        components.hour = 14
        components.minute = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        XCTAssertEqual(published, calendar.date(from: components))
    }

    func testHTMLSummaryIsNormalizedToPlainText() throws {
        let feed = try FeedParser().parse(Data(rssFixture.utf8))
        let summary = try XCTUnwrap(feed.items.first?.summary)

        XCTAssertEqual(summary, "Three operators told regulators that August reserves fall below target. A hearing is scheduled.")
        XCTAssertFalse(summary.contains("<"))
        XCTAssertFalse(summary.contains("&lt;"))
    }

    func testMalformedLinkBecomesNilRatherThanAPlaceholderHost() throws {
        let feed = try FeedParser().parse(Data(rssFixture.utf8))
        let item = try XCTUnwrap(feed.items.last)

        XCTAssertNil(item.link)
        XCTAssertEqual(item.title, "Second Story With A Broken Link")
    }

    func testNonWebSchemesAreRejected() {
        XCTAssertNil(FeedParser.webURL(from: "javascript:alert(1)"))
        XCTAssertNil(FeedParser.webURL(from: "/relative/path"))
        XCTAssertNil(FeedParser.webURL(from: "   "))
        XCTAssertNotNil(FeedParser.webURL(from: "https://meridianwire.example/a"))
    }

    // MARK: Atom

    func testParsesAtomFeed() throws {
        let feed = try FeedParser().parse(Data(atomFixture.utf8))

        XCTAssertEqual(feed.format, .atom)
        XCTAssertEqual(feed.channelTitle, "The Delta Review")
        XCTAssertEqual(feed.items.count, 1)
    }

    func testAtomEntryPrefersAlternateLinkAndParsesNestedAuthor() throws {
        let feed = try FeedParser().parse(Data(atomFixture.utf8))
        let item = try XCTUnwrap(feed.items.first)

        XCTAssertEqual(item.link?.absoluteString, "https://deltareview.example/basin/certainty-lost")
        XCTAssertEqual(item.author, "Lucía Ferreira")
        XCTAssertEqual(item.guid, "tag:deltareview.example,2026:991")
        XCTAssertEqual(item.summary, "The remand hands another season of uncertainty to the lower basin.")
    }

    func testAtomPublishedDateIsParsed() throws {
        let feed = try FeedParser().parse(Data(atomFixture.utf8))
        let published = try XCTUnwrap(feed.items.first?.publishedAt)

        XCTAssertEqual(published.timeIntervalSince1970, 1_785_324_600, accuracy: 1)
    }

    // MARK: Errors

    func testMalformedXMLThrowsATypedError() {
        let malformed = "<rss version=\"2.0\"><channel><title>Broken</title><item><title>Unclosed</channel></rss>"

        XCTAssertThrowsError(try FeedParser().parse(Data(malformed.utf8))) { error in
            guard case FeedParsingError.malformedXML(let line, _, _)? = error as? FeedParsingError else {
                return XCTFail("Expected malformedXML, got \(error)")
            }
            XCTAssertGreaterThan(line, 0)
        }
    }

    func testNonFeedDocumentThrowsUnsupportedFormat() {
        let html = "<html><body><h1>Not a feed</h1></body></html>"

        XCTAssertThrowsError(try FeedParser().parse(Data(html.utf8))) { error in
            XCTAssertEqual(error as? FeedParsingError, .unsupportedFormat(rootElement: "html"))
        }
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try FeedParser().parse(Data())) { error in
            XCTAssertEqual(error as? FeedParsingError, .emptyDocument)
        }
    }

    func testParserErrorsAreNotSilentlySwallowed() {
        // A parse failure must surface; returning an empty article list would hide it.
        let truncated = "<?xml version=\"1.0\"?><feed><entry><title>Half"
        XCTAssertThrowsError(try FeedParser().parse(Data(truncated.utf8)))
    }

    // MARK: Date parsing

    func testDateParserHandlesCommonFeedFormats() {
        XCTAssertNotNil(FeedDateParser.date(from: "Wed, 29 Jul 2026 14:05:00 GMT"))
        XCTAssertNotNil(FeedDateParser.date(from: "Wed, 9 Jul 2026 14:05:00 +0000"))
        XCTAssertNotNil(FeedDateParser.date(from: "2026-07-29T14:05:00Z"))
        XCTAssertNotNil(FeedDateParser.date(from: "2026-07-29T14:05:00.250Z"))
        XCTAssertNotNil(FeedDateParser.date(from: "2026-07-29"))
    }

    func testUnparseableDateReturnsNilInsteadOfNow() {
        XCTAssertNil(FeedDateParser.date(from: "sometime last week"))
        XCTAssertNil(FeedDateParser.date(from: ""))
    }

    // MARK: Mapping

    func testMappedArticleUsesFeedChannelIdentityNotAHardCodedPublisher() throws {
        let feed = try FeedParser().parse(Data(rssFixture.utf8))
        let publisher = FeedArticleMapper.publisher(for: feed, feedURL: nil)

        XCTAssertEqual(publisher.name, "Meridian Wire — Energy")
        XCTAssertEqual(publisher.domain, "meridianwire.example")
        XCTAssertNil(publisher.baseline, "Broadsheet has no baseline for an arbitrary URL and must not invent one")
    }

    func testMappedArticleKeepsFeedDateAndMarksExtractionHonestly() throws {
        let feed = try FeedParser().parse(Data(rssFixture.utf8))
        let publisher = FeedArticleMapper.publisher(for: feed, feedURL: nil)
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let withContent = FeedArticleMapper.article(from: feed.items[0], publisher: publisher, fetchedAt: fetchedAt)
        XCTAssertEqual(withContent.publishedAt, feed.items[0].publishedAt)
        XCTAssertEqual(withContent.contentSource, .liveFeed)
        if case .partial = withContent.extraction {} else {
            XCTFail("Feed-supplied content should be marked partial, got \(withContent.extraction)")
        }

        let feedOnly = FeedArticleMapper.article(from: feed.items[1], publisher: publisher, fetchedAt: fetchedAt)
        XCTAssertEqual(feedOnly.extraction, .feedOnly)
        XCTAssertNil(feedOnly.canonicalURL)
    }

    // MARK: HTML normalization

    func testNormalizerDecodesEntitiesAndCollapsesWhitespace() {
        let html = "<p>Reserves   fall &amp; margins\n tighten&hellip;</p>"
        XCTAssertEqual(HTMLTextNormalizer.plainText(from: html), "Reserves fall & margins tighten…")
    }

    func testNormalizerPreservesComparisonOperatorsInProse() {
        XCTAssertEqual(HTMLTextNormalizer.plainText(from: "margin &lt; 15 percent"), "margin < 15 percent")
    }

    func testNormalizerHandlesEscapedMarkup() {
        XCTAssertEqual(HTMLTextNormalizer.plainText(from: "&lt;p&gt;Escaped&lt;/p&gt;"), "Escaped")
    }

    func testNormalizerSplitsBlockElementsIntoParagraphs() {
        let html = "<p>First paragraph.</p><p>Second paragraph.</p>"
        XCTAssertEqual(
            HTMLTextNormalizer.paragraphs(from: html),
            ["First paragraph.", "Second paragraph."]
        )
    }
}
