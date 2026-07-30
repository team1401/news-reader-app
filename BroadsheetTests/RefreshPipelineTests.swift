import SwiftData
import XCTest
@testable import Broadsheet

/// Records which articles it was asked to analyze so a test can prove *which*
/// engine ran on which content.
private final class RecordingAnalyzer: BiasAnalyzing, @unchecked Sendable {
    let engine: BiasEngine
    private let lock = NSLock()
    private var seen: [String] = []

    init(engine: BiasEngine) {
        self.engine = engine
    }

    var headlines: [String] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    var availabilityDescription: String { "Recording analyzer for tests." }
    var isAvailable: Bool { true }

    func analyze(_ input: BiasModelInput) async throws -> BiasAnalysisResult {
        lock.lock()
        seen.append(input.headline)
        lock.unlock()

        return BiasAnalysisResult(
            label: .center,
            confidenceScore: 0.6,
            rationale: "Recorded.",
            evidence: [],
            provenance: BiasProvenance(engine: engine, modelVersion: "test-1")
        )
    }
}

private final class UnavailableAnalyzer: BiasAnalyzing, @unchecked Sendable {
    let engine: BiasEngine = .appleFoundationModels
    var availabilityDescription: String { "The on-device model is unavailable in this test." }
    var isAvailable: Bool { false }

    func analyze(_ input: BiasModelInput) async throws -> BiasAnalysisResult {
        throw BiasAnalysisError.localModelUnavailable(reason: availabilityDescription)
    }
}

@MainActor
final class RefreshPipelineTests: XCTestCase {

    private var container: ModelContainer!
    private var store: BroadsheetStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        URLProtocolStub.reset()
        container = try PersistenceController.makeInMemoryContainer()
        store = BroadsheetStore(container: container)
    }

    override func tearDown() {
        URLProtocolStub.reset()
        store = nil
        container = nil
        super.tearDown()
    }

    // MARK: Builders

    private func makeService(
        transport: any HTTPTransport,
        analysis: BiasAnalysisService
    ) -> FeedRefreshService {
        let robots = RobotsPolicy(transport: transport)
        return FeedRefreshService(
            store: store,
            transport: transport,
            resolver: ArticleResolver(transport: transport, robots: robots),
            analysis: analysis
        )
    }

    private func stubTransport() -> URLSessionHTTPTransport {
        URLSessionHTTPTransport.forTesting(protocolClasses: [URLProtocolStub.self])
    }

    private let excerptFeed = """
    <?xml version="1.0"?>
    <rss version="2.0"><channel>
      <title>Example News</title><link>https://news.example.org</link>
      <item><title>Harbour authority publishes a full-year dredging schedule</title>
        <link>https://news.example.org/open</link>
        <description>A short excerpt supplied by the feed.</description>
        <pubDate>Mon, 27 Jul 2026 09:00:00 GMT</pubDate></item>
      <item><title>Subscribers only: the financing decision</title>
        <link>https://news.example.org/restricted</link>
        <description>A short excerpt for a restricted story.</description>
        <pubDate>Mon, 27 Jul 2026 08:00:00 GMT</pubDate></item>
    </channel></rss>
    """

    private func seedSource(_ url: String = "https://news.example.org/feed.xml") -> FeedSource {
        store.upsert(FeedSource(feedURL: URL(string: url)!, title: "Example News"))
    }

    // MARK: Resolution

    func testOpenPageIsExtractedAndRestrictedPageFallsBackToTheExcerpt() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let analysis = BiasAnalysisService(localModelAnalyzer: RecordingAnalyzer(engine: .appleFoundationModels))
        let service = makeService(transport: stubTransport(), analysis: analysis)
        let source = seedSource()

        let report = await service.refresh(sources: [source])

        XCTAssertEqual(report.failures.count, 0)
        XCTAssertEqual(store.articleCount(), 2)

        let open = try XCTUnwrap(store.article(id: ArticleID(rawValue: "https://news.example.org/open")))
        XCTAssertEqual(open.extraction, .full)
        XCTAssertGreaterThanOrEqual(open.blocks.count, 6)
        XCTAssertTrue(open.bodyText.contains("eastern quay"))

        let restricted = try XCTUnwrap(store.article(id: ArticleID(rawValue: "https://news.example.org/restricted")))
        guard case .paywalled(let note) = restricted.extraction else {
            return XCTFail("Expected a paywalled status, got \(restricted.extraction)")
        }
        XCTAssertTrue(note.localizedCaseInsensitiveContains("excerpt"))
        XCTAssertTrue(restricted.extraction.isExcerptOnly)
        XCTAssertNotNil(restricted.canonicalURL, "The original-source link must survive the fallback")
    }

    /// The fallback shows only what the feed published. Nothing is manufactured to
    /// fill the space where the article would have been.
    func testRestrictedFallbackContainsOnlyFeedSuppliedText() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        await service.refresh(sources: [seedSource()])

        let restricted = try XCTUnwrap(store.article(id: ArticleID(rawValue: "https://news.example.org/restricted")))
        XCTAssertEqual(restricted.bodyText, "A short excerpt for a restricted story.")
        XCTAssertFalse(restricted.bodyText.localizedCaseInsensitiveContains("financing decision has been circulating"))
    }

    func testRobotsDisallowStopsTheFetchAndSaysSo() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nDisallow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        await service.refresh(sources: [seedSource()])

        let article = try XCTUnwrap(store.article(id: ArticleID(rawValue: "https://news.example.org/open")))
        guard case .excerptOnly(let reason) = article.extraction else {
            return XCTFail("Expected an excerpt-only status, got \(article.extraction)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("robots.txt"))

        // And the page itself was never requested.
        XCTAssertFalse(URLProtocolStub.requestedURLs.contains { $0.path == "/open" })
    }

    func testUnfetchablePageFallsBackWithItsReason() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain")
            // Both article pages 404.
        ])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        await service.refresh(sources: [seedSource()])

        let article = try XCTUnwrap(store.article(id: ArticleID(rawValue: "https://news.example.org/open")))
        guard case .excerptOnly(let reason) = article.extraction else {
            return XCTFail("Expected an excerpt-only status, got \(article.extraction)")
        }
        XCTAssertTrue(reason.contains("404"), "The reason should name what happened. Got: \(reason)")
    }

    func testFullContentFeedIsUsedWithoutFetchingThePage() async throws {
        let fullFeed = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>
          <title>Full Feed</title><link>https://full.example.org</link>
          <item><title>Harbour authority publishes a full-year dredging schedule</title>
            <link>https://full.example.org/story</link>
            <description>An excerpt.</description>
            <pubDate>Mon, 27 Jul 2026 09:00:00 GMT</pubDate>
            <content:encoded><![CDATA[\(HTMLFixtures.feedContentFragment)]]></content:encoded></item>
        </channel></rss>
        """
        URLProtocolStub.map(["https://full.example.org/feed.xml": .text(fullFeed)])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        await service.refresh(sources: [seedSource("https://full.example.org/feed.xml")])

        let article = try XCTUnwrap(store.article(id: ArticleID(rawValue: "https://full.example.org/story")))
        XCTAssertEqual(article.extraction, .full)
        XCTAssertTrue(article.blocks.contains { if case .list = $0 { return true } else { return false } })
        XCTAssertFalse(
            URLProtocolStub.requestedURLs.contains { $0.path == "/story" },
            "A feed that carries the article must not trigger a page fetch"
        )
        XCTAssertFalse(URLProtocolStub.requestedURLs.contains { $0.path == "/robots.txt" })
    }

    // MARK: Failures

    func testAFailingSourceKeepsItsCachedArticles() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html")
        ])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        let source = seedSource()
        await service.refresh(sources: [source])
        let cachedBefore = store.articleCount()
        XCTAssertGreaterThan(cachedBefore, 0)

        // The source goes down entirely.
        URLProtocolStub.respondingWith { _ in
            .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        }
        let report = await service.refresh(sources: [store.source(id: source.id)!])

        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.failures[0].sourceTitle, "Example News")
        XCTAssertEqual(report.failures[0].errorMessage, "The server did not respond in time.")
        XCTAssertEqual(store.articleCount(), cachedBefore, "A failure must not empty the library")
        XCTAssertEqual(store.source(id: source.id)?.lastStatus, .failed)
    }

    func testOneBadSourceDoesNotStopTheOthers() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://broken.example.org/feed.xml": .respond(status: 500, body: Data("boom".utf8))
        ])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        let good = seedSource()
        let bad = seedSource("https://broken.example.org/feed.xml")

        let report = await service.refresh(sources: [bad, good])

        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.successes.count, 1)
        XCTAssertGreaterThan(store.articleCount(), 0)
        XCTAssertTrue(report.summary.contains("failed"))
    }

    func testAMalformedFeedIsReportedAsAParseFailure() async {
        URLProtocolStub.map(["https://news.example.org/feed.xml": .text("<rss><channel><title>oops")])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        let report = await service.refresh(sources: [seedSource()])

        XCTAssertEqual(report.failures.count, 1)
        XCTAssertTrue(report.failures[0].errorMessage?.contains("not valid XML") ?? false)
    }

    // MARK: Deduplication across refreshes

    func testRefreshingTwiceDoesNotDuplicateArticles() async {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        let source = seedSource()

        await service.refresh(sources: [source])
        let first = store.articleCount()
        await service.refresh(sources: [store.source(id: source.id)!])

        XCTAssertEqual(store.articleCount(), first)
        XCTAssertEqual(first, 2)
    }

    func testAlreadyResolvedArticlesAreNotRefetched() async {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let service = makeService(
            transport: stubTransport(),
            analysis: BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        )
        let source = seedSource()
        await service.refresh(sources: [source])

        let fetchesAfterFirst = URLProtocolStub.requestedURLs.filter { $0.path == "/open" }.count
        await service.refresh(sources: [store.source(id: source.id)!])
        let fetchesAfterSecond = URLProtocolStub.requestedURLs.filter { $0.path == "/open" }.count

        XCTAssertEqual(fetchesAfterFirst, fetchesAfterSecond, "A fully extracted article should not be re-fetched")
    }

    // MARK: Analyzer selection

    /// The single most important invariant in the analysis pipeline: the
    /// deterministic fixture heuristic is a demo device and must never be applied
    /// to real reporting, because that would present a lexicon lookup as machine
    /// analysis.
    func testLiveArticlesNeverReachTheFixtureAnalyzer() async {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let fixture = RecordingAnalyzer(engine: .deterministicFixture)
        let localModel = RecordingAnalyzer(engine: .appleFoundationModels)
        let analysis = BiasAnalysisService(fixtureAnalyzer: fixture, localModelAnalyzer: localModel)
        let service = makeService(transport: stubTransport(), analysis: analysis)

        await service.refresh(sources: [seedSource()])

        XCTAssertTrue(fixture.headlines.isEmpty, "The fixture heuristic saw live articles: \(fixture.headlines)")
        XCTAssertFalse(localModel.headlines.isEmpty)

        for article in store.articles() {
            XCTAssertEqual(article.contentSource, .liveFeed)
            XCTAssertEqual(
                analysis.state(for: article).result?.provenance.engine,
                .appleFoundationModels
            )
        }
    }

    func testDemoArticlesUseTheFixtureHeuristicAndNotTheModel() async {
        let fixture = RecordingAnalyzer(engine: .deterministicFixture)
        let localModel = RecordingAnalyzer(engine: .appleFoundationModels)
        let analysis = BiasAnalysisService(fixtureAnalyzer: fixture, localModelAnalyzer: localModel)

        await analysis.analyzeEagerly(DemoEdition.edition().allArticles)

        XCTAssertTrue(localModel.headlines.isEmpty, "Bundled fiction must not occupy the on-device model")
        XCTAssertFalse(fixture.headlines.isEmpty)
    }

    func testEagerAnalysisResultsArePersistedDuringRefresh() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let analysis = BiasAnalysisService(localModelAnalyzer: RecordingAnalyzer(engine: .appleFoundationModels))
        analysis.persistence = store
        let service = makeService(transport: stubTransport(), analysis: analysis)

        await service.refresh(sources: [seedSource()])

        let reopened = BroadsheetStore(container: container)
        let states = reopened.analysisStates()
        XCTAssertEqual(states.count, 2)
        XCTAssertTrue(states.values.allSatisfy { $0.result?.label == .center })
    }

    func testAnalysisUnavailabilityIsPersistedHonestly() async throws {
        URLProtocolStub.map([
            "https://news.example.org/feed.xml": .text(excerptFeed),
            "https://news.example.org/robots.txt": .text("User-agent: *\nAllow: /", contentType: "text/plain"),
            "https://news.example.org/open": .text(HTMLFixtures.accessibleArticle, contentType: "text/html"),
            "https://news.example.org/restricted": .text(HTMLFixtures.paywalledArticle, contentType: "text/html")
        ])

        let analysis = BiasAnalysisService(localModelAnalyzer: UnavailableAnalyzer())
        analysis.persistence = store
        let service = makeService(transport: stubTransport(), analysis: analysis)

        await service.refresh(sources: [seedSource()])

        let states = BroadsheetStore(container: container).analysisStates()
        XCTAssertFalse(states.isEmpty)
        for state in states.values {
            guard case .unavailable(let reason) = state else { return XCTFail("Expected unavailable, got \(state)") }
            XCTAssertTrue(reason.localizedCaseInsensitiveContains("unavailable"))
        }
    }
}

@MainActor
final class AppModelRefreshTests: XCTestCase {

    private var container: ModelContainer!
    private var store: BroadsheetStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        URLProtocolStub.reset()
        container = try PersistenceController.makeInMemoryContainer()
        store = BroadsheetStore(container: container)
    }

    override func tearDown() {
        URLProtocolStub.reset()
        store = nil
        container = nil
        super.tearDown()
    }

    func testFirstLaunchSeedsStarterSourcesAndShowsAnEmptyEdition() {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()

        XCTAssertEqual(model.sources.count, 4)
        XCTAssertEqual(model.enabledSourceCount, 4)
        XCTAssertNil(model.displayedEdition, "Nothing has been downloaded yet")
        XCTAssertTrue(model.canRefresh)
        XCTAssertFalse(model.isDemoMode, "Demo mode is opt-in, never the default")
    }

    func testRefreshReplacesTheEmptyEditionWithLiveContent() async throws {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()

        await model.refresh()

        let edition = try XCTUnwrap(model.displayedEdition)
        XCTAssertGreaterThan(edition.allArticles.count, 1)
        XCTAssertTrue(edition.allArticles.allSatisfy { $0.contentSource == .liveFeed })
        XCTAssertEqual(model.lastReport.failures.count, 0, "Fixture feeds should all parse")
        XCTAssertNotNil(model.lastRefreshedAt)
    }

    func testContentSurvivesRelaunch() async throws {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()
        await model.refresh()
        let countBefore = model.liveArticles.count
        XCTAssertGreaterThan(countBefore, 0)

        // A second model over the same container is the relaunch.
        let relaunched = AppModel(store: BroadsheetStore(container: container), transport: UITestFixtures.transport())
        relaunched.bootstrap()

        XCTAssertEqual(relaunched.liveArticles.count, countBefore)
        XCTAssertNotNil(relaunched.displayedEdition)
        XCTAssertEqual(relaunched.sources.count, 4, "Seeding must not run again")
    }

    func testDemoModeIsExplicitAndOfflineOnly() async {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()
        await model.refresh()
        let liveCount = model.liveArticles.count

        model.isDemoMode = true

        XCTAssertFalse(model.canRefresh, "Demo mode must never hit the network")
        XCTAssertTrue(model.allArticles.allSatisfy { $0.contentSource == .bundledFixture })
        XCTAssertTrue(model.allArticles.allSatisfy { $0.publisher.domain.hasSuffix(".example") })

        model.isDemoMode = false
        XCTAssertEqual(model.liveArticles.count, liveCount, "Live content is untouched by the preview")
    }

    func testSearchRunsOverPersistedLiveContent() async {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()
        await model.refresh()

        let results = ArticleSearchIndex.search("harbour", in: model.allArticles)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.article.contentSource == .liveFeed })
    }

    func testSavingAndReadStateArePersistedForLiveArticles() async throws {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()
        await model.refresh()

        let article = try XCTUnwrap(model.liveArticles.first)
        model.toggleSaved(article)
        model.markRead(article)

        let relaunched = AppModel(store: BroadsheetStore(container: container), transport: UITestFixtures.transport())
        relaunched.bootstrap()
        XCTAssertEqual(relaunched.savedArticles.map(\.id), [article.id])
        XCTAssertTrue(relaunched.store.isRead(article.id))
    }

    func testAddingAndDeletingASourceWorksEndToEnd() async throws {
        URLProtocolStub.map([
            "https://added.example.org/feed.xml": .text("""
            <?xml version="1.0"?><rss version="2.0"><channel><title>Added Source</title>
            <link>https://added.example.org</link>
            <item><title>An item</title><link>https://added.example.org/1</link></item>
            </channel></rss>
            """)
        ])

        let model = AppModel(
            store: store,
            transport: URLSessionHTTPTransport.forTesting(protocolClasses: [URLProtocolStub.self])
        )
        model.bootstrap()

        let candidates = try await model.validateCandidates(for: "added.example.org/feed.xml")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertFalse(model.isAlreadySubscribed(candidates[0]))

        let added = model.addSource(candidates[0], folder: "Extra")
        XCTAssertEqual(model.sources.count, 5)
        XCTAssertTrue(model.isAlreadySubscribed(candidates[0]))
        XCTAssertEqual(added.folder, "Extra")

        model.deleteSource(id: added.id)
        XCTAssertEqual(model.sources.count, 4)
    }

    func testDisablingASourceRemovesItFromRefresh() async {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()

        for source in model.sources where source.title != "BBC News" {
            model.setSourceEnabled(false, id: source.id)
        }
        XCTAssertEqual(model.enabledSourceCount, 1)

        await model.refresh()

        XCTAssertEqual(model.lastReport.outcomes.count, 1)
        XCTAssertEqual(model.lastReport.outcomes.first?.sourceTitle, "BBC News")
    }

    func testCorrectionsPersistThroughTheModel() async throws {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()
        await model.refresh()

        let article = try XCTUnwrap(model.liveArticles.first)
        model.recordCorrection(.left, for: article)

        let relaunched = AppModel(store: BroadsheetStore(container: container), transport: UITestFixtures.transport())
        relaunched.bootstrap()
        XCTAssertEqual(relaunched.correction(for: article), .left)
    }

    /// The fixture feeds include a page that declares itself restricted and one
    /// that cannot be fetched at all; both must end up as honest excerpt states.
    func testFixtureRefreshProducesHonestFallbackStates() async {
        let model = AppModel(store: store, transport: UITestFixtures.transport())
        model.bootstrap()
        await model.refresh()

        let statuses = model.liveArticles.map(\.extraction)
        XCTAssertTrue(statuses.contains { if case .paywalled = $0 { return true } else { return false } })
        XCTAssertTrue(statuses.contains { if case .excerptOnly = $0 { return true } else { return false } })
        XCTAssertTrue(statuses.contains { $0 == .full })
    }
}
