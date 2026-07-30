import Foundation
import Observation

/// Runs article-lean analysis eagerly during refresh and publishes per-article
/// state so the label is already present when a story card appears.
///
/// Analyzer selection is deliberate and not a fallback chain:
/// - ``ContentSource/bundledFixture`` articles use the deterministic fixture
///   heuristic, so demo screenshots and tests are reproducible.
/// - ``ContentSource/liveFeed`` articles use the real on-device language model. If
///   it cannot run, the state becomes ``BiasAnalysisState/unavailable(reason:)``.
///   The fixture heuristic is never substituted for a real model, because that
///   would present a rule-based guess as machine analysis.
@MainActor
@Observable
public final class BiasAnalysisService {
    public private(set) var states: [ArticleID: BiasAnalysisState] = [:]

    private let cache: BiasAnalysisCache
    private let fixtureAnalyzer: any BiasAnalyzing
    private let localModelAnalyzer: any BiasAnalyzing

    /// Reader corrections, kept on the device. They are recorded for evaluation and
    /// never rewrite the model's own estimate.
    public private(set) var corrections: [ArticleID: BiasLabel] = [:]

    public init(
        cache: BiasAnalysisCache = BiasAnalysisCache(),
        fixtureAnalyzer: any BiasAnalyzing = DeterministicFixtureBiasAnalyzer(),
        localModelAnalyzer: any BiasAnalyzing = FoundationModelsBiasAnalyzer()
    ) {
        self.cache = cache
        self.fixtureAnalyzer = fixtureAnalyzer
        self.localModelAnalyzer = localModelAnalyzer
    }

    public var localModelAvailabilityDescription: String {
        localModelAnalyzer.availabilityDescription
    }

    public var isLocalModelAvailable: Bool {
        localModelAnalyzer.isAvailable
    }

    public func state(for article: ArticleDocument) -> BiasAnalysisState {
        states[article.id] ?? .pending
    }

    public func correction(for article: ArticleDocument) -> BiasLabel? {
        corrections[article.id]
    }

    public func recordCorrection(_ label: BiasLabel?, for article: ArticleDocument) {
        if let label {
            corrections[article.id] = label
        } else {
            corrections.removeValue(forKey: article.id)
        }
    }

    private func analyzer(for article: ArticleDocument) -> any BiasAnalyzing {
        switch article.contentSource {
        case .bundledFixture: return fixtureAnalyzer
        case .liveFeed: return localModelAnalyzer
        }
    }

    /// Analyzes a batch during refresh, prioritizing headline and dek so the badge
    /// is ready before the reader scrolls to the story.
    public func analyzeEagerly(_ articles: [ArticleDocument]) async {
        await withTaskGroup(of: Void.self) { group in
            for article in articles where states[article.id]?.result == nil {
                group.addTask { @MainActor in
                    await self.analyze(article)
                }
            }
        }
    }

    @discardableResult
    public func analyze(_ article: ArticleDocument) async -> BiasAnalysisState {
        if let existing = states[article.id], existing.result != nil {
            return existing
        }

        let analyzer = self.analyzer(for: article)
        states[article.id] = .analyzing

        let key = BiasAnalysisCache.Key(
            articleID: article.id,
            engine: analyzer.engine,
            modelVersion: modelVersion(for: analyzer)
        )
        let input = BiasModelInputBuilder.build(from: article)

        let state: BiasAnalysisState
        do {
            let result = try await cache.result(for: key) {
                try await analyzer.analyze(input)
            }
            state = .analyzed(result)
        } catch let error as BiasAnalysisError {
            state = .unavailable(reason: error.errorDescription ?? "Local analysis could not run.")
        } catch {
            state = .unavailable(reason: error.localizedDescription)
        }

        states[article.id] = state
        return state
    }

    private func modelVersion(for analyzer: any BiasAnalyzing) -> String {
        switch analyzer.engine {
        case .deterministicFixture: return DeterministicFixtureBiasAnalyzer.version
        case .appleFoundationModels: return FoundationModelsBiasAnalyzer.version
        }
    }

    public func reset() async {
        states.removeAll()
        await cache.removeAll()
    }
}
