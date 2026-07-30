import XCTest

/// Drives the real app: Today → reader → analysis sheet → Library → Search.
///
/// Every step attaches a screenshot so the visual result can be inspected
/// alongside the assertions.
final class BroadsheetUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTodayShowsMastheadLeadStoryAndClusterWithLabels() {
        XCTAssertTrue(app.staticTexts["BROADSHEET"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["LEAD STORY"].exists)
        capture("01-today-top")

        // Every card carries its article-level estimate before it is opened.
        let estimate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'On-device article estimate'")
        ).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))

        app.swipeUp()
        app.swipeUp()
        capture("02-today-cluster")
        XCTAssertTrue(app.staticTexts["Coverage by source baseline"].exists)

        app.swipeUp()
        app.swipeUp()
        capture("03-today-river")
    }

    func testReaderShowsSourceLinkAboveHeroAndRepeatsItInTheFooter() {
        app.staticTexts["Grid Operators Warn Summer Reserve Margins Are Thinner Than Forecast"].tap()

        let topLink = app.buttons["Read at Meridian Wire"]
        XCTAssertTrue(topLink.waitForExistence(timeout: 10))
        capture("04-reader-header")

        // The canonical action must sit above the hero image.
        let hero = app.images["Transmission towers crossing dry hills at dusk, with a low sun behind them."]
        XCTAssertTrue(hero.exists, "The hero figure should expose its alt text")
        XCTAssertLessThan(topLink.frame.midY, hero.frame.midY)

        // Inline links keep their text and remain tappable.
        XCTAssertTrue(app.links["joint filing"].exists)

        for _ in 0..<16 { app.swipeUp() }
        capture("05-reader-footer")
        XCTAssertTrue(app.buttons["Read the original at Meridian Wire"].exists)
        XCTAssertTrue(app.staticTexts["PERSPECTIVE"].exists)
    }

    func testTappingTheEstimateOpensProvenanceEvidenceAndCorrection() {
        app.staticTexts["Grid Operators Warn Summer Reserve Margins Are Thinner Than Forecast"].tap()

        let estimate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'On-device article estimate'")
        ).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 10))
        estimate.tap()

        XCTAssertTrue(app.staticTexts["On-device analysis"].waitForExistence(timeout: 5))
        capture("06-analysis-sheet")

        XCTAssertTrue(app.staticTexts["Article estimate"].exists)
        XCTAssertTrue(app.staticTexts["Confidence"].exists)
        XCTAssertTrue(app.staticTexts["Evidence from the article"].exists)

        // Provenance names the engine that actually ran and never claims a model.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] 'fixture heuristic'"))
                .firstMatch.exists
        )

        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        // The publisher baseline stays in its own section rather than being merged.
        XCTAssertTrue(app.staticTexts["Publisher baseline — sourced separately"].exists)
        XCTAssertTrue(app.staticTexts["Your correction"].exists)
        capture("06b-analysis-baseline-and-correction")

        app.buttons["Done"].tap()
    }

    func testLibraryAndSearchAreUsable() {
        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Nothing saved yet."].exists)
        capture("07-library")

        // The app states plainly whether the on-device model can run here.
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["On-device analysis"].exists)
        XCTAssertTrue(app.staticTexts["Apple Foundation Models"].exists)
        capture("07b-library-analysis-status")

        app.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("water")
        capture("08-search-results")
        XCTAssertTrue(app.staticTexts["Appeals Court Vacates Water Allocation Rule, Orders New Rulemaking"].waitForExistence(timeout: 5))
    }

    func testSavingAStoryPutsItInTheLibrary() {
        app.staticTexts["Grid Operators Warn Summer Reserve Margins Are Thinner Than Forecast"].tap()

        let save = app.buttons["Save to Library"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Library"].tap()

        XCTAssertTrue(
            app.staticTexts["Grid Operators Warn Summer Reserve Margins Are Thinner Than Forecast"]
                .waitForExistence(timeout: 5)
        )
        capture("09-library-saved")
    }
}

extension BroadsheetUITests {
    /// The capsule sits inside the story row's navigation link, so this guards
    /// against it either becoming inert or swallowing the row's tap.
    func testFeedCapsuleOpensAnalysisWithoutOpeningTheStory() {
        let capsule = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'On-device article estimate'")
        ).firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: 10))
        capsule.tap()

        XCTAssertTrue(app.staticTexts["On-device analysis"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Read at Meridian Wire"].exists, "The story should not have opened")
        capture("10-feed-capsule-analysis")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["LEAD STORY"].waitForExistence(timeout: 5))
    }
}
