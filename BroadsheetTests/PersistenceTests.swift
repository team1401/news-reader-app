import SwiftData
import XCTest
@testable import Broadsheet

@MainActor
final class PersistenceTests: XCTestCase {

    private var container: ModelContainer!
    private var store: BroadsheetStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try PersistenceController.makeInMemoryContainer()
        store = BroadsheetStore(container: container)
    }

    override func tearDown() {
        store = nil
        container = nil
        super.tearDown()
    }

    // MARK: Helpers

    private func makeArticle(
        id: String = "https://news.example.org/story-1",
        title: String = "A stored story about the harbour",
        publishedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        blocks: [ArticleBlock]? = nil,
        extraction: ExtractionStatus = .full
    ) -> ArticleDocument {
        ArticleDocument(
            id: ArticleID(rawValue: id),
            canonicalURL: URL(string: id),
            publisher: Publisher(id: "news.example.org", name: "Example News", domain: "news.example.org"),
            title: title,
            dek: "A stored dek.",
            author: "A Byline",
            publishedAt: publishedAt,
            heroImage: ArticleImage(remoteURL: URL(string: "https://news.example.org/a.jpg"), altText: "Alt text"),
            blocks: blocks ?? [
                .heading("A heading"),
                .paragraph(RichText(runs: [
                    .plain("Body text with "),
                    .link(text: "a link", url: URL(string: "https://example.org/link")!),
                    .plain(" inside it.")
                ])),
                .list(ordered: true, items: [RichText("One"), RichText("Two")]),
                .pullQuote(text: "A quotation.", attribution: "A speaker"),
                .divider
            ],
            extraction: extraction,
            contentSource: .liveFeed
        )
    }

    private func makeSource(_ url: String = "https://news.example.org/feed.xml", title: String = "Example News") -> FeedSource {
        FeedSource(feedURL: URL(string: url)!, title: title, siteURL: URL(string: "https://news.example.org"))
    }

    // MARK: Round trip

    func testArticleSurvivesAFreshModelContextFetch() throws {
        store.upsert(makeSource())
        let original = makeArticle()
        store.persistArticles([original], sourceID: makeSource().id, fetchedAt: Date())

        // A brand-new store over the same container is the relaunch case: nothing
        // is served from the first context's memory.
        let reopened = BroadsheetStore(container: container)
        let fetched = try XCTUnwrap(reopened.article(id: original.id))

        XCTAssertEqual(fetched.title, original.title)
        XCTAssertEqual(fetched.dek, original.dek)
        XCTAssertEqual(fetched.author, original.author)
        XCTAssertEqual(fetched.canonicalURL, original.canonicalURL)
        XCTAssertEqual(fetched.publishedAt, original.publishedAt)
        XCTAssertEqual(fetched.publisher, original.publisher)
        XCTAssertEqual(fetched.heroImage, original.heroImage)
        XCTAssertEqual(fetched.extraction, original.extraction)
        XCTAssertEqual(fetched.contentSource, .liveFeed)
        XCTAssertEqual(fetched.blocks, original.blocks, "Semantic blocks must round-trip exactly")
    }

    func testOriginalSourceMetadataIsNeverLost() throws {
        let baseline = PublisherBaseline(rating: "Center", provider: "A rating provider", asOf: Date(timeIntervalSince1970: 1_700_000_000))
        let article = ArticleDocument(
            id: ArticleID(rawValue: "https://news.example.org/story-2"),
            canonicalURL: URL(string: "https://news.example.org/story-2?utm_source=x"),
            publisher: Publisher(id: "news.example.org", name: "Example News", domain: "news.example.org", baseline: baseline),
            kicker: "A kicker",
            title: "Second story",
            dek: nil,
            author: nil,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500),
            blocks: [.paragraph(RichText("Body."))],
            extraction: .excerptOnly(reason: "A stated reason."),
            contentSource: .liveFeed
        )
        store.persistArticles([article], sourceID: nil, fetchedAt: Date())

        let fetched = try XCTUnwrap(BroadsheetStore(container: container).article(id: article.id))
        XCTAssertEqual(fetched.kicker, "A kicker")
        XCTAssertEqual(fetched.updatedAt, article.updatedAt)
        XCTAssertEqual(fetched.publisher.baseline, baseline)
        XCTAssertEqual(fetched.extraction, .excerptOnly(reason: "A stated reason."))
        XCTAssertEqual(fetched.canonicalURL?.absoluteString, "https://news.example.org/story-2?utm_source=x")
    }

    func testSavedAndReadStateSurviveRelaunch() throws {
        let article = makeArticle()
        store.persistArticles([article], sourceID: nil, fetchedAt: Date())

        store.setSaved(true, id: article.id, at: Date(timeIntervalSince1970: 1_800_000_900))
        store.markRead(article.id)

        let reopened = BroadsheetStore(container: container)
        XCTAssertTrue(reopened.isSaved(article.id))
        XCTAssertTrue(reopened.isRead(article.id))
        XCTAssertEqual(reopened.savedArticles().map(\.id), [article.id])
    }

    func testRepersistingKeepsReaderStateAndUpdatesContent() throws {
        let article = makeArticle()
        store.persistArticles([article], sourceID: nil, fetchedAt: Date(timeIntervalSince1970: 1))
        store.setSaved(true, id: article.id)
        store.setCorrection(.center, for: article.id)

        let edited = makeArticle(title: "A stored story about the harbour, updated")
        store.persistArticles([edited], sourceID: nil, fetchedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(store.article(id: article.id)?.title, "A stored story about the harbour, updated")
        XCTAssertTrue(store.isSaved(article.id), "A content update must not clear a save")
        XCTAssertEqual(store.corrections()[article.id], .center)
        XCTAssertEqual(store.articleCount(), 1, "The same identity must not create a second row")
    }

    func testRepublishedStoryAtANewURLCollapsesAcrossRefreshesAndKeepsReaderState() throws {
        let original = makeArticle(
            id: "https://news.example.org/2026/07/harbour-schedule",
            title: "Harbour authority publishes dredging schedule",
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            blocks: [.paragraph(RichText("The original short report."))]
        )
        store.persistArticles([original], sourceID: nil, fetchedAt: Date(timeIntervalSince1970: 1))
        store.setSaved(true, id: original.id)
        store.markRead(original.id)
        store.setCorrection(.center, for: original.id)

        let republished = makeArticle(
            id: "https://news.example.org/story/98213",
            title: "Harbour Authority Publishes Dredging Schedule",
            publishedAt: Date(timeIntervalSince1970: 1_800_000_600),
            blocks: [
                .paragraph(RichText("The expanded republished report.")),
                .paragraph(RichText("A second paragraph with additional detail."))
            ]
        )
        let persisted = store.persistArticles([republished], sourceID: nil, fetchedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(store.articleCount(), 1, "Near duplicates must collapse across refresh transactions")
        XCTAssertEqual(persisted.map(\.id), [original.id], "The stable stored identity preserves reader state")
        XCTAssertNil(store.article(id: republished.id), "A second row must not be created for the new URL")
        let updated = try XCTUnwrap(store.article(id: original.id))
        XCTAssertEqual(updated.canonicalURL, republished.canonicalURL)
        XCTAssertEqual(updated.blocks, republished.blocks)
        XCTAssertTrue(store.isSaved(original.id))
        XCTAssertTrue(store.isRead(original.id))
        XCTAssertEqual(store.corrections()[original.id], .center)
    }

    // MARK: Sources

    func testStarterSourcesAreSeededOnceAndAreEditable() {
        let seeded = store.seedStarterSourcesIfNeeded()

        XCTAssertEqual(seeded.count, 4)
        XCTAssertEqual(
            Set(store.sources().map(\.feedURL.absoluteString)),
            Set(StarterSources.all.map(\.feedURL.absoluteString))
        )

        // Idempotent: a second call adds nothing.
        XCTAssertTrue(store.seedStarterSourcesIfNeeded().isEmpty)
        XCTAssertEqual(store.sources().count, 4)

        // And a deleted starter source never comes back.
        let bbc = try! XCTUnwrap(store.sources().first { $0.title == "BBC News" })
        store.deleteSource(id: bbc.id)
        XCTAssertTrue(store.seedStarterSourcesIfNeeded().isEmpty)
        XCTAssertEqual(store.sources().count, 3)
        XCTAssertFalse(store.sources().contains { $0.title == "BBC News" })
    }

    func testSeedingIsIdempotentAcrossRelaunch() {
        store.seedStarterSourcesIfNeeded()
        let reopened = BroadsheetStore(container: container)
        XCTAssertTrue(reopened.seedStarterSourcesIfNeeded().isEmpty)
        XCTAssertEqual(reopened.sources().count, 4)
    }

    func testStarterSourcesUseTheVerifiedEndpoints() {
        store.seedStarterSourcesIfNeeded()
        let urls = Set(store.sources().map(\.feedURL.absoluteString))

        XCTAssertTrue(urls.contains("https://feeds.bbci.co.uk/news/rss.xml?edition=int"))
        XCTAssertTrue(urls.contains("https://feeds.npr.org/1001/rss.xml"))
        XCTAssertTrue(urls.contains("https://feeds.arstechnica.com/arstechnica/index"))
        XCTAssertTrue(urls.contains("https://www.propublica.org/feeds/propublica/main"))
        XCTAssertTrue(urls.allSatisfy { $0.hasPrefix("https://") })
    }

    func testSourceEditsPersist() throws {
        var source = store.upsert(makeSource())
        source.title = "Renamed"
        source.folder = "Reading"
        source.isEnabled = false
        store.upsert(source)

        let reopened = BroadsheetStore(container: container)
        let fetched = try XCTUnwrap(reopened.source(id: source.id))
        XCTAssertEqual(fetched.title, "Renamed")
        XCTAssertEqual(fetched.folder, "Reading")
        XCTAssertFalse(fetched.isEnabled)
        XCTAssertTrue(reopened.enabledSources().isEmpty)
    }

    func testTheSameFeedCannotBeSubscribedTwice() {
        store.upsert(makeSource("https://news.example.org/feed.xml"))
        store.upsert(makeSource("https://NEWS.example.org/feed.xml/", title: "Duplicate"))

        XCTAssertEqual(store.sources().count, 1)
        XCTAssertEqual(store.sources().first?.title, "Duplicate", "The later write should update, not duplicate")
    }

    func testDeletingASourceRemovesItsCachedArticles() {
        let source = store.upsert(makeSource())
        store.persistArticles([makeArticle()], sourceID: source.id, fetchedAt: Date())
        XCTAssertEqual(store.articleCount(), 1)

        store.deleteSource(id: source.id)
        XCTAssertEqual(store.articleCount(), 0)
    }

    func testRefreshFailureIsRecordedWithoutLosingArticles() {
        let source = store.upsert(makeSource())
        store.persistArticles([makeArticle()], sourceID: source.id, fetchedAt: Date())

        store.recordRefreshOutcome(
            sourceID: source.id,
            status: .failed,
            itemCount: 0,
            errorMessage: "The server did not respond in time.",
            at: Date(timeIntervalSince1970: 1_800_001_000)
        )

        let fetched = store.source(id: source.id)
        XCTAssertEqual(fetched?.lastStatus, .failed)
        XCTAssertEqual(fetched?.lastErrorMessage, "The server did not respond in time.")
        XCTAssertEqual(store.articleCount(), 1, "A failure must never drop cached content")
    }

    // MARK: Analysis

    private func makeResult(_ label: BiasLabel = .center) -> BiasAnalysisResult {
        BiasAnalysisResult(
            label: label,
            confidenceScore: 0.8,
            rationale: "A rationale.",
            evidence: [BiasEvidence(excerpt: "A verbatim excerpt from the article.")],
            provenance: BiasProvenance(engine: .appleFoundationModels, modelVersion: FoundationModelsBiasAnalyzer.version)
        )
    }

    func testAnalysisResultSurvivesRelaunch() throws {
        let article = makeArticle()
        store.persistArticles([article], sourceID: nil, fetchedAt: Date())
        store.persistAnalysis(makeResult(.right), for: article.id)

        let reopened = BroadsheetStore(container: container)
        let state = try XCTUnwrap(reopened.analysisStates()[article.id])
        guard case .analyzed(let result) = state else { return XCTFail("Expected an analyzed state, got \(state)") }

        XCTAssertEqual(result.label, .right)
        XCTAssertEqual(result.confidenceScore, 0.8, accuracy: 0.0001)
        XCTAssertEqual(result.rationale, "A rationale.")
        XCTAssertEqual(result.evidence.map(\.excerpt), ["A verbatim excerpt from the article."])
        XCTAssertEqual(result.provenance.engine, .appleFoundationModels)
        XCTAssertEqual(result.provenance.modelVersion, FoundationModelsBiasAnalyzer.version)
    }

    func testAnalysisFailureIsPersistedHonestlyRatherThanLeftBlank() throws {
        let article = makeArticle()
        store.persistArticles([article], sourceID: nil, fetchedAt: Date())
        store.persistAnalysisFailure(
            reason: "Apple Intelligence is turned off.",
            engine: .appleFoundationModels,
            modelVersion: FoundationModelsBiasAnalyzer.version,
            for: article.id
        )

        let reopened = BroadsheetStore(container: container)
        XCTAssertEqual(
            reopened.analysisStates()[article.id],
            .unavailable(reason: "Apple Intelligence is turned off.")
        )
    }

    func testReanalysisReplacesTheEstimateButNotTheCorrection() throws {
        let article = makeArticle()
        store.persistArticles([article], sourceID: nil, fetchedAt: Date())
        store.persistAnalysis(makeResult(.left), for: article.id)
        store.setCorrection(.center, for: article.id)

        store.persistAnalysis(makeResult(.right), for: article.id)

        let reopened = BroadsheetStore(container: container)
        XCTAssertEqual(reopened.analysisStates()[article.id]?.result?.label, .right)
        XCTAssertEqual(reopened.corrections()[article.id], .center, "The reader's correction is theirs, not the model's")
    }

    func testClearingACorrectionPersists() {
        let article = makeArticle()
        store.persistArticles([article], sourceID: nil, fetchedAt: Date())
        store.setCorrection(.left, for: article.id)
        store.setCorrection(nil, for: article.id)

        XCTAssertTrue(BroadsheetStore(container: container).corrections().isEmpty)
    }

    // MARK: Retention

    func testPruningKeepsTheNewestAndNeverDropsASavedStory() {
        let source = store.upsert(makeSource())
        let documents = (0..<10).map { index in
            makeArticle(
                id: "https://news.example.org/story-\(index)",
                title: "Story \(index)",
                publishedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 60)
            )
        }
        store.persistArticles(documents, sourceID: source.id, fetchedAt: Date())
        store.setSaved(true, id: documents[0].id)

        store.pruneArticles(maxPerSource: 3)

        let remaining = Set(store.articles().map(\.id.rawValue))
        XCTAssertEqual(remaining.count, 4, "Three newest plus the saved one")
        XCTAssertTrue(remaining.contains("https://news.example.org/story-0"), "A saved story must never be pruned")
        XCTAssertTrue(remaining.contains("https://news.example.org/story-9"))
    }

    // MARK: Preferences

    func testDemoModeAndRefreshTimestampPersist() {
        store.isDemoModeEnabled = true
        store.lastFullRefreshAt = Date(timeIntervalSince1970: 1_800_002_000)

        let reopened = BroadsheetStore(container: container)
        XCTAssertTrue(reopened.isDemoModeEnabled)
        XCTAssertEqual(reopened.lastFullRefreshAt, Date(timeIntervalSince1970: 1_800_002_000))
    }

    func testSchemaIsVersionedAndHasAMigrationPlan() {
        XCTAssertEqual(BroadsheetSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(BroadsheetSchemaV1.models.count, 4)
        XCTAssertEqual(BroadsheetMigrationPlan.schemas.count, 1)
        XCTAssertTrue(BroadsheetMigrationPlan.stages.isEmpty, "V1 is the only version so far")
    }
}
