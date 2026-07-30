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

    /// The demo edition is the deterministic content, so these exercise reader
    /// state against fixed articles. Live persistence has its own suite.
    private func makeModel() -> AppModel {
        let store = try! BroadsheetStore(inMemory: true)
        let model = AppModel(store: store, analysis: BiasAnalysisService(), buildsPipeline: false)
        model.isDemoMode = true
        return model
    }

    private func edition(_ model: AppModel) throws -> EditionContent {
        try XCTUnwrap(model.displayedEdition)
    }

    func testSavingAndRemovingStories() throws {
        let model = makeModel()
        let article = try edition(model).lead

        XCTAssertFalse(model.isSaved(article))

        model.toggleSaved(article)
        XCTAssertTrue(model.isSaved(article))
        XCTAssertEqual(model.savedArticles.map(\.id), [article.id])

        model.toggleSaved(article)
        XCTAssertFalse(model.isSaved(article))
        XCTAssertTrue(model.savedArticles.isEmpty)
    }

    func testMostRecentlySavedStoryAppearsFirst() throws {
        let model = makeModel()
        let content = try edition(model)
        let first = content.lead
        let second = content.river[0]

        model.toggleSaved(first)
        model.toggleSaved(second)

        XCTAssertEqual(model.savedArticles.map(\.id), [second.id, first.id])
    }

    func testRemoveSavedIsIdempotent() throws {
        let model = makeModel()
        let article = try edition(model).lead

        model.removeSaved(article)
        model.toggleSaved(article)
        model.removeSaved(article)
        model.removeSaved(article)

        XCTAssertTrue(model.savedArticles.isEmpty)
    }

    func testDemoSavesNeverReachTheDurableLibrary() throws {
        let model = makeModel()
        let article = try edition(model).lead

        model.toggleSaved(article)

        XCTAssertTrue(model.isSaved(article))
        XCTAssertTrue(model.store.savedArticles().isEmpty, "Demo fiction must not be written to the reader's library")
        XCTAssertEqual(model.store.articleCount(), 0)
    }

    func testArticleLookupByIdentity() throws {
        let model = makeModel()
        let article = try edition(model).river[1]

        XCTAssertEqual(model.article(with: article.id)?.title, article.title)
        XCTAssertNil(model.article(with: ArticleID(rawValue: "guid:nothing")))
    }

    func testEagerAnalysisLabelsEveryVisibleStory() async throws {
        let model = makeModel()

        await model.analyzeVisible()

        for article in model.allArticles {
            XCTAssertNotNil(model.state(for: article).result, "\u{201C}\(article.title)\u{201D} had no label after analysis")
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
