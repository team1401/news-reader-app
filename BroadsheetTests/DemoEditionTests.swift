import XCTest
@testable import Broadsheet

final class DemoEditionTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    private var edition: EditionContent {
        DemoEdition.edition(referenceDate: referenceDate)
    }

    func testEditionIsDeterministicForAGivenReferenceDate() {
        XCTAssertEqual(DemoEdition.edition(referenceDate: referenceDate), edition)
    }

    func testEditionHasALeadAClusterAndARiver() throws {
        let cluster = try XCTUnwrap(edition.cluster)
        XCTAssertGreaterThanOrEqual(cluster.articles.count, 3)
        XCTAssertGreaterThanOrEqual(edition.river.count, 4)
        XCTAssertGreaterThanOrEqual(edition.allArticles.count, 8)
    }

    func testEveryPublisherIsClearlyFictional() {
        for article in edition.allArticles {
            XCTAssertTrue(
                article.publisher.domain.hasSuffix(".example"),
                "\(article.publisher.name) does not use the reserved .example domain"
            )
        }
    }

    func testNoRealWireServiceOrAgencyCreditIsImplied() {
        let forbidden = ["getty", "reuters", "associated press", "ap photo", "afp", "shutterstock", "bloomberg"]

        for article in edition.allArticles {
            let credits = ([article.heroImage] + article.blocks.compactMap { block -> ArticleImage? in
                if case .image(let image) = block { return image }
                return nil
            })
            .compactMap { $0 }
            .compactMap { [$0.credit, $0.caption].compactMap { $0 }.joined(separator: " ") }
            .joined(separator: " ")
            .lowercased()

            for term in forbidden {
                XCTAssertFalse(credits.contains(term), "“\(term)” appears in a credit for “\(article.title)”")
            }
        }
    }

    func testIllustrationCreditsIdentifyThemselvesAsDemoData() {
        for article in edition.allArticles {
            guard let credit = article.heroImage?.credit else { continue }
            XCTAssertTrue(credit.contains("Broadsheet"), "Credit does not identify itself as fixture art: \(credit)")
        }
    }

    func testDemoContentIsMarkedAsFixtureSoItIsNeverAttributedToAModel() {
        for article in edition.allArticles {
            XCTAssertEqual(article.contentSource, .bundledFixture)
        }
    }

    func testArticlesUseVariedSemanticBlockTypes() {
        var seenHeading = false
        var seenList = false
        var seenQuote = false
        var seenInlineImage = false
        var seenLink = false
        var seenDivider = false

        for article in edition.allArticles {
            for block in article.blocks {
                switch block {
                case .heading: seenHeading = true
                case .list: seenList = true
                case .pullQuote: seenQuote = true
                case .image: seenInlineImage = true
                case .divider: seenDivider = true
                case .paragraph(let rich): seenLink = seenLink || !rich.linkURLs.isEmpty
                }
            }
        }

        XCTAssertTrue(seenHeading)
        XCTAssertTrue(seenList)
        XCTAssertTrue(seenQuote)
        XCTAssertTrue(seenInlineImage)
        XCTAssertTrue(seenLink)
        XCTAssertTrue(seenDivider)
    }

    func testLeadStoryHasArtACaptionAndACredit() throws {
        let hero = try XCTUnwrap(edition.lead.heroImage)
        XCTAssertNotNil(hero.artwork)
        XCTAssertNotNil(hero.caption)
        XCTAssertNotNil(hero.credit)
        XCTAssertFalse(hero.altText.isEmpty)
    }

    func testLongFormArticlesAreSubstantialRatherThanPlaceholders() {
        XCTAssertGreaterThan(edition.lead.wordCount, 400)
        XCTAssertGreaterThan(edition.lead.readingTimeMinutes, 1)

        let fullArticles = edition.allArticles.filter { $0.extraction == .full }
        XCTAssertGreaterThanOrEqual(fullArticles.count, 8)
        for article in fullArticles {
            XCTAssertGreaterThan(article.wordCount, 120, "“\(article.title)” reads like placeholder copy")
        }
    }

    func testEveryArticleHasAUniqueIdentity() {
        let ids = edition.allArticles.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testExtractionFailureStatesAreRepresented() {
        let statuses = edition.allArticles.map(\.extraction)
        XCTAssertTrue(statuses.contains { if case .paywalled = $0 { return true } else { return false } })
    }

    /// The demo edition must exercise all four labels so the feed shows the real
    /// range rather than one repeated badge.
    func testFixtureAnalysisCoversAllFourLabels() async throws {
        let analyzer = DeterministicFixtureBiasAnalyzer()
        var labels: Set<BiasLabel> = []

        for article in edition.allArticles {
            let input = BiasModelInputBuilder.build(from: article)
            labels.insert(try await analyzer.analyze(input).label)
        }

        XCTAssertEqual(labels, Set(BiasLabel.allCases), "Missing labels: \(Set(BiasLabel.allCases).subtracting(labels))")
    }

    func testClusterBaselineDistributionCoversSeveralSources() throws {
        let cluster = try XCTUnwrap(edition.cluster)
        let distribution = cluster.baselineDistribution
        XCTAssertGreaterThanOrEqual(distribution.count, 3)
        XCTAssertEqual(distribution.reduce(0) { $0 + $1.count }, cluster.articles.count)
    }

    func testBaselineBucketsMapFromRatingText() {
        XCTAssertEqual(BaselineBucket(rating: "Center-Left"), .centerLeft)
        XCTAssertEqual(BaselineBucket(rating: "Right"), .right)
        XCTAssertEqual(BaselineBucket(rating: nil), .unrated)
        XCTAssertEqual(BaselineBucket(rating: "Something else"), .unrated)
    }
}
