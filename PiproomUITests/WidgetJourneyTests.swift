import XCTest

final class WidgetJourneyTests: XCTestCase {
    func testHomeScreenWidgetOpensDisplayedMonth() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Review")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Piproom"].firstMatch
        for _ in 0..<4 where !icon.isHittable { springboard.swipeLeft() }
        XCTAssertTrue(icon.isHittable)
        let widget = springboard.icons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "Piproom", "Widget")).firstMatch
        if !widget.exists {
            icon.press(forDuration: 1.2)
            let small = springboard.buttons["Small widget"]
            XCTAssertTrue(small.waitForExistence(timeout: 5))
            small.tap()
        }
        XCTAssertTrue(widget.waitForExistence(timeout: 12))
        let title = widget.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[A-Za-z]+ [0-9]{4}|Undated")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let expectedMonth = title.label
        let capture = XCTAttachment(screenshot: widget.screenshot())
        capture.name = "Monthly contact sheet"; capture.lifetime = .keepAlways
        add(capture)
        widget.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(app.staticTexts[expectedMonth].waitForExistence(timeout: 8))
    }
}
