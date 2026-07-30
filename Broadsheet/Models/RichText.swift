import Foundation

/// Inline text with preserved reporting semantics.
///
/// Publisher HTML never reaches the reading surface. Extraction converts inline
/// markup into these runs, and the native reader decides how they are typeset.
public struct RichText: Codable, Equatable, Sendable {
    public enum Run: Codable, Equatable, Sendable {
        case plain(String)
        case emphasis(String)
        case strong(String)
        case link(text: String, url: URL)

        public var text: String {
            switch self {
            case .plain(let value), .emphasis(let value), .strong(let value):
                return value
            case .link(let text, _):
                return text
            }
        }
    }

    public let runs: [Run]

    public init(runs: [Run]) {
        self.runs = runs
    }

    public init(_ plain: String) {
        self.runs = [.plain(plain)]
    }

    public var plainText: String {
        runs.map(\.text).joined()
    }

    public var linkURLs: [URL] {
        runs.compactMap { run in
            if case .link(_, let url) = run { return url }
            return nil
        }
    }

    public var isEmpty: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
