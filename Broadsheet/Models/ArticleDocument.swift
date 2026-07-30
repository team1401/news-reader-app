import Foundation

// MARK: - Stable identity

/// Stable identity for an article across refreshes.
///
/// Feeds re-publish the same story with changing tracking parameters, mixed host
/// casing, and inconsistent trailing slashes. Identity is therefore derived from a
/// normalized canonical URL, or from a publisher-supplied GUID when it is opaque.
public struct ArticleID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(canonicalURL: URL) {
        self.rawValue = ArticleID.normalizedKey(for: canonicalURL)
    }

    /// Prefers the normalized canonical URL. A GUID is only used when no usable
    /// link exists, because GUIDs are frequently publisher-local counters.
    public init(canonicalURL: URL?, guid: String?) {
        if let canonicalURL {
            self.rawValue = ArticleID.normalizedKey(for: canonicalURL)
        } else if let guid, !guid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.rawValue = "guid:" + guid.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.rawValue = "unidentified:" + UUID().uuidString
        }
    }

    public var description: String { rawValue }

    /// Query parameters that only describe how a reader arrived at a story.
    static let trackingParameterPrefixes = ["utm_", "mc_", "pk_"]
    static let trackingParameterNames: Set<String> = [
        "fbclid", "gclid", "igshid", "cmpid", "cmp", "ref", "referrer", "src",
        "smid", "partner", "ito", "at_medium", "at_campaign", "s"
    ]

    public static func normalizedKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.user = nil
        components.password = nil

        if let host = components.host, host.hasPrefix("www.") {
            components.host = String(host.dropFirst(4))
        }
        if let port = components.port,
           (components.scheme == "https" && port == 443) || (components.scheme == "http" && port == 80) {
            components.port = nil
        }

        if let items = components.queryItems {
            let kept = items
                .filter { item in
                    let name = item.name.lowercased()
                    if trackingParameterNames.contains(name) { return false }
                    return !trackingParameterPrefixes.contains { name.hasPrefix($0) }
                }
                .sorted { $0.name < $1.name }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path

        return (components.url?.absoluteString ?? url.absoluteString).lowercased()
    }
}

// MARK: - Publisher

public struct PublisherBaseline: Codable, Equatable, Sendable {
    /// Free text such as `Center-Left`. Deliberately not the same type as
    /// ``BiasLabel`` so a source rating can never be mistaken for an article estimate.
    public let rating: String
    public let provider: String
    public let asOf: Date

    public init(rating: String, provider: String, asOf: Date) {
        self.rating = rating
        self.provider = provider
        self.asOf = asOf
    }
}

public struct Publisher: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let domain: String
    public let baseline: PublisherBaseline?

    public init(id: String, name: String, domain: String, baseline: PublisherBaseline? = nil) {
        self.id = id
        self.name = name
        self.domain = domain
        self.baseline = baseline
    }

    public static func == (lhs: Publisher, rhs: Publisher) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Semantic blocks

/// Deterministic vector illustration drawn natively by the reader.
///
/// The demo edition ships no photography. Illustrations are generated in SwiftUI so
/// the app is useful offline, screenshots are deterministic, and no real
/// photograph or wire-service credit is ever implied.
public enum EditorialArtwork: String, Codable, Sendable, CaseIterable {
    case duskTransmissionLines
    case harborGantries
    case riverDelta
    case statehouseSteps
    case nightClinic
    case classroomWindows
    case rowHouses
    case rangeRoad
}

public struct ArticleImage: Codable, Equatable, Sendable {
    public let artwork: EditorialArtwork?
    public let remoteURL: URL?
    public let aspectRatio: Double
    public let altText: String
    public let caption: String?
    public let credit: String?

    public init(
        artwork: EditorialArtwork? = nil,
        remoteURL: URL? = nil,
        aspectRatio: Double = 16.0 / 9.0,
        altText: String,
        caption: String? = nil,
        credit: String? = nil
    ) {
        self.artwork = artwork
        self.remoteURL = remoteURL
        self.aspectRatio = aspectRatio
        self.altText = altText
        self.caption = caption
        self.credit = credit
    }
}

public enum ArticleBlock: Codable, Equatable, Sendable {
    case paragraph(RichText)
    case heading(String)
    case image(ArticleImage)
    case pullQuote(text: String, attribution: String?)
    case list(ordered: Bool, items: [RichText])
    case divider

    /// Text a local classifier or the search index may read. Captions and credits
    /// are excluded because they routinely carry publisher identity.
    public var analyzableText: String {
        switch self {
        case .paragraph(let rich):
            return rich.plainText
        case .heading(let text):
            return text
        case .pullQuote(let text, let attribution):
            return [text, attribution].compactMap { $0 }.joined(separator: " ")
        case .list(_, let items):
            return items.map(\.plainText).joined(separator: " ")
        case .image, .divider:
            return ""
        }
    }
}

// MARK: - Extraction honesty

public enum ExtractionStatus: Codable, Equatable, Sendable {
    case full
    case partial(note: String)
    case feedOnly
    /// Broadsheet tried to read the full article and could not, and `reason` says
    /// why in the reader's own words. The feed excerpt is shown instead; nothing
    /// is invented to fill the gap.
    case excerptOnly(reason: String)
    case paywalled(note: String)
    case failed(reason: String)

    public var isReadableInApp: Bool {
        switch self {
        case .full, .partial, .feedOnly, .excerptOnly, .paywalled: return true
        case .failed: return false
        }
    }

    /// True when the reader is seeing the publisher's excerpt rather than the
    /// article, so the surface can push them to the original.
    public var isExcerptOnly: Bool {
        switch self {
        case .feedOnly, .excerptOnly, .paywalled: return true
        case .full, .partial, .failed: return false
        }
    }

    public var disclosure: String? {
        switch self {
        case .full:
            return nil
        case .partial(let note):
            return note
        case .feedOnly:
            return "Only the publisher-supplied excerpt was available. Read the full story at the publisher."
        case .excerptOnly(let reason):
            return reason
        case .paywalled(let note):
            return note
        case .failed(let reason):
            return reason
        }
    }

    /// A short status for the source list and the story card.
    public var shortLabel: String? {
        switch self {
        case .full: return nil
        case .partial: return "Partial"
        case .feedOnly, .excerptOnly: return "Excerpt only"
        case .paywalled: return "Publisher restricted"
        case .failed: return "Unavailable"
        }
    }
}

/// Where an article's text came from, which decides which analyzer may run on it.
public enum ContentSource: String, Codable, Sendable {
    /// Bundled fictional demo journalism. Analyzed by the deterministic fixture
    /// analyzer so demo screenshots and tests are reproducible.
    case bundledFixture
    /// Parsed from a real subscribed feed. Only a real local model may label it.
    case liveFeed
}

// MARK: - Article

public struct ArticleDocument: Identifiable, Equatable, Codable, Sendable {
    public let id: ArticleID
    public let canonicalURL: URL?
    public let publisher: Publisher
    public let kicker: String?
    public let title: String
    public let dek: String?
    public let author: String?
    public let publishedAt: Date
    public let updatedAt: Date?
    public let heroImage: ArticleImage?
    public let blocks: [ArticleBlock]
    public let extraction: ExtractionStatus
    public let contentSource: ContentSource

    public init(
        id: ArticleID,
        canonicalURL: URL?,
        publisher: Publisher,
        kicker: String? = nil,
        title: String,
        dek: String? = nil,
        author: String? = nil,
        publishedAt: Date,
        updatedAt: Date? = nil,
        heroImage: ArticleImage? = nil,
        blocks: [ArticleBlock] = [],
        extraction: ExtractionStatus = .full,
        contentSource: ContentSource
    ) {
        self.id = id
        self.canonicalURL = canonicalURL
        self.publisher = publisher
        self.kicker = kicker
        self.title = title
        self.dek = dek
        self.author = author
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.heroImage = heroImage
        self.blocks = blocks
        self.extraction = extraction
        self.contentSource = contentSource
    }

    public var bodyText: String {
        blocks
            .map(\.analyzableText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public var wordCount: Int {
        let text = [title, dek ?? "", bodyText].joined(separator: " ")
        return text.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.count
    }

    /// 220 words per minute, floored at one minute so short items still read sensibly.
    public var readingTimeMinutes: Int {
        max(1, Int((Double(wordCount) / 220.0).rounded(.up)))
    }

    /// Everything the local search index should see, including publisher name.
    /// The bias model input is built separately and deliberately excludes it.
    public var searchableText: String {
        [title, dek ?? "", kicker ?? "", author ?? "", publisher.name, bodyText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
