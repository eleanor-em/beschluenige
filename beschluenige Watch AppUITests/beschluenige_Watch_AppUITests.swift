import XCTest

final class BeschluenigeWatchAppUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
    }

    @MainActor
    func testStartButtonExists() throws {
        app.launch()

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartButtonBeginsRecording() throws {
        app.launch()

        app.buttons["Start"].tap()

        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BPM"].exists)
    }

    @MainActor
    func testStopButtonReturnsToStart() throws {
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExportButtonAppearsAfterRecording() throws {
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkoutViewDisplaysHeartRateInfo() throws {
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
        let fallbackText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Transfer failed'")
        ).firstMatch
        XCTAssertTrue(fallbackText.waitForExistence(timeout: 10))
    }

    @MainActor
    func testExportDoneButtonDismisses() throws {
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
    func testWorkoutListShowsSeededWorkout() throws {
        app.launch()

        XCTAssertTrue(app.buttons["Workouts"].waitForExistence(timeout: 5))
        app.buttons["Workouts"].tap()

        // The UI-testing path seeds one workout with 42 samples
        let samplesText = app.staticTexts["42 samples"]
        XCTAssertTrue(samplesText.waitForExistence(timeout: 5))
    }

    @MainActor
    func testExportSheetPresents() throws {
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Export Data"].waitForExistence(timeout: 5))

        app.buttons["Export Data"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }
}
