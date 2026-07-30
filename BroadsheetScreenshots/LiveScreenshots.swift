import XCTest

/// Drives the shipping app against the **real network** and captures screenshots.
///
/// This target is deliberately not part of the `Broadsheet` scheme's test action:
/// it needs BBC News, NPR, Ars Technica, and ProPublica to be reachable, and the
/// offline suite must never need that. It is run on purpose with
/// `-scheme BroadsheetScreenshots`.
///
/// The library is in memory so a screenshot run never disturbs the reader's own
/// data, but every feed, article page, extraction, and analysis is real.
final class LiveScreenshots: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-broadsheet-in-memory-store"]
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func refreshAndWait() {
        let refresh = app.buttons["Refresh now"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 30))
        refresh.tap()

        // A real refresh fetches four feeds and extracts up to 25 pages each.
        let lead = app.staticTexts["LEAD STORY"]
        XCTAssertTrue(lead.waitForExistence(timeout: 300), "The live edition never appeared")
    }

    func testCaptureLightMode() {
        app.launch()

        XCTAssertTrue(app.staticTexts["BROADSHEET"].waitForExistence(timeout: 30))
        capture("live-01-first-launch")

        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 30))
        app.buttons["Manage sources, 4 subscribed"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 20))
        capture("live-02-sources")

        app.buttons["Today"].firstMatch.tap()
        refreshAndWait()
        capture("live-03-today")

        app.swipeUp()
        app.swipeUp()
        capture("live-04-today-river")

        // Open the lead story.
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        let firstHeadline = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'On-device article estimate'")
        ).firstMatch
        XCTAssertTrue(firstHeadline.waitForExistence(timeout: 30))

        app.staticTexts["LEAD STORY"].tap()
        let lead = app.otherElements.containing(NSPredicate(format: "label CONTAINS[c] 'LEAD STORY'")).firstMatch
        _ = lead.waitForExistence(timeout: 5)
        app.links.firstMatch.waitForExistence(timeout: 3)
        capture("live-05-lead-tapped-context")
    }

    func testCaptureReaderAndAnalysis() {
        app.launch()
        refreshAndWait()

        // The lead story card is the first navigation link under LEAD STORY.
        let cards = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'min read' OR label CONTAINS[c] 'min'"))
        if cards.count > 0 {
            cards.element(boundBy: 0).tap()
        } else {
            app.staticTexts.element(boundBy: 6).tap()
        }

        let readAt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Read at '")).firstMatch
        XCTAssertTrue(readAt.waitForExistence(timeout: 30), "The reader did not open")
        capture("live-06-reader")

        for _ in 0..<10 { app.swipeUp() }
        capture("live-07-reader-perspective")

        let estimate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'On-device article estimate'")
        ).firstMatch
        if estimate.exists {
            estimate.tap()
            XCTAssertTrue(app.staticTexts["On-device analysis"].waitForExistence(timeout: 20))
            capture("live-08-analysis-sheet")
            app.buttons["Done"].tap()
        }
    }

    func testCaptureDarkMode() {
        app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        app.launch()
        refreshAndWait()
        capture("live-09-today-dark")

        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 30))
        capture("live-10-library-dark")

        app.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        field.typeText("the")
        capture("live-11-search-dark")
    }
}
