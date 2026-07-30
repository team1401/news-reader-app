import XCTest
@testable import Broadsheet

final class ArticleCanonicalizerTests: XCTestCase {

    private func article(
        url: String,
        title: String,
        domain: String = "news.example.org",
        publishedAt: TimeInterval = 1_800_000_000,
        paragraphs: Int = 3
    ) -> ArticleDocument {
        ArticleDocument(
            id: ArticleID(canonicalURL: URL(string: url)!),
            canonicalURL: URL(string: url),
            publisher: Publisher(id: domain, name: domain, domain: domain),
            title: title,
            dek: "A dek.",
            publishedAt: Date(timeIntervalSince1970: publishedAt),
            blocks: (0..<paragraphs).map { .paragraph(RichText("Paragraph \($0).")) },
            contentSource: .liveFeed
        )
    }

    // MARK: Canonicalization

    func testTrackingParametersAndCasingCollapseToOneIdentity() {
        let a = article(url: "https://News.Example.org/story/one?utm_source=twitter&utm_medium=social", title: "One")
        let b = article(url: "https://news.example.org/story/one/#comments", title: "One")

        XCTAssertEqual(ArticleCanonicalizer.canonicalKey(for: a), ArticleCanonicalizer.canonicalKey(for: b))
    }

    func testMeaningfulQueryParametersAreKept() {
        let a = article(url: "https://news.example.org/story?id=1", title: "One")
        let b = article(url: "https://news.example.org/story?id=2", title: "Two")

        XCTAssertNotEqual(ArticleCanonicalizer.canonicalKey(for: a), ArticleCanonicalizer.canonicalKey(for: b))
    }

    func testContentHashIsStableAndSensitive() {
        let a = article(url: "https://news.example.org/a", title: "Headline")
        let sameAgain = article(url: "https://news.example.org/a", title: "Headline")
        let edited = article(url: "https://news.example.org/a", title: "Headline", paragraphs: 4)

        XCTAssertEqual(ArticleCanonicalizer.contentHash(for: a), ArticleCanonicalizer.contentHash(for: sameAgain))
        XCTAssertNotEqual(ArticleCanonicalizer.contentHash(for: a), ArticleCanonicalizer.contentHash(for: edited))
        XCTAssertEqual(ArticleCanonicalizer.contentHash(for: a).count, 64)
    }

    func testTitleNormalizationFoldsPunctuationAndCase() {
        XCTAssertEqual(
            ArticleCanonicalizer.normalizedTitle("Ruling — Round Two, Again!"),
            ArticleCanonicalizer.normalizedTitle("ruling - round two: again")
        )
    }

    // MARK: Deduplication

    func testDuplicateURLsCollapse() {
        let documents = [
            article(url: "https://news.example.org/a?utm_source=x", title: "A"),
            article(url: "https://news.example.org/a", title: "A")
        ]
        XCTAssertEqual(ArticleCanonicalizer.deduplicate(documents).count, 1)
    }

    func testSamePublisherRepublishingUnderANewURLCollapses() {
        let documents = [
            article(url: "https://news.example.org/2026/07/harbour-dredging-schedule", title: "Harbour authority publishes dredging schedule"),
            article(url: "https://news.example.org/story/98213", title: "Harbour Authority Publishes Dredging Schedule")
        ]
        XCTAssertEqual(ArticleCanonicalizer.deduplicate(documents).count, 1)
    }

    func testTwoPublishersCoveringTheSameStoryAreBothKept() {
        let documents = [
            article(url: "https://a.example.org/x", title: "Harbour authority publishes dredging schedule", domain: "a.example.org"),
            article(url: "https://b.example.org/y", title: "Harbour authority publishes dredging schedule", domain: "b.example.org")
        ]
        XCTAssertEqual(ArticleCanonicalizer.deduplicate(documents).count, 2, "Independent coverage is not duplication")
    }

    func testTheRicherCopyWins() {
        let thin = article(url: "https://news.example.org/a", title: "A", paragraphs: 1)
        let full = article(url: "https://news.example.org/a?utm_source=x", title: "A", paragraphs: 9)

        let result = ArticleCanonicalizer.deduplicate([thin, full])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].blocks.count, 9)
    }

    func testOutputIsNewestFirst() {
        let documents = [
            article(url: "https://news.example.org/old", title: "Old", publishedAt: 1_800_000_000),
            article(url: "https://news.example.org/new", title: "New", publishedAt: 1_800_009_000),
            article(url: "https://news.example.org/mid", title: "Mid", publishedAt: 1_800_005_000)
        ]
        XCTAssertEqual(ArticleCanonicalizer.deduplicate(documents).map(\.title), ["New", "Mid", "Old"])
    }

    func testDeduplicationIsDeterministicRegardlessOfInputOrder() {
        let documents = [
            article(url: "https://news.example.org/a", title: "Alpha story about the harbour"),
            article(url: "https://news.example.org/a?utm_source=x", title: "Alpha Story About The Harbour"),
            article(url: "https://other.example.org/b", title: "Beta story", domain: "other.example.org"),
            article(url: "https://news.example.org/c", title: "Gamma story", publishedAt: 1_800_000_500)
        ]

        let reference = ArticleCanonicalizer.deduplicate(documents).map(\.id.rawValue)
        for permutation in [documents.reversed().map { $0 }, documents.shuffled(), documents.shuffled()] {
            XCTAssertEqual(ArticleCanonicalizer.deduplicate(permutation).map(\.id.rawValue), reference)
        }
    }

    func testEqualTimestampsAreBrokenByIdentityNotByChance() {
        let a = article(url: "https://news.example.org/aaa", title: "A")
        let b = article(url: "https://news.example.org/bbb", title: "B")

        XCTAssertEqual(ArticleCanonicalizer.deduplicate([a, b]).map(\.id.rawValue),
                       ArticleCanonicalizer.deduplicate([b, a]).map(\.id.rawValue))
    }

    func testVeryShortTitlesDoNotCollapseUnrelatedStories() {
        let documents = [
            article(url: "https://news.example.org/1", title: "Fire"),
            article(url: "https://news.example.org/2", title: "Flood")
        ]
        XCTAssertEqual(ArticleCanonicalizer.deduplicate(documents).count, 2)
    }
}

final class EditionBuilderTests: XCTestCase {

    private func article(
        id: String,
        title: String,
        domain: String,
        publishedAt: TimeInterval
    ) -> ArticleDocument {
        ArticleDocument(
            id: ArticleID(rawValue: id),
            canonicalURL: URL(string: id),
            publisher: Publisher(id: domain, name: domain, domain: domain),
            title: title,
            publishedAt: Date(timeIntervalSince1970: publishedAt),
            blocks: [.paragraph(RichText("Body."))],
            contentSource: .liveFeed
        )
    }

    func testEmptyLibraryProducesNoEdition() {
        XCTAssertNil(EditionBuilder.build(from: []))
    }

    func testNewestStoryLeads() throws {
        let edition = try XCTUnwrap(EditionBuilder.build(from: [
            article(id: "https://a.example/1", title: "Older harbour report", domain: "a.example", publishedAt: 100),
            article(id: "https://a.example/2", title: "Newest transit report", domain: "a.example", publishedAt: 900)
        ]))

        XCTAssertEqual(edition.lead.title, "Newest transit report")
        XCTAssertEqual(edition.river.map(\.title), ["Older harbour report"])
    }

    func testIndependentCoverageOfOneEventBecomesACluster() throws {
        let edition = try XCTUnwrap(EditionBuilder.build(from: [
            article(id: "https://lead.example/0", title: "Unrelated lead story about weather", domain: "lead.example", publishedAt: 999),
            article(id: "https://a.example/1", title: "Appeals court vacates water allocation rule", domain: "a.example", publishedAt: 500),
            article(id: "https://b.example/2", title: "Court vacates water allocation rule, orders new rulemaking", domain: "b.example", publishedAt: 400),
            article(id: "https://c.example/3", title: "Judges vacate the water allocation rule", domain: "c.example", publishedAt: 300)
        ]))

        let cluster = try XCTUnwrap(edition.cluster)
        XCTAssertEqual(cluster.articles.count, 3)
        XCTAssertEqual(Set(cluster.articles.map(\.publisher.id)).count, 3)
        XCTAssertFalse(edition.river.contains { cluster.articles.map(\.id).contains($0.id) })
    }

    func testOnePublisherAloneIsNotACluster() throws {
        let edition = try XCTUnwrap(EditionBuilder.build(from: [
            article(id: "https://a.example/0", title: "Lead story", domain: "a.example", publishedAt: 999),
            article(id: "https://a.example/1", title: "Appeals court vacates water allocation rule", domain: "a.example", publishedAt: 500),
            article(id: "https://a.example/2", title: "Appeals court vacates water allocation rule again", domain: "a.example", publishedAt: 400)
        ]))

        XCTAssertNil(edition.cluster, "Sources covering this must mean more than one source")
    }

    func testUnrelatedStoriesProduceNoCluster() throws {
        let edition = try XCTUnwrap(EditionBuilder.build(from: [
            article(id: "https://a.example/1", title: "Harbour dredging schedule published", domain: "a.example", publishedAt: 300),
            article(id: "https://b.example/2", title: "Kelp bloom closes three beaches", domain: "b.example", publishedAt: 200),
            article(id: "https://c.example/3", title: "Transit board reviews fare proposal", domain: "c.example", publishedAt: 100)
        ]))

        XCTAssertNil(edition.cluster)
        XCTAssertEqual(edition.river.count, 2)
    }

    func testBuildIsDeterministic() {
        let documents = [
            article(id: "https://a.example/1", title: "Appeals court vacates water allocation rule", domain: "a.example", publishedAt: 500),
            article(id: "https://b.example/2", title: "Court vacates water allocation rule again", domain: "b.example", publishedAt: 400),
            article(id: "https://c.example/3", title: "Harbour dredging schedule published", domain: "c.example", publishedAt: 900)
        ]
        let reference = Date(timeIntervalSince1970: 1_800_000_000)

        let first = EditionBuilder.build(from: documents, referenceDate: reference)
        let second = EditionBuilder.build(from: documents.shuffled(), referenceDate: reference)

        XCTAssertEqual(first?.lead.id, second?.lead.id)
        XCTAssertEqual(first?.cluster?.articles.map(\.id), second?.cluster?.articles.map(\.id))
        XCTAssertEqual(first?.river.map(\.id), second?.river.map(\.id))
    }

    func testEveryArticleAppearsExactlyOnce() throws {
        let documents = (0..<12).map {
            article(id: "https://a.example/\($0)", title: "Story number \($0) about something", domain: "d\($0).example", publishedAt: Double(1000 - $0))
        }
        let edition = try XCTUnwrap(EditionBuilder.build(from: documents))

        let ids = edition.allArticles.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(documents.map(\.id)))
    }
}
