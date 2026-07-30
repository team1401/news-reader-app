import XCTest
@testable import Broadsheet

final class ArticleSearchIndexTests: XCTestCase {

    private let edition = DemoEdition.edition(referenceDate: Date(timeIntervalSince1970: 1_800_000_000))

    func testFindsArticlesByHeadlineTerm() {
        let results = ArticleSearchIndex.search("reserve margins", in: edition.allArticles)

        XCTAssertEqual(results.first?.article.id, edition.lead.id)
    }

    func testSearchesBodyTextNotJustHeadlines() {
        let results = ArticleSearchIndex.search("reconductoring", in: edition.allArticles)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.article.id, edition.lead.id)
    }

    func testFindsArticlesByPublisherName() {
        let results = ArticleSearchIndex.search("delta review", in: edition.allArticles)

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.article.publisher.name.contains("Delta") })
    }

    func testAllTermsMustMatch() {
        let narrow = ArticleSearchIndex.search("kelp allocation", in: edition.allArticles)
        XCTAssertTrue(narrow.isEmpty)

        let broad = ArticleSearchIndex.search("kelp", in: edition.allArticles)
        XCTAssertFalse(broad.isEmpty)
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(ArticleSearchIndex.search("", in: edition.allArticles).isEmpty)
        XCTAssertTrue(ArticleSearchIndex.search("   ", in: edition.allArticles).isEmpty)
    }

    func testHeadlineMatchesOutrankBodyMatches() {
        let results = ArticleSearchIndex.search("water", in: edition.allArticles)

        XCTAssertGreaterThan(results.count, 1)
        let top = try? XCTUnwrap(results.first)
        XCTAssertTrue(top?.article.title.localizedCaseInsensitiveContains("water") ?? false)
    }

    func testResultsCarryASnippetForContext() {
        let results = ArticleSearchIndex.search("urchin", in: edition.allArticles)

        let snippet = results.first?.snippet ?? ""
        XCTAssertTrue(snippet.localizedCaseInsensitiveContains("urchin"))
        XCTAssertLessThanOrEqual(snippet.count, 181)
    }

    func testTokenizerDropsPunctuationAndSingleCharacters() {
        XCTAssertEqual(ArticleSearchIndex.tokenize("a water-allocation rule!"), ["water", "allocation", "rule"])
    }
}

@MainActor
final class LibraryTests: XCTestCase {

    private func makeModel() -> AppModel {
        AppModel(
            edition: DemoEdition.edition(referenceDate: Date(timeIntervalSince1970: 1_800_000_000)),
            analysis: BiasAnalysisService()
        )
    }

    func testSavingAndRemovingStories() {
        let model = makeModel()
        let article = model.edition.lead

        XCTAssertFalse(model.isSaved(article))

        model.toggleSaved(article)
        XCTAssertTrue(model.isSaved(article))
        XCTAssertEqual(model.savedArticles.map(\.id), [article.id])

        model.toggleSaved(article)
        XCTAssertFalse(model.isSaved(article))
        XCTAssertTrue(model.savedArticles.isEmpty)
    }

    func testMostRecentlySavedStoryAppearsFirst() {
        let model = makeModel()
        let first = model.edition.lead
        let second = model.edition.river[0]

        model.toggleSaved(first)
        model.toggleSaved(second)

        XCTAssertEqual(model.savedArticles.map(\.id), [second.id, first.id])
    }

    func testRemoveSavedIsIdempotent() {
        let model = makeModel()
        let article = model.edition.lead

        model.removeSaved(article)
        model.toggleSaved(article)
        model.removeSaved(article)
        model.removeSaved(article)

        XCTAssertTrue(model.savedArticles.isEmpty)
    }

    func testSourcesAreDeduplicatedAndSorted() {
        let model = makeModel()
        let names = model.sources.map(\.name)

        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names, names.sorted())
        XCTAssertTrue(names.contains("Meridian Wire"))
    }

    func testArticleLookupByIdentity() {
        let model = makeModel()
        let article = model.edition.river[1]

        XCTAssertEqual(model.article(with: article.id)?.title, article.title)
        XCTAssertNil(model.article(with: ArticleID(rawValue: "guid:nothing")))
    }

    func testRefreshRebuildsTheEditionAndAnalyzesEagerly() async {
        let model = makeModel()
        let newDate = Date(timeIntervalSince1970: 1_800_100_000)

        await model.refresh(referenceDate: newDate)

        XCTAssertEqual(model.lastRefreshedAt, newDate)
        XCTAssertFalse(model.isRefreshing)
        for article in model.allArticles {
            XCTAssertNotNil(model.state(for: article).result, "“\(article.title)” had no label after refresh")
        }
    }

    func testReaderSettingsAdjustTextSizeWithinBounds() {
        let settings = ReaderSettings()

        for _ in 0..<20 { settings.increaseTextSize() }
        XCTAssertLessThanOrEqual(settings.textSize, .accessibility3)

        for _ in 0..<40 { settings.decreaseTextSize() }
        XCTAssertGreaterThanOrEqual(settings.textSize, .xSmall)
    }
}
