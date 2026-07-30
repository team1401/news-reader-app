import XCTest
@testable import Broadsheet

final class AccessGateClassifierTests: XCTestCase {

    func testAnOpenArticleIsOpen() {
        let assessment = AccessGateClassifier.assess(
            html: HTMLFixtures.accessibleArticle,
            extractedCharacters: 1_800,
            extractedParagraphs: 6
        )
        XCTAssertEqual(assessment, .open)
        XCTAssertTrue(assessment.allowsRendering)
    }

    func testStructuredNotFreeDeclarationIsRestricted() {
        let assessment = AccessGateClassifier.assess(
            html: HTMLFixtures.paywalledArticle,
            extractedCharacters: 4_000,
            extractedParagraphs: 12
        )
        guard case .restricted(let note) = assessment else { return XCTFail("Expected restricted, got \(assessment)") }
        XCTAssertTrue(note.localizedCaseInsensitiveContains("not free"))
        XCTAssertFalse(assessment.allowsRendering)
    }

    /// Even with a plausible amount of extracted text, a publisher's own
    /// "not free" declaration wins. Broadsheet stops rather than rendering it.
    func testStructuredDeclarationOutranksAHealthyExtraction() {
        let assessment = AccessGateClassifier.assess(
            html: "<html>{\"isAccessibleForFree\":false}</html>",
            extractedCharacters: 20_000,
            extractedParagraphs: 40
        )
        guard case .restricted = assessment else { return XCTFail("Expected restricted, got \(assessment)") }
    }

    func testRegistrationWallMarkupIsRestricted() {
        let assessment = AccessGateClassifier.assess(
            html: HTMLFixtures.regwallArticle,
            extractedCharacters: 120,
            extractedParagraphs: 2
        )
        guard case .restricted = assessment else { return XCTFail("Expected restricted, got \(assessment)") }
    }

    func testAThinOpenPageIsInsufficientNotRestricted() {
        let assessment = AccessGateClassifier.assess(
            html: HTMLFixtures.thinPage,
            extractedCharacters: 60,
            extractedParagraphs: 1
        )
        guard case .insufficient = assessment else { return XCTFail("Expected insufficient, got \(assessment)") }
    }

    /// An investigation *about* paywalls is not itself paywalled. Prompt phrases
    /// only count when the extracted body is thin.
    func testReportingAboutSubscriptionsIsNotMisclassified() {
        let html = "<html><body><article>" +
            "<p>Subscribe to continue reading, the message said, and readers did not.</p>" +
            String(repeating: "<p>An ordinary paragraph of reporting about the subscription industry.</p>", count: 12) +
            "</article></body></html>"

        let assessment = AccessGateClassifier.assess(html: html, extractedCharacters: 2_400, extractedParagraphs: 13)
        XCTAssertEqual(assessment, .open)
    }

    func testRefusalStatusCodesMapToRestricted() {
        for code in [401, 402, 403, 451] {
            guard case .restricted? = AccessGateClassifier.assessment(forStatusCode: code) else {
                return XCTFail("\(code) should be a refusal")
            }
        }
        XCTAssertNil(AccessGateClassifier.assessment(forStatusCode: 404))
        XCTAssertNil(AccessGateClassifier.assessment(forStatusCode: 500))
    }
}

@MainActor
final class ReadabilityExtractorTests: XCTestCase {

    private var extractor: ReadabilityExtractor!

    override func setUp() async throws {
        try await super.setUp()
        extractor = ReadabilityExtractor()
    }

    override func tearDown() async throws {
        extractor = nil
        try await super.tearDown()
    }

    private let baseURL = URL(string: "https://news.example.org/harbour/dredging-schedule")!

    func testTheVendoredScriptsAreBundled() {
        XCTAssertTrue(extractor.isAvailable, "Readability.js and the bridge must ship in the app bundle")
        XCTAssertNotNil(BroadsheetResources.bundle.url(forResource: "Readability", withExtension: "js"))
        XCTAssertNotNil(BroadsheetResources.bundle.url(forResource: "broadsheet-extract", withExtension: "js"))
    }

    func testTheApacheLicenceTravelsWithTheCode() throws {
        let url = try XCTUnwrap(BroadsheetResources.bundle.url(forResource: "LICENSE", withExtension: "md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Apache License"))
        XCTAssertTrue(text.contains("Version 2.0"))
    }

    func testAccessibleArticleExtractsSemanticBlocks() async throws {
        let extraction = try await extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)

        XCTAssertGreaterThanOrEqual(extraction.paragraphCount, 5)
        XCTAssertGreaterThan(extraction.textLength, AccessGateClassifier.minimumArticleCharacters)

        let text = extraction.blocks.map(\.analyzableText).joined(separator: " ")
        XCTAssertTrue(text.contains("dredging schedule"))

        // Structure survives, not just prose.
        XCTAssertTrue(extraction.blocks.contains { if case .heading = $0 { return true } else { return false } })
        XCTAssertTrue(extraction.blocks.contains { if case .pullQuote = $0 { return true } else { return false } })
        XCTAssertTrue(extraction.blocks.contains { if case .list = $0 { return true } else { return false } })
    }

    func testInlineLinksArePreservedAsTypedRuns() async throws {
        let extraction = try await extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)

        let links = extraction.blocks.flatMap { block -> [URL] in
            if case .paragraph(let rich) = block { return rich.linkURLs }
            return []
        }
        XCTAssertTrue(
            links.contains { $0.absoluteString == "https://news.example.org/documents/schedule" },
            "Relative links must be resolved against the article URL. Got \(links)"
        )
    }

    func testHeroImageAndCaptionAreCaptured() async throws {
        let extraction = try await extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)

        let hero = try XCTUnwrap(extraction.leadImage)
        XCTAssertEqual(hero.remoteURL?.absoluteString, "https://cdn.example.org/harbour.jpg")
        XCTAssertEqual(hero.altText, "A dredger alongside a quay")
        XCTAssertEqual(hero.caption, "A dredger alongside the eastern quay.")
    }

    func testPublisherChromeIsRemoved() async throws {
        let extraction = try await extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)
        let text = extraction.blocks.map(\.analyzableText).joined(separator: " ").lowercased()

        XCTAssertFalse(text.contains("advertisement"))
        XCTAssertFalse(text.contains("sign up for our newsletter"))
        XCTAssertFalse(text.contains("another story you should read"))
    }

    func testRestrictedPageYieldsNothingWorthRendering() async throws {
        let extraction: ExtractedArticle
        do {
            extraction = try await extractor.extract(html: HTMLFixtures.paywalledArticle, baseURL: baseURL)
        } catch {
            // Readability finding no content at all is an equally correct outcome.
            return
        }

        XCTAssertLessThan(
            extraction.textLength,
            AccessGateClassifier.minimumArticleCharacters,
            "A gated page must not yield a renderable article"
        )
    }

    func testFeedFragmentModeNormalisesPublisherSuppliedContent() async throws {
        let wrapped = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(HTMLFixtures.feedContentFragment)</body></html>"
        let extraction = try await extractor.extract(html: wrapped, baseURL: baseURL, mode: .fragment)

        XCTAssertGreaterThanOrEqual(extraction.paragraphCount, 5)
        XCTAssertTrue(extraction.blocks.contains { if case .list = $0 { return true } else { return false } })
        XCTAssertTrue(extraction.blocks.contains { if case .heading = $0 { return true } else { return false } })
    }

    func testExtractionIsDeterministicAcrossRuns() async throws {
        let first = try await extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)
        let second = try await extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)

        XCTAssertEqual(first.blocks, second.blocks)
    }

    func testConcurrentExtractionsAreSerialisedAndCorrect() async throws {
        async let a = extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)
        async let b = extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)
        async let c = extractor.extract(html: HTMLFixtures.accessibleArticle, baseURL: baseURL)

        let results = try await [a, b, c]
        XCTAssertEqual(results[0].blocks, results[1].blocks)
        XCTAssertEqual(results[1].blocks, results[2].blocks)
    }

    func testAPageWithNoArticleReportsNoContent() async {
        do {
            let extraction = try await extractor.extract(html: "<html><body><div></div></body></html>", baseURL: baseURL)
            XCTAssertEqual(extraction.textLength, 0)
        } catch let error as ArticleExtractionError {
            guard case .noContent = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOnlyTheSingleInitialInMemoryNavigationIsAllowed() {
        XCTAssertTrue(ReadabilityExtractor.shouldAllowNavigation(
            isAwaitingInitialDocument: true,
            isMainFrame: true,
            navigationType: .other
        ))
        XCTAssertFalse(ReadabilityExtractor.shouldAllowNavigation(
            isAwaitingInitialDocument: false,
            isMainFrame: true,
            navigationType: .other
        ), "Publisher window.location navigation must not reuse the initial-load permit")
        XCTAssertFalse(ReadabilityExtractor.shouldAllowNavigation(
            isAwaitingInitialDocument: true,
            isMainFrame: false,
            navigationType: .other
        ), "A subframe must never receive the initial-load permit")
        XCTAssertFalse(ReadabilityExtractor.shouldAllowNavigation(
            isAwaitingInitialDocument: true,
            isMainFrame: true,
            navigationType: .linkActivated
        ))
    }
}
