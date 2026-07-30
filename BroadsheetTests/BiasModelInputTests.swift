import XCTest
@testable import Broadsheet

/// The central privacy/validity property of the bias engine: an analyzer must
/// never see who published the article.
final class BiasModelInputTests: XCTestCase {

    private func article(blocks: [ArticleBlock]) -> ArticleDocument {
        let canonical = URL(string: "https://www.northgatejournal.example/opinion/cost-analysis?utm_source=rss")!
        return ArticleDocument(
            id: ArticleID(canonicalURL: canonical),
            canonicalURL: canonical,
            publisher: DemoPublishers.northgateJournal,
            kicker: "Commentary",
            title: "The Court Faulted the Agency for Skipping the Cost Analysis",
            dek: "A rule written without the promised accounting was always going to come back.",
            author: "Grant Weatherby",
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            blocks: blocks,
            contentSource: .bundledFixture
        )
    }

    private var articleWithIdentityInTheProse: ArticleDocument {
        article(blocks: [
            .paragraph(RichText("The agency promised a cost analysis when it opened this docket in 2022.")),
            .paragraph(RichText(runs: [
                .plain("As the Northgate Journal reported at northgatejournal.example, Grant Weatherby filed the first request. "),
                .link(text: "the docket", url: URL(string: "https://www.northgatejournal.example/docket")!),
                .plain(" remains open.")
            ])),
            .paragraph(RichText("Weatherby has covered the basin for eleven years.")),
            .image(ArticleImage(altText: "alt", caption: "A courthouse", credit: "Northgate Journal")),
            .paragraph(RichText("Irrigation districts spent four years arguing that compliance costs would land on operators."))
        ])
    }

    // MARK: What is included

    func testInputIncludesTitleDekAndArticleBlocks() {
        let input = BiasModelInputBuilder.build(from: articleWithIdentityInTheProse)

        XCTAssertTrue(input.headline.contains("Skipping the Cost Analysis"))
        XCTAssertEqual(input.dek, "A rule written without the promised accounting was always going to come back.")
        XCTAssertTrue(input.promptText.contains("promised a cost analysis"))
        XCTAssertTrue(input.promptText.contains("compliance costs would land on operators"))
    }

    func testInputIsChunkedByRole() {
        let input = BiasModelInputBuilder.build(from: articleWithIdentityInTheProse)
        let roles = Set(input.chunks.map(\.role))

        XCTAssertTrue(roles.contains(.headline))
        XCTAssertTrue(roles.contains(.dek))
        XCTAssertTrue(roles.contains(.lead))
        XCTAssertTrue(roles.contains(.conclusion))
    }

    // MARK: What is excluded

    func testInputExcludesPublisherName() {
        let input = BiasModelInputBuilder.build(from: articleWithIdentityInTheProse)

        XCTAssertFalse(input.promptText.localizedCaseInsensitiveContains("Northgate Journal"))
        XCTAssertFalse(input.promptText.localizedCaseInsensitiveContains("Northgate"))
    }

    func testInputExcludesDomainAndCanonicalURL() {
        let input = BiasModelInputBuilder.build(from: articleWithIdentityInTheProse)

        XCTAssertFalse(input.promptText.localizedCaseInsensitiveContains("northgatejournal.example"))
        XCTAssertFalse(input.promptText.localizedCaseInsensitiveContains("https://"))
    }

    func testInputExcludesAuthorIncludingBareSurname() {
        let input = BiasModelInputBuilder.build(from: articleWithIdentityInTheProse)

        XCTAssertFalse(input.promptText.localizedCaseInsensitiveContains("Grant Weatherby"))
        XCTAssertFalse(input.promptText.localizedCaseInsensitiveContains("Weatherby"))
    }

    func testInputExcludesPublisherBaselineAndItsProvider() {
        let input = BiasModelInputBuilder.build(from: article(blocks: [
            .paragraph(RichText("Ratings from Broadsheet demo ratings (fictional) place this outlet at Center-Right, which readers should weigh.")),
            .paragraph(RichText("The agency promised a cost analysis when it opened this docket in 2022 and never produced one."))
        ]))

        XCTAssertFalse(input.promptText.contains("Center-Right"))
        XCTAssertFalse(input.promptText.contains(DemoPublishers.ratingProvider))
    }

    func testInputExcludesCaptionsAndCredits() {
        let input = BiasModelInputBuilder.build(from: articleWithIdentityInTheProse)

        XCTAssertFalse(input.promptText.contains("A courthouse"))
    }

    func testRedactionLeavesAMarkerSoRemovalIsVisibleRatherThanSilent() {
        let input = BiasModelInputBuilder.build(from: articleWithIdentityInTheProse)

        XCTAssertTrue(input.promptText.contains(BiasModelInputBuilder.redactionToken))
    }

    func testEveryDemoArticleIsFreeOfItsOwnSourceIdentity() {
        for article in DemoEdition.edition(referenceDate: Date(timeIntervalSince1970: 1_800_000_000)).allArticles {
            let text = BiasModelInputBuilder.build(from: article).promptText
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains(article.publisher.name),
                "\(article.publisher.name) leaked into the model input for “\(article.title)”"
            )
            XCTAssertFalse(text.localizedCaseInsensitiveContains(article.publisher.domain))
            if let author = article.author {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(author))
            }
            if let baseline = article.publisher.baseline {
                XCTAssertFalse(text.contains(baseline.provider))
            }
        }
    }

    // MARK: Sufficiency and budget

    func testShortArticlesAreMarkedInsufficient() {
        let input = BiasModelInputBuilder.build(from: article(blocks: [
            .paragraph(RichText("Terms remain confidential."))
        ]))

        XCTAssertFalse(input.hasSufficientContent)
    }

    func testLongArticlesAreSampledWithinTheContextBudget() {
        let paragraph = String(repeating: "The commission reviewed the filings carefully. ", count: 60)
        let input = BiasModelInputBuilder.build(
            from: article(blocks: (0..<12).map { _ in .paragraph(RichText(paragraph)) }),
            characterBudget: 2_000
        )

        XCTAssertLessThan(input.promptText.count, 3_000)
        XCTAssertTrue(input.chunks.contains { $0.role == .conclusion })
    }
}
