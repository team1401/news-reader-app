import Foundation
import Observation
import SwiftUI

/// Reader preferences from the shape brief: text size and serif/sans body.
@Observable
public final class ReaderSettings {
    public enum BodyFace: String, CaseIterable, Identifiable {
        case serif
        case sans

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .serif: return "Serif"
            case .sans: return "Sans"
            }
        }
    }

    public var bodyFace: BodyFace = .serif
    public var textSize: DynamicTypeSize = .large

    public init() {}

    public func bodyFont(_ style: Font.TextStyle) -> Font {
        switch bodyFace {
        case .serif: return BSFont.serif(style)
        case .sans: return BSFont.sans(style)
        }
    }

    public func increaseTextSize() {
        if let next = DynamicTypeSize.allCases.first(where: { $0 > textSize }) {
            textSize = min(next, .accessibility3)
        }
    }

    public func decreaseTextSize() {
        if let previous = DynamicTypeSize.allCases.last(where: { $0 < textSize }) {
            textSize = max(previous, .xSmall)
        }
    }
}

/// A source and how much of the library it accounts for.
public struct SourceSummary: Identifiable, Equatable, Sendable {
    public let source: FeedSource
    public let articleCount: Int
    public var id: String { source.id }
}

/// Application state.
///
/// Live, persisted articles are the app. The bundled demo edition is an explicit,
/// offline-only preview the reader turns on in Library: it never mixes with real
/// reporting, it is never refreshed from the network, and it is never written to
/// the library.
@MainActor
@Observable
public final class AppModel {
    public let store: BroadsheetStore
    public let analysis: BiasAnalysisService
    public let settings = ReaderSettings()

    private let refreshService: FeedRefreshService?
    private let validator: SourceValidator?

    public private(set) var edition: EditionContent?
    public private(set) var liveArticles: [ArticleDocument] = []
    public private(set) var sourceSummaries: [SourceSummary] = []
    public private(set) var isRefreshing = false
    public private(set) var lastReport: RefreshReport = .empty
    public private(set) var lastRefreshedAt: Date?
    public private(set) var hasBootstrapped = false

    /// Demo saves are kept in memory so bundled fiction never lands in the
    /// reader's real library.
    private var demoSavedIDs: [ArticleID] = []
    private var demoEdition: EditionContent?

    public init(
        store: BroadsheetStore,
        transport: (any HTTPTransport)? = nil,
        analysis: BiasAnalysisService? = nil,
        buildsPipeline: Bool = true
    ) {
        self.store = store
        let analysisService = analysis ?? BiasAnalysisService()
        self.analysis = analysisService

        if buildsPipeline {
            let transport = transport ?? URLSessionHTTPTransport()
            let robots = RobotsPolicy(transport: transport)
            let resolver = ArticleResolver(transport: transport, robots: robots)
            self.refreshService = FeedRefreshService(
                store: store,
                transport: transport,
                resolver: resolver,
                analysis: analysisService
            )
            self.validator = SourceValidator(transport: transport)
        } else {
            self.refreshService = nil
            self.validator = nil
        }

        analysisService.persistence = store
        self.lastRefreshedAt = store.lastFullRefreshAt
    }

    /// An offline model for SwiftUI previews and pure-logic tests: in-memory
    /// store, no networking, bundled demo content.
    public static func preview() -> AppModel {
        let store = try! BroadsheetStore(inMemory: true)
        let model = AppModel(store: store, buildsPipeline: false)
        model.isDemoMode = true
        return model
    }

    // MARK: - Lifecycle

    /// First launch seeds the four verified starter sources; every launch restores
    /// persisted articles and their labels before anything is recomputed.
    public func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        store.seedStarterSourcesIfNeeded()
        analysis.hydrate(states: store.analysisStates(), corrections: store.corrections())
        reload()
    }

    public func reload() {
        liveArticles = store.articles()
        edition = EditionBuilder.build(from: liveArticles, referenceDate: Date())
        lastRefreshedAt = store.lastFullRefreshAt
        reloadSources()
    }

    private func reloadSources() {
        let counts = store.articleCountsBySource()
        sourceSummaries = store.sources().map {
            SourceSummary(source: $0, articleCount: counts[$0.id] ?? 0)
        }
    }

    // MARK: - Demo mode

    public var isDemoMode: Bool {
        get { store.isDemoModeEnabled }
        set {
            store.isDemoModeEnabled = newValue
            if newValue, demoEdition == nil {
                demoEdition = DemoEdition.edition()
            }
            Task { await analyzeVisible() }
        }
    }

    /// The edition on screen: the bundled preview when demo mode is on, otherwise
    /// whatever the last refresh persisted.
    public var displayedEdition: EditionContent? {
        if isDemoMode {
            if demoEdition == nil { demoEdition = DemoEdition.edition() }
            return demoEdition
        }
        return edition
    }

    public var allArticles: [ArticleDocument] {
        isDemoMode ? (displayedEdition?.allArticles ?? []) : liveArticles
    }

    public var sources: [FeedSource] {
        sourceSummaries.map(\.source)
    }

    public var enabledSourceCount: Int {
        sourceSummaries.filter(\.source.isEnabled).count
    }

    // MARK: - Articles

    public func article(with id: ArticleID) -> ArticleDocument? {
        if isDemoMode { return allArticles.first { $0.id == id } }
        return store.article(id: id) ?? liveArticles.first { $0.id == id }
    }

    public var savedArticles: [ArticleDocument] {
        if isDemoMode {
            return demoSavedIDs.compactMap { id in allArticles.first { $0.id == id } }
        }
        return store.savedArticles()
    }

    public func isSaved(_ article: ArticleDocument) -> Bool {
        isDemoMode ? demoSavedIDs.contains(article.id) : store.isSaved(article.id)
    }

    public func toggleSaved(_ article: ArticleDocument) {
        if isDemoMode {
            if let index = demoSavedIDs.firstIndex(of: article.id) {
                demoSavedIDs.remove(at: index)
            } else {
                demoSavedIDs.insert(article.id, at: 0)
            }
            return
        }
        store.setSaved(!store.isSaved(article.id), id: article.id)
    }

    public func removeSaved(_ article: ArticleDocument) {
        if isDemoMode {
            demoSavedIDs.removeAll { $0 == article.id }
            return
        }
        store.setSaved(false, id: article.id)
    }

    public func markRead(_ article: ArticleDocument) {
        guard !isDemoMode else { return }
        store.markRead(article.id)
    }

    // MARK: - Refresh

    public var canRefresh: Bool {
        refreshService != nil && !isDemoMode && enabledSourceCount > 0
    }

    public func refresh() async {
        guard let refreshService, !isDemoMode, !isRefreshing else {
            await analyzeVisible()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        lastReport = await refreshService.refreshAll()
        reload()
    }

    public func refreshSource(id: String) async {
        guard let refreshService, let source = store.source(id: id) else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastReport = await refreshService.refresh(sources: [source])
        reload()
    }

    /// Analysis for whatever is currently on screen. Live articles go to the real
    /// on-device model; demo fiction goes to the deterministic fixture heuristic.
    public func analyzeVisible() async {
        await analysis.analyzeEagerly(allArticles)
    }

    public func state(for article: ArticleDocument) -> BiasAnalysisState {
        analysis.state(for: article)
    }

    // MARK: - Source management

    public func validateCandidates(for input: String) async throws -> [FeedCandidate] {
        guard let validator else {
            throw SourceValidationError.notAFeed(reason: "Networking is disabled in this build.")
        }
        return try await validator.candidates(for: input)
    }

    @discardableResult
    public func addSource(_ candidate: FeedCandidate, folder: String = FeedSource.defaultFolder) -> FeedSource {
        let source = store.upsert(candidate.makeSource(folder: folder))
        reloadSources()
        return source
    }

    public func update(_ source: FeedSource) {
        store.upsert(source)
        reloadSources()
    }

    public func setSourceEnabled(_ enabled: Bool, id: String) {
        store.setSourceEnabled(enabled, id: id)
        reloadSources()
    }

    public func deleteSource(id: String) {
        store.deleteSource(id: id)
        reload()
    }

    public var folders: [String] {
        Array(Set(sources.map(\.folder))).sorted()
    }

    public func isAlreadySubscribed(_ candidate: FeedCandidate) -> Bool {
        store.containsSource(feedURL: candidate.feedURL)
    }

    // MARK: - Corrections

    public func correction(for article: ArticleDocument) -> BiasLabel? {
        analysis.correction(for: article)
    }

    public func recordCorrection(_ label: BiasLabel?, for article: ArticleDocument) {
        analysis.recordCorrection(label, for: article)
    }
}
