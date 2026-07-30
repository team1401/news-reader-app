import Foundation

/// Serves bundled documents instead of making network requests.
///
/// Used only when the UI test runner passes `-broadsheet-stub-network`, and by
/// unit tests that need a deterministic refresh. Everything downstream of it — the
/// parsers, the deduplicator, the robots check, Readability, the store, the
/// analyzer selection — is the real implementation.
public struct FixtureHTTPTransport: HTTPTransport {
    public struct Response: Sendable {
        public let data: Data
        public let mimeType: String
        public let statusCode: Int

        public init(text: String, mimeType: String, statusCode: Int = 200) {
            self.data = Data(text.utf8)
            self.mimeType = mimeType
            self.statusCode = statusCode
        }
    }

    private let responses: [String: Response]

    public init(responses: [String: Response]) {
        self.responses = responses
    }

    public func fetch(_ url: URL, accept: String, limits: HTTPFetchLimits) async throws -> HTTPFetchResult {
        try URLSessionHTTPTransport.validateHTTPS(url)

        guard let response = responses[FeedURLNormalizer.key(for: url)] else {
            throw HTTPFetchError.httpStatus(code: 404, url: url.absoluteString)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPFetchError.httpStatus(code: response.statusCode, url: url.absoluteString)
        }
        guard response.data.count <= limits.maximumBytes else {
            throw HTTPFetchError.responseTooLarge(limit: limits.maximumBytes)
        }

        return HTTPFetchResult(
            data: response.data,
            finalURL: url,
            statusCode: response.statusCode,
            mimeType: response.mimeType,
            textEncodingName: "utf-8",
            redirectCount: 0
        )
    }
}

/// The bundled documents the four starter feeds return under `-broadsheet-stub-network`.
///
/// Every headline and sentence here is invented for testing and says so. Nothing in
/// this file reproduces or paraphrases real reporting from BBC News, NPR, Ars
/// Technica, or ProPublica; the real endpoints are used only so the test exercises
/// the same URLs the shipping app subscribes to on first launch.
public enum UITestFixtures {
    public static func transport() -> FixtureHTTPTransport {
        var responses: [String: FixtureHTTPTransport.Response] = [:]

        func put(_ urlString: String, _ response: FixtureHTTPTransport.Response) {
            guard let url = URL(string: urlString) else { return }
            responses[FeedURLNormalizer.key(for: url)] = response
        }

        // Every fixture host permits automated reading.
        for host in ["feeds.bbci.co.uk", "www.bbc.com", "feeds.npr.org", "www.npr.org",
                     "feeds.arstechnica.com", "arstechnica.com", "www.propublica.org"] {
            put("https://\(host)/robots.txt", .init(text: "User-agent: *\nAllow: /\n", mimeType: "text/plain"))
        }

        put("https://feeds.bbci.co.uk/news/rss.xml?edition=int", .init(text: bbcRSS, mimeType: "application/rss+xml"))
        put("https://feeds.npr.org/1001/rss.xml", .init(text: nprRSS, mimeType: "application/rss+xml"))
        put("https://feeds.arstechnica.com/arstechnica/index", .init(text: arsAtom, mimeType: "application/atom+xml"))
        put("https://www.propublica.org/feeds/propublica/main", .init(text: proPublicaJSONFeed, mimeType: "application/feed+json"))

        put("https://www.bbc.com/news/fixture/open-story", .init(text: openArticlePage, mimeType: "text/html"))
        put("https://www.bbc.com/news/fixture/restricted-story", .init(text: restrictedArticlePage, mimeType: "text/html"))
        // Deliberately absent: https://www.bbc.com/news/fixture/missing-story returns 404.

        put("https://arstechnica.com/fixture/open-story", .init(text: openArticlePage, mimeType: "text/html"))
        put("https://www.propublica.org/fixture/open-story", .init(text: openArticlePage, mimeType: "text/html"))

        return FixtureHTTPTransport(responses: responses)
    }

    // MARK: Feeds

    static let bbcRSS = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>BBC News</title>
        <link>https://www.bbc.com/news</link>
        <description>Test fixture channel</description>
        <item>
          <title>Fixture story one: the harbour authority publishes its dredging schedule</title>
          <link>https://www.bbc.com/news/fixture/open-story</link>
          <guid>https://www.bbc.com/news/fixture/open-story</guid>
          <description>A fictional summary written for Broadsheet's user interface tests.</description>
          <pubDate>Mon, 27 Jul 2026 09:00:00 GMT</pubDate>
        </item>
        <item>
          <title>Fixture story two: the transit board reviews its fare proposal</title>
          <link>https://www.bbc.com/news/fixture/restricted-story</link>
          <guid>https://www.bbc.com/news/fixture/restricted-story</guid>
          <description>A fictional summary for a fixture page that declares itself restricted.</description>
          <pubDate>Mon, 27 Jul 2026 08:00:00 GMT</pubDate>
        </item>
        <item>
          <title>Fixture story three: the county posts its reservoir readings</title>
          <link>https://www.bbc.com/news/fixture/missing-story</link>
          <guid>https://www.bbc.com/news/fixture/missing-story</guid>
          <description>A fictional summary for a fixture page that cannot be fetched at all.</description>
          <pubDate>Mon, 27 Jul 2026 07:00:00 GMT</pubDate>
        </item>
      </channel>
    </rss>
    """

    static let nprRSS = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>NPR News</title>
        <link>https://www.npr.org</link>
        <description>Test fixture channel</description>
        <item>
          <title>Fixture story four: a full-content feed item carries its whole article</title>
          <link>https://www.npr.org/fixture/full-content</link>
          <guid>https://www.npr.org/fixture/full-content</guid>
          <dc:creator>A Fixture Byline</dc:creator>
          <description>A fictional summary for a feed that publishes complete articles.</description>
          <pubDate>Mon, 27 Jul 2026 06:30:00 GMT</pubDate>
          <content:encoded><![CDATA[\(fullFeedContentHTML)]]></content:encoded>
        </item>
      </channel>
    </rss>
    """

    static let arsAtom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Ars Technica</title>
      <link rel="alternate" href="https://arstechnica.com"/>
      <entry>
        <title>Fixture story five: an Atom entry links to an openly readable page</title>
        <link rel="alternate" href="https://arstechnica.com/fixture/open-story"/>
        <id>tag:arstechnica.com,2026:fixture-open</id>
        <author><name>Another Fixture Byline</name></author>
        <summary>A fictional Atom summary written for Broadsheet's tests.</summary>
        <published>2026-07-27T05:00:00Z</published>
      </entry>
    </feed>
    """

    static let proPublicaJSONFeed = """
    {
      "version": "https://jsonfeed.org/version/1.1",
      "title": "ProPublica",
      "home_page_url": "https://www.propublica.org",
      "feed_url": "https://www.propublica.org/feeds/propublica/main",
      "authors": [{ "name": "Fixture Newsroom" }],
      "items": [
        {
          "id": "https://www.propublica.org/fixture/open-story",
          "url": "https://www.propublica.org/fixture/open-story",
          "title": "Fixture story six: a JSON Feed 1.1 item links to an openly readable page",
          "summary": "A fictional JSON Feed summary written for Broadsheet's tests.",
          "date_published": "2026-07-27T04:00:00Z",
          "authors": [{ "name": "A JSON Fixture Byline" }]
        }
      ]
    }
    """

    // MARK: Pages

    static let fixtureParagraphs = [
        "This paragraph is fixture text written for Broadsheet's automated tests. It exists so the extraction pipeline has a realistic amount of prose to normalise into semantic blocks, and it deliberately describes nothing that happened anywhere.",
        "A second paragraph follows, because the access-gate classifier requires at least three paragraphs and several hundred characters before it will accept a page as a readable article rather than an index or an interstitial.",
        "A third paragraph completes the body. It contains <a href=\"https://example.org/fixture-link\">an inline link</a> so the reader's rich-text rendering is exercised, and it stays firmly in the territory of invented placeholder prose.",
        "A fourth paragraph gives the reader something to scroll, and gives the deduplicator and the content hash something stable to work with across repeated fixture refreshes."
    ]

    static let fullFeedContentHTML: String = {
        let body = fixtureParagraphs.map { "<p>\($0)</p>" }.joined()
        return body + "<h2>A fixture subheading</h2>" + body
    }()

    static let openArticlePage = """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Fixture story one</title>
        <meta property="og:title" content="Fixture story one">
        <meta property="article:published_time" content="2026-07-27T09:00:00Z">
      </head>
      <body>
        <nav class="site-navigation"><a href="https://example.org/">Chrome that must be removed</a></nav>
        <article>
          <h1>Fixture story one: the harbour authority publishes its dredging schedule</h1>
          \(fixtureParagraphs.map { "<p>\($0)</p>" }.joined())
          <blockquote>A fixture pull quote, invented for testing.<footer>A fixture speaker</footer></blockquote>
          <ul><li>A first fixture list item</li><li>A second fixture list item</li></ul>
          \(fixtureParagraphs.map { "<p>\($0)</p>" }.joined())
        </article>
        <aside class="newsletter-promo">Subscribe to our newsletter</aside>
        <footer class="site-footer">Fixture footer chrome</footer>
      </body>
    </html>
    """

    /// Declares itself not free to read, exactly the way schema.org specifies.
    /// Broadsheet must stop, not look for the text.
    static let restrictedArticlePage = """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>Fixture story two</title>
        <meta property="article:content_tier" content="locked">
        <script type="application/ld+json">
          {"@context":"https://schema.org","@type":"NewsArticle","isAccessibleForFree":false,
           "headline":"Fixture story two"}
        </script>
      </head>
      <body>
        <article>
          <h1>Fixture story two: the transit board reviews its fare proposal</h1>
          <p>A short fixture teaser paragraph, which is all a gated page offers.</p>
          <div class="paywall-overlay">Subscribe to continue reading.</div>
        </article>
      </body>
    </html>
    """
}
