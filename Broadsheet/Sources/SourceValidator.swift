import Foundation

/// A feed Broadsheet has actually fetched and parsed, ready to be saved.
public struct FeedCandidate: Equatable, Sendable, Identifiable, Hashable {
    public let feedURL: URL
    public let title: String
    public let siteURL: URL?
    public let format: FeedFormat
    public let itemCount: Int
    /// True when the feed carries article bodies, not just excerpts. Shown before
    /// saving because it decides how much of the story the reader will get.
    public let carriesFullContent: Bool

    public var id: String { FeedURLNormalizer.key(for: feedURL) }

    public init(
        feedURL: URL,
        title: String,
        siteURL: URL?,
        format: FeedFormat,
        itemCount: Int,
        carriesFullContent: Bool
    ) {
        self.feedURL = feedURL
        self.title = title
        self.siteURL = siteURL
        self.format = format
        self.itemCount = itemCount
        self.carriesFullContent = carriesFullContent
    }

    public func makeSource(folder: String = FeedSource.defaultFolder, sortIndex: Int = 0) -> FeedSource {
        FeedSource(
            feedURL: feedURL,
            title: title,
            siteURL: siteURL,
            folder: folder,
            sortIndex: sortIndex
        )
    }
}

public enum SourceValidationError: Error, Equatable, LocalizedError {
    case emptyAddress
    case invalidAddress(String)
    case insecureAddress(String)
    case network(HTTPFetchError)
    case notAFeed(reason: String)
    case noFeedsDiscovered(page: String)

    public var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "Enter a feed or website address."
        case .invalidAddress(let text):
            return "“\(text)” is not a web address Broadsheet can open."
        case .insecureAddress(let text):
            return "“\(text)” is not secure. Broadsheet only subscribes over HTTPS."
        case .network(let error):
            return error.errorDescription
        case .notAFeed(let reason):
            return reason
        case .noFeedsDiscovered(let page):
            return "No RSS, Atom, or JSON feed is advertised on \(page)."
        }
    }
}

/// Fetches and parses an address before it can become a source.
///
/// Nothing is saved on the strength of the URL alone: the feed is retrieved under
/// the same limits a refresh uses, parsed by the same parsers, and reported with
/// the title and item count that actually came back.
public struct SourceValidator: Sendable {
    /// Discovery follows at most this many advertised feeds, so a hostile page
    /// cannot turn one paste into dozens of requests.
    public static let maximumDiscoveredFeeds = 6

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// Normalizes what a person is likely to type. A bare host becomes HTTPS; an
    /// explicit `http://` is refused rather than silently upgraded, because the
    /// reader should know their subscription address changed.
    public static func normalizedURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SourceValidationError.emptyAddress }

        let withScheme: String
        if trimmed.lowercased().hasPrefix("feed://") {
            withScheme = "https://" + trimmed.dropFirst("feed://".count)
        } else if trimmed.contains("://") {
            withScheme = trimmed
        } else {
            withScheme = "https://" + trimmed
        }

        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased() else {
            throw SourceValidationError.invalidAddress(trimmed)
        }
        guard scheme == "https" else {
            throw SourceValidationError.insecureAddress(trimmed)
        }
        guard let host = url.host, host.contains(".") else {
            throw SourceValidationError.invalidAddress(trimmed)
        }
        return url
    }

    /// Returns every feed the address yields: one if it is itself a feed, or each
    /// advertised feed if it is a publisher page.
    public func candidates(for input: String) async throws -> [FeedCandidate] {
        let url = try SourceValidator.normalizedURL(from: input)
        return try await candidates(for: url)
    }

    public func candidates(for url: URL) async throws -> [FeedCandidate] {
        let response: HTTPFetchResult
        do {
            response = try await transport.fetch(url, accept: HTTPAccept.feed, limits: .feed)
        } catch let error as HTTPFetchError {
            throw SourceValidationError.network(error)
        }

        if let candidate = candidate(from: response) {
            return [candidate]
        }

        // Not a feed: treat it as a publisher page and read what it advertises.
        let html = response.text
        let links = FeedDiscovery.links(inHTML: html, baseURL: response.finalURL)
        guard !links.isEmpty else {
            throw SourceValidationError.noFeedsDiscovered(page: response.finalURL.host ?? url.absoluteString)
        }

        var candidates: [FeedCandidate] = []
        for link in links.prefix(SourceValidator.maximumDiscoveredFeeds) {
            guard link.url.scheme?.lowercased() == "https" else { continue }
            guard let fetched = try? await transport.fetch(link.url, accept: HTTPAccept.feed, limits: .feed),
                  var candidate = candidate(from: fetched) else { continue }

            if let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty,
               candidate.title.isEmpty {
                candidate = FeedCandidate(
                    feedURL: candidate.feedURL,
                    title: title,
                    siteURL: candidate.siteURL,
                    format: candidate.format,
                    itemCount: candidate.itemCount,
                    carriesFullContent: candidate.carriesFullContent
                )
            }
            candidates.append(candidate)
        }

        guard !candidates.isEmpty else {
            throw SourceValidationError.noFeedsDiscovered(page: response.finalURL.host ?? url.absoluteString)
        }
        return candidates
    }

    /// Validates a single address and requires it to be a feed, not a page.
    public func validateFeed(at url: URL) async throws -> FeedCandidate {
        let response: HTTPFetchResult
        do {
            response = try await transport.fetch(url, accept: HTTPAccept.feed, limits: .feed)
        } catch let error as HTTPFetchError {
            throw SourceValidationError.network(error)
        }
        guard let candidate = candidate(from: response) else {
            let parseError = (try? FeedDocumentParser.parse(
                response.data,
                contentType: response.mimeType,
                feedURL: response.finalURL
            )) == nil ? feedParseFailureReason(response) : "The feed contained no items."
            throw SourceValidationError.notAFeed(reason: parseError)
        }
        return candidate
    }

    private func feedParseFailureReason(_ response: HTTPFetchResult) -> String {
        do {
            _ = try FeedDocumentParser.parse(response.data, contentType: response.mimeType, feedURL: response.finalURL)
            return "The feed contained no items."
        } catch let error as FeedParsingError {
            return error.errorDescription ?? "The response is not a feed."
        } catch {
            return error.localizedDescription
        }
    }

    private func candidate(from response: HTTPFetchResult) -> FeedCandidate? {
        guard let feed = try? FeedDocumentParser.parse(
            response.data,
            contentType: response.mimeType,
            feedURL: response.finalURL
        ) else { return nil }
        guard !feed.items.isEmpty else { return nil }

        let title = feed.channelTitle.isEmpty
            ? (response.finalURL.host ?? response.finalURL.absoluteString)
            : feed.channelTitle

        let fullContentItems = feed.items.filter { item in
            guard let content = item.contentHTML else { return false }
            return HTMLTextNormalizer.plainText(from: content).count >= 800
        }

        return FeedCandidate(
            feedURL: response.finalURL,
            title: title,
            siteURL: feed.channelLink,
            format: feed.format,
            itemCount: feed.items.count,
            carriesFullContent: fullContentItems.count * 2 >= feed.items.count
        )
    }
}
