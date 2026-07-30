import XCTest
@testable import Broadsheet

final class BiasLabelTests: XCTestCase {

    func testAllFourLabelsHaveDistinctDisplayNames() {
        XCTAssertEqual(BiasLabel.allCases.count, 4)
        XCTAssertEqual(BiasLabel.left.displayName, "Left")
        XCTAssertEqual(BiasLabel.center.displayName, "Center")
        XCTAssertEqual(BiasLabel.right.displayName, "Right")
        XCTAssertEqual(BiasLabel.notApplicable.displayName, "N/A")
    }

    func testAllFourLabelsDecodeFromPersistedResults() throws {
        for label in BiasLabel.allCases {
            let json = """
            {
              "label": "\(label.rawValue)",
              "confidenceScore": 0.8,
              "rationale": "Test",
              "evidence": [{"excerpt": "A supporting sentence from the article."}],
              "provenance": {
                "engine": "deterministicFixture",
                "modelVersion": "fixture-heuristic-1.0",
                "analyzedOnDevice": true
              }
            }
            """
            let decoded = try JSONDecoder().decode(BiasAnalysisResult.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.label, label)
            XCTAssertEqual(decoded.evidence.count, 1)
        }
    }

    func testResultsSurviveACodableRoundTrip() throws {
        let result = BiasAnalysisResult(
            label: .right,
            confidenceScore: 0.71,
            rationale: "Framing weight favours right-of-centre language.",
            evidence: [BiasEvidence(excerpt: "Taxpayer dollars funded four years of proceedings.")],
            provenance: BiasProvenance(engine: .appleFoundationModels, modelVersion: "x")
        )

        let decoded = try JSONDecoder().decode(
            BiasAnalysisResult.self,
            from: JSONEncoder().encode(result)
        )
        XCTAssertEqual(decoded, result)
    }

    func testModelTokensAreParsedTolerantly() {
        XCTAssertEqual(BiasLabel(modelToken: "Left"), .left)
        XCTAssertEqual(BiasLabel(modelToken: " CENTER "), .center)
        XCTAssertEqual(BiasLabel(modelToken: "right-leaning"), .right)
        XCTAssertEqual(BiasLabel(modelToken: "not_applicable"), .notApplicable)
        XCTAssertEqual(BiasLabel(modelToken: "N/A"), .notApplicable)
        XCTAssertNil(BiasLabel(modelToken: "somewhat progressive"))
    }

    func testConfidenceBucketsAreOrdered() {
        XCTAssertEqual(BiasConfidence(score: 0.2), .low)
        XCTAssertEqual(BiasConfidence(score: 0.6), .medium)
        XCTAssertEqual(BiasConfidence(score: 0.95), .high)
    }

    func testConfidenceScoreIsClamped() {
        let over = BiasAnalysisResult(
            label: .center, confidenceScore: 4.2, rationale: "", evidence: [],
            provenance: BiasProvenance(engine: .deterministicFixture, modelVersion: "v")
        )
        XCTAssertEqual(over.confidenceScore, 1.0)
    }

    func testOnlyTheSystemModelEngineIsDescribedAsMachineLearning() {
        XCTAssertTrue(BiasEngine.appleFoundationModels.isMachineLearning)
        XCTAssertFalse(BiasEngine.deterministicFixture.isMachineLearning)
        XCTAssertTrue(BiasEngine.deterministicFixture.disclosure.contains("not machine learning"))
    }
}

final class DeterministicFixtureBiasAnalyzerTests: XCTestCase {

    private let analyzer = DeterministicFixtureBiasAnalyzer()

    private func input(headline: String, body: String) -> BiasModelInput {
        BiasModelInput(
            headline: headline,
            dek: nil,
            chunks: [
                .init(role: .headline, text: headline),
                .init(role: .lead, text: body)
            ]
        )
    }

    func testProducesLeftForLeftFramedText() async throws {
        let result = try await analyzer.analyze(input(
            headline: "Council Approves Rent Stabilization for Working Families",
            body: """
            The ordinance is an affordable housing measure for working families whose rent has \
            outpaced wages for a decade. Tenant organisers documented price gouging in three \
            neighbourhoods after buildings changed hands, and the council said public investment \
            in enforcement would follow. Watchdogs warn that inequality in the rental market has \
            widened while the housing agency stayed underfunded.
            """
        ))

        XCTAssertEqual(result.label, .left)
        XCTAssertFalse(result.evidence.isEmpty)
    }

    func testProducesRightForRightFramedText() async throws {
        let result = try await analyzer.analyze(input(
            headline: "Licensing Rule Adds Compliance Costs for Small Business Owners",
            body: """
            Small business owners told the licensing board the rule is government overreach. \
            The compliance costs are not in the fee but in the hours, and the red tape falls on \
            operators least able to absorb it. Taxpayer dollars funded a review that the board's \
            own staff called burdensome, and the regulatory burden now falls on shops with no \
            bookkeeper.
            """
        ))

        XCTAssertEqual(result.label, .right)
    }

    func testProducesCenterForBalancedPoliticalReporting() async throws {
        let result = try await analyzer.analyze(input(
            headline: "Appeals Court Vacates Water Allocation Rule",
            body: """
            A federal appeals court vacated the basin allocation rule and returned it to the \
            agency for a new rulemaking. The panel wrote that the agency had not explained why it \
            departed from the earlier formula. Vacatur takes effect in ninety days, so deliveries \
            scheduled by the commission for this season proceed as published. Both the districts \
            that brought the challenge and the intervenors that opposed them described the ruling \
            as partial, and the agency said it was reviewing the opinion.
            """
        ))

        XCTAssertEqual(result.label, .center)
    }

    func testProducesNotApplicableForNonpoliticalReporting() async throws {
        let result = try await analyzer.analyze(input(
            headline: "Marine Biologists Track an Unusually Early Kelp Bloom",
            body: """
            Divers surveying the reef recorded canopy-forming kelp six weeks earlier than the \
            ten-year average for the site. Water temperature at ten metres has been about half a \
            degree cooler than usual since April, and nitrate concentrations stayed high. Urchin \
            counts at the northern transect have fallen for a third consecutive year, which may \
            matter more than the temperature.
            """
        ))

        XCTAssertEqual(result.label, .notApplicable)
    }

    func testAbstainsWhenThereIsTooLittleText() async throws {
        let result = try await analyzer.analyze(input(
            headline: "Port Authority Weighs a Berth Lease",
            body: "Terms remain confidential."
        ))

        XCTAssertEqual(result.label, .notApplicable)
        XCTAssertTrue(result.rationale.contains("not enough"))
    }

    func testIsDeterministicAcrossRuns() async throws {
        let sample = input(
            headline: "Licensing Rule Adds Compliance Costs for Small Business Owners",
            body: "Small business owners called it government overreach and said the red tape and compliance costs fall on the smallest shops. The board will vote in September after staff return with a tiered proposal for the licence."
        )

        let first = try await analyzer.analyze(sample)
        let second = try await analyzer.analyze(sample)

        XCTAssertEqual(first, second)
    }

    func testNeverClaimsToBeAModel() async throws {
        let result = try await analyzer.analyze(input(
            headline: "Appeals Court Vacates Water Allocation Rule",
            body: "A federal appeals court vacated the basin allocation rule and returned it to the agency for a new rulemaking after the commission's hearing."
        ))

        XCTAssertEqual(result.provenance.engine, .deterministicFixture)
        XCTAssertFalse(result.provenance.engine.isMachineLearning)
        XCTAssertNotEqual(result.provenance.engine, .appleFoundationModels)
        XCTAssertTrue(result.provenance.analyzedOnDevice)
    }

    func testWordBoundaryMatchingAvoidsSubstringFalsePositives() {
        XCTAssertEqual(DeterministicFixtureBiasAnalyzer.occurrences(of: "union", in: "the communion service"), 0)
        XCTAssertEqual(DeterministicFixtureBiasAnalyzer.occurrences(of: "union", in: "the union voted"), 1)
    }
}

final class FoundationModelsBiasAnalyzerTests: XCTestCase {

    private let analyzer = FoundationModelsBiasAnalyzer()

    private var sufficientInput: BiasModelInput {
        BiasModelInput(
            headline: "Appeals Court Vacates Water Allocation Rule",
            dek: "The panel held that the agency did not explain its departure from the prior formula.",
            chunks: [
                .init(role: .headline, text: "Appeals Court Vacates Water Allocation Rule"),
                .init(role: .lead, text: String(repeating: "The commission reviewed the filings and returned the rule to the agency for a new rulemaking. ", count: 5))
            ]
        )
    }

    /// Attaches the outcome so the result bundle records whether the system model
    /// actually ran on the machine that ran the tests.
    private func record(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "foundation-models-outcome"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAvailabilityIsAlwaysExplained() {
        XCTAssertFalse(analyzer.availabilityDescription.isEmpty)
    }

    /// The behaviour that must hold on every machine: either the system model
    /// actually ran and the result says so, or an explicit unavailable error is
    /// thrown. A simulated or substituted result is never acceptable.
    func testEitherTheSystemModelRunsOrAnExplicitErrorIsThrown() async {
        record("availability: \(analyzer.availabilityDescription)")

        do {
            let result = try await analyzer.analyze(sufficientInput)
            XCTAssertTrue(analyzer.isAvailable, "A result was returned while the model reported itself unavailable")
            XCTAssertEqual(result.provenance.engine, .appleFoundationModels)
            XCTAssertTrue(BiasLabel.allCases.contains(result.label))
            record("""
            outcome: the on-device system model ran
            label: \(result.label.displayName)
            confidence: \(result.confidenceScore)
            rationale: \(result.rationale)
            verified evidence spans: \(result.evidence.count)
            """)
        } catch let error as BiasAnalysisError {
            record("outcome: analysis did not run — \(error.errorDescription ?? "no reason given")")
            switch error {
            case .localModelUnavailable(let reason):
                XCTAssertFalse(reason.isEmpty)
                XCTAssertFalse(analyzer.isAvailable)
            case .generationFailed(let reason):
                XCTAssertFalse(reason.isEmpty)
            case .insufficientArticleContent:
                XCTFail("The fixture input has sufficient content")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testShortInputIsRejectedBeforeAnyInference() async {
        let tiny = BiasModelInput(headline: "Berth lease", dek: nil, chunks: [.init(role: .lead, text: "Terms remain confidential.")])

        do {
            _ = try await analyzer.analyze(tiny)
            XCTFail("Expected insufficientArticleContent")
        } catch {
            XCTAssertEqual(error as? BiasAnalysisError, .insufficientArticleContent)
        }
    }

    func testFabricatedEvidenceIsRejected() {
        let source = "The commission reviewed the filings and returned the rule to the agency for a new rulemaking."

        XCTAssertTrue(FoundationModelsBiasAnalyzer.appearsVerbatim("returned the rule to the agency", in: source))
        XCTAssertTrue(FoundationModelsBiasAnalyzer.appearsVerbatim("“returned the rule to the agency”", in: source))
        XCTAssertFalse(FoundationModelsBiasAnalyzer.appearsVerbatim("the agency acted with reckless disregard", in: source))
        XCTAssertFalse(FoundationModelsBiasAnalyzer.appearsVerbatim("rule", in: source), "Fragments are too short to verify")
    }
}
