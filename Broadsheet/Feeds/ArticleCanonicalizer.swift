import CryptoKit
import Foundation

/// Deterministic canonicalization and deduplication for cached articles.
///
/// Feeds re-publish the same story with changing tracking parameters, and the same
/// wire report often appears twice inside one publisher's feed under a slightly
/// edited headline. Both collapse here, and they collapse the same way every time:
/// nothing in this type reads the clock, hashes an object identity, or depends on
/// dictionary ordering.
public enum ArticleCanonicalizer {

    // MARK: Content hash

    /// Stable SHA-256 over the reader-visible content. Used to detect that a cached
    /// row needs rewriting and to spot byte-identical reprints.
    public static func contentHash(for document: ArticleDocument) -> String {
        let material = [
            normalizedTitle(document.title),
            document.dek.map(normalizedText) ?? "",
            normalizedText(document.bodyText),
            document.canonicalURL.map { ArticleID.normalizedKey(for: $0) } ?? ""
        ].joined(separator: "\u{1F}")

        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Duplicate keys

    /// Primary identity: the normalized canonical URL (or feed GUID) already
    /// computed by ``ArticleID``.
    public static func canonicalKey(for document: ArticleDocument) -> String {
        document.id.rawValue
    }

    /// Near-duplicate identity: the same publisher republishing the same headline
    /// at a different URL. Deliberately scoped to one publisher — two outlets
    /// writing the same headline is coverage, not duplication, and the coverage
    /// cluster depends on keeping both.
    public static func nearDuplicateKey(for document: ArticleDocument) -> String {
        let title = normalizedTitle(document.title)
        guard title.count >= 12 else { return canonicalKey(for: document) }
        return document.publisher.domain.lowercased() + "\u{1F}" + title
    }

    // MARK: Deduplication

    /// Collapses duplicates and returns a stable order: newest first, ties broken
    /// by identity so the same input always yields the same output.
    public static func deduplicate(_ documents: [ArticleDocument]) -> [ArticleDocument] {
        var winners: [String: ArticleDocument] = [:]
        var aliasToPrimary: [String: String] = [:]

        for document in documents.sorted(by: isOrderedBefore) {
            let canonical = canonicalKey(for: document)
            let near = nearDuplicateKey(for: document)
            let primary = aliasToPrimary[canonical] ?? aliasToPrimary[near] ?? canonical

            if let existing = winners[primary] {
                winners[primary] = preferred(existing, document)
            } else {
                winners[primary] = document
            }
            aliasToPrimary[canonical] = primary
            aliasToPrimary[near] = primary
        }

        return winners.values.sorted(by: isOrderedBefore)
    }

    /// Keeps the copy with more extracted content; falls back to the newer one and
    /// then to identity so the choice never depends on input ordering.
    static func preferred(_ lhs: ArticleDocument, _ rhs: ArticleDocument) -> ArticleDocument {
        if lhs.blocks.count != rhs.blocks.count {
            return lhs.blocks.count > rhs.blocks.count ? lhs : rhs
        }
        if lhs.publishedAt != rhs.publishedAt {
            return lhs.publishedAt > rhs.publishedAt ? lhs : rhs
        }
        return lhs.id.rawValue <= rhs.id.rawValue ? lhs : rhs
    }

    static func isOrderedBefore(_ lhs: ArticleDocument, _ rhs: ArticleDocument) -> Bool {
        if lhs.publishedAt != rhs.publishedAt {
            return lhs.publishedAt > rhs.publishedAt
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    // MARK: Normalization

    /// Lowercases, folds smart punctuation, drops everything that is not a letter,
    /// digit, or single space. `“Ruling — Round Two”` and `"Ruling - Round two"`
    /// become the same key.
    static func normalizedTitle(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false

        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !scalars.isEmpty { scalars.append(" ") }
                pendingSpace = false
                scalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return String(scalars)
    }

    static func normalizedText(_ text: String) -> String {
        HTMLTextNormalizer.collapseWhitespace(in: text)
    }
}
