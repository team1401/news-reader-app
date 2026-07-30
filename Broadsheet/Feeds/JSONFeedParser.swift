import Foundation

/// JSON Feed 1.1, with 1.0 accepted for the feeds that never updated.
///
/// Reference: https://www.jsonfeed.org/version/1.1/
///
/// Like the XML parser, nothing here invents a value. A missing or unparseable
/// `date_published` stays `nil` rather than becoming "now", and an item link that
/// is not a usable web URL is dropped rather than replaced.
public enum JSONFeedParser {
    static let supportedVersionPrefixes = [
        "https://jsonfeed.org/version/1.1",
        "https://jsonfeed.org/version/1"
    ]

    public static func parse(_ data: Data, feedURL: URL? = nil) throws -> ParsedFeed {
        guard !data.isEmpty else { throw FeedParsingError.emptyDocument }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw FeedParsingError.malformedJSON(message: error.localizedDescription)
        }

        guard let root = object as? [String: Any] else {
            throw FeedParsingError.notAJSONFeed
        }
        guard let version = root["version"] as? String else {
            throw FeedParsingError.notAJSONFeed
        }
        guard supportedVersionPrefixes.contains(where: { version.hasPrefix($0) }) else {
            throw FeedParsingError.unsupportedJSONFeedVersion(version)
        }

        let title = (root["title"] as? String).map(HTMLTextNormalizer.plainText(from:)) ?? ""
        let homePage = FeedParser.webURL(from: root["home_page_url"] as? String)
        let description = (root["description"] as? String).map(HTMLTextNormalizer.plainText(from:))

        // A 1.1 feed carries `authors`; 1.0 carried a single `author`.
        let feedAuthor = authorName(from: root)

        let rawItems = root["items"] as? [[String: Any]] ?? []
        let items = rawItems.map { item(from: $0, feedAuthor: feedAuthor) }

        return ParsedFeed(
            format: .jsonFeed,
            channelTitle: title,
            channelLink: homePage ?? feedURL,
            channelDescription: description?.isEmpty == true ? nil : description,
            items: items
        )
    }

    static func item(from raw: [String: Any], feedAuthor: String?) -> ParsedFeedItem {
        let contentHTML = (raw["content_html"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentText = (raw["content_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = raw["summary"] as? String

        // JSON Feed's `title` is optional — microblog-style feeds omit it — so the
        // first line of the content stands in rather than an empty headline.
        let rawTitle = (raw["title"] as? String).map(HTMLTextNormalizer.plainText(from:)) ?? ""
        let bodyPlain = HTMLTextNormalizer.plainText(from: contentHTML ?? contentText ?? "")
        let title = rawTitle.isEmpty ? String(bodyPlain.prefix(120)) : rawTitle

        let summaryText: String = {
            if let summary, !summary.isEmpty { return HTMLTextNormalizer.plainText(from: summary) }
            return bodyPlain
        }()

        // `id` is required by the spec but is often a permalink; `url` is the
        // reader-facing link, and `external_url` is deliberately *not* used as the
        // canonical link because it points at someone else's page.
        let link = FeedParser.webURL(from: raw["url"] as? String)
            ?? FeedParser.webURL(from: raw["id"] as? String)

        let identifier = (raw["id"] as? String) ?? (raw["id"] as? Int).map(String.init)

        let imageURL = FeedParser.webURL(from: raw["image"] as? String)
            ?? FeedParser.webURL(from: raw["banner_image"] as? String)

        return ParsedFeedItem(
            title: title,
            link: link,
            guid: identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summaryText,
            contentHTML: (contentHTML?.isEmpty == false) ? contentHTML : nil,
            publishedAt: FeedDateParser.date(from: (raw["date_published"] as? String) ?? ""),
            author: authorName(from: raw) ?? feedAuthor,
            imageURL: imageURL
        )
    }

    /// Reads 1.1's `authors` array first, then 1.0's singular `author`.
    static func authorName(from raw: [String: Any]) -> String? {
        if let authors = raw["authors"] as? [[String: Any]] {
            let names = authors.compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        if let author = raw["author"] as? [String: Any],
           let name = (author["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return nil
    }
}

/// Picks a parser from the response rather than from the file extension.
///
/// Publishers serve JSON Feed as `application/json`, `application/feed+json`, and
/// sometimes `text/plain`, so the content type is a hint and the first non-space
/// byte is the decision.
public enum FeedDocumentParser {
    public static func parse(_ data: Data, contentType: String?, feedURL: URL? = nil) throws -> ParsedFeed {
        guard !data.isEmpty else { throw FeedParsingError.emptyDocument }

        if looksLikeJSON(data) || (contentType?.lowercased().contains("json") ?? false) {
            return try JSONFeedParser.parse(data, feedURL: feedURL)
        }
        return try FeedParser().parse(data)
    }

    static func looksLikeJSON(_ data: Data) -> Bool {
        for byte in data.prefix(64) {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF:
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                return true
            default:
                return false
            }
        }
        return false
    }
}
