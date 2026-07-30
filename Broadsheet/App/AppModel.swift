import Foundation
import Observation
import SwiftUI

/// Reader preferences from the shape brief: text size and serif/sans body.
@Observable
public final class ReaderSettings {
    public enum BodyFace: String, CaseIterable, Identifiable {
        case serif
        case sans

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .serif: return "Serif"
            case .sans: return "Sans"
            }
        }
    }

    public var bodyFace: BodyFace = .serif
    public var textSize: DynamicTypeSize = .large

    public init() {}

    public func bodyFont(_ style: Font.TextStyle) -> Font {
        switch bodyFace {
        case .serif: return BSFont.serif(style)
        case .sans: return BSFont.sans(style)
        }
    }

    public func increaseTextSize() {
        if let next = DynamicTypeSize.allCases.first(where: { $0 > textSize }) {
            textSize = min(next, .accessibility3)
        }
    }

    public func decreaseTextSize() {
        if let previous = DynamicTypeSize.allCases.last(where: { $0 < textSize }) {
            textSize = max(previous, .xSmall)
        }
    }
}

/// Application state for the vertical slice.
///
/// The demo edition is bundled, so the app is fully usable offline and screenshots
/// are deterministic. Saved stories live in memory for now; durable storage arrives
/// with the database layer.
@MainActor
@Observable
public final class AppModel {
    public private(set) var edition: EditionContent
    public private(set) var savedArticleIDs: [ArticleID] = []
    public private(set) var lastRefreshedAt: Date
    public private(set) var isRefreshing = false

    public let analysis: BiasAnalysisService
    public let settings = ReaderSettings()

    public init(
        edition: EditionContent = DemoEdition.edition(),
        analysis: BiasAnalysisService? = nil
    ) {
        self.edition = edition
        self.analysis = analysis ?? BiasAnalysisService()
        self.lastRefreshedAt = edition.editionDate
    }

    public var allArticles: [ArticleDocument] {
        edition.allArticles
    }

    public var sources: [Publisher] {
        var seen = Set<String>()
        return allArticles.compactMap { article in
            seen.insert(article.publisher.id).inserted ? article.publisher : nil
        }
        .sorted { $0.name < $1.name }
    }

    public var savedArticles: [ArticleDocument] {
        savedArticleIDs.compactMap { id in allArticles.first { $0.id == id } }
    }

    public func article(with id: ArticleID) -> ArticleDocument? {
        allArticles.first { $0.id == id }
    }

    public func isSaved(_ article: ArticleDocument) -> Bool {
        savedArticleIDs.contains(article.id)
    }

    public func toggleSaved(_ article: ArticleDocument) {
        if let index = savedArticleIDs.firstIndex(of: article.id) {
            savedArticleIDs.remove(at: index)
        } else {
            savedArticleIDs.insert(article.id, at: 0)
        }
    }

    public func removeSaved(_ article: ArticleDocument) {
        savedArticleIDs.removeAll { $0 == article.id }
    }

    /// Eager analysis, as specified: labels are computed during refresh so the
    /// badge is present when the card appears rather than after it is tapped.
    public func refresh(referenceDate: Date = Date()) async {
        isRefreshing = true
        defer { isRefreshing = false }

        edition = DemoEdition.edition(referenceDate: referenceDate)
        lastRefreshedAt = referenceDate
        await analysis.analyzeEagerly(edition.allArticles)
    }

    public func analyzeIfNeeded() async {
        await analysis.analyzeEagerly(allArticles)
    }

    public func state(for article: ArticleDocument) -> BiasAnalysisState {
        analysis.state(for: article)
    }
}
