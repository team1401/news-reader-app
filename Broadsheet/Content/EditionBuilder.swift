import Foundation

/// Arranges cached articles into the day's edition.
///
/// This is editing, not ranking. There is no engagement signal, no personalization,
/// and no behavioural history in it: the newest story leads, independent reports on
/// the same event are grouped so the reader can see who else covered it, and
/// everything else runs in the river in publication order. The same input always
/// produces the same edition.
public enum EditionBuilder {
    /// Stories carried in the river. Beyond this the reader is better served by
    /// Search than by more scrolling.
    public static let riverLimit = 60

    /// Titles must share at least this proportion of their significant words to be
    /// treated as coverage of the same event.
    public static let clusterOverlapThreshold = 0.34

    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "into", "over", "after",
        "says", "said", "will", "amid", "than", "more", "less", "have", "has", "was",
        "were", "are", "its", "his", "her", "their", "they", "but", "not", "new",
        "about", "what", "when", "where", "how", "why", "who", "you", "your"
    ]

    public static func build(from articles: [ArticleDocument], referenceDate: Date = Date()) -> EditionContent? {
        let ordered = ArticleCanonicalizer.deduplicate(articles)
        guard let lead = ordered.first else { return nil }

        let rest = Array(ordered.dropFirst())
        let cluster = clusterCandidate(in: rest)
        let clusteredIDs = Set(cluster?.articles.map(\.id) ?? [])
        let river = rest.filter { !clusteredIDs.contains($0.id) }.prefix(riverLimit)

        return EditionContent(
            editionDate: referenceDate,
            lead: lead,
            cluster: cluster,
            river: Array(river)
        )
    }

    /// Finds the strongest group of independent reports on one event.
    ///
    /// Deliberately requires two *different* publishers: one outlet republishing
    /// itself is duplication, which deduplication already handled, and presenting
    /// it as "sources covering this" would be false.
    static func clusterCandidate(in articles: [ArticleDocument]) -> CoverageCluster? {
        let tokenized = articles.map { (article: $0, tokens: significantTokens(in: $0.title)) }
        var used = Set<ArticleID>()
        var best: [ArticleDocument] = []

        for (index, entry) in tokenized.enumerated() where !used.contains(entry.article.id) {
            guard entry.tokens.count >= 3 else { continue }

            var group = [entry.article]
            var publishers: Set<String> = [entry.article.publisher.id]

            for other in tokenized.dropFirst(index + 1) where !used.contains(other.article.id) {
                guard other.article.publisher.id != entry.article.publisher.id else { continue }
                guard overlap(entry.tokens, other.tokens) >= clusterOverlapThreshold else { continue }
                group.append(other.article)
                publishers.insert(other.article.publisher.id)
            }

            guard publishers.count >= 2 else { continue }
            if group.count > best.count {
                best = group
                used = Set(group.map(\.id))
            }
        }

        guard best.count >= 2, let first = best.first else { return nil }

        return CoverageCluster(
            id: "cluster." + ArticleCanonicalizer.normalizedTitle(first.title).replacingOccurrences(of: " ", with: "-"),
            title: first.title,
            articles: best
        )
    }

    static func significantTokens(in title: String) -> Set<String> {
        Set(
            ArticleCanonicalizer.normalizedTitle(title)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 4 && !stopWords.contains($0) }
        )
    }

    static func overlap(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let shared = Double(lhs.intersection(rhs).count)
        return shared / Double(min(lhs.count, rhs.count))
    }
}
