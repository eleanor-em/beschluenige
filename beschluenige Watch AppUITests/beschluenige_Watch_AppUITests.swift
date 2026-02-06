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
    func testStopButtonOpensExport() throws {
        app.launch()

        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()
        // Export sheet auto-appears after stopping
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExportAutoStartsAfterStop() throws {
        app.launch()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))

        app.buttons["Stop"].tap()

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
        // Export sheet auto-appears
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))

        app.buttons["Done"].tap()

        // Should return to main screen with Start button
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
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
    func testWorkoutListShowsSeededWorkout() throws {
        app.launch()

        XCTAssertTrue(app.buttons["Workouts"].waitForExistence(timeout: 5))
        app.buttons["Workouts"].tap()

        // The UI-testing path seeds one workout with 0 chunks
        let chunkText = app.staticTexts["0 chunks - 0.0 MB"]
        XCTAssertTrue(chunkText.waitForExistence(timeout: 5))
    }
}
