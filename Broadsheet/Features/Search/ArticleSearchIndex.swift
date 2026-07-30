import Foundation

public struct ArticleSearchResult: Equatable, Identifiable, Sendable {
    public let article: ArticleDocument
    public let score: Double
    public let snippet: String

    public var id: ArticleID { article.id }
}

/// Local full-text search over the articles already on the device.
///
/// Nothing leaves the device and no query is logged. This is a straightforward
/// weighted term match; FTS5 replaces it when the database layer lands.
public enum ArticleSearchIndex {
    /// All terms must appear somewhere in the article, so a two-word query narrows
    /// rather than widens.
    public static func search(_ query: String, in articles: [ArticleDocument]) -> [ArticleSearchResult] {
        let terms = tokenize(query)
        guard !terms.isEmpty else { return [] }

        return articles.compactMap { article -> ArticleSearchResult? in
            let title = article.title.lowercased()
            let dek = (article.dek ?? "").lowercased()
            let body = article.bodyText.lowercased()
            let publisher = article.publisher.name.lowercased()

            var score = 0.0
            for term in terms {
                let titleHits = count(term, in: title)
                let dekHits = count(term, in: dek)
                let bodyHits = count(term, in: body)
                let publisherHits = count(term, in: publisher)

                guard titleHits + dekHits + bodyHits + publisherHits > 0 else { return nil }

                score += Double(titleHits) * 5
                score += Double(dekHits) * 3
                score += Double(publisherHits) * 2
                score += Double(bodyHits)
            }

            return ArticleSearchResult(
                article: article,
                score: score,
                snippet: snippet(for: terms, in: article)
            )
        }
        .sorted {
            $0.score == $1.score ? $0.article.publishedAt > $1.article.publishedAt : $0.score > $1.score
        }
    }

    static func tokenize(_ query: String) -> [String] {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func count(_ term: String, in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var total = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: term, options: [], range: range) {
            total += 1
            range = found.upperBound..<text.endIndex
        }
        return total
    }

    static func snippet(for terms: [String], in article: ArticleDocument) -> String {
        let sentences = article.bodyText
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 30 }

        if let match = sentences.first(where: { sentence in
            let lowered = sentence.lowercased()
            return terms.contains { lowered.contains($0) }
        }) {
            return match.count > 180 ? String(match.prefix(177)) + "…" : match
        }

        return article.dek ?? sentences.first ?? ""
    }
}
