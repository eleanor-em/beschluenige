import XCTest

final class beschluenige_Watch_AppUITests: XCTestCase {

    override func setUpWithError() throws {
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
    func testWaitingTextShownDuringRecording() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Start"].tap()

        // Before any HR samples arrive, should show "waiting..." or a sample count
        XCTAssertTrue(
            app.staticTexts["waiting..."].waitForExistence(timeout: 5)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'samples'")).firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
