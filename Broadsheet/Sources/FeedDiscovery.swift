import Foundation

/// Finds the feeds a publisher advertises on their own page.
///
/// Only `<link rel="alternate">` declarations and anchors that plainly point at a
/// feed are considered. Nothing is guessed from the site structure, so a reader who
/// pastes a homepage gets the feeds the publisher chose to publish.
public enum FeedDiscovery {
    public struct DiscoveredLink: Equatable, Sendable, Hashable {
        public let url: URL
        public let title: String?
        public let type: String?

        public init(url: URL, title: String?, type: String?) {
            self.url = url
            self.title = title
            self.type = type
        }
    }

    static let feedTypes: Set<String> = [
        "application/rss+xml",
        "application/atom+xml",
        "application/feed+json",
        "application/json",
        "text/xml",
        "application/xml"
    ]

    public static func links(inHTML html: String, baseURL: URL) -> [DiscoveredLink] {
        var found: [DiscoveredLink] = []
        var seen = Set<String>()

        for tag in tags(named: "link", in: html) {
            let rel = tag["rel"]?.lowercased() ?? ""
            guard rel.split(separator: " ").contains("alternate") else { continue }
            guard let type = tag["type"]?.lowercased(),
                  feedTypes.contains(type.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)) else { continue }
            guard let href = tag["href"], let url = absoluteURL(href, relativeTo: baseURL) else { continue }
            guard seen.insert(FeedURLNormalizer.key(for: url)).inserted else { continue }
            found.append(DiscoveredLink(url: url, title: tag["title"], type: type))
        }

        // Some publishers only expose the feed as an ordinary link in the footer.
        for tag in tags(named: "a", in: html) {
            guard let href = tag["href"], let url = absoluteURL(href, relativeTo: baseURL) else { continue }
            let path = url.path.lowercased()
            let looksLikeFeed = path.hasSuffix("/feed")
                || path.hasSuffix("/rss")
                || path.hasSuffix("/rss.xml")
                || path.hasSuffix("/atom.xml")
                || path.hasSuffix("/feed.json")
                || path.hasSuffix("/index.xml")
            guard looksLikeFeed else { continue }
            guard seen.insert(FeedURLNormalizer.key(for: url)).inserted else { continue }
            found.append(DiscoveredLink(url: url, title: nil, type: nil))
        }

        return found
    }

    static func absoluteURL(_ href: String, relativeTo base: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let resolved: URL?
        if trimmed.hasPrefix("//") {
            resolved = URL(string: (base.scheme ?? "https") + ":" + trimmed)
        } else {
            resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL
        }
        guard let url = resolved, let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "https" || scheme == "http" else { return nil }
        guard url.host != nil else { return nil }
        return url
    }

    /// A tolerant scan for a named tag and its attributes.
    ///
    /// Real publisher HTML is not XML — unclosed tags, unquoted attributes, and
    /// stray `<` are routine — so this reads attributes off the raw text rather
    /// than demanding a well-formed document.
    static func tags(named name: String, in html: String) -> [[String: String]] {
        var results: [[String: String]] = []
        let lowered = html.lowercased()
        let needle = "<" + name.lowercased()
        var searchStart = lowered.startIndex

        while let open = lowered.range(of: needle, range: searchStart..<lowered.endIndex) {
            searchStart = open.upperBound

            // Require a delimiter so `<linkedin>` does not match `<link>`.
            guard let boundary = lowered[open.upperBound...].first,
                  boundary == " " || boundary == "\t" || boundary == "\n" || boundary == "\r" || boundary == ">" || boundary == "/" else {
                continue
            }
            guard let close = lowered.range(of: ">", range: open.upperBound..<lowered.endIndex) else { break }

            let body = String(html[open.upperBound..<close.lowerBound])
            results.append(attributes(in: body))
            searchStart = close.upperBound
        }

        return results
    }

    static func attributes(in text: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = text.startIndex

        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace || text[index] == "/" {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            var name = ""
            while index < text.endIndex, text[index] != "=", !text[index].isWhitespace {
                name.append(text[index])
                index = text.index(after: index)
            }
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex, text[index] == "=" else {
                if !name.isEmpty { attributes[name.lowercased()] = "" }
                continue
            }
            index = text.index(after: index)
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            var value = ""
            if text[index] == "\"" || text[index] == "'" {
                let quote = text[index]
                index = text.index(after: index)
                while index < text.endIndex, text[index] != quote {
                    value.append(text[index])
                    index = text.index(after: index)
                }
                if index < text.endIndex { index = text.index(after: index) }
            } else {
                while index < text.endIndex, !text[index].isWhitespace {
                    value.append(text[index])
                    index = text.index(after: index)
                }
            }

            if !name.isEmpty {
                attributes[name.lowercased()] = HTMLTextNormalizer.decodeEntities(in: value)
            }
        }

        return attributes
    }
}
