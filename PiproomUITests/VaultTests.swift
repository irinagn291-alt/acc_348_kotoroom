import XCTest
import Photos
import CryptoKit
import LocalAuthentication

final class VaultTests: XCTestCase {
    private let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false }

    // Runs only on the disposable QA simulator. Both records belong to this test run.
    @MainActor func testVaultRoundTrip() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Vault QA")
        XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .readWrite), .authorized)
        let leftover = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Don’t Allow|Cancel|Отмена|Не разрешать")).firstMatch
        if leftover.exists { leftover.tap() }
        let bundle = Bundle(for: Self.self)
        let image = try XCTUnwrap(bundle.url(forResource: "VaultMotion", withExtension: "jpg"))
        let video = try XCTUnwrap(bundle.url(forResource: "VaultMotion", withExtension: "mov"))
        let prefix = UUID().uuidString
        let date = Date(timeIntervalSince1970: 2_410_000_000)
        let albumName = "Protected " + prefix.prefix(6)
        var ids: [String] = []
        try await PHPhotoLibrary.shared().performChanges {
            let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: String(albumName))
            for live in [false, true] {
                let req = PHAssetCreationRequest.forAsset()
                req.creationDate = date.addingTimeInterval(live ? 1 : 0)
                let name = PHAssetResourceCreationOptions()
                name.originalFilename = prefix + (live ? "-live.jpg" : "-photo.jpg")
                req.addResource(with: .photo, fileURL: image, options: name)
                if live {
                    let paired = PHAssetResourceCreationOptions()
                    paired.originalFilename = prefix + ".mov"
                    req.addResource(with: .pairedVideo, fileURL: video, options: paired)
                }
                let placeholder = req.placeholderForCreatedAsset!
                ids.append(placeholder.localIdentifier)
                if !live { album.addAssets([placeholder] as NSArray) }
            }
        }
        let original = try XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [ids[1]], options: nil).firstObject)
        XCTAssertTrue(original.mediaSubtypes.contains(.photoLive))
        let expectedMotion = try await fingerprints(original)
        let expectedPhoto = try await fingerprints(XCTUnwrap(PHAsset.fetchAssets(withLocalIdentifiers: [ids[0]], options: nil).firstObject))

        app = XCUIApplication()
        app.launch()
        let albums = app.buttons["albums"]
        if !albums.isHittable { app.swipeUp() }
        albums.tap()
        app.switches[String(albumName)].tap()
        app.terminate(); app.launch()
        openVault()
        XCTAssertFalse(app.buttons["addToVault"].exists)
        try enterPIN()

        app.buttons["addToVault"].tap()
        for id in ids {
            let choice = app.buttons["pick-" + id]
            XCTAssertTrue(choice.waitForExistence(timeout: 10))
            choice.tap()
        }
        app.buttons["importVaultSelection"].tap()
        XCTAssertTrue(app.buttons["deleteVaultOriginals"].waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 2)
        XCTAssertEqual(app.buttons["deleteVaultOriginals"].label, "Remove originals from Photos (1)")
        app.buttons["deleteVaultOriginals"].tap()
        let confirm = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Delete.*|Удалить.*")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), system.debugDescription)
        let cancel = system.alerts.buttons.matching(NSPredicate(format: "label MATCHES[c] %@", "Don’t Allow|Cancel|Не разрешать|Отмена")).firstMatch
        cancel.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 2)
        app.buttons["deleteVaultOriginals"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        if !confirm.waitForNonExistence(timeout: 3) { confirm.tap() }
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10), app.debugDescription + system.debugDescription)
        app.buttons["Done"].tap()
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count, 1)
        XCTAssertNotNil(PHAsset.fetchAssets(withLocalIdentifiers: [ids[0]], options: nil).firstObject)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.secureTextFields["vaultPIN"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["addToVault"].exists)
        app.terminate()
        app.launch()
        openVault()
        submit("111111")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 6))
        app.alerts.firstMatch.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["addToVault"].exists)
        try enterPIN()
        for (type, live) in [("vaultLiveTile", true), ("vaultPhotoTile", false)] {
            // New copies appear first in the vault.
            app.buttons.matching(identifier: type).firstMatch.tap()
            if live {
                app.buttons["playVaultMotion"].tap()
                XCTAssertTrue(app.descendants(matching: .any)["vaultMotionPlayer"].waitForExistence(timeout: 8))
            }
            app.buttons["exportVaultPhoto"].tap()
            let done = app.buttons["Done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.staticTexts["Saved to Photos. Your vault copy stays here."].exists)
            done.tap()
            let fetch = PHFetchOptions()
            fetch.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", date as NSDate, date.addingTimeInterval(2) as NSDate)
            let result = PHAsset.fetchAssets(with: .image, options: fetch)
            var restored: PHAsset?
            result.enumerateObjects { asset, _, _ in
                if !ids.contains(asset.localIdentifier), PHAssetResource.assetResources(for: asset).contains(where: {
                    $0.originalFilename == prefix + (live ? "-live.jpg" : "-photo.jpg")
                }) { restored = asset }
            }
            let asset = try XCTUnwrap(restored)
            let actual = try await fingerprints(asset)
            XCTAssertEqual(actual, live ? expectedMotion : expectedPhoto)
            if live {
                XCTAssertTrue(asset.mediaSubtypes.contains(.photoLive))
                let motion: PHLivePhoto? = await withCheckedContinuation { c in
                    let opts = PHLivePhotoRequestOptions()
                    opts.deliveryMode = .highQualityFormat
                    PHImageManager.default().requestLivePhoto(for: asset, targetSize: CGSize(width: 160, height: 160),
                        contentMode: .aspectFit, options: opts) { photo, info in
                        if info?[PHLivePhotoInfoIsDegradedKey] as? Bool != true { c.resume(returning: photo) }
                    }
                }
                XCTAssertNotNil(motion)
            }
            app.buttons["All photos"].tap()
            XCTAssertTrue(app.buttons.matching(identifier: type).firstMatch.exists)
        }
    }

    private func openVault() {
        let button = app.buttons["openVault"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        if !button.isHittable { app.swipeUp() }
        button.tap()
        XCTAssertTrue(app.secureTextFields["vaultPIN"].waitForExistence(timeout: 8))
    }
    private func submit(_ pin: String) {
        let field = app.secureTextFields["vaultPIN"]
        field.tap(); field.typeText(pin)
        app.buttons["submitVaultPIN"].tap()
    }
    private func enterPIN() throws {
        if app.buttons["submitVaultPIN"].label == "Continue" { submit("628419") }
        submit("628419")
        XCTAssertTrue(app.buttons["addToVault"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testFaceIDAndPINFallback() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == "Piproom Vault QA")
        app = XCUIApplication(); app.launch(); openVault(); try enterPIN()
        let configure = app.buttons["configureFace"]
        XCTAssertTrue(configure.waitForExistence(timeout: 6), "Enroll Face ID on the dedicated simulator before running this test.")
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 0.8, repeating: 0.4)
        timer.setEventHandler { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("com.apple.BiometricKit_Sim.pearl.match" as CFString), nil, nil, true) }
        timer.resume()
        defer { timer.cancel() }
        if configure.label == "Enable Face ID" {
            configure.tap()
            let allow = system.alerts.buttons.matching(NSPredicate(format:"label MATCHES[c] %@", "Allow|OK")).firstMatch
            if allow.waitForExistence(timeout: 2) { allow.tap() }
            let local = app.alerts.buttons.matching(NSPredicate(format:"label MATCHES[c] %@", "Allow|OK")).firstMatch
            if local.exists { local.tap() }
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Turn off Face ID"), object: configure)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed, app.debugDescription)
        }
        let attached = XCTAttachment(screenshot: app.screenshot())
        attached.name = "Secret Folder collection"; attached.lifetime = .keepAlways; add(attached)
        app.buttons["lockVault"].tap()
        XCTAssertTrue(app.buttons["unlockVault"].waitForExistence(timeout: 8), app.debugDescription)
        let cover = XCTAttachment(screenshot: app.screenshot())
        cover.name = "Secret Folder locked"; cover.lifetime = .keepAlways; add(cover)
        app.buttons["unlockVault"].tap()
        XCTAssertTrue(app.buttons["addToVault"].waitForExistence(timeout: 8))
        app.buttons["lockVault"].tap()
        try enterPIN()
    }

    private func fingerprints(_ asset: PHAsset) async throws -> [String] {
        var result: [String] = []
        for resource in PHAssetResource.assetResources(for: asset) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: nil)
            let hash = SHA256.hash(data: try Data(contentsOf: url))
            result.append("\(resource.type.rawValue)-\(Data(hash).base64EncodedString())")
        }
        return result.sorted()
    }
}
