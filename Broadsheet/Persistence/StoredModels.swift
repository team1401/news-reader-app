import Foundation
import SwiftData

// MARK: - Coding

/// One encoder/decoder pair for every blob column, so a value written by one
/// release decodes identically in the next.
enum StoredCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

// MARK: - Source

/// A subscribed feed as it is stored on the device.
@Model
public final class StoredSource {
    /// Normalized feed URL. Unique, so the same feed cannot be subscribed twice.
    @Attribute(.unique) public var id: String
    public var title: String
    public var feedURLString: String
    public var siteURLString: String?
    public var folder: String
    public var isEnabled: Bool
    public var sortIndex: Int
    public var isStarter: Bool
    public var createdAt: Date
    public var lastRefreshedAt: Date?
    public var lastStatusRaw: String
    public var lastErrorMessage: String?
    public var lastItemCount: Int

    @Relationship(deleteRule: .cascade, inverse: \StoredArticle.source)
    public var articles: [StoredArticle]

    public init(source: FeedSource, createdAt: Date = Date()) {
        self.id = source.id
        self.title = source.title
        self.feedURLString = source.feedURL.absoluteString
        self.siteURLString = source.siteURL?.absoluteString
        self.folder = source.folder
        self.isEnabled = source.isEnabled
        self.sortIndex = source.sortIndex
        self.isStarter = source.isStarter
        self.createdAt = createdAt
        self.lastRefreshedAt = source.lastRefreshedAt
        self.lastStatusRaw = source.lastStatus.rawValue
        self.lastErrorMessage = source.lastErrorMessage
        self.lastItemCount = source.lastItemCount
        self.articles = []
    }

    public func apply(_ source: FeedSource) {
        title = source.title
        feedURLString = source.feedURL.absoluteString
        siteURLString = source.siteURL?.absoluteString
        folder = source.folder
        isEnabled = source.isEnabled
        sortIndex = source.sortIndex
        lastRefreshedAt = source.lastRefreshedAt
        lastStatusRaw = source.lastStatus.rawValue
        lastErrorMessage = source.lastErrorMessage
        lastItemCount = source.lastItemCount
    }

    public var lastStatus: SourceRefreshStatus {
        get { SourceRefreshStatus(rawValue: lastStatusRaw) ?? .never }
        set { lastStatusRaw = newValue.rawValue }
    }

    public var value: FeedSource {
        FeedSource(
            feedURL: URL(string: feedURLString) ?? URL(string: "https://invalid.invalid")!,
            title: title,
            siteURL: siteURLString.flatMap(URL.init(string:)),
            folder: folder,
            isEnabled: isEnabled,
            sortIndex: sortIndex,
            isStarter: isStarter,
            lastRefreshedAt: lastRefreshedAt,
            lastStatus: SourceRefreshStatus(rawValue: lastStatusRaw) ?? .never,
            lastErrorMessage: lastErrorMessage,
            lastItemCount: lastItemCount
        )
    }
}

// MARK: - Article

/// A cached semantic article.
///
/// The semantic blocks are stored as encoded ``ArticleBlock`` values rather than
/// publisher HTML, so nothing raw can ever reach the reading surface from the
/// cache either. Original-source metadata (canonical URL, publisher, byline,
/// dates) is stored alongside and never discarded.
@Model
public final class StoredArticle {
    @Attribute(.unique) public var id: String
    /// Stable hash of the rendered content, used for deterministic near-duplicate
    /// detection and to avoid rewriting unchanged rows.
    public var contentHash: String

    public var canonicalURLString: String?
    public var publisherID: String
    public var publisherName: String
    public var publisherDomain: String
    public var baselineRating: String?
    public var baselineProvider: String?
    public var baselineAsOf: Date?

    public var kicker: String?
    public var title: String
    public var dek: String?
    public var author: String?
    public var publishedAt: Date
    public var updatedAt: Date?
    public var fetchedAt: Date

    public var blocksData: Data
    public var heroImageData: Data?
    public var extractionData: Data
    public var contentSourceRaw: String

    public var isSaved: Bool
    public var savedAt: Date?
    public var isRead: Bool
    public var readAt: Date?
    /// Reader's manual label correction. Kept beside the article so it survives a
    /// re-analysis that replaces the model's own estimate.
    public var correctionRaw: String?

    public var source: StoredSource?

    @Relationship(deleteRule: .cascade, inverse: \StoredAnalysis.article)
    public var analysis: StoredAnalysis?

    public init(document: ArticleDocument, source: StoredSource?, fetchedAt: Date) {
        self.id = document.id.rawValue
        self.contentHash = ArticleCanonicalizer.contentHash(for: document)
        self.canonicalURLString = document.canonicalURL?.absoluteString
        self.publisherID = document.publisher.id
        self.publisherName = document.publisher.name
        self.publisherDomain = document.publisher.domain
        self.baselineRating = document.publisher.baseline?.rating
        self.baselineProvider = document.publisher.baseline?.provider
        self.baselineAsOf = document.publisher.baseline?.asOf
        self.kicker = document.kicker
        self.title = document.title
        self.dek = document.dek
        self.author = document.author
        self.publishedAt = document.publishedAt
        self.updatedAt = document.updatedAt
        self.fetchedAt = fetchedAt
        self.blocksData = StoredCoding.encode(document.blocks)
        self.heroImageData = document.heroImage.map { StoredCoding.encode($0) }
        self.extractionData = StoredCoding.encode(document.extraction)
        self.contentSourceRaw = document.contentSource.rawValue
        self.isSaved = false
        self.isRead = false
        self.source = source
    }

    /// Updates the cached content while preserving reader state (saved, read,
    /// correction) and the original first-seen fetch time.
    public func applyContent(_ document: ArticleDocument, fetchedAt: Date) {
        contentHash = ArticleCanonicalizer.contentHash(for: document)
        canonicalURLString = document.canonicalURL?.absoluteString
        publisherID = document.publisher.id
        publisherName = document.publisher.name
        publisherDomain = document.publisher.domain
        baselineRating = document.publisher.baseline?.rating
        baselineProvider = document.publisher.baseline?.provider
        baselineAsOf = document.publisher.baseline?.asOf
        kicker = document.kicker
        title = document.title
        dek = document.dek
        author = document.author
        publishedAt = document.publishedAt
        updatedAt = document.updatedAt
        self.fetchedAt = fetchedAt
        blocksData = StoredCoding.encode(document.blocks)
        heroImageData = document.heroImage.map { StoredCoding.encode($0) }
        extractionData = StoredCoding.encode(document.extraction)
        contentSourceRaw = document.contentSource.rawValue
    }

    public var document: ArticleDocument {
        let baseline: PublisherBaseline?
        if let baselineRating, let baselineProvider, let baselineAsOf {
            baseline = PublisherBaseline(rating: baselineRating, provider: baselineProvider, asOf: baselineAsOf)
        } else {
            baseline = nil
        }

        return ArticleDocument(
            id: ArticleID(rawValue: id),
            canonicalURL: canonicalURLString.flatMap(URL.init(string:)),
            publisher: Publisher(
                id: publisherID,
                name: publisherName,
                domain: publisherDomain,
                baseline: baseline
            ),
            kicker: kicker,
            title: title,
            dek: dek,
            author: author,
            publishedAt: publishedAt,
            updatedAt: updatedAt,
            heroImage: StoredCoding.decode(ArticleImage.self, from: heroImageData),
            blocks: StoredCoding.decode([ArticleBlock].self, from: blocksData) ?? [],
            extraction: StoredCoding.decode(ExtractionStatus.self, from: extractionData) ?? .feedOnly,
            contentSource: ContentSource(rawValue: contentSourceRaw) ?? .liveFeed
        )
    }

    public var correction: BiasLabel? {
        get { correctionRaw.flatMap(BiasLabel.init(rawValue:)) }
        set { correctionRaw = newValue?.rawValue }
    }
}

// MARK: - Analysis

/// A persisted local analysis outcome.
///
/// A failure is recorded too, with its verbatim reason, so the reader sees the same
/// honest status after relaunch instead of a silent blank label.
@Model
public final class StoredAnalysis {
    public var labelRaw: String?
    public var confidenceScore: Double
    public var rationale: String
    public var evidenceData: Data
    public var engineRaw: String
    public var modelVersion: String
    public var analyzedAt: Date
    public var failureReason: String?

    public var article: StoredArticle?

    public init(result: BiasAnalysisResult, analyzedAt: Date = Date()) {
        self.labelRaw = result.label.rawValue
        self.confidenceScore = result.confidenceScore
        self.rationale = result.rationale
        self.evidenceData = StoredCoding.encode(result.evidence)
        self.engineRaw = result.provenance.engine.rawValue
        self.modelVersion = result.provenance.modelVersion
        self.analyzedAt = analyzedAt
        self.failureReason = nil
    }

    public init(failureReason: String, engine: BiasEngine, modelVersion: String, analyzedAt: Date = Date()) {
        self.labelRaw = nil
        self.confidenceScore = 0
        self.rationale = ""
        self.evidenceData = Data()
        self.engineRaw = engine.rawValue
        self.modelVersion = modelVersion
        self.analyzedAt = analyzedAt
        self.failureReason = failureReason
    }

    public func apply(result: BiasAnalysisResult, analyzedAt: Date = Date()) {
        labelRaw = result.label.rawValue
        confidenceScore = result.confidenceScore
        rationale = result.rationale
        evidenceData = StoredCoding.encode(result.evidence)
        engineRaw = result.provenance.engine.rawValue
        modelVersion = result.provenance.modelVersion
        self.analyzedAt = analyzedAt
        failureReason = nil
    }

    public func apply(failureReason: String, engine: BiasEngine, modelVersion: String, analyzedAt: Date = Date()) {
        labelRaw = nil
        confidenceScore = 0
        rationale = ""
        evidenceData = Data()
        engineRaw = engine.rawValue
        self.modelVersion = modelVersion
        self.analyzedAt = analyzedAt
        self.failureReason = failureReason
    }

    public var result: BiasAnalysisResult? {
        guard failureReason == nil,
              let labelRaw,
              let label = BiasLabel(rawValue: labelRaw),
              let engine = BiasEngine(rawValue: engineRaw) else { return nil }

        return BiasAnalysisResult(
            label: label,
            confidenceScore: confidenceScore,
            rationale: rationale,
            evidence: StoredCoding.decode([BiasEvidence].self, from: evidenceData) ?? [],
            provenance: BiasProvenance(engine: engine, modelVersion: modelVersion)
        )
    }

    public var state: BiasAnalysisState {
        if let failureReason { return .unavailable(reason: failureReason) }
        if let result { return .analyzed(result) }
        return .pending
    }
}
