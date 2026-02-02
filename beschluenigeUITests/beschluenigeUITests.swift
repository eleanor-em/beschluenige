//
//  beschluenigeUITests.swift
//  beschluenigeUITests
//
//  Created by Eleanor McMurtry on 01.02.2026.
//

import XCTest

final class BeschluenigeUITests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    @MainActor
    func testNoRecordingsShownInitially() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["No Recordings"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testNavigationTitleShown() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.navigationBars["beschluenige"].waitForExistence(timeout: 5)
        )
    }
}
