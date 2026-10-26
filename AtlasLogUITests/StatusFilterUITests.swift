import XCTest

@MainActor
final class StatusFilterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFiltersApplyToCitiesDerivedRegionsAndManualStatusEdits() throws {
        let app = launchCleanMap()
        app.buttons["map-settings"].tap()
        app.buttons["Load sample journey"].tap()
        app.alerts.buttons["OK"].tap()
        app.buttons["Done"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing-expanded"]
        app.launch()

        for (filter, count) in [("All", 6), ("Visited", 6), ("Meaningful", 5), ("Want to visit", 0), ("Want to return", 1)] {
            chooseFilter(filter, in: app)
            assertCount(count, in: app)
        }
        XCTAssertTrue(app.buttons["place-row-geonames:2643743"].exists) // London
        XCTAssertFalse(app.buttons["place-row-geonames:4684888"].exists) // Dallas

        chooseLayer("Countries", in: app)
        chooseFilter("All", in: app)
        assertNonzeroCount(in: app)
        for (filter, count) in [("Visited", 5), ("Meaningful", 4), ("Want to visit", 0), ("Want to return", 1)] {
            chooseFilter(filter, in: app)
            assertCount(count, in: app)
        }
        XCTAssertTrue(app.buttons["region-row-country:GB"].exists)
        XCTAssertFalse(app.buttons["region-row-country:US"].exists)

        chooseLayer("Continents", in: app)
        chooseFilter("Visited", in: app)
        assertCount(4, in: app)
        chooseFilter("Meaningful", in: app)
        assertCount(3, in: app)
        XCTAssertFalse(app.buttons["region-row-continent:north-america"].exists)
        attachScreenshot("Meaningful filter excludes the limited-visit continent", in: app)

        chooseFilter("Want to visit", in: app)
        assertCount(0, in: app)
        XCTAssertTrue(app.staticTexts["No matching continents"].exists)
        app.buttons["Show all"].tap()
        assertCount(6, in: app)
        app.buttons["region-row-continent:asia"].tap()
        toggle("Visited", in: app)
        toggle("Want to visit", in: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Asia"].waitForNonExistence(timeout: 5))
        chooseFilter("Want to visit", in: app)
        assertCount(1, in: app)
        XCTAssertTrue(app.buttons["region-row-continent:asia"].exists)
        XCTAssertFalse(app.buttons["region-row-continent:europe"].exists)
        attachScreenshot("Wishlist filter shows the manually saved region", in: app)

        chooseFilter("Meaningful", in: app)
        assertCount(2, in: app)
        app.buttons["region-row-continent:europe"].tap()
        toggle("Meaningful visit", in: app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Europe"].waitForNonExistence(timeout: 5))
        assertCount(1, in: app)
        XCTAssertFalse(app.buttons["region-row-continent:europe"].exists)
        XCTAssertTrue(app.buttons["region-row-continent:south-america"].exists)
    }

    func testEmptyFiltersAcrossRegionLayersAndMapSelectionRecovery() throws {
        let app = launchCleanMap()
        for layer in ["Countries", "Travel regions", "Large regions", "Subcontinents", "Continents"] {
            chooseLayer(layer, in: app)
            chooseFilter("Visited", in: app)
            assertCount(0, in: app)
            XCTAssertTrue(app.staticTexts["No matching \(layer.lowercased())"].exists)
            app.buttons["Show all"].tap()
            assertNonzeroCount(in: app)
        }
        chooseFilter("Visited", in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.64, dy: 0.28)).tap()
        let row = app.buttons["region-row-continent:europe"]
        expectation(for: NSPredicate(format: "selected == true AND hittable == true"), evaluatedWith: row)
        waitForExpectations(timeout: 8)
        revealFilter(in: app)
        XCTAssertEqual(app.buttons["status-filter"].value as? String, "All")
        assertCount(6, in: app)
    }

    private func launchCleanMap() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.textFields["place-search"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["status-filter"].waitForExistence(timeout: 10))
        return app
    }

    private func chooseLayer(_ title: String, in app: XCUIApplication) {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Map level,'")).firstMatch.tap()
        app.buttons[title].tap()
    }

    private func revealFilter(in app: XCUIApplication) {
        let picker = app.buttons["status-filter"]
        for _ in 0..<6 {
            if picker.exists && picker.isHittable { return }
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(picker.exists && picker.isHittable)
    }

    private func chooseFilter(_ title: String, in app: XCUIApplication) {
        revealFilter(in: app)
        app.buttons["status-filter"].tap()
        app.buttons[title].tap()
    }

    private func assertCount(_ count: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let header = app.descendants(matching: .any).matching(identifier: "explore-result-count").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(header.value as? String, String(count), file: file, line: line)
    }

    private func assertNonzeroCount(in app: XCUIApplication) {
        let header = app.descendants(matching: .any).matching(identifier: "explore-result-count").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(Int(header.value as? String ?? "") ?? 0, 0)
    }

    private func toggle(_ title: String, in app: XCUIApplication) {
        let control = app.switches[title]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
