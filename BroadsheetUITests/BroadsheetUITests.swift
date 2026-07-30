import XCTest

/// Drives the real app.
///
/// Two things are swapped by launch argument and nothing else: the library is in
/// memory so a test never touches the reader's real data, and the transport serves
/// bundled fixtures so the suite does not depend on four publishers being up. The
/// refresh pipeline, the parsers, Readability, the store, and the analyzer
/// selection are all the shipping implementations.
final class BroadsheetUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-broadsheet-in-memory-store", "-broadsheet-stub-network"]
    }

    private func launch(demoMode: Bool = false) {
        if demoMode {
            app.launchArguments.append("-broadsheet-demo-mode")
        }
        app.launch()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Pull-to-refresh on the Today river.
    private func pullToRefresh() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func refreshAndWaitForContent(timeout: TimeInterval = 90) {
        app.buttons["Refresh now"].firstMatch.tap()
        let firstStory = app.staticTexts["Fixture story one: the harbour authority publishes its dredging schedule"]
        XCTAssertTrue(
            firstStory.waitForExistence(timeout: timeout),
            "The refreshed edition never appeared"
        )
    }

    // MARK: First launch

    func testFirstLaunchSeedsTheFourVerifiedSourcesAndSaysNothingIsDownloaded() {
        launch()

        XCTAssertTrue(app.staticTexts["BROADSHEET"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Nothing downloaded yet"].exists)
        XCTAssertTrue(app.buttons["Refresh now"].exists)
        capture("01-first-launch-today")

        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))
        app.buttons["Manage sources, 4 subscribed"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 10))
        for title in ["BBC News", "NPR News", "Ars Technica", "ProPublica"] {
            XCTAssertTrue(app.staticTexts[title].exists, "\(title) should be seeded on first launch")
        }
        capture("02-first-launch-sources")
    }

    // MARK: Refresh

    func testRefreshReplacesTheEmptyEditionWithLiveContent() {
        launch()
        XCTAssertTrue(app.staticTexts["Nothing downloaded yet"].waitForExistence(timeout: 20))

        refreshAndWaitForContent()

        XCTAssertFalse(app.staticTexts["Nothing downloaded yet"].exists)
        XCTAssertTrue(app.staticTexts["LEAD STORY"].exists)
        capture("03-after-refresh-today")

        // Every card carries its article-level estimate before it is opened.
        let estimate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'On-device article estimate'")
        ).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 20))
    }

    func testPullToRefreshWorksFromTheRiver() {
        launch()
        XCTAssertTrue(app.staticTexts["Nothing downloaded yet"].waitForExistence(timeout: 20))

        pullToRefresh()

        XCTAssertTrue(
            app.staticTexts["Fixture story one: the harbour authority publishes its dredging schedule"]
                .waitForExistence(timeout: 90)
        )
        capture("04-pull-to-refresh")
    }

    // MARK: Reader

    func testReaderShowsExtractedProseAndTheCanonicalLinkAboveAndBelow() {
        launch()
        XCTAssertTrue(app.staticTexts["Nothing downloaded yet"].waitForExistence(timeout: 20))
        refreshAndWaitForContent()

        app.staticTexts["Fixture story one: the harbour authority publishes its dredging schedule"].firstMatch.tap()

        let topLink = app.buttons["Read at BBC News"]
        XCTAssertTrue(topLink.waitForExistence(timeout: 20))
        capture("05-reader-header")

        // Prose that only exists on the fetched page, so this proves extraction ran.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'fixture text written for'")).firstMatch.exists,
            "Extracted body text should be rendered natively"
        )

        for _ in 0..<14 { app.swipeUp() }
        XCTAssertTrue(app.buttons["Read the original at BBC News"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["PERSPECTIVE"].exists)
        capture("06-reader-footer")
    }

    /// The restricted fixture page declares itself not free to read. The reader
    /// must show the feed excerpt with an honest reason and a link to the
    /// publisher, and must not show article text from behind the gate.
    func testRestrictedArticleFallsBackToTheExcerptWithAnHonestStatus() {
        launch()
        XCTAssertTrue(app.staticTexts["Nothing downloaded yet"].waitForExistence(timeout: 20))
        refreshAndWaitForContent()

        let restricted = app.staticTexts["Fixture story two: the transit board reviews its fare proposal"]
        for _ in 0..<8 where !restricted.exists {
            app.swipeUp()
        }
        XCTAssertTrue(restricted.waitForExistence(timeout: 20))
        restricted.firstMatch.tap()

        XCTAssertTrue(app.buttons["Read at BBC News"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] 'gates this article' OR label CONTAINS[c] 'not free to read'")
            ).firstMatch.exists,
            "The reader must state why the full article is not shown"
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'circulating in draft'")).firstMatch.exists,
            "Text from behind the publisher's gate must never be rendered"
        )
        capture("07-restricted-fallback")
    }

    // MARK: Source management

    func testAddingASourceValidatesItBeforeSaving() {
        launch()
        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))
        app.buttons["Manage sources, 4 subscribed"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 10))

        app.buttons["Add source"].tap()
        XCTAssertTrue(app.navigationBars["Add source"].waitForExistence(timeout: 10))

        let field = app.textFields["Feed or website address"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("nowhere.invalid/feed.xml")
        app.buttons["Find feeds"].tap()

        // The stub transport has no such host, so the failure must be reported and
        // nothing must be saved.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'server replied'")).firstMatch
                .waitForExistence(timeout: 20)
        )
        capture("08-add-source-validation")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 10))
    }

    func testASourceCanBeDisabledAndDeleted() {
        launch()
        app.buttons["Library"].tap()
        app.buttons["Manage sources, 4 subscribed"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 20))

        let ars = app.staticTexts["Ars Technica"]
        XCTAssertTrue(ars.waitForExistence(timeout: 10))
        ars.firstMatch.tap()

        let toggle = app.switches["Enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        capture("09-source-detail")

        app.buttons["Delete source"].tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Ars Technica"].exists)
    }

    // MARK: Library, Search, demo mode

    func testLibraryAndSearchWorkOverDownloadedContent() {
        launch()
        XCTAssertTrue(app.staticTexts["Nothing downloaded yet"].waitForExistence(timeout: 20))
        refreshAndWaitForContent()

        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Nothing saved yet."].exists)
        capture("10-library")

        app.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText("harbour")

        XCTAssertTrue(
            app.staticTexts["Fixture story one: the harbour authority publishes its dredging schedule"]
                .waitForExistence(timeout: 20)
        )
        capture("11-search-results")
    }

    func testSavingAStoryPutsItInTheLibrary() {
        launch()
        XCTAssertTrue(app.staticTexts["Nothing downloaded yet"].waitForExistence(timeout: 20))
        refreshAndWaitForContent()

        app.staticTexts["Fixture story one: the harbour authority publishes its dredging schedule"].firstMatch.tap()

        let save = app.buttons["Save to Library"]
        XCTAssertTrue(save.waitForExistence(timeout: 20))
        save.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Library"].tap()

        XCTAssertTrue(
            app.staticTexts["Fixture story one: the harbour authority publishes its dredging schedule"]
                .waitForExistence(timeout: 20)
        )
        capture("12-library-saved")
    }

    /// Demo mode is an explicit, clearly labelled preview of bundled fiction.
    func testDemoModeIsLabelledAndShowsBundledFiction() {
        launch(demoMode: true)

        XCTAssertTrue(app.staticTexts["BROADSHEET"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Demo edition"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["LEAD STORY"].exists)
        capture("13-demo-mode")

        let estimate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'On-device article estimate'")
        ).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 20))
        estimate.tap()

        XCTAssertTrue(app.staticTexts["On-device analysis"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Article estimate"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] 'fixture heuristic'"))
                .firstMatch.exists,
            "The demo label must name the rule-based heuristic rather than claim a model"
        )
        capture("14-demo-analysis-sheet")
        app.buttons["Done"].tap()
    }

    /// Accessibility text sizes and dark appearance are first-class, not an
    /// afterthought: the masthead, the refresh action, and the source list must
    /// still be present and hittable at an accessibility size.
    func testAccessibilityTextSizeAndDarkModeKeepControlsUsable() {
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
            "-AppleInterfaceStyle", "Dark"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["BROADSHEET"].waitForExistence(timeout: 20))
        let refresh = app.buttons["Refresh now"]
        XCTAssertTrue(refresh.exists)
        XCTAssertTrue(refresh.isHittable, "The primary action must stay reachable at accessibility sizes")
        capture("16-accessibility-large-text-dark")

        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))
        let manage = app.buttons["Manage sources, 4 subscribed"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        XCTAssertTrue(manage.isHittable)
        capture("17-accessibility-library")
    }

    func testAnalysisStatusIsStatedHonestlyInLibrary() {
        launch()
        app.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 20))

        for _ in 0..<6 { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["On-device analysis"].exists)
        XCTAssertTrue(app.staticTexts["Apple Foundation Models"].exists)
        capture("15-library-analysis-status")
    }
}
