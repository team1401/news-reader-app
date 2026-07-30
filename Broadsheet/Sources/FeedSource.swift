import Foundation

/// Outcome of the most recent refresh attempt for a source.
///
/// A failure never removes the source's cached articles; it only changes what the
/// source list reports, so the reader can tell "stale" from "gone".
public enum SourceRefreshStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case never
    case succeeded
    case failed

    public var displayName: String {
        switch self {
        case .never: return "Not refreshed yet"
        case .succeeded: return "OK"
        case .failed: return "Failed"
        }
    }
}

/// A subscribed feed. Identity is the normalized feed URL so the same feed cannot
/// be added twice with different casing or a trailing slash.
public struct FeedSource: Identifiable, Equatable, Sendable, Hashable {
    public static let defaultFolder = "News"

    public let id: String
    public var title: String
    public var feedURL: URL
    public var siteURL: URL?
    public var folder: String
    public var isEnabled: Bool
    public var sortIndex: Int
    /// True for the four sources seeded on first launch. Starter sources are fully
    /// editable and deletable; the flag only makes seeding idempotent.
    public var isStarter: Bool
    public var lastRefreshedAt: Date?
    public var lastStatus: SourceRefreshStatus
    public var lastErrorMessage: String?
    public var lastItemCount: Int

    public init(
        feedURL: URL,
        title: String,
        siteURL: URL? = nil,
        folder: String = FeedSource.defaultFolder,
        isEnabled: Bool = true,
        sortIndex: Int = 0,
        isStarter: Bool = false,
        lastRefreshedAt: Date? = nil,
        lastStatus: SourceRefreshStatus = .never,
        lastErrorMessage: String? = nil,
        lastItemCount: Int = 0
    ) {
        self.id = FeedURLNormalizer.key(for: feedURL)
        self.title = title
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.folder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? FeedSource.defaultFolder
            : folder.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
        self.isStarter = isStarter
        self.lastRefreshedAt = lastRefreshedAt
        self.lastStatus = lastStatus
        self.lastErrorMessage = lastErrorMessage
        self.lastItemCount = lastItemCount
    }
}

/// Normalizes a feed URL into a stable identity.
///
/// Unlike ``ArticleID/normalizedKey(for:)`` this keeps every query parameter: a
/// feed's query routinely selects the edition (`?edition=int`) and dropping it
/// would silently subscribe the reader to a different feed.
public enum FeedURLNormalizer {
    public static func key(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.user = nil
        components.password = nil

        if let port = components.port,
           (components.scheme == "https" && port == 443) || (components.scheme == "http" && port == 80) {
            components.port = nil
        }

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path

        if let items = components.queryItems {
            components.queryItems = items.sorted {
                $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name
            }
        }

        return components.url?.absoluteString ?? url.absoluteString
    }
}

/// The four verified starter feeds seeded on first launch.
///
/// They are ordinary editable sources: the reader can rename, refolder, disable, or
/// delete any of them, and seeding never reinstates a deleted one.
public enum StarterSources {
    public static let all: [FeedSource] = [
        FeedSource(
            feedURL: URL(string: "https://feeds.bbci.co.uk/news/rss.xml?edition=int")!,
            title: "BBC News",
            siteURL: URL(string: "https://www.bbc.com/news"),
            folder: "World",
            sortIndex: 0,
            isStarter: true
        ),
        FeedSource(
            feedURL: URL(string: "https://feeds.npr.org/1001/rss.xml")!,
            title: "NPR News",
            siteURL: URL(string: "https://www.npr.org"),
            folder: "World",
            sortIndex: 1,
            isStarter: true
        ),
        FeedSource(
            feedURL: URL(string: "https://feeds.arstechnica.com/arstechnica/index")!,
            title: "Ars Technica",
            siteURL: URL(string: "https://arstechnica.com"),
            folder: "Technology",
            sortIndex: 2,
            isStarter: true
        ),
        FeedSource(
            feedURL: URL(string: "https://www.propublica.org/feeds/propublica/main")!,
            title: "ProPublica",
            siteURL: URL(string: "https://www.propublica.org"),
            folder: "Investigations",
            sortIndex: 3,
            isStarter: true
        )
    ]
}
