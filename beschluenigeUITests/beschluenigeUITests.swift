import XCTest

final class BeschluenigeUITests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "System Alert") { alert in
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            let dontAllowButton = alert.buttons["Don\u{2019}t Allow"]
            if dontAllowButton.exists {
                dontAllowButton.tap()
                return true
            }
            return false
        }
    }

    @MainActor
    func testNoWorkoutsShownInitially() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["No Workouts"].waitForExistence(timeout: 5)
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

    // MARK: - UI tests with seeded data

    @MainActor
    private func launchWithTestData() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }

    /// Find the list cell that contains the given text.
    @MainActor
    private func cell(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.staticText, identifier: text).firstMatch
    }

    /// Find the first cell whose label contains the given substring.
    @MainActor
    private func cellContaining(
        substring: String, in app: XCUIApplication, timeout: TimeInterval = 5
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", substring)
        let text = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: timeout), "Expected text containing '\(substring)'")
        // Find the cell that contains this text
        let cellQuery = app.cells.containing(predicate)
        let foundCell = cellQuery.firstMatch
        if foundCell.waitForExistence(timeout: 2) {
            return foundCell
        }
        // Fallback: return the text element itself
        return text
    }

    // MARK: ContentView closures

    @MainActor
    func testWorkoutListShowsWorkouts() throws {
        let app = launchWithTestData()

        // The incomplete workout should show "Receiving" text
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Receiving'")
            ).firstMatch.waitForExistence(timeout: 5),
            "Should show an incomplete workout with 'Receiving' text"
        )

        // The complete workout should show chunk count
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '2 chunks -'")
            ).firstMatch.waitForExistence(timeout: 2),
            "Should show the complete workout with chunk count"
        )
    }

    @MainActor
    func testNavigateToWorkoutDetail() throws {
        let app = launchWithTestData()

        // Wait for workouts to appear, then tap the complete workout cell
        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        // Should navigate to the detail view
        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5),
            "Should navigate to Workout detail view"
        )

        // The Summary tab should be selected by default
        XCTAssertTrue(
            app.staticTexts["Overview"].waitForExistence(timeout: 2),
            "Summary tab should show Overview section"
        )
    }

    @MainActor
    func testSwipeToDelete() throws {
        let app = launchWithTestData()

        // Wait for the incomplete workout row
        let receivingCell = cellContaining(substring: "Receiving", in: app)

        // Swipe left to reveal delete action
        receivingCell.swipeLeft()

        // Tap the Delete button from swipe action
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 3),
            "Should show Delete swipe action"
        )
        deleteButton.tap()

        // Alert should appear
        let alert = app.alerts["Delete Workout"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 3),
            "Should show delete confirmation alert"
        )

        // Tap Cancel to dismiss
        alert.buttons["Cancel"].tap()

        // The workout should still be there
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Receiving'")
            ).firstMatch.waitForExistence(timeout: 2),
            "Workout should still exist after cancelling delete"
        )
    }

    @MainActor
    func testSwipeToDeleteConfirm() throws {
        let app = launchWithTestData()

        let receivingCell = cellContaining(substring: "Receiving", in: app)

        receivingCell.swipeLeft()

        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        let alert = app.alerts["Delete Workout"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))

        // Confirm deletion
        alert.buttons["Delete"].tap()

        // The incomplete workout should be gone
        sleep(1)
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Receiving'")
            ).firstMatch.exists,
            "Workout should be removed after confirming delete"
        )
    }

    // MARK: WorkoutDetailView closures

    @MainActor
    func testDetailTabPicker() throws {
        let app = launchWithTestData()

        // Navigate to the complete workout
        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        // The segmented picker should have Summary and Charts tabs (ForEach)
        XCTAssertTrue(
            app.buttons["Summary"].waitForExistence(timeout: 2),
            "Summary tab should be visible in picker"
        )
        XCTAssertTrue(
            app.buttons["Charts"].waitForExistence(timeout: 2),
            "Charts tab should be visible in picker"
        )

        // Switch to Charts tab
        app.buttons["Charts"].tap()

        // Chart content should render (Heart Rate title from TimeseriesView)
        XCTAssertTrue(
            app.staticTexts["Heart Rate"].waitForExistence(timeout: 3),
            "Charts tab should show Heart Rate chart"
        )
    }

    @MainActor
    func testDetailSummaryContent() throws {
        let app = launchWithTestData()

        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        // Wait for detail view
        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        // Summary sections should show seeded data
        XCTAssertTrue(
            app.staticTexts["Heart Rate"].waitForExistence(timeout: 2),
            "Should show Heart Rate section"
        )
        XCTAssertTrue(
            app.staticTexts["GPS"].waitForExistence(timeout: 2),
            "Should show GPS section"
        )
        // The status row contains "Complete" text inside a NavigationLink
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Complete'")
            ).firstMatch.waitForExistence(timeout: 2),
            "Should show Complete status"
        )
    }

    @MainActor
    func testChunkListNavigation() throws {
        let app = launchWithTestData()

        // Navigate to the complete workout
        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        // Tap the "Complete" status cell to navigate to ChunkListView
        let statusCell = cellContaining(substring: "Complete", in: app)
        statusCell.tap()

        // ChunkListView should render with chunk rows (ForEach over chunk indices)
        XCTAssertTrue(
            app.navigationBars["2/2 Chunks"].waitForExistence(timeout: 5),
            "Should show ChunkListView with chunk count"
        )

        // Individual chunk rows should appear
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Chunk 0'")
            ).firstMatch.waitForExistence(timeout: 2),
            "Should show Chunk 0 row"
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Chunk 1'")
            ).firstMatch.waitForExistence(timeout: 2),
            "Should show Chunk 1 row"
        )

        // Manifest row should also appear
        XCTAssertTrue(
            app.staticTexts["Manifest received"].waitForExistence(timeout: 2),
            "Should show manifest status"
        )
    }

    // MARK: TimeseriesView closures

    @MainActor
    func testChartsTabRendersChart() throws {
        let app = launchWithTestData()

        // Navigate to complete workout, then Charts tab
        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        app.buttons["Charts"].tap()

        // TimeseriesView should render with HR data
        XCTAssertTrue(
            app.staticTexts["Heart Rate"].waitForExistence(timeout: 3),
            "Should show Heart Rate chart title"
        )

        // Stats bar should show Min/Avg/Max labels
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Min:'")
            ).firstMatch.waitForExistence(timeout: 2),
            "Should show Min stat"
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Max:'")
            ).firstMatch.waitForExistence(timeout: 2),
            "Should show Max stat"
        )
    }

    @MainActor
    func testChartDoubleTapResetZoom() throws {
        let app = launchWithTestData()

        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        app.buttons["Charts"].tap()

        // Wait for chart to render
        XCTAssertTrue(
            app.staticTexts["Heart Rate"].waitForExistence(timeout: 3)
        )

        // Double-tap on the chart area to fire the double-tap gesture closure
        let hrText = app.staticTexts["Heart Rate"]
        let chartCoord = hrText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 5.0))
        chartCoord.doubleTap()

        // The chart should still be visible (zoom reset is a no-op when not zoomed)
        XCTAssertTrue(
            app.staticTexts["Heart Rate"].exists,
            "Chart should still be visible after double-tap"
        )
    }

    @MainActor
    func testChartPanGesture() throws {
        let app = launchWithTestData()

        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        app.buttons["Charts"].tap()

        XCTAssertTrue(
            app.staticTexts["Heart Rate"].waitForExistence(timeout: 3)
        )

        // Drag on the chart area to fire the pan gesture closure
        let hrText = app.staticTexts["Heart Rate"]
        let start = hrText.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 5.0))
        let end = hrText.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 5.0))
        start.press(forDuration: 0.1, thenDragTo: end)

        // Chart should still be visible after panning
        XCTAssertTrue(
            app.staticTexts["Heart Rate"].exists,
            "Chart should still be visible after panning"
        )
    }

    // MARK: WorkoutDetailView files section (ForEach over disk files)

    @MainActor
    func testFilesSectionRendersOnDisk() throws {
        let app = launchWithTestData()

        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        // Scroll down to reveal the Files on Disk section
        app.swipeUp()

        // The Files on Disk section should exist -- the merged CBOR file we wrote
        // should appear in the list via ForEach
        XCTAssertTrue(
            app.staticTexts["Files on Disk"].waitForExistence(timeout: 3),
            "Should show Files on Disk section"
        )
    }

    // MARK: WorkoutDetailView actions section (ShareLink)

    @MainActor
    func testActionsShareLink() throws {
        let app = launchWithTestData()

        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        // Scroll down to find the Share Workout button (actionsSection with ShareLink)
        app.swipeUp()

        let shareButton = app.buttons["Share Workout"]
        XCTAssertTrue(
            shareButton.waitForExistence(timeout: 3),
            "Should show Share Workout button for complete workout with merged file"
        )
    }

    // MARK: ChunkListView refreshable + alert closures

    @MainActor
    func testChunkListPullToRefresh() throws {
        let app = launchWithTestData()

        // Navigate to the complete (merged) workout
        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        // Tap the "Complete" status cell to go to ChunkListView
        let statusCell = cellContaining(substring: "Complete", in: app)
        statusCell.tap()

        XCTAssertTrue(
            app.navigationBars["2/2 Chunks"].waitForExistence(timeout: 5)
        )

        // Pull to refresh via swipeDown on the list
        // Need a slow, long drag from top to trigger .refreshable
        let list = app.tables.firstMatch.exists ? app.tables.firstMatch : app.collectionViews.firstMatch
        let startCoord = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let endCoord = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        startCoord.press(forDuration: 0.05, thenDragTo: endCoord)

        // The "Already Merged" alert should appear
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            // Dismiss whatever alert appeared
            let okButton = alert.buttons.firstMatch
            if okButton.exists { okButton.tap() }
        }

        // Just verify we navigated and refreshed without crash
        XCTAssertTrue(
            app.navigationBars["2/2 Chunks"].exists
                || app.navigationBars["Workout"].exists
                || app.alerts.firstMatch.exists,
            "Should still be in ChunkListView or showing alert"
        )
    }

    // MARK: TimeseriesView zoom gesture

    @MainActor
    func testChartPinchZoom() throws {
        let app = launchWithTestData()

        let completeCell = cellContaining(substring: "2 chunks -", in: app)
        completeCell.tap()

        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 5)
        )

        app.buttons["Charts"].tap()

        XCTAssertTrue(
            app.staticTexts["Heart Rate"].waitForExistence(timeout: 3)
        )

        // Pinch on the chart area to fire the zoom gesture closures
        // Pinch in (zoom) then pinch out (zoom out) on the main view
        let chartElement = app.otherElements.firstMatch
        chartElement.pinch(withScale: 2.0, velocity: 1.0)
        chartElement.pinch(withScale: 0.5, velocity: -1.0)

        // Chart should still be visible
        XCTAssertTrue(
            app.staticTexts["Heart Rate"].exists,
            "Chart should still be visible after pinch zoom"
        )
    }

    // MARK: ContentView context menu

    @MainActor
    func testContextMenuShareOnWorkout() throws {
        let app = launchWithTestData()

        // Wait for the complete workout cell
        let completeCell = cellContaining(substring: "2 chunks -", in: app)

        // Long-press to open context menu
        completeCell.press(forDuration: 1.5)

        // ShareLink renders as a "Share" or "Share..." button in context menu
        let sharePredicate = NSPredicate(format: "label BEGINSWITH 'Share'")
        let shareButton = app.buttons.matching(sharePredicate).firstMatch
        XCTAssertTrue(
            shareButton.waitForExistence(timeout: 3),
            "Context menu should show Share button for merged workout"
        )

        // Tap Share to exercise the ShareLink closure
        shareButton.tap()

        // Dismiss the share sheet if it appeared
        sleep(1)
        let closeButton = app.buttons["Close"]
        if closeButton.waitForExistence(timeout: 2) {
            closeButton.tap()
        }
    }

    @MainActor
    func testContextMenuDeleteOnWorkout() throws {
        let app = launchWithTestData()

        // Wait for the incomplete workout cell (safe to delete in this test)
        let receivingCell = cellContaining(substring: "Receiving", in: app)

        // Long-press to open context menu
        receivingCell.press(forDuration: 1.5)

        // Tap Delete in context menu to exercise the action closure
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 3),
            "Context menu should show Delete button"
        )
        deleteButton.tap()

        // Delete confirmation alert should appear
        let alert = app.alerts["Delete Workout"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 3),
            "Should show delete confirmation alert from context menu"
        )

        // Cancel to keep the workout
        alert.buttons["Cancel"].tap()
    }
}
