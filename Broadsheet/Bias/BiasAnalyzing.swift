import Foundation

/// A local article-lean analyzer.
///
/// The input type is deliberately ``BiasModelInput`` rather than
/// ``ArticleDocument``: an analyzer has no access to publisher, domain, author, or
/// source baseline, so it cannot learn or repeat a source-identity shortcut.
public protocol BiasAnalyzing: Sendable {
    /// The engine this analyzer will claim in the result's provenance.
    var engine: BiasEngine { get }

    /// Human-readable statement of whether this analyzer can run right now.
    var availabilityDescription: String { get }

    /// Whether ``analyze(_:)`` can currently produce a result. When `false`,
    /// `analyze` throws ``BiasAnalysisError/localModelUnavailable(reason:)``.
    var isAvailable: Bool { get }

    func analyze(_ input: BiasModelInput) async throws -> BiasAnalysisResult
}
