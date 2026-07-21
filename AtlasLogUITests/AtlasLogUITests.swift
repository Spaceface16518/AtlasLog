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

        let visited = app.switches["visited-toggle"]
        XCTAssertTrue(visited.waitForExistence(timeout: 5))
        visited.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.swipeUp()
        let meaningful = app.switches["meaningful-toggle"]
        XCTAssertTrue(meaningful.waitForExistence(timeout: 5))
        meaningful.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["save-place"].tap()

        let passport = app.buttons["Passport"]
        XCTAssertTrue(passport.waitForExistence(timeout: 5))
        passport.tap()
        XCTAssertTrue(app.staticTexts["1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dallas"].waitForExistence(timeout: 5))
        app.staticTexts["Dallas"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-expanded"]
        app.launch()
        app.buttons["Passport"].tap()
        XCTAssertTrue(app.staticTexts["Dallas"].waitForExistence(timeout: 5))
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
}
