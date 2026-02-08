import XCTest

final class BeschluenigeWatchAppUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Wait for the app to fully load before each test. Under parallel
        // execution the simulator can be slow, especially on the first boot.
        XCTAssertTrue(
            app.buttons["Start"].waitForExistence(timeout: 10),
            "App should show Start button after launch"
        )
    }

    /// Tap Start and wait for the recording view to appear. If the first
    /// tap does not register (slow simulator), retries automatically.
    private func tapStart() {
        let startButton = app.buttons["Start"]
        let stopButton = app.buttons["Stop"]

        startButton.tap()
        if !stopButton.waitForExistence(timeout: 3) {
            // First tap may not have registered on a slow simulator; retry
            startButton.tap()
        }
    }

    @MainActor
    func testStartButtonExists() throws {
        XCTAssertTrue(app.buttons["Start"].exists)
    }

    @MainActor
    func testStartButtonBeginsRecording() throws {
        app.buttons["Start"].tap()

        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["BPM"].exists)
    }

    @MainActor
    func testStopButtonOpensExport() throws {
        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))

        app.buttons["Stop"].tap()
        // Export sheet auto-appears after stopping
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExportAutoStartsAfterStop() throws {
        tapStart()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))

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
        app.buttons["Start"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))

        app.buttons["Stop"].tap()
        // Export sheet auto-appears
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))

        app.buttons["Done"].tap()

        // Should return to main screen with Start button
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkoutViewDisplaysHeartRateInfo() throws {
        app.buttons["Start"].tap()

        // Recording view should show either "waiting..." (no samples yet)
        // or "Xs ago" (samples received). Both confirm the recording view is shown.
        let waitingText = app.staticTexts["waiting..."]
        let agoText = app.staticTexts.matching(
            NSPredicate(format: "label ENDSWITH 's ago'")
        ).firstMatch

        let found = waitingText.waitForExistence(timeout: 10)
            || agoText.waitForExistence(timeout: 1)
        XCTAssertTrue(found)
    }

    @MainActor
    func testWorkoutListShowsSeededWorkout() throws {
        app.buttons["Workouts"].tap()

        // The UI-testing path seeds one workout with 0 chunks
        let chunkText = app.staticTexts["0 chunks - 0 B"]
        XCTAssertTrue(chunkText.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLogsViewShowsEntries() throws {
        app.buttons["Logs"].tap()

        // The app logs during startup, so at least one entry should appear
        let logsTitle = app.staticTexts["Logs"]
        XCTAssertTrue(logsTitle.waitForExistence(timeout: 5))

        // Verify that a log entry row rendered (ForEach closure executed).
        // Each log entry row shows a category label like "[SomeCategory]".
        let entryRow = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH '['")
        ).firstMatch
        XCTAssertTrue(entryRow.waitForExistence(timeout: 5))
    }
}
