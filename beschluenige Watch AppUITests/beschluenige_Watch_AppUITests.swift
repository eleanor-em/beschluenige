import XCTest

final class BeschluenigeWatchAppUITests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testStartButtonExists() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartButtonBeginsRecording() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()

        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BPM"].exists)
    }

    @MainActor
    func testStopButtonReturnsToStart() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExportButtonAppearsAfterRecording() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordingViewDisplaysHeartRateInfo() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()

        // Recording view should show either "waiting..." (no samples yet)
        // or "Xs ago" (samples received). Both confirm the recording view is shown.
        let waitingText = app.staticTexts["waiting..."]
        let agoText = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH 's ago'")
        ).firstMatch

        let found = waitingText.waitForExistence(timeout: 5)
            || agoText.waitForExistence(timeout: 1)
        XCTAssertTrue(found)
    }

    @MainActor
    func testExportViewShowsButtons() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))

        app.buttons["Export Data"].tap()
        XCTAssertTrue(app.buttons["Send to iPhone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    @MainActor
    func testExportSendFallsBackToLocalSave() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))

        app.buttons["Export Data"].tap()
        XCTAssertTrue(app.buttons["Send to iPhone"].waitForExistence(timeout: 5))

        app.buttons["Send to iPhone"].tap()

        // On simulator, WCSession is not activated, so transfer fails
        // and falls back to local save
        XCTAssertTrue(
            app.staticTexts["Transfer failed. Saved locally:"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testExportDoneButtonDismisses() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))

        app.buttons["Export Data"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))

        app.buttons["Done"].tap()

        // Should return to main screen with Export Data button
        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHeartRateDisplayedAfterSimulatedData() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        // Wait for simulated data fallback (10+ seconds)
        // Check that "Simulated data" label appears
        XCTAssertTrue(
            app.staticTexts["Simulated data"].waitForExistence(timeout: 15)
        )

        // BPM text and sample counts should also be visible
        XCTAssertTrue(app.staticTexts["BPM"].exists)
    }

    // Commented out for now because this makes the tests take forever.
//    @MainActor
//    func testLaunchPerformance() throws {
//        measure(metrics: [XCTApplicationLaunchMetric()]) {
//            XCUIApplication().launch()
//        }
//    }
}
