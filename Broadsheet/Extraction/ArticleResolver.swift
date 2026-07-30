import Foundation

/// Turns a feed item into the most complete article Broadsheet is permitted to
/// render, and records honestly how much that was.
///
/// The order is fixed and the boundaries are hard:
///
/// 1. **Feed full content.** If the publisher put the article in the feed, that is
///    the article. Nothing is fetched.
/// 2. **Openly accessible page.** Only if `robots.txt` permits it, only over
///    HTTPS, and only if the page does not declare itself gated.
/// 3. **Feed excerpt.** Everything else, with the reason attached and the
///    publisher's own page one tap away.
///
/// There is no fourth step. Broadsheet does not log in, accept a cookie wall,
/// reset a meter, strip an overlay, or read a gated page from a cache.
@MainActor
public final class ArticleResolver {
    /// Feed content at or above this length is treated as the whole article.
    public static let fullFeedContentCharacters = 1_200

    private let transport: any HTTPTransport
    private let robots: RobotsPolicy
    private let extractor: ReadabilityExtractor

    public init(
        transport: any HTTPTransport,
        robots: RobotsPolicy,
        extractor: ReadabilityExtractor? = nil
    ) {
        self.transport = transport
        self.robots = robots
        self.extractor = extractor ?? ReadabilityExtractor()
    }

    /// Resolves one article. `base` is the feed-derived document, which is also the
    /// fallback: whatever happens, the reader keeps the excerpt and the link.
    public func resolve(_ base: ArticleDocument, feedContentHTML: String?, now: Date = Date()) async -> ArticleDocument {
        if let resolved = await resolveFromFeedContent(base, feedContentHTML: feedContentHTML) {
            return resolved
        }

        guard let url = base.canonicalURL else {
            return fallback(base, reason: "This item did not include a link to the publisher's article.")
        }
        guard url.scheme?.lowercased() == "https" else {
            return fallback(base, reason: "The publisher's article is not served over HTTPS, so Broadsheet did not fetch it.")
        }
        guard extractor.isAvailable else {
            return fallback(base, reason: "The article extractor is unavailable in this build, so the feed excerpt is shown.")
        }
        guard await robots.isFetchAllowed(url, now: now) else {
            return fallback(
                base,
                reason: "This publisher's robots.txt asks automated readers not to fetch this page, so Broadsheet is showing the feed excerpt and a link to the original."
            )
        }

        let response: HTTPFetchResult
        do {
            response = try await transport.fetch(url, accept: HTTPAccept.html, limits: .page)
        } catch let error as HTTPFetchError {
            if case .httpStatus(let code, _) = error,
               case .restricted(let note)? = AccessGateClassifier.assessment(forStatusCode: code) {
                return restricted(base, note: note)
            }
            return fallback(base, reason: "Broadsheet could not fetch the publisher's page: \(error.errorDescription ?? "unknown error").")
        } catch {
            return fallback(base, reason: "Broadsheet could not fetch the publisher's page: \(error.localizedDescription).")
        }

        guard (response.mimeType ?? "text/html").contains("html") else {
            return fallback(base, reason: "The publisher's link did not return a web page, so the feed excerpt is shown.")
        }

        let html = response.text

        let extraction: ExtractedArticle
        do {
            extraction = try await extractor.extract(html: html, baseURL: response.finalURL, mode: .readability)
        } catch let error as ArticleExtractionError {
            // A page that yields nothing to Readability is treated the same way a
            // gated page is: excerpt plus link, with the reason stated.
            switch AccessGateClassifier.assess(html: html, extractedCharacters: 0, extractedParagraphs: 0) {
            case .restricted(let note):
                return restricted(base, note: note)
            default:
                return fallback(base, reason: error.errorDescription ?? "The publisher's page could not be read.")
            }
        } catch {
            return fallback(base, reason: error.localizedDescription)
        }

        switch AccessGateClassifier.assess(
            html: html,
            extractedCharacters: extraction.textLength,
            extractedParagraphs: extraction.paragraphCount
        ) {
        case .restricted(let note):
            return restricted(base, note: note)
        case .insufficient(let note):
            return fallback(base, reason: note)
        case .open:
            break
        }

        return merged(base, with: extraction, canonicalURL: response.finalURL)
    }

    // MARK: Feed content

    private func resolveFromFeedContent(_ base: ArticleDocument, feedContentHTML: String?) async -> ArticleDocument? {
        guard let feedContentHTML else { return nil }
        let plain = HTMLTextNormalizer.plainText(from: feedContentHTML)
        guard plain.count >= ArticleResolver.fullFeedContentCharacters else { return nil }
        guard extractor.isAvailable else { return nil }

        let baseURL = base.canonicalURL ?? URL(string: "https://\(base.publisher.domain)/")!
        let wrapped = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(feedContentHTML)</body></html>"

        guard let extraction = try? await extractor.extract(html: wrapped, baseURL: baseURL, mode: .fragment),
              extraction.paragraphCount >= AccessGateClassifier.minimumParagraphs,
              extraction.textLength >= AccessGateClassifier.minimumArticleCharacters else {
            return nil
        }

        return ArticleDocument(
            id: base.id,
            canonicalURL: base.canonicalURL,
            publisher: base.publisher,
            kicker: base.kicker,
            title: base.title,
            dek: base.dek,
            author: base.author,
            publishedAt: base.publishedAt,
            updatedAt: base.updatedAt,
            heroImage: base.heroImage ?? extraction.leadImage,
            blocks: extraction.blocks,
            extraction: .full,
            contentSource: base.contentSource
        )
    }

    // MARK: Outcomes

    private func merged(_ base: ArticleDocument, with extraction: ExtractedArticle, canonicalURL: URL) -> ArticleDocument {
        ArticleDocument(
            id: base.id,
            canonicalURL: base.canonicalURL ?? canonicalURL,
            publisher: base.publisher,
            kicker: base.kicker,
            // The feed's headline is the publisher's own; Readability's is derived
            // from the page and only used when the feed had none.
            title: base.title.isEmpty ? (extraction.title ?? base.title) : base.title,
            dek: base.dek ?? extraction.excerpt,
            author: base.author ?? extraction.byline,
            publishedAt: base.publishedAt,
            updatedAt: base.updatedAt,
            heroImage: base.heroImage ?? extraction.leadImage,
            blocks: extraction.blocks,
            extraction: .full,
            contentSource: base.contentSource
        )
    }

    private func restricted(_ base: ArticleDocument, note: String) -> ArticleDocument {
        rewritten(base, extraction: .paywalled(note: note))
    }

    private func fallback(_ base: ArticleDocument, reason: String) -> ArticleDocument {
        rewritten(base, extraction: .excerptOnly(reason: reason))
    }

    /// Keeps exactly the blocks the feed supplied. Nothing is added, so a fallback
    /// can never show text the publisher did not publish in the feed.
    private func rewritten(_ base: ArticleDocument, extraction: ExtractionStatus) -> ArticleDocument {
        ArticleDocument(
            id: base.id,
            canonicalURL: base.canonicalURL,
            publisher: base.publisher,
            kicker: base.kicker,
            title: base.title,
            dek: base.dek,
            author: base.author,
            publishedAt: base.publishedAt,
            updatedAt: base.updatedAt,
            heroImage: base.heroImage,
            blocks: base.blocks,
            extraction: extraction,
            contentSource: base.contentSource
        )
    }
}
