import XCTest

final class AtlasLogUITests: XCTestCase {
    @MainActor
    func testMapTapsSelectAndRevealRegionsWithoutChangingVisits() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.textFields["place-search"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = []
        app.launch()

        func chooseLayer(_ title: String) {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Map level,'")).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 8))
            menu.tap()
            app.buttons[title].tap()
        }
        func assertSelected(_ id: String) {
            let row = app.buttons["region-row-\(id)"]
            let selectedAndVisible = NSPredicate(format: "selected == true AND hittable == true")
            expectation(for: selectedAndVisible, evaluatedWith: row)
            waitForExpectations(timeout: 8)
        }
        func attachScreenshot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // Interior land/water points in the initial portrait map viewport.
        // These tap the map itself, without using a list row or selection hook.
        let europe = app.coordinate(withNormalizedOffset: CGVector(dx: 0.64, dy: 0.28))
        let africa = app.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.43))
        let france = app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.30))
        let atlantic = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.30))

        chooseLayer("Continents")
        europe.tap()
        assertSelected("continent:europe")
        attachScreenshot("Map tap selects Europe and reveals its row")
        africa.tap()
        assertSelected("continent:africa")
        XCTAssertFalse(app.buttons["region-row-continent:europe"].isSelected)
        atlantic.tap()
        XCTAssertFalse(app.buttons["region-row-continent:africa"].isSelected)

        chooseLayer("Countries")
        france.tap()
        assertSelected("country:FR")
        let label = app.descendants(matching: .any).matching(identifier: "selected-region-label").firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(label.label, "France")
        XCTAssertLessThan(abs(label.frame.midX - france.screenPoint.x), 60)
        XCTAssertLessThan(abs(label.frame.midY - france.screenPoint.y), 60)
        attachScreenshot("Map tap selects unvisited France and scrolls the country list")
        app.buttons["Passport"].tap()
        assertMetric("countries", equals: "0", in: app)
        france.tap()
        assertSelected("country:FR")
        XCTAssertTrue(app.staticTexts["Explore"].exists)

        chooseLayer("Subcontinents")
        XCTAssertFalse(app.buttons["region-row-country:FR"].exists)
        africa.tap()
        assertSelected("subcontinent:northern-africa")
        chooseLayer("Cities")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "selected-region-label").firstMatch.exists)
        europe.tap()
        XCTAssertTrue(app.staticTexts["No visits yet"].exists)
    }

    @MainActor
    func testWashingtonVisitUpdatesRegionalPassportAndMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        let search = app.textFields["place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("Washington DC")
        let washington = app.staticTexts["Washington, DC"].firstMatch
        XCTAssertTrue(washington.waitForExistence(timeout: 5))
        washington.tap()
        XCTAssertTrue(app.navigationBars["Add visit"].waitForExistence(timeout: 5))
        app.buttons["save-place"].tap()
        XCTAssertTrue(app.navigationBars["Add visit"].waitForNonExistence(timeout: 5))
        app.buttons["Passport"].tap()
        assertMetric("regions", equals: "2", in: app)
        assertMetric("countries", equals: "1", in: app)

        let capital = app.staticTexts["Washington Capital Region"].firstMatch
        reveal(capital, in: app)
        capital.tap()
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Map level, Travel regions"].firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing-expanded"]
        app.launch()
        app.buttons["Passport"].tap()
        assertMetric("regions", equals: "2", in: app)
        let south = app.staticTexts["U.S. South"].firstMatch
        reveal(south, in: app)
        south.tap()
        XCTAssertTrue(app.buttons["Map level, Large regions"].firstMatch.waitForExistence(timeout: 5))
    }

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
    func testRegionLabelClearsWhenChangingLayers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.textFields["place-search"].waitForExistence(timeout: 8))
        app.terminate()
        app.launchArguments = []
        app.launch()

        func chooseLayer(_ title: String) {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Map level,'")).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.tap()
            app.buttons[title].tap()
        }
        func selectAfrica() {
            let africa = app.staticTexts["Africa"].firstMatch
            XCTAssertTrue(africa.waitForExistence(timeout: 5))
            africa.tap()
            XCTAssertTrue(app.navigationBars["Africa"].waitForExistence(timeout: 5))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["Africa"].waitForNonExistence(timeout: 5))
        }

        let regionLabel = app.descendants(matching: .any).matching(identifier: "selected-region-label").firstMatch
        chooseLayer("Continents")
        selectAfrica()
        XCTAssertTrue(regionLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(regionLabel.label, "Africa")

        for layer in ["Countries", "Subcontinents", "Travel regions", "Large regions", "Cities", "Continents"] {
            chooseLayer(layer)
            XCTAssertTrue(regionLabel.waitForNonExistence(timeout: 5), "Stale region label on \(layer)")
        }

        selectAfrica()
        XCTAssertTrue(regionLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(regionLabel.label, "Africa")
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
