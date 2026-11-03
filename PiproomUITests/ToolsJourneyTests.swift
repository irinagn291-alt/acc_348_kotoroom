import XCTest

final class ToolsJourneyTests: XCTestCase {
    @MainActor func testDeskToolsWithoutPhotosPermission() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Tools QA")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        func openTools() {
            let row = app.buttons["openTools"]
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            if !row.isHittable { app.swipeUp() }
            row.tap()
            XCTAssertTrue(app.buttons["generatePassword"].waitForExistence(timeout: 6))
        }
        openTools()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Piproom Tools"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["generatePassword"].tap()
        let value = app.staticTexts["generatedPassword"]
        XCTAssertTrue(value.waitForExistence(timeout: 6))
        XCTAssertEqual(value.label.count, 20)
        let first = value.label
        app.buttons["rollPassword"].tap()
        XCTAssertNotEqual(value.label, first)
        app.buttons["Copy password"].tap()
        XCTAssertTrue(app.buttons["Copied"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["generateNames"].tap()
        let field = app.textFields["nameSeed"]
        field.tap(); field.typeText("marina\n")
        app.buttons["Short"].tap()
        app.buttons["rollNames"].tap()
        XCTAssertTrue(app.buttons["nameIdea-0"].label.contains("marin"))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["checkPassword"].tap()
        XCTAssertFalse(app.buttons["submitLookup"].isEnabled)
        app.secureTextFields["lookupInput"].tap()
        app.secureTextFields["lookupInput"].typeText("password")
        XCTAssertFalse(app.staticTexts["passwordFound"].exists)
        XCTAssertTrue(app.buttons["submitLookup"].isEnabled)
        if ProcessInfo.processInfo.environment["PIPROOM_LIVE_HIBP_TEST"] == "1" {
            app.buttons["submitLookup"].tap()
            XCTAssertTrue(app.staticTexts["passwordFound"].waitForExistence(timeout: 25), app.debugDescription)
        }
        app.terminate(); app.launch(); openTools()
        app.buttons["checkEmail"].tap()
        let web = app.buttons["websiteLookup"]
        XCTAssertTrue(web.waitForExistence(timeout: 6))
        web.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10) || app.buttons["Close"].exists || app.otherElements["SafariViewService"].exists, app.debugDescription)
    }
}
