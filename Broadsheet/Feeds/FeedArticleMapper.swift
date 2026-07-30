import Foundation

/// Converts parsed feed items into semantic ``ArticleDocument`` values.
///
/// Nothing here fabricates a value: a missing date falls back to the feed's fetch
/// time and the article is marked as feed-only so the reader can say so.
public enum FeedArticleMapper {
    public static func article(
        from item: ParsedFeedItem,
        publisher: Publisher,
        fetchedAt: Date
    ) -> ArticleDocument {
        let paragraphs = HTMLTextNormalizer
            .paragraphs(from: item.contentHTML ?? item.summary)
            .filter { !$0.isEmpty }

        var blocks: [ArticleBlock] = paragraphs.map { .paragraph(RichText($0)) }
        if blocks.isEmpty, !item.summary.isEmpty {
            blocks = [.paragraph(RichText(item.summary))]
        }

        let heroImage = item.imageURL.map {
            ArticleImage(
                remoteURL: $0,
                altText: "Publisher-supplied image for “\(item.title)”",
                credit: publisher.name
            )
        }

        let extraction: ExtractionStatus = item.contentHTML == nil ? .feedOnly : .partial(
            note: "Rendered from the publisher's feed content. Broadsheet has not yet fetched the full article."
        )

        return ArticleDocument(
            id: item.identity,
            canonicalURL: item.link,
            publisher: publisher,
            title: item.title,
            dek: item.summary.isEmpty ? nil : String(item.summary.prefix(280)),
            author: item.author,
            publishedAt: item.publishedAt ?? fetchedAt,
            heroImage: heroImage,
            blocks: blocks,
            extraction: extraction,
            contentSource: .liveFeed
        )
    }

    /// Derives a publisher from the feed's own channel identity rather than
    /// hard-coding one. Baseline stays `nil` because a source rating is external
    /// data Broadsheet has not been given for an arbitrary URL.
    public static func publisher(for feed: ParsedFeed, feedURL: URL?) -> Publisher {
        let host = feed.channelLink?.host ?? feedURL?.host ?? ""
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let name = feed.channelTitle.isEmpty ? (domain.isEmpty ? "Unknown source" : domain) : feed.channelTitle
        let identifier = domain.isEmpty ? name.lowercased() : domain
        return Publisher(id: identifier, name: name, domain: domain, baseline: nil)
    }
}
