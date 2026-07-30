import Foundation

/// Per-request safety limits.
///
/// A news reader fetches URLs the reader supplies, so every request is bounded:
/// an unbounded body, an unbounded redirect chain, or an unbounded wait are all
/// ways a single bad source can hang or exhaust the app.
public struct HTTPFetchLimits: Sendable, Equatable {
    public var maximumBytes: Int
    public var timeout: TimeInterval
    public var maximumRedirects: Int

    public init(maximumBytes: Int, timeout: TimeInterval, maximumRedirects: Int) {
        self.maximumBytes = maximumBytes
        self.timeout = timeout
        self.maximumRedirects = maximumRedirects
    }

    /// Feeds are text; 8 MB is far above any real feed and far below trouble.
    public static let feed = HTTPFetchLimits(maximumBytes: 8_000_000, timeout: 20, maximumRedirects: 5)
    /// Article pages carry more markup but are still text.
    public static let page = HTTPFetchLimits(maximumBytes: 4_000_000, timeout: 20, maximumRedirects: 5)
    /// `robots.txt` is tiny and must never delay a refresh.
    public static let robots = HTTPFetchLimits(maximumBytes: 512_000, timeout: 8, maximumRedirects: 3)
}

public struct HTTPFetchResult: Sendable, Equatable {
    public let data: Data
    public let finalURL: URL
    public let statusCode: Int
    public let mimeType: String?
    public let textEncodingName: String?
    public let redirectCount: Int

    public init(
        data: Data,
        finalURL: URL,
        statusCode: Int,
        mimeType: String?,
        textEncodingName: String?,
        redirectCount: Int
    ) {
        self.data = data
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.mimeType = mimeType
        self.textEncodingName = textEncodingName
        self.redirectCount = redirectCount
    }

    /// Decodes using the server's declared charset, then UTF-8, then Latin-1.
    /// Latin-1 never fails, so a mislabelled feed still parses rather than
    /// disappearing without explanation.
    public var text: String {
        if let name = textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let decoded = String(data: data, encoding: encoding) { return decoded }
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum HTTPFetchError: Error, Equatable, LocalizedError {
    case insecureScheme(scheme: String)
    case unsupportedURL(String)
    case timedOut
    case notConnected
    case cancelled
    case transportFailure(String)
    case httpStatus(code: Int, url: String)
    case tooManyRedirects(limit: Int)
    case insecureRedirect(to: String)
    case responseTooLarge(limit: Int)
    case emptyResponse
    case unexpectedContentType(String)

    public var errorDescription: String? {
        switch self {
        case .insecureScheme(let scheme):
            return "Broadsheet only fetches over HTTPS, and this address uses \(scheme)."
        case .unsupportedURL(let url):
            return "“\(url)” is not a usable web address."
        case .timedOut:
            return "The server did not respond in time."
        case .notConnected:
            return "This device is offline."
        case .cancelled:
            return "The request was cancelled."
        case .transportFailure(let message):
            return message
        case .httpStatus(let code, _):
            return "The server replied \(code) \(HTTPURLResponse.localizedString(forStatusCode: code))."
        case .tooManyRedirects(let limit):
            return "The address redirected more than \(limit) times."
        case .insecureRedirect(let target):
            return "The address redirected to a non-HTTPS location (\(target)), which Broadsheet will not follow."
        case .responseTooLarge(let limit):
            return "The response was larger than the \(limit / 1_000_000) MB limit."
        case .emptyResponse:
            return "The server returned an empty response."
        case .unexpectedContentType(let type):
            return "The server returned “\(type)”, which is not a feed or a web page."
        }
    }

    /// True when retrying later is reasonable and cached content should be kept.
    public var isTransient: Bool {
        switch self {
        case .timedOut, .notConnected, .transportFailure, .cancelled:
            return true
        case .httpStatus(let code, _):
            return code >= 500 || code == 429
        default:
            return false
        }
    }
}

public protocol HTTPTransport: Sendable {
    func fetch(_ url: URL, accept: String, limits: HTTPFetchLimits) async throws -> HTTPFetchResult
}

public extension HTTPTransport {
    func fetch(_ url: URL, accept: String) async throws -> HTTPFetchResult {
        try await fetch(url, accept: accept, limits: .feed)
    }
}

public enum HTTPAccept {
    public static let feed = "application/rss+xml, application/atom+xml, application/feed+json, application/json;q=0.9, application/xml;q=0.8, text/xml;q=0.8, */*;q=0.5"
    public static let html = "text/html, application/xhtml+xml;q=0.9, */*;q=0.5"
    public static let text = "text/plain, */*;q=0.5"
}
