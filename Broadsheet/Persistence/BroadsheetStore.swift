import Foundation
import SwiftData

/// Everything the app reads or writes on disk goes through here.
///
/// Reads and writes run on the main actor. Feed fetching, parsing, extraction, and
/// inference all happen off it; only the short transactional writes land here, and
/// a refresh commits its articles in one `save()` so a crash mid-refresh cannot
/// leave half a feed behind.
@MainActor
public final class BroadsheetStore {
    public let container: ModelContainer
    private let context: ModelContext

    public init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    public convenience init(inMemory: Bool = false) throws {
        self.init(container: inMemory
            ? try PersistenceController.makeInMemoryContainer()
            : try PersistenceController.makeContainer())
    }

    private func commit() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // A failed write must not be silent, and must not be papered over with
            // an in-memory copy that later looks persisted.
            assertionFailure("Broadsheet failed to persist: \(error)")
        }
    }

    // MARK: - Preferences

    public var preferences: StoredPreferences {
        let descriptor = FetchDescriptor<StoredPreferences>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = StoredPreferences()
        context.insert(created)
        commit()
        return created
    }

    public var isDemoModeEnabled: Bool {
        get { preferences.demoModeEnabled }
        set {
            preferences.demoModeEnabled = newValue
            commit()
        }
    }

    public var lastFullRefreshAt: Date? {
        get { preferences.lastFullRefreshAt }
        set {
            preferences.lastFullRefreshAt = newValue
            commit()
        }
    }

    // MARK: - Sources

    public func sources() -> [FeedSource] {
        storedSources().map(\.value)
    }

    public func enabledSources() -> [FeedSource] {
        storedSources().filter(\.isEnabled).map(\.value)
    }

    func storedSources() -> [StoredSource] {
        let descriptor = FetchDescriptor<StoredSource>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.title)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func storedSource(id: String) -> StoredSource? {
        let descriptor = FetchDescriptor<StoredSource>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    public func source(id: String) -> FeedSource? {
        storedSource(id: id)?.value
    }

    public func containsSource(feedURL: URL) -> Bool {
        storedSource(id: FeedURLNormalizer.key(for: feedURL)) != nil
    }

    /// Inserts a new source or updates the existing row with the same normalized
    /// feed URL. Returns the stored value.
    @discardableResult
    public func upsert(_ source: FeedSource) -> FeedSource {
        if let existing = storedSource(id: source.id) {
            existing.apply(source)
            commit()
            return existing.value
        }
        var inserted = source
        if inserted.sortIndex == 0 {
            inserted.sortIndex = (storedSources().map(\.sortIndex).max() ?? -1) + 1
        }
        let record = StoredSource(source: inserted)
        context.insert(record)
        commit()
        return record.value
    }

    public func deleteSource(id: String) {
        guard let record = storedSource(id: id) else { return }
        context.delete(record)
        commit()
    }

    public func setSourceEnabled(_ enabled: Bool, id: String) {
        guard let record = storedSource(id: id) else { return }
        record.isEnabled = enabled
        commit()
    }

    public func recordRefreshOutcome(
        sourceID: String,
        status: SourceRefreshStatus,
        itemCount: Int,
        errorMessage: String?,
        at date: Date
    ) {
        guard let record = storedSource(id: sourceID) else { return }
        record.lastStatus = status
        record.lastRefreshedAt = date
        record.lastErrorMessage = errorMessage
        if status == .succeeded {
            record.lastItemCount = itemCount
        }
        commit()
    }

    /// Seeds the four verified starter feeds exactly once.
    ///
    /// Idempotent in two independent ways: the one-shot flag means a reader who
    /// deletes a starter source never gets it back, and the unique feed-URL key
    /// means a second call cannot duplicate a row even if the flag is cleared.
    @discardableResult
    public func seedStarterSourcesIfNeeded(now: Date = Date()) -> [FeedSource] {
        let prefs = preferences
        guard !prefs.hasSeededStarterSources else { return [] }

        var seeded: [FeedSource] = []
        for starter in StarterSources.all where storedSource(id: starter.id) == nil {
            let record = StoredSource(source: starter, createdAt: now)
            context.insert(record)
            seeded.append(record.value)
        }
        prefs.hasSeededStarterSources = true
        commit()
        return seeded
    }

    // MARK: - Articles

    func storedArticles(limit: Int? = nil) -> [StoredArticle] {
        var descriptor = FetchDescriptor<StoredArticle>(
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse), SortDescriptor(\.id)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return (try? context.fetch(descriptor)) ?? []
    }

    func storedArticle(id: ArticleID) -> StoredArticle? {
        let key = id.rawValue
        let descriptor = FetchDescriptor<StoredArticle>(predicate: #Predicate { $0.id == key })
        return (try? context.fetch(descriptor))?.first
    }

    public func articles(limit: Int? = nil) -> [ArticleDocument] {
        storedArticles(limit: limit).map(\.document)
    }

    public func article(id: ArticleID) -> ArticleDocument? {
        storedArticle(id: id)?.document
    }

    /// Cached article count per source, read from the relationship rather than
    /// matched by domain — a feed host and a site host are frequently different.
    public func articleCountsBySource() -> [String: Int] {
        storedSources().reduce(into: [String: Int]()) { counts, source in
            counts[source.id] = source.articles.count
        }
    }

    public func articleCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<StoredArticle>())) ?? 0
    }

    /// Writes a refresh's articles in a single transaction.
    ///
    /// Existing rows keep their reader state and their first-seen `fetchedAt`;
    /// unchanged content is left untouched so a refresh does not churn the store.
    @discardableResult
    public func persistArticles(
        _ documents: [ArticleDocument],
        sourceID: String?,
        fetchedAt: Date
    ) -> [ArticleDocument] {
        let stored = storedSource(id: sourceID ?? "")
        var results: [ArticleDocument] = []

        // Batch deduplication is not enough: a publisher can republish tomorrow's
        // copy at a new URL. Index the existing cache by the same publisher+title
        // key so the new copy updates the old row and preserves saved/read state,
        // analysis, and corrections instead of creating a duplicate.
        var existingByNearDuplicateKey: [String: StoredArticle] = [:]
        for record in storedArticles() {
            let key = ArticleCanonicalizer.nearDuplicateKey(for: record.document)
            if let current = existingByNearDuplicateKey[key] {
                let preferred = ArticleCanonicalizer.preferred(current.document, record.document)
                if preferred.id == record.document.id {
                    existingByNearDuplicateKey[key] = record
                }
            } else {
                existingByNearDuplicateKey[key] = record
            }
        }

        for document in ArticleCanonicalizer.deduplicate(documents) {
            let exact = storedArticle(id: document.id)
            let nearKey = ArticleCanonicalizer.nearDuplicateKey(for: document)
            if let existing = exact ?? existingByNearDuplicateKey[nearKey] {
                let hash = ArticleCanonicalizer.contentHash(for: document)
                let shouldApplyIncoming: Bool
                if exact != nil {
                    shouldApplyIncoming = existing.contentHash != hash
                } else {
                    shouldApplyIncoming = ArticleCanonicalizer.preferred(existing.document, document).id == document.id
                }
                if shouldApplyIncoming {
                    existing.applyContent(document, fetchedAt: existing.fetchedAt)
                }
                if existing.source == nil, let stored { existing.source = stored }
                results.append(existing.document)
                existingByNearDuplicateKey[nearKey] = existing
            } else {
                let record = StoredArticle(document: document, source: stored, fetchedAt: fetchedAt)
                context.insert(record)
                results.append(record.document)
                existingByNearDuplicateKey[nearKey] = record
            }
        }

        commit()
        return results
    }

    /// Caps the cache per source, newest first. Saved stories are never pruned.
    public func pruneArticles(maxPerSource: Int) {
        for source in storedSources() {
            let ordered = source.articles
                .filter { !$0.isSaved }
                .sorted { lhs, rhs in
                    lhs.publishedAt == rhs.publishedAt ? lhs.id < rhs.id : lhs.publishedAt > rhs.publishedAt
                }
            guard ordered.count > maxPerSource else { continue }
            for record in ordered.dropFirst(maxPerSource) {
                context.delete(record)
            }
        }
        commit()
    }

    // MARK: - Reader state

    public func savedArticles() -> [ArticleDocument] {
        let descriptor = FetchDescriptor<StoredArticle>(
            predicate: #Predicate { $0.isSaved },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse), SortDescriptor(\.id)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.document)
    }

    public func isSaved(_ id: ArticleID) -> Bool {
        storedArticle(id: id)?.isSaved ?? false
    }

    public func setSaved(_ saved: Bool, id: ArticleID, at date: Date = Date()) {
        guard let record = storedArticle(id: id) else { return }
        record.isSaved = saved
        record.savedAt = saved ? date : nil
        commit()
    }

    public func markRead(_ id: ArticleID, at date: Date = Date()) {
        guard let record = storedArticle(id: id), !record.isRead else { return }
        record.isRead = true
        record.readAt = date
        commit()
    }

    public func isRead(_ id: ArticleID) -> Bool {
        storedArticle(id: id)?.isRead ?? false
    }

    // MARK: - Analysis

    public func analysisStates() -> [ArticleID: BiasAnalysisState] {
        var states: [ArticleID: BiasAnalysisState] = [:]
        for record in storedArticles() {
            guard let analysis = record.analysis else { continue }
            let state = analysis.state
            if state != .pending {
                states[ArticleID(rawValue: record.id)] = state
            }
        }
        return states
    }

    public func persistAnalysis(_ result: BiasAnalysisResult, for id: ArticleID, at date: Date = Date()) {
        guard let record = storedArticle(id: id) else { return }
        if let existing = record.analysis {
            existing.apply(result: result, analyzedAt: date)
        } else {
            let analysis = StoredAnalysis(result: result, analyzedAt: date)
            analysis.article = record
            context.insert(analysis)
        }
        commit()
    }

    public func persistAnalysisFailure(
        reason: String,
        engine: BiasEngine,
        modelVersion: String,
        for id: ArticleID,
        at date: Date = Date()
    ) {
        guard let record = storedArticle(id: id) else { return }
        if let existing = record.analysis {
            existing.apply(failureReason: reason, engine: engine, modelVersion: modelVersion, analyzedAt: date)
        } else {
            let analysis = StoredAnalysis(
                failureReason: reason,
                engine: engine,
                modelVersion: modelVersion,
                analyzedAt: date
            )
            analysis.article = record
            context.insert(analysis)
        }
        commit()
    }

    public func corrections() -> [ArticleID: BiasLabel] {
        var result: [ArticleID: BiasLabel] = [:]
        for record in storedArticles() {
            if let correction = record.correction {
                result[ArticleID(rawValue: record.id)] = correction
            }
        }
        return result
    }

    /// A correction is stored beside the article, not inside the analysis row, so
    /// re-running the model replaces its estimate without discarding the reader's.
    public func setCorrection(_ label: BiasLabel?, for id: ArticleID) {
        guard let record = storedArticle(id: id) else { return }
        record.correction = label
        commit()
    }

    // MARK: - Test and reset support

    public func deleteEverything() {
        for record in storedArticles() { context.delete(record) }
        for record in storedSources() { context.delete(record) }
        commit()
    }
}

/// Analysis results are written straight through to the store, so a label computed
/// during a refresh is on the card again after relaunch without recomputing it.
extension BroadsheetStore: BiasAnalysisPersisting {}
