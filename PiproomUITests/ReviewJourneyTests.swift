import XCTest
import Photos
import UIKit

final class ReviewJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFirstLaunchRequestsAccessFromMonthPicker() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Review")
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .photos)
        app.launch()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(app.buttons["featured"].waitForExistence(timeout: 8))
        XCTAssertFalse(system.alerts.firstMatch.exists)
        tap("featured", in: app)
        let fullAccess = system.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", ".*Full Access.*|Allow Access to All Photos")).firstMatch
        XCTAssertTrue(fullAccess.waitForExistence(timeout: 8), system.debugDescription)
        fullAccess.tap()
        XCTAssertTrue(app.staticTexts["Months"].waitForExistence(timeout: 12), app.debugDescription)
    }

    func testReviewJourneyWithPhotos() throws {
        // This integration test edits only fixtures on the named disposable simulator.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Review")
        XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized)
        let library = PHPhotoLibrary.shared()
        let suffix = String(UUID().uuidString.prefix(6))
        let albumTitle = "Family " + suffix
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let last = PHAsset.fetchAssets(with: .image, options: options).firstObject?.creationDate ?? Date()
        let year = max(2030, cal.component(.year, from: last) + 1)
        var ids = [String]()
        try library.performChangesAndWait {
            let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
            for day in 1...4 {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 420)).image { ctx in
                    [UIColor.systemPink, .systemIndigo, .systemMint, .systemOrange][day-1].setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 420))
                    ("Piproom / \(day)" as NSString).draw(at: CGPoint(x: 30, y: 190), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 32)])
                }
                let photo = PHAssetChangeRequest.creationRequestForAsset(from: image)
                photo.creationDate = cal.date(from: .init(year: year, month: 8, day: day, hour: 12))
                let placeholder = photo.placeholderForCreatedAsset!
                ids.append(placeholder.localIdentifier)
                if day == 4 { album.addAssets([placeholder] as NSArray) }
            }
        }
        let app = XCUIApplication()
        app.launch()
        tap("roll", in: app)
        XCTAssertTrue(app.buttons["startRolled"].waitForExistence(timeout: 10))
        app.buttons["startRolled"].tap()
        XCTAssertTrue(app.buttons["photoCard"].waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        tap("months", in: app)
        tap("month-\(year)-8", in: app)
        let card = app.buttons["photoCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        card.swipeRight()
        expect("1 / 4", app.staticTexts["progress"])
        tap("undo", in: app)
        expect("0 / 4", app.staticTexts["progress"])
        card.swipeLeft() // day 4: later protected
        expect("1 / 4", app.staticTexts["progress"])
        tap("queue", in: app) // day 3: later restored
        tap("queue", in: app) // day 2: the only final deletion
        app.terminate(); app.launch()
        tap("reminders", in: app)
        let toggle = app.switches["reminderToggle"]
        if toggle.value as? String != "1" {
            toggle.tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
        }
        XCTAssertTrue(app.descendants(matching: .any)["scheduledReminder"].firstMatch.waitForExistence(timeout: 8))
        // Same deep link used by the widget, Handoff and local notifications.
        app.open(URL(string: "piproom://month/\(year)/8")!)
        expect("3 / 4", app.staticTexts["progress"])
        tap("keep", in: app)
        XCTAssertTrue(app.staticTexts["monthDone"].waitForExistence(timeout: 6))
        app.terminate(); app.launch()
        tap("reminders", in: app)
        XCTAssertTrue(app.staticTexts["A reminder will be set when you leave a month unfinished."].waitForExistence(timeout: 6))
        app.switches["reminderToggle"].tap()
        app.terminate(); app.launch()
        tap("albums", in: app)
        app.switches[albumTitle].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 4) { app.alerts.firstMatch.buttons.firstMatch.tap() }
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 4)
        app.terminate(); app.launch()
        tap("homeBasket", in: app)
        expect("0 of 2 selected", app.staticTexts["binCount"])
        app.buttons.matching(identifier: "previewBinPhoto").firstMatch.tap()
        tap("Done", in: app)
        app.buttons.matching(identifier: "selectBinPhoto").firstMatch.tap()
        tap("restoreSelected", in: app)
        expect("0 of 1 selected", app.staticTexts["binCount"])
        app.buttons.matching(identifier: "selectBinPhoto").firstMatch.tap()
        tap("deleteSelected", in: app)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = system.buttons.matching(NSPredicate(format:"label MATCHES[c] %@", "Cancel|Don’t Allow")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        cancel.tap()
        expect("1 of 1 selected", app.staticTexts["binCount"])
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 4)
        tap("deleteSelected", in: app)
        let confirm = system.buttons.matching(NSPredicate(format:"label MATCHES[c] %@", "Delete.*")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["emptyBin"].waitForExistence(timeout: 10))
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 3)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: [ids[1]], options: nil).count, 0)
    }
    private func tap(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 8), identifier + " " + app.debugDescription, file: file, line: line)
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }
    private func expect(_ label: String, _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 8), .completed, file: file, line: line)
    }
}
