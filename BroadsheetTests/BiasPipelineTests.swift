import XCTest
@testable import Broadsheet

/// Records how many times it ran so cache behaviour is observable.
private final class CountingAnalyzer: BiasAnalyzing, @unchecked Sendable {
    let engine: BiasEngine
    let isAvailable: Bool
    let availabilityDescription = "Test analyzer"
    private let failure: BiasAnalysisError?
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    init(engine: BiasEngine = .deterministicFixture, isAvailable: Bool = true, failure: BiasAnalysisError? = nil) {
        self.engine = engine
        self.isAvailable = isAvailable
        self.failure = failure
    }

    func analyze(_ input: BiasModelInput) async throws -> BiasAnalysisResult {
        lock.lock()
        _callCount += 1
        lock.unlock()

        if let failure { throw failure }

        return BiasAnalysisResult(
            label: .center,
            confidenceScore: 0.7,
            rationale: "Counted analysis",
            evidence: [],
            provenance: BiasProvenance(engine: engine, modelVersion: "test-1")
        )
    }
}

final class BiasAnalysisCacheTests: XCTestCase {

    private func key(_ url: String) -> BiasAnalysisCache.Key {
        BiasAnalysisCache.Key(
            articleID: ArticleID(canonicalURL: URL(string: url)!),
            engine: .deterministicFixture,
            modelVersion: "fixture-heuristic-1.0"
        )
    }

    private func result(_ label: BiasLabel) -> BiasAnalysisResult {
        BiasAnalysisResult(
            label: label, confidenceScore: 0.8, rationale: "r", evidence: [],
            provenance: BiasProvenance(engine: .deterministicFixture, modelVersion: "fixture-heuristic-1.0")
        )
    }

    func testComputesOnceAndServesFromCacheAfterwards() async throws {
        let cache = BiasAnalysisCache()
        let counter = Counter()

        let first = try await cache.result(for: key("https://meridianwire.example/a")) {
            await counter.increment()
            return self.result(.left)
        }
        let second = try await cache.result(for: key("https://meridianwire.example/a")) {
            await counter.increment()
            return self.result(.right)
        }

        XCTAssertEqual(first.label, .left)
        XCTAssertEqual(second.label, .left, "The cached result must win over a fresh computation")
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testCacheIsKeyedByArticleIdentityNotByURLSpelling() async throws {
        let cache = BiasAnalysisCache()

        _ = try await cache.result(for: key("https://meridianwire.example/a")) { self.result(.left) }
        let tracked = try await cache.result(for: key("https://WWW.meridianwire.example/a/?utm_source=rss")) {
            self.result(.right)
        }

        XCTAssertEqual(tracked.label, .left)
        let count = await cache.count
        XCTAssertEqual(count, 1)
    }

    func testDistinctArticlesAreCachedSeparately() async throws {
        let cache = BiasAnalysisCache()

        _ = try await cache.result(for: key("https://meridianwire.example/a")) { self.result(.left) }
        _ = try await cache.result(for: key("https://meridianwire.example/b")) { self.result(.right) }

        let count = await cache.count
        XCTAssertEqual(count, 2)
    }

    func testFailuresAreNotCachedSoAnUnavailableModelCanRecover() async throws {
        let cache = BiasAnalysisCache()
        let target = key("https://meridianwire.example/a")

        do {
            _ = try await cache.result(for: target) {
                throw BiasAnalysisError.localModelUnavailable(reason: "not ready")
            }
            XCTFail("Expected the error to propagate")
        } catch {
            XCTAssertEqual(error as? BiasAnalysisError, .localModelUnavailable(reason: "not ready"))
        }

        let recovered = try await cache.result(for: target) { self.result(.center) }
        XCTAssertEqual(recovered.label, .center)
    }

    func testConcurrentRequestsForOneArticleShareASingleComputation() async throws {
        let cache = BiasAnalysisCache()
        let counter = Counter()
        let target = key("https://meridianwire.example/a")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    _ = try? await cache.result(for: target) {
                        await counter.increment()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        return self.result(.center)
                    }
                }
            }
        }

        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testRemoveAllClearsStoredResults() async throws {
        let cache = BiasAnalysisCache()
        _ = try await cache.result(for: key("https://meridianwire.example/a")) { self.result(.left) }
        await cache.removeAll()

        let count = await cache.count
        XCTAssertEqual(count, 0)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@MainActor
final class BiasAnalysisServiceTests: XCTestCase {

    private func fixtureArticle(source: ContentSource) -> ArticleDocument {
        let canonical = URL(string: "https://meridianwire.example/law/water-rule")!
        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: DemoPublishers.meridianWire,
            title: "Appeals Court Vacates Water Allocation Rule",
            dek: "The panel returned the rule to the agency for a new rulemaking.",
            author: "Tomas Beaulieu",
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            blocks: [
                .paragraph(RichText("A federal appeals court vacated the basin water allocation rule and sent it back to the agency for a new rulemaking, holding that it had not explained its departure from the earlier formula.")),
                .paragraph(RichText("Vacatur takes effect in ninety days, so deliveries scheduled by the commission for this season proceed as published."))
            ],
            contentSource: source
        )
    }

    func testEagerAnalysisFillsStateBeforeTheCardIsTapped() async {
        let service = BiasAnalysisService(
            fixtureAnalyzer: DeterministicFixtureBiasAnalyzer(),
            localModelAnalyzer: CountingAnalyzer(engine: .appleFoundationModels)
        )
        let edition = DemoEdition.edition(referenceDate: Date(timeIntervalSince1970: 1_800_000_000))

        await service.analyzeEagerly(edition.allArticles)

        for article in edition.allArticles {
            XCTAssertNotNil(service.state(for: article).result, "No label ready for “\(article.title)”")
        }
    }

    func testBundledFixtureContentUsesTheFixtureHeuristic() async {
        let localModel = CountingAnalyzer(engine: .appleFoundationModels)
        let service = BiasAnalysisService(
            fixtureAnalyzer: DeterministicFixtureBiasAnalyzer(),
            localModelAnalyzer: localModel
        )

        let state = await service.analyze(fixtureArticle(source: .bundledFixture))

        XCTAssertEqual(state.result?.provenance.engine, .deterministicFixture)
        XCTAssertEqual(localModel.callCount, 0, "Demo content must not be attributed to the system model")
    }

    func testLiveFeedContentUsesTheLocalModel() async {
        let localModel = CountingAnalyzer(engine: .appleFoundationModels)
        let service = BiasAnalysisService(
            fixtureAnalyzer: DeterministicFixtureBiasAnalyzer(),
            localModelAnalyzer: localModel
        )

        let state = await service.analyze(fixtureArticle(source: .liveFeed))

        XCTAssertEqual(state.result?.provenance.engine, .appleFoundationModels)
        XCTAssertEqual(localModel.callCount, 1)
    }

    /// The rule that matters most: when the real model cannot run, the app says so
    /// rather than silently substituting the fixture heuristic.
    func testUnavailableLocalModelYieldsAnExplicitUnavailableStateNotAFallbackLabel() async {
        let service = BiasAnalysisService(
            fixtureAnalyzer: DeterministicFixtureBiasAnalyzer(),
            localModelAnalyzer: CountingAnalyzer(
                engine: .appleFoundationModels,
                isAvailable: false,
                failure: .localModelUnavailable(reason: "Apple Intelligence is turned off.")
            )
        )

        let state = await service.analyze(fixtureArticle(source: .liveFeed))

        guard case .unavailable(let reason) = state else {
            return XCTFail("Expected an unavailable state, got \(state)")
        }
        XCTAssertEqual(reason, "Apple Intelligence is turned off.")
        XCTAssertNil(state.result)
    }

    func testRepeatedAnalysisReusesTheCachedResult() async {
        let localModel = CountingAnalyzer(engine: .appleFoundationModels)
        let service = BiasAnalysisService(
            fixtureAnalyzer: DeterministicFixtureBiasAnalyzer(),
            localModelAnalyzer: localModel
        )
        let article = fixtureArticle(source: .liveFeed)

        await service.analyze(article)
        await service.analyze(article)

        XCTAssertEqual(localModel.callCount, 1)
    }

    func testCorrectionsAreRecordedWithoutOverwritingTheEstimate() async {
        let service = BiasAnalysisService(
            fixtureAnalyzer: DeterministicFixtureBiasAnalyzer(),
            localModelAnalyzer: CountingAnalyzer()
        )
        let article = fixtureArticle(source: .bundledFixture)
        let state = await service.analyze(article)

        service.recordCorrection(.right, for: article)

        XCTAssertEqual(service.correction(for: article), .right)
        XCTAssertEqual(service.state(for: article).result?.label, state.result?.label)

        service.recordCorrection(nil, for: article)
        XCTAssertNil(service.correction(for: article))
    }
}
