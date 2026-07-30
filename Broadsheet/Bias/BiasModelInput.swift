import Foundation

/// The only text a bias analyzer is ever given.
///
/// Analyzers take this type rather than ``ArticleDocument`` so publisher identity
/// cannot reach a classifier by accident: there is no field to read it from.
/// Bias predictors trained on articles readily learn "this publisher is usually
/// left" instead of reading the article, so the source is removed before inference.
public struct BiasModelInput: Equatable, Sendable {
    public struct Chunk: Equatable, Sendable {
        public enum Role: String, Equatable, Sendable {
            case headline
            case dek
            case lead
            case middle
            case conclusion
        }

        public let role: Role
        public let text: String

        public init(role: Role, text: String) {
            self.role = role
            self.text = text
        }
    }

    public let headline: String
    public let dek: String?
    public let chunks: [Chunk]

    public init(headline: String, dek: String?, chunks: [Chunk]) {
        self.headline = headline
        self.dek = dek
        self.chunks = chunks
    }

    public var bodyText: String {
        chunks
            .filter { $0.role != .headline && $0.role != .dek }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    /// The full sanitized text, headline first. Used for prompting and for
    /// deterministic fixture scoring.
    public var promptText: String {
        var sections: [String] = ["HEADLINE: \(headline)"]
        if let dek, !dek.isEmpty {
            sections.append("SUMMARY: \(dek)")
        }
        for chunk in chunks where chunk.role != .headline && chunk.role != .dek {
            sections.append("\(chunk.role.rawValue.uppercased()): \(chunk.text)")
        }
        return sections.joined(separator: "\n\n")
    }

    public var wordCount: Int {
        promptText.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.count
    }

    /// Below this, an estimate would be noise, so the pipeline abstains with N/A.
    public var hasSufficientContent: Bool {
        wordCount >= 40
    }
}

/// Builds ``BiasModelInput`` from an article by including only reporting text and
/// then redacting any residual source identity found inside it.
public enum BiasModelInputBuilder {
    /// Conservative budget for the on-device model's 4096-token context window.
    /// Roughly four characters per token, leaving room for instructions and output.
    public static let characterBudget = 6_000

    public static let redactionToken = "[source]"

    public static func build(from article: ArticleDocument, characterBudget: Int = characterBudget) -> BiasModelInput {
        let redactions = identityTerms(for: article)

        let headline = redact(article.title, terms: redactions)
        let dek = article.dek.map { redact($0, terms: redactions) }

        let paragraphs = article.blocks
            .compactMap { block -> String? in
                // Captions, credits, and dividers carry no reporting argument and
                // frequently carry publisher identity, so they are excluded.
                let text = block.analyzableText.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : redact(text, terms: redactions)
            }

        var chunks: [BiasModelInput.Chunk] = [.init(role: .headline, text: headline)]
        if let dek, !dek.isEmpty {
            chunks.append(.init(role: .dek, text: dek))
        }
        chunks.append(contentsOf: bodyChunks(from: paragraphs, characterBudget: characterBudget))

        return BiasModelInput(headline: headline, dek: dek, chunks: chunks)
    }

    /// Weighted sampling per the bias-engine spec: the lead, representative middle,
    /// and the conclusion, rather than a truncated prefix.
    private static func bodyChunks(from paragraphs: [String], characterBudget: Int) -> [BiasModelInput.Chunk] {
        guard !paragraphs.isEmpty else { return [] }

        if paragraphs.joined(separator: " ").count <= characterBudget {
            let split = partition(paragraphs)
            return [
                split.lead.isEmpty ? nil : BiasModelInput.Chunk(role: .lead, text: split.lead),
                split.middle.isEmpty ? nil : BiasModelInput.Chunk(role: .middle, text: split.middle),
                split.conclusion.isEmpty ? nil : BiasModelInput.Chunk(role: .conclusion, text: split.conclusion)
            ].compactMap { $0 }
        }

        let leadBudget = characterBudget / 2
        let conclusionBudget = characterBudget / 4
        let middleBudget = characterBudget - leadBudget - conclusionBudget

        let split = partition(paragraphs)
        return [
            BiasModelInput.Chunk(role: .lead, text: String(split.lead.prefix(leadBudget))),
            BiasModelInput.Chunk(role: .middle, text: String(split.middle.prefix(middleBudget))),
            BiasModelInput.Chunk(role: .conclusion, text: String(split.conclusion.suffix(conclusionBudget)))
        ].filter { !$0.text.isEmpty }
    }

    private static func partition(_ paragraphs: [String]) -> (lead: String, middle: String, conclusion: String) {
        switch paragraphs.count {
        case 1:
            return (paragraphs[0], "", "")
        case 2:
            return (paragraphs[0], "", paragraphs[1])
        default:
            let leadCount = max(1, paragraphs.count / 4)
            let lead = paragraphs.prefix(leadCount).joined(separator: "\n\n")
            let conclusion = paragraphs.suffix(1).joined(separator: "\n\n")
            let middle = paragraphs.dropFirst(leadCount).dropLast().joined(separator: "\n\n")
            return (lead, middle, conclusion)
        }
    }

    /// Publisher name, domain, canonical host/URL, author, and the publisher's
    /// baseline rating and provider. All are removed from the model's view.
    static func identityTerms(for article: ArticleDocument) -> [String] {
        var terms: [String] = [article.publisher.name, article.publisher.domain]

        if let host = article.canonicalURL?.host {
            terms.append(host)
            if host.hasPrefix("www.") { terms.append(String(host.dropFirst(4))) }
        }
        if let url = article.canonicalURL {
            terms.append(url.absoluteString)
        }
        if let author = article.author {
            terms.append(author)
            // Bylines appear as both "Ana Reyes" and "Reyes".
            let parts = author.split(separator: " ").map(String.init)
            if parts.count > 1, let surname = parts.last, surname.count > 3 {
                terms.append(surname)
            }
        }
        if let baseline = article.publisher.baseline {
            terms.append(baseline.rating)
            terms.append(baseline.provider)
        }

        // Bare domain labels ("meridianwire") leak identity as effectively as the
        // full host does.
        for domainPart in article.publisher.domain.split(separator: ".").map(String.init)
        where domainPart.count > 3 && domainPart != "example" && domainPart != "com" {
            terms.append(domainPart)
        }

        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
    }

    static func redact(_ text: String, terms: [String]) -> String {
        var output = text
        for term in terms {
            guard !term.isEmpty else { continue }
            output = output.replacingOccurrences(
                of: term,
                with: redactionToken,
                options: [.caseInsensitive]
            )
        }
        return output
    }
}
