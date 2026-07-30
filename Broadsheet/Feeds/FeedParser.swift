import Foundation

// MARK: - Parsed values

public enum FeedFormat: String, Equatable, Sendable {
    case rss
    case atom
}

public struct ParsedFeedItem: Equatable, Sendable {
    public let title: String
    /// `nil` when the feed supplied no link, or supplied one that is not a usable
    /// web URL. It is never replaced with a placeholder host.
    public let link: URL?
    public let guid: String?
    /// Publisher summary with markup and entities normalized away.
    public let summary: String
    /// Full content when the feed carries it (`content:encoded` or Atom `content`).
    public let contentHTML: String?
    /// `nil` when the feed omitted a date or published one we could not parse.
    public let publishedAt: Date?
    public let author: String?
    public let imageURL: URL?

    public var identity: ArticleID {
        ArticleID(canonicalURL: link, guid: guid)
    }
}

public struct ParsedFeed: Equatable, Sendable {
    public let format: FeedFormat
    public let channelTitle: String
    public let channelLink: URL?
    public let channelDescription: String?
    public let items: [ParsedFeedItem]
}

public enum FeedParsingError: Error, Equatable, LocalizedError {
    case emptyDocument
    case malformedXML(line: Int, column: Int, message: String)
    case unsupportedFormat(rootElement: String?)

    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "The feed response was empty."
        case .malformedXML(let line, let column, let message):
            return "The feed is not valid XML (line \(line), column \(column)): \(message)"
        case .unsupportedFormat(let rootElement):
            if let rootElement {
                return "Expected an RSS or Atom feed but found a <\(rootElement)> document."
            }
            return "The response is not an RSS or Atom feed."
        }
    }
}

// MARK: - Parser

/// A small, honest RSS 2.0 and Atom 1.0 parser built on `XMLParser`.
///
/// It reports failures instead of hiding them, leaves unknown values `nil` instead
/// of inventing them, and reads the channel identity from the document rather than
/// assuming one.
public final class FeedParser: NSObject {
    private var format: FeedFormat?
    private var rootElement: String?

    private var elementStack: [String] = []
    private var textBuffer = ""

    private var channelTitle = ""
    private var channelLink: String?
    private var channelDescription: String?

    private var items: [ParsedFeedItem] = []
    private var inItem = false

    private var itemTitle = ""
    private var itemLink: String?
    private var itemGUID: String?
    private var itemSummary = ""
    private var itemContent = ""
    private var itemDate: String?
    private var itemUpdatedDate: String?
    private var itemAuthor: String?
    private var itemImageURL: String?

    private var parseError: FeedParsingError?

    public override init() {
        super.init()
    }

    public func parse(_ data: Data) throws -> ParsedFeed {
        guard !data.isEmpty else { throw FeedParsingError.emptyDocument }

        reset()

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        let succeeded = parser.parse()

        if let parseError {
            // An unsupported root element aborts parsing deliberately; surface that
            // rather than the abort itself.
            throw parseError
        }

        if !succeeded {
            let nsError = parser.parserError as NSError?
            throw FeedParsingError.malformedXML(
                line: parser.lineNumber,
                column: parser.columnNumber,
                message: nsError?.localizedDescription ?? "Unknown XML error"
            )
        }

        guard let format else {
            throw FeedParsingError.unsupportedFormat(rootElement: rootElement)
        }

        return ParsedFeed(
            format: format,
            channelTitle: HTMLTextNormalizer.plainText(from: channelTitle),
            channelLink: FeedParser.webURL(from: channelLink),
            channelDescription: channelDescription.map(HTMLTextNormalizer.plainText(from:)),
            items: items
        )
    }

    private func reset() {
        format = nil
        rootElement = nil
        elementStack = []
        textBuffer = ""
        channelTitle = ""
        channelLink = nil
        channelDescription = nil
        items = []
        inItem = false
        parseError = nil
        resetItem()
    }

    private func resetItem() {
        itemTitle = ""
        itemLink = nil
        itemGUID = nil
        itemSummary = ""
        itemContent = ""
        itemDate = nil
        itemUpdatedDate = nil
        itemAuthor = nil
        itemImageURL = nil
    }

    /// Only absolute `http`/`https` URLs with a host are accepted. Anything else is
    /// dropped so the reader can say the link is missing instead of linking to a
    /// fabricated destination.
    static func webURL(from string: String?) -> URL? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, host.contains(".") else { return nil }
        return url
    }

    private var currentPathSuffix: String {
        elementStack.suffix(2).joined(separator: "/")
    }
}

// MARK: - XMLParserDelegate

extension FeedParser: XMLParserDelegate {
    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()

        if elementStack.isEmpty {
            rootElement = name
            switch name {
            case "rss", "rdf:rdf":
                format = .rss
            case "feed":
                format = .atom
            default:
                parseError = .unsupportedFormat(rootElement: name)
                parser.abortParsing()
                return
            }
        }

        elementStack.append(name)
        textBuffer = ""

        switch name {
        case "item", "entry":
            inItem = true
            resetItem()
        case "link":
            guard inItem else {
                if format == .atom, elementStack.count == 2, let href = attributeDict["href"] {
                    channelLink = href
                }
                return
            }
            // Atom carries the target in `href`; `rel="self"` and friends are not
            // the reader-facing story.
            if let href = attributeDict["href"] {
                let rel = attributeDict["rel"]?.lowercased() ?? "alternate"
                if rel == "alternate", itemLink == nil {
                    itemLink = href
                }
            }
        case "enclosure":
            if inItem, let type = attributeDict["type"]?.lowercased(), type.hasPrefix("image/") {
                itemImageURL = attributeDict["url"]
            }
        case "media:content", "media:thumbnail":
            if inItem, itemImageURL == nil {
                let type = attributeDict["type"]?.lowercased() ?? "image/"
                let medium = attributeDict["medium"]?.lowercased() ?? "image"
                if type.hasPrefix("image/") || medium == "image" {
                    itemImageURL = attributeDict["url"]
                }
            }
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            textBuffer += text
        }
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let text = textBuffer
        let path = currentPathSuffix
        elementStack.removeLast()
        textBuffer = ""

        if inItem {
            handleItemElement(name: name, path: path, text: text)
            return
        }

        switch name {
        case "title":
            if channelTitle.isEmpty { channelTitle = text }
        case "link":
            if channelLink == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                channelLink = text
            }
        case "description", "subtitle":
            if channelDescription == nil { channelDescription = text }
        default:
            break
        }
    }

    private func handleItemElement(name: String, path: String, text: String) {
        switch name {
        case "item", "entry":
            inItem = false
            appendCurrentItem()
        case "title":
            itemTitle = text
        case "link":
            if itemLink == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                itemLink = text
            }
        case "guid", "id":
            itemGUID = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "description", "summary":
            itemSummary = text
        case "content", "content:encoded":
            itemContent = text
        case "pubdate", "dc:date", "published":
            itemDate = text
        case "updated":
            itemUpdatedDate = text
        case "author", "dc:creator":
            // Atom nests the display name inside `<author><name>`.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { itemAuthor = trimmed }
        case "name":
            if path == "author/name" {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { itemAuthor = trimmed }
            }
        default:
            break
        }
    }

    private func appendCurrentItem() {
        let summarySource = itemSummary.isEmpty ? itemContent : itemSummary
        let contentHTML = itemContent.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = ParsedFeedItem(
            title: HTMLTextNormalizer.plainText(from: itemTitle),
            link: FeedParser.webURL(from: itemLink),
            guid: itemGUID?.isEmpty == false ? itemGUID : nil,
            summary: HTMLTextNormalizer.plainText(from: summarySource),
            contentHTML: contentHTML.isEmpty ? nil : contentHTML,
            publishedAt: FeedDateParser.date(from: itemDate ?? itemUpdatedDate ?? ""),
            author: itemAuthor,
            imageURL: FeedParser.webURL(from: itemImageURL)
        )
        items.append(item)
        resetItem()
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
        // Recorded here only for completeness; `parse(_:)` reads `parserError`
        // so an aborted unsupported-format parse keeps its more specific error.
        guard self.parseError == nil else { return }
        let nsError = parseError as NSError
        self.parseError = .malformedXML(
            line: parser.lineNumber,
            column: parser.columnNumber,
            message: nsError.localizedDescription
        )
    }
}
