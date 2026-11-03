import XCTest
import Photos
import UIKit
import ImageIO
import UniformTypeIdentifiers

final class CleanupJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor func testProtectedCollectionsSharePersistentBin() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Cleanup QA")
        XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized)
        let bundle = Bundle(for: Self.self)
        let jpg = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "VaultMotion", withExtension: "jpg")))
        let token = UUID().uuidString
        let base = try XCTUnwrap(UIImage(data: jpg))
        func render(variant: Bool) throws -> Data {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format).image { ctx in
                base.draw(in: CGRect(x: 0, y: 0, width: 320, height: 240))
                (String(token.prefix(12)) as NSString).draw(at: CGPoint(x: 10, y: 10),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.white])
                (variant ? UIColor.orange : UIColor.yellow).setFill()
                ctx.fill(CGRect(x: 22, y: 200, width: 8, height: 8))
            }
            let data = NSMutableData()
            let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            let tags = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Screenshot"]] as CFDictionary
            CGImageDestinationAddImage(dest, try XCTUnwrap(image.cgImage), tags)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            return data as Data
        }
        let exact = try render(variant: false), other = try render(variant: true)
        let originalClip = try XCTUnwrap(bundle.url(forResource: "VaultMotion", withExtension: "mov"))
        let large = FileManager.default.temporaryDirectory.appendingPathComponent(token + ".mov")
        try FileManager.default.copyItem(at: originalClip, to: large)
        defer { try? FileManager.default.removeItem(at: large) }
        let file = try FileHandle(forWritingTo: large)
        let offset = try file.seekToEnd()
        let padding: UInt32 = 100_000_000
        var length = padding.bigEndian
        try file.write(contentsOf: withUnsafeBytes(of: &length) { Data($0) } + Data("free".utf8))
        try file.truncate(atOffset: offset + UInt64(padding))
        try file.close()

        let lib = PHPhotoLibrary.shared()
        let firstAlbum = "Protected A " + token.prefix(6), secondAlbum = "Protected B " + token.prefix(6)
        let keeperAlbum = "Keeper " + token.prefix(6)
        var ids = [String]()
        var video = ""
        try await lib.performChanges {
            let a = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: String(firstAlbum))
            let b = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: String(secondAlbum))
            let keep = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: String(keeperAlbum))
            for (index, bytes) in [exact, exact, exact, other].enumerated() {
                let req = PHAssetCreationRequest.forAsset()
                req.creationDate = Date().addingTimeInterval(Double(index))
                req.isFavorite = index == 0
                req.addResource(with: .photo, data: bytes, options: nil)
                let item = req.placeholderForCreatedAsset!
                ids.append(item.localIdentifier)
                if index == 0 { keep.addAssets([item] as NSArray) }
                if index == 1 { b.addAssets([item] as NSArray) }
                if index == 2 { a.addAssets([item] as NSArray) }
            }
            let clip = PHAssetCreationRequest.forAsset()
            clip.addResource(with: .video, fileURL: large, options: nil)
            video = clip.placeholderForCreatedAsset!.localIdentifier
        }

        let app = XCUIApplication()
        func launch() { app.terminate(); app.launch() }
        func tap(_ button: String) {
            let item = app.buttons[button]
            XCTAssertTrue(item.waitForExistence(timeout: 12), button)
            if !item.isHittable { app.swipeUp() }
            item.tap()
        }
        func protect(_ album: String) {
            launch(); tap("albums")
            app.switches[album].tap()
            if app.alerts.firstMatch.waitForExistence(timeout: 2) { app.alerts.firstMatch.buttons["Done"].tap() }
        }
        protect(String(firstAlbum))
        launch(); tap("openCleanup")
        for name in ["duplicates","screenshots","videos","recordings"] { XCTAssertTrue(app.buttons["category-" + name].waitForExistence(timeout: 6)) }
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "Storage cleanup"; home.lifetime = .keepAlways; add(home)
        tap("category-duplicates")
        let extra = app.buttons["cleanupSelect-" + ids[1]]
        XCTAssertTrue(extra.waitForExistence(timeout: 25))
        XCTAssertFalse(app.buttons["cleanupSelect-" + ids[2]].exists)
        XCTAssertFalse(app.buttons["cleanupSelect-" + ids[3]].exists)
        tap("Select extra copies")
        XCTAssertEqual(extra.label, "Deselect item")
        XCTAssertEqual(app.buttons["cleanupSelect-" + ids[0]].label, "Select item")
        tap("Clear selection")
        tap("cleanupSelect-" + ids[1])
        XCTAssertEqual(app.buttons["queueCleanup"].label, "Add to bin (1)")
        tap("queueCleanup")
        XCTAssertTrue(app.staticTexts["Added to review bin: 1"].waitForExistence(timeout: 6))
        XCTAssertFalse(extra.isEnabled)
        XCTAssertFalse(app.buttons["cleanupSelect-" + ids[0]].isEnabled)
        XCTAssertTrue(PHAsset.fetchAssets(withLocalIdentifiers: [ids[1]], options: nil).firstObject!.mediaSubtypes.contains(.photoScreenshot))
        launch(); tap("openCleanup"); tap("category-screenshots")
        XCTAssertTrue(extra.waitForExistence(timeout: 8))
        XCTAssertFalse(extra.isEnabled)
        XCTAssertFalse(app.buttons["cleanupSelect-" + ids[2]].exists)
        launch(); tap("openCleanup"); tap("category-videos")
        XCTAssertTrue(app.buttons["cleanupSelect-" + video].waitForExistence(timeout: 25))
        tap("cleanupPreview-" + video)
        XCTAssertTrue(app.navigationBars["Video preview"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.descendants(matching: .any)["clipPlayer"].firstMatch.waitForExistence(timeout: 10))
        tap("Done"); tap("cleanupSelect-" + video); tap("queueCleanup"); tap("collectionBin")
        XCTAssertTrue(app.staticTexts["0 of 2 selected"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Exact duplicates"].exists)
        XCTAssertTrue(app.staticTexts["Large videos"].exists)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids + [video], options: nil).count, 5)
        protect(String(keeperAlbum))
        launch(); tap("homeBasket"); tap("Select all"); tap("deleteSelected")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 12))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "matching copy")).firstMatch.exists)
        app.alerts.firstMatch.buttons["Done"].tap()
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids + [video], options: nil).count, 5)
        protect(String(secondAlbum))
        launch(); tap("homeBasket")
        XCTAssertTrue(app.staticTexts["0 of 1 selected"].waitForExistence(timeout: 8))
        tap("Select all"); tap("deleteSelected")
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Delete.*")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["emptyBin"].waitForExistence(timeout: 12))
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 4)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: [video], options: nil).count, 0)

    }
    @MainActor func testRecordingCollectionMatchesSystemClassification() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Cleanup QA")
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "StorageRecording", withExtension: "mp4"))
        var id = ""
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "RPReplay_Final" + String(Int(Date.now.timeIntervalSince1970)) + ".mp4"
            req.addResource(with: .video, fileURL: fixture, options: options)
            id = req.placeholderForCreatedAsset!.localIdentifier
        }
        let asset = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject)
        // Photos can import a movie carrying ReplayKit tags as a regular video.
        // A filename or an author tag alone must never classify it as a recording.
        let isRecording = asset.mediaSubtypes.contains(.videoScreenRecording)
        let app = XCUIApplication(); app.launch()
        app.buttons["openCleanup"].tap()
        app.buttons["category-recordings"].tap()
        let select = app.buttons["cleanupSelect-" + id]
        XCTAssertTrue(app.staticTexts["Screen recordings"].waitForExistence(timeout: 8))
        if !isRecording {
            XCTAssertFalse(select.exists)
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.videoScreenRecording.rawValue)
            if PHAsset.fetchAssets(with: .video, options: options).count == 0 {
                XCTAssertTrue(app.staticTexts["No matching items"].waitForExistence(timeout: 5))
            }
            return
        }
        XCTAssertTrue(select.waitForExistence(timeout: 8))
        app.buttons["Duration"].tap()
        app.buttons["cleanupPreview-" + id].tap()
        XCTAssertTrue(app.descendants(matching: .any)["clipPlayer"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        select.tap()
        app.buttons["queueCleanup"].tap()
        app.buttons["collectionBin"].tap()
        XCTAssertTrue(app.staticTexts["Screen recordings"].waitForExistence(timeout: 6))
        app.buttons["Select all"].tap(); app.buttons["restoreSelected"].tap()
        XCTAssertTrue(app.staticTexts["emptyBin"].waitForExistence(timeout: 6))
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count, 1)
    }

}
