import XCTest

final class AtlasLogUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddMeaningfulCityUpdatesPassportAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Import"].exists)

        let search = app.textFields["place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Dallas")
        XCTAssertTrue(app.staticTexts["Dallas"].waitForExistence(timeout: 5))
        app.staticTexts["Dallas"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Add visit"].waitForExistence(timeout: 5))

        app.swipeUp()
        let meaningful = app.switches["meaningful-toggle"]
        XCTAssertTrue(meaningful.waitForExistence(timeout: 5))
        meaningful.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["save-place"].tap()
        XCTAssertTrue(app.navigationBars["Add visit"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))

        let passport = app.buttons["Passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        passport.tap()
        assertMetric("countries", equals: "1", in: app)
        assertMetric("cities", equals: "1", in: app)
        assertMetric("continents", equals: "1", in: app)
        let savedCity = app.staticTexts["Dallas"].firstMatch
        reveal(savedCity, in: app)
        savedCity.tap()
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-expanded"]
        app.launch()
        app.buttons["Passport"].tap()
        assertMetric("countries", equals: "1", in: app)
        reveal(app.staticTexts["Dallas"].firstMatch, in: app)
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["map-settings"].exists)
        app.buttons["map-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Import"].exists)
        app.buttons["Import"].tap()
        XCTAssertTrue(app.staticTexts["Choose travel photos"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testComposedGeographyLevelsLoad() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 8))

        let mapLevel = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Map level,'")
        ).firstMatch
        XCTAssertTrue(mapLevel.waitForExistence(timeout: 5))
        mapLevel.tap()
        app.buttons["Continents"].tap()
        XCTAssertTrue(app.staticTexts["Africa"].waitForExistence(timeout: 5))

        app.buttons["Map level, Continents"].firstMatch.tap()
        app.buttons["Subcontinents"].tap()
        XCTAssertTrue(
            app.staticTexts["Northern Africa"].waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testWishlistAndNotesPersistWithoutAddingAVisit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        let search = app.textFields["place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Tokyo")
        let tokyo = app.staticTexts["Tokyo"].firstMatch
        XCTAssertTrue(tokyo.waitForExistence(timeout: 5))
        tokyo.tap()
        XCTAssertTrue(app.navigationBars["Add visit"].waitForExistence(timeout: 5))
        app.swipeUp()
        let visited = app.switches["visited-toggle"]
        XCTAssertTrue(visited.waitForExistence(timeout: 5))
        visited.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let wishlist = app.switches["wishlist-toggle"]
        XCTAssertTrue(wishlist.waitForExistence(timeout: 5))
        wishlist.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let notes = app.textFields["place-notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("Visit the gardens")
        app.buttons["save-place"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing-expanded"]
        app.launch()
        app.buttons["Passport"].tap()
        assertMetric("cities", equals: "0", in: app)
        assertMetric("wishlist", equals: "1", in: app)
        XCTAssertTrue(app.staticTexts["Tokyo"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Tokyo"].firstMatch.tap()
        let editSearch = app.textFields["place-search"]
        XCTAssertTrue(editSearch.waitForExistence(timeout: 5))
        app.staticTexts["Tokyo"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["City details"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertEqual(app.switches["wishlist-toggle"].value as? String, "1")
        XCTAssertEqual(app.textFields["place-notes"].value as? String, "Visit the gardens")
        XCTAssertFalse(app.switches["meaningful-toggle"].exists)
    }

    @MainActor
    private func assertMetric(_ name: String, equals value: String, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let metric = app.descendants(matching: .any).matching(identifier: "passport-\(name)").firstMatch
        XCTAssertTrue(metric.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(metric.value as? String, value, file: file, line: line)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, file: file, line: line)
    }
}
