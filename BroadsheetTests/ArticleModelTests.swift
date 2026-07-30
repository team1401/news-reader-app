import XCTest
@testable import Broadsheet

final class ArticleModelTests: XCTestCase {

    private func makeArticle(
        url: String = "https://meridianwire.example/energy/story",
        blocks: [ArticleBlock] = []
    ) -> ArticleDocument {
        let canonical = URL(string: url)!
        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: DemoPublishers.meridianWire,
            title: "Grid Operators Warn Reserve Margins Are Thin",
            dek: "Three operators filed with regulators.",
            author: "Adaeze Okonjo",
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            blocks: blocks,
            contentSource: .bundledFixture
        )
    }

    // MARK: Stable identity

    func testIdentityIgnoresTrackingParametersHostCaseAndTrailingSlash() {
        let plain = ArticleID(canonicalURL: URL(string: "https://meridianwire.example/energy/story")!)
        let tracked = ArticleID(canonicalURL: URL(string: "https://WWW.MeridianWire.example/energy/story/?utm_source=rss&utm_medium=feed#top")!)

        XCTAssertEqual(plain, tracked)
    }

    func testIdentityKeepsMeaningfulQueryParameters() {
        let first = ArticleID(canonicalURL: URL(string: "https://meridianwire.example/archive?page=2")!)
        let second = ArticleID(canonicalURL: URL(string: "https://meridianwire.example/archive?page=3")!)

        XCTAssertNotEqual(first, second)
    }

    func testIdentityIsStableAcrossQueryParameterOrder() {
        let first = ArticleID(canonicalURL: URL(string: "https://meridianwire.example/a?b=2&a=1")!)
        let second = ArticleID(canonicalURL: URL(string: "https://meridianwire.example/a?a=1&b=2")!)

        XCTAssertEqual(first, second)
    }

    func testIdentityFallsBackToGUIDWhenNoLinkExists() {
        let identity = ArticleID(canonicalURL: nil, guid: "meridian-2026-07-29-001")
        XCTAssertEqual(identity.rawValue, "guid:meridian-2026-07-29-001")
    }

    func testDifferentArticlesGetDifferentIdentities() {
        let first = ArticleID(canonicalURL: URL(string: "https://meridianwire.example/one")!)
        let second = ArticleID(canonicalURL: URL(string: "https://meridianwire.example/two")!)

        XCTAssertNotEqual(first, second)
    }

    // MARK: Semantic blocks

    func testSemanticBlocksSurviveACodableRoundTrip() throws {
        let blocks: [ArticleBlock] = [
            .paragraph(RichText(runs: [
                .plain("See the "),
                .link(text: "joint filing", url: URL(string: "https://meridianwire.example/doc")!),
                .plain(" for the numbers.")
            ])),
            .heading("What the filings say"),
            .image(ArticleImage(
                artwork: .duskTransmissionLines,
                altText: "Transmission towers at dusk.",
                caption: "Kestrel Bend.",
                credit: "Illustration by Broadsheet for demo data"
            )),
            .pullQuote(text: "We are not short of electrons.", attribution: "Priya Raghunathan"),
            .list(ordered: true, items: [RichText("First"), RichText("Second")]),
            .divider
        ]

        let data = try JSONEncoder().encode(blocks)
        let decoded = try JSONDecoder().decode([ArticleBlock].self, from: data)

        XCTAssertEqual(decoded, blocks)
    }

    func testRichTextExposesPlainTextAndLinks() {
        let rich = RichText(runs: [
            .plain("See the "),
            .link(text: "joint filing", url: URL(string: "https://meridianwire.example/doc")!),
            .strong(" now"),
            .emphasis(".")
        ])

        XCTAssertEqual(rich.plainText, "See the joint filing now.")
        XCTAssertEqual(rich.linkURLs.map(\.absoluteString), ["https://meridianwire.example/doc"])
    }

    func testImageAndDividerBlocksContributeNoAnalyzableText() {
        let image = ArticleBlock.image(ArticleImage(altText: "alt", caption: "caption", credit: "Meridian Wire"))
        XCTAssertEqual(image.analyzableText, "")
        XCTAssertEqual(ArticleBlock.divider.analyzableText, "")
    }

    func testBodyTextExcludesCaptionsAndCredits() {
        let article = makeArticle(blocks: [
            .paragraph(RichText("Reserve margin is the cushion between demand and supply.")),
            .image(ArticleImage(altText: "alt", caption: "A caption naming the photographer", credit: "Some credit"))
        ])

        XCTAssertTrue(article.bodyText.contains("Reserve margin"))
        XCTAssertFalse(article.bodyText.contains("caption"))
        XCTAssertFalse(article.bodyText.contains("credit"))
    }

    func testReadingTimeIsAtLeastOneMinuteAndScalesWithLength() {
        let short = makeArticle(blocks: [.paragraph(RichText("Two words."))])
        XCTAssertEqual(short.readingTimeMinutes, 1)

        let words = Array(repeating: "word", count: 900).joined(separator: " ")
        let long = makeArticle(blocks: [.paragraph(RichText(words))])
        XCTAssertGreaterThanOrEqual(long.readingTimeMinutes, 4)
    }

    func testSearchableTextIncludesPublisherButBodyTextDoesNot() {
        let article = makeArticle(blocks: [.paragraph(RichText("The filings were submitted on Tuesday."))])

        XCTAssertTrue(article.searchableText.contains("Meridian Wire"))
        XCTAssertFalse(article.bodyText.contains("Meridian Wire"))
    }

    // MARK: Extraction status

    func testExtractionStatusesDescribeThemselvesHonestly() {
        XCTAssertNil(ExtractionStatus.full.disclosure)
        XCTAssertNotNil(ExtractionStatus.feedOnly.disclosure)
        XCTAssertNotNil(ExtractionStatus.paywalled(note: "Free excerpt only.").disclosure)
        XCTAssertFalse(ExtractionStatus.failed(reason: "Extraction failed.").isReadableInApp)
        XCTAssertTrue(ExtractionStatus.partial(note: "Partial.").isReadableInApp)
    }
}
