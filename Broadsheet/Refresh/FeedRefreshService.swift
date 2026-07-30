import Foundation

public struct SourceRefreshOutcome: Equatable, Sendable, Identifiable {
    public let sourceID: String
    public let sourceTitle: String
    public let status: SourceRefreshStatus
    public let itemCount: Int
    public let newItemCount: Int
    public let errorMessage: String?

    public var id: String { sourceID }
    public var didFail: Bool { status == .failed }
}

public struct RefreshReport: Equatable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let outcomes: [SourceRefreshOutcome]

    public var failures: [SourceRefreshOutcome] { outcomes.filter(\.didFail) }
    public var successes: [SourceRefreshOutcome] { outcomes.filter { $0.status == .succeeded } }
    public var totalItems: Int { outcomes.reduce(0) { $0 + $1.itemCount } }
    public var newItems: Int { outcomes.reduce(0) { $0 + $1.newItemCount } }

    /// A short, honest sentence for the masthead.
    public var summary: String {
        if outcomes.isEmpty { return "No sources are enabled." }
        if failures.isEmpty { return "\(successes.count) of \(outcomes.count) sources refreshed." }
        return "\(successes.count) of \(outcomes.count) sources refreshed · \(failures.count) failed."
    }

    public static let empty = RefreshReport(startedAt: .distantPast, finishedAt: .distantPast, outcomes: [])
}

/// Fetches every enabled source, resolves each item's content, and commits the
/// result — without ever letting one bad source take the library with it.
///
/// A failing source keeps its cached articles and gets a recorded reason. A slow
/// source cannot stall the others past its own timeout. Nothing is deleted on
/// failure, so an offline launch still shows yesterday's paper.
@MainActor
public final class FeedRefreshService {
    /// Sources fetched at once. Small on purpose: four feeds fetched politely is
    /// not the same as four feeds hammered in parallel with everything else.
    public static let sourceConcurrency = 3
    /// Newest items resolved per source per refresh. Older items are still stored
    /// from the feed; this only bounds how many full pages are fetched.
    public static let maximumResolvedItemsPerSource = 25
    /// Cached articles kept per source.
    public static let articleRetentionPerSource = 200

    private let store: BroadsheetStore
    private let transport: any HTTPTransport
    private let resolver: ArticleResolver
    private let analysis: BiasAnalysisService

    public private(set) var isRefreshing = false
    public private(set) var lastReport: RefreshReport = .empty

    public init(
        store: BroadsheetStore,
        transport: any HTTPTransport,
        resolver: ArticleResolver,
        analysis: BiasAnalysisService
    ) {
        self.store = store
        self.transport = transport
        self.resolver = resolver
        self.analysis = analysis
    }

    @discardableResult
    public func refreshAll(now: Date = Date()) async -> RefreshReport {
        let sources = store.enabledSources()
        return await refresh(sources: sources, now: now)
    }

    @discardableResult
    public func refresh(sources: [FeedSource], now: Date = Date()) async -> RefreshReport {
        guard !isRefreshing else { return lastReport }
        isRefreshing = true
        defer { isRefreshing = false }

        let startedAt = now
        var outcomes: [SourceRefreshOutcome] = []
        var persisted: [ArticleDocument] = []

        // Fetch and parse concurrently; commit serially so each source's items land
        // in one transaction and the store is never touched from two places.
        var index = 0
        while index < sources.count {
            let window = Array(sources[index..<min(index + FeedRefreshService.sourceConcurrency, sources.count)])
            index += window.count

            let fetched = await withTaskGroup(of: (Int, Result<ParsedFeed, any Error>).self) { group -> [(Int, Result<ParsedFeed, any Error>)] in
                for (offset, source) in window.enumerated() {
                    let transport = self.transport
                    group.addTask {
                        do {
                            let response = try await transport.fetch(
                                source.feedURL,
                                accept: HTTPAccept.feed,
                                limits: .feed
                            )
                            let feed = try FeedDocumentParser.parse(
                                response.data,
                                contentType: response.mimeType,
                                feedURL: response.finalURL
                            )
                            return (offset, .success(feed))
                        } catch {
                            return (offset, .failure(error))
                        }
                    }
                }
                var collected: [(Int, Result<ParsedFeed, any Error>)] = []
                for await item in group { collected.append(item) }
                return collected.sorted { $0.0 < $1.0 }
            }

            for (offset, result) in fetched {
                let source = window[offset]
                switch result {
                case .failure(let error):
                    let message = describe(error)
                    store.recordRefreshOutcome(
                        sourceID: source.id,
                        status: .failed,
                        itemCount: 0,
                        errorMessage: message,
                        at: now
                    )
                    outcomes.append(SourceRefreshOutcome(
                        sourceID: source.id,
                        sourceTitle: source.title,
                        status: .failed,
                        itemCount: 0,
                        newItemCount: 0,
                        errorMessage: message
                    ))
                case .success(let feed):
                    let stored = await ingest(feed: feed, source: source, now: now)
                    persisted.append(contentsOf: stored.documents)
                    store.recordRefreshOutcome(
                        sourceID: source.id,
                        status: .succeeded,
                        itemCount: feed.items.count,
                        errorMessage: nil,
                        at: now
                    )
                    outcomes.append(SourceRefreshOutcome(
                        sourceID: source.id,
                        sourceTitle: source.title,
                        status: .succeeded,
                        itemCount: feed.items.count,
                        newItemCount: stored.newCount,
                        errorMessage: nil
                    ))
                }
            }
        }

        store.pruneArticles(maxPerSource: FeedRefreshService.articleRetentionPerSource)
        store.lastFullRefreshAt = now

        // Eager analysis, as specified: the label is computed during refresh so it
        // is already on the card when the story appears.
        await analysis.analyzeEagerly(persisted)

        let report = RefreshReport(startedAt: startedAt, finishedAt: Date(), outcomes: outcomes)
        lastReport = report
        return report
    }

    // MARK: Ingest

    private func ingest(
        feed: ParsedFeed,
        source: FeedSource,
        now: Date
    ) async -> (documents: [ArticleDocument], newCount: Int) {
        let mapped = FeedArticleMapper.articles(from: feed, source: source, fetchedAt: now)

        // Deduplicate before resolving, so the same story is never fetched twice.
        let deduplicated = ArticleCanonicalizer.deduplicate(mapped.map(\.document))
        var contentByID: [ArticleID: String] = [:]
        for pair in mapped {
            if let html = pair.contentHTML { contentByID[pair.document.id] = html }
        }

        let knownIDs = Set(deduplicated.compactMap { store.article(id: $0.id) != nil ? $0.id : nil })
        let toResolve = deduplicated.prefix(FeedRefreshService.maximumResolvedItemsPerSource)

        var resolved: [ArticleDocument] = []
        for document in toResolve {
            // Already-resolved articles are not re-fetched: a refresh should not
            // re-request every publisher page it has ever seen.
            if let existing = store.article(id: document.id), existing.extraction == .full {
                resolved.append(existing)
                continue
            }
            resolved.append(await resolver.resolve(document, feedContentHTML: contentByID[document.id], now: now))
        }
        resolved.append(contentsOf: deduplicated.dropFirst(FeedRefreshService.maximumResolvedItemsPerSource))

        let documents = store.persistArticles(resolved, sourceID: source.id, fetchedAt: now)
        let newCount = documents.filter { !knownIDs.contains($0.id) }.count
        return (documents, newCount)
    }

    private func describe(_ error: any Error) -> String {
        if let fetchError = error as? HTTPFetchError {
            return fetchError.errorDescription ?? "The feed could not be fetched."
        }
        if let parseError = error as? FeedParsingError {
            return parseError.errorDescription ?? "The feed could not be parsed."
        }
        return error.localizedDescription
    }
}
