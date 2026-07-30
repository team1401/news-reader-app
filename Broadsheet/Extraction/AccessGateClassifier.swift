import Foundation

/// Whether Broadsheet may render a page's content in its own reader.
public enum AccessAssessment: Equatable, Sendable {
    /// The publisher has published the article openly.
    case open
    /// The publisher gates this article. Broadsheet stops here.
    case restricted(note: String)
    /// The page is open but yielded too little to be an article — a video page, a
    /// live blog shell, an index, a consent interstitial.
    case insufficient(note: String)

    public var allowsRendering: Bool { self == .open }
}

/// Decides, conservatively, whether a fetched page is openly readable.
///
/// This is a *stop* signal, never a workaround. When a publisher marks an article
/// as gated, Broadsheet declines to render it and hands the reader to the
/// publisher's own page — it does not look for the text behind the gate, strip an
/// overlay, or count a meter. The bias is deliberate: a false "restricted" costs
/// the reader a tap to the publisher, while a false "open" would render content the
/// publisher did not make free.
public enum AccessGateClassifier {
    /// Below this, whatever came back is not an article body.
    public static let minimumArticleCharacters = 700
    public static let minimumParagraphs = 3

    /// Structured declarations. `isAccessibleForFree: false` is schema.org's own
    /// way for a publisher to say this article is not free.
    static let structuredRestrictionMarkers = [
        "\"isaccessibleforfree\":false",
        "\"isaccessibleforfree\":\"false\"",
        "\"isaccessibleforfree\": false",
        "\"isaccessibleforfree\": \"false\""
    ]

    /// Markup hooks publishers use for their own gates.
    static let markupRestrictionMarkers = [
        "content_tier\" content=\"locked",
        "content_tier\" content=\"metered",
        "article:content_tier\" content=\"locked",
        "data-paywall=\"true\"",
        "id=\"paywall",
        "class=\"paywall",
        "paywall-overlay",
        "subscriber-only",
        "subscription-required",
        "regwall",
        "meteredcontent",
        "metered-content"
    ]

    /// Sentences a gate shows the reader. Matched only when the extracted article
    /// body is thin, so an investigation *about* paywalls is not misclassified.
    static let promptRestrictionMarkers = [
        "subscribe to continue reading",
        "subscribe to read the full",
        "this article is for subscribers",
        "already a subscriber?",
        "sign in to read this article",
        "create a free account to continue",
        "register to continue reading",
        "to continue reading this article"
    ]

    /// Status codes that are a refusal rather than a failure.
    public static func assessment(forStatusCode code: Int) -> AccessAssessment? {
        switch code {
        case 401:
            return .restricted(note: "The publisher requires an account to read this article, so Broadsheet is showing the feed excerpt.")
        case 402:
            return .restricted(note: "The publisher requires a subscription to read this article, so Broadsheet is showing the feed excerpt.")
        case 403:
            return .restricted(note: "The publisher declined to serve this article to Broadsheet, so the feed excerpt is shown instead.")
        case 451:
            return .restricted(note: "The publisher has made this article legally unavailable here, so the feed excerpt is shown instead.")
        default:
            return nil
        }
    }

    public static func assess(
        html: String,
        extractedCharacters: Int,
        extractedParagraphs: Int
    ) -> AccessAssessment {
        let lowered = html.lowercased()
        let compact = lowered.replacingOccurrences(of: " ", with: "")

        for marker in structuredRestrictionMarkers where compact.contains(marker.replacingOccurrences(of: " ", with: "")) {
            return .restricted(note: "The publisher marks this article as not free to read, so Broadsheet is showing the feed excerpt and a link to the original.")
        }
        for marker in markupRestrictionMarkers where lowered.contains(marker) {
            return .restricted(note: "The publisher gates this article behind a subscription or sign-in, so Broadsheet is showing the feed excerpt and a link to the original.")
        }

        let isThin = extractedCharacters < minimumArticleCharacters || extractedParagraphs < minimumParagraphs

        if isThin {
            for marker in promptRestrictionMarkers where lowered.contains(marker) {
                return .restricted(note: "The page asks the reader to subscribe or sign in before the article, so Broadsheet is showing the feed excerpt and a link to the original.")
            }
            return .insufficient(note: "Broadsheet could not read a full article from this page, so the publisher's excerpt is shown instead.")
        }

        return .open
    }

    /// Applied after extraction to catch pages that produced *something* but not an
    /// article.
    public static func assess(extraction: ExtractedArticle) -> AccessAssessment {
        guard extraction.textLength >= minimumArticleCharacters,
              extraction.paragraphCount >= minimumParagraphs else {
            return .insufficient(note: "Broadsheet could not read a full article from this page, so the publisher's excerpt is shown instead.")
        }
        return .open
    }
}
