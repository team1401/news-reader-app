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

    /// The publisher for a subscribed source. The reader's own title for the
    /// source wins, because they may well have renamed it deliberately.
    public static func publisher(for feed: ParsedFeed, source: FeedSource) -> Publisher {
        let derived = publisher(for: feed, feedURL: source.feedURL)
        let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return derived }
        return Publisher(id: derived.id, name: title, domain: derived.domain, baseline: derived.baseline)
    }

    /// Maps a whole feed, pairing each article with the publisher-supplied content
    /// HTML so the resolver can prefer it without re-parsing the feed.
    public static func articles(
        from feed: ParsedFeed,
        source: FeedSource,
        fetchedAt: Date
    ) -> [(document: ArticleDocument, contentHTML: String?)] {
        let publisher = publisher(for: feed, source: source)
        return feed.items.map { item in
            (article(from: item, publisher: publisher, fetchedAt: fetchedAt), item.contentHTML)
        }
    }
}
