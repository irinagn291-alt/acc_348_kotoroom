import CryptoKit
import LocalAuthentication
import Photos
import UIKit
import CoreLocation

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var unlocked = false
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published private(set) var photos: [VaultPhoto] = []
    @Published var notice: String?
    @Published private(set) var recent: [VaultPhoto] = []
    private let files = VaultFiles()
    private let shield = PrivacyShield()
    private var credentials: VaultCredentials?
    @Published private(set) var configured = false
    @Published private(set) var faceEnabled = false
    @Published private(set) var usedPIN = false
    var supportsFaceID: Bool {
        let auth = LAContext()
        return auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) && auth.biometryType == .faceID
    }
    private var key: SymmetricKey?
    private var context: LAContext?
    private var importJob: Task<Void, Never>?
    private var session = UUID()
    private var storageError: String?

    init() {
        do {
            try files.prepare()
            let credentials = try VaultCredentials(root: files.root, catalog: files.catalog)
            self.credentials = credentials
            configured = try credentials.configured
            faceEnabled = credentials.hasFaceKey
            if !configured && FileManager.default.fileExists(atPath: files.catalog.path) {
                throw VaultError("The key for this Secret Folder is unavailable. Existing files have been preserved.")
            }
        } catch { storageError = (error as? VaultError)?.errorDescription ?? "Could not open the vault folder on this iPhone." }
        shield.shouldCover = { [weak self] in self?.unlocked == true }
    }
    func lock() {
        importJob?.cancel()
        if unlocked, let workspaces = try? FileManager.default.contentsOfDirectory(at: files.scratch, includingPropertiesForKeys: nil) {
            for folder in workspaces { try? FileManager.default.removeItem(at: folder) }
        }
        session = UUID()
        context?.invalidate()
        context = nil
        key = nil
        unlocked = false
        usedPIN = false
        photos = []
        recent = []
        progress = ""
        notice = nil
    }
    private func openCollection(key secret: SymmetricKey, token: UUID, pin: Bool) throws {
        guard token == session, UIApplication.shared.applicationState != .background else { throw CancellationError() }
        if !FileManager.default.fileExists(atPath: files.catalog.path) {
            let contents = try FileManager.default.contentsOfDirectory(at: files.root, includingPropertiesForKeys: nil)
            guard !contents.contains(where: { UUID(uuidString: $0.lastPathComponent) != nil }) else {
                throw VaultError("The vault index is unavailable. Your encrypted files have been kept.")
            }
            try files.save([], key: secret)
        }
        let loaded = try files.load(key: secret)
        // Each index commit covers one complete photo. A crash before commit only leaves an orphan copy.
        let committed = Set(loaded.map(\.id))
        for folder in try FileManager.default.contentsOfDirectory(at: files.root, includingPropertiesForKeys: nil)
            where UUID(uuidString: folder.lastPathComponent) != nil && !committed.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
        photos = loaded
        key = secret
        usedPIN = pin
        faceEnabled = credentials?.hasFaceKey == true
        unlocked = true
    }

    func enter(pin: String, creating: Bool) async {
        guard !busy, !unlocked else { return }
        if let storageError { notice = storageError; return }
        guard let credentials, configured != creating else { return }
        let token = session
        busy = true
        defer { busy = false }
        do {
            let key = try await Task.detached(priority: .userInitiated) {
                try creating ? credentials.create(pin: pin) : credentials.unlock(pin: pin)
            }.value
            configured = true
            try openCollection(key: key, token: token, pin: true)
        } catch {
            if token == session { notice = (error as? VaultError)?.errorDescription ?? "Could not open your Secret Folder." }
        }
    }

    func faceID(enroll: Bool) async {
        guard !busy, let credentials, supportsFaceID, enroll ? (unlocked && usedPIN) : (!unlocked && faceEnabled) else { return }
        let token = session
        let auth = LAContext()
        auth.localizedFallbackTitle = ""
        context = auth
        busy = true
        defer { busy = false; auth.invalidate(); context = nil }
        do {
            guard try await auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: enroll ? "Enable Face ID for your Secret Folder" : "Open your Secret Folder"),
                  token == session, UIApplication.shared.applicationState != .background else { return }
            if enroll, let key {
                try credentials.registerFaceID(key, context: auth)
                faceEnabled = true
            } else {
                try openCollection(key: credentials.unlockFaceID(context: auth), token: token, pin: false)
            }
        } catch {
            guard token == session else { return }
            faceEnabled = credentials.hasFaceKey
            let e = error as NSError
            if e.domain != LAError.errorDomain || ![LAError.userCancel.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue].contains(e.code) {
                notice = (error as? VaultError)?.errorDescription ?? "Face ID could not verify you. Use your Secret Folder PIN."
            }
        }
    }

    func turnOffFaceID() {
        guard unlocked, !busy, usedPIN, let credentials else { return }
        do { try credentials.disableFaceID(); faceEnabled = false }
        catch { notice = "Face ID could not be disabled." }
    }
    func check(_ token: UUID) throws {
        guard token == session, unlocked else { throw CancellationError() }
    }
    func startImport(_ assets: [PHAsset]) {
        guard unlocked, !busy, importJob == nil else { return }
        importJob = Task {
            defer { importJob = nil }
            await importPhotos(assets)
        }
    }
    private func importPhotos(_ assets: [PHAsset]) async {
        guard let key, !busy, !assets.isEmpty else { return }
        let token = session
        busy = true
        recent = []
        defer { busy = false }
        var verified: [VaultPhoto] = []
        var failures = 0
        var lastError = ""
        for (index, asset) in assets.enumerated() {
            guard token == session else { return }
            progress = "Verifying copy \(index + 1) of \(assets.count)…"
            do {
                if let existing = photos.first(where: { $0.sourceID == asset.localIdentifier && $0.modification == asset.modificationDate }) {
                    try await files.verify(existing, against: asset, key: key)
                    verified.append(existing)
                } else {
                    let photo = try await files.archive(asset, key: key)
                    do {
                        try check(token)
                        let updated = [photo] + photos
                        try files.save(updated, key: key)
                        photos = updated
                    } catch { try? FileManager.default.removeItem(at: files.folder(photo.id)); throw error }
                    verified.append(photo)
                }
            } catch { failures += 1; lastError = (error as? VaultError)?.errorDescription ?? "Check Photos access and available storage." }
        }
        guard token == session else { return }
        recent = verified
        progress = ""
        if failures > 0 { notice = "Verified \(verified.count) of \(assets.count). Your originals are still in Photos. " + lastError }
    }
    func dismissReceipt() { recent = [] }

    private func original(_ photo: VaultPhoto) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photo.sourceID], options: nil).firstObject,
              asset.modificationDate == photo.modification, asset.canPerform(.delete) else {
            throw VaultError("An original changed or is unavailable. Deletion was canceled.")
        }
        return asset
    }
    func deleteOriginals(_ copies: [VaultPhoto], library: Library) async {
        guard let key, !busy, !copies.isEmpty else { return }
        let token = session
        busy = true
        defer { busy = false; progress = "" }
        do {
            let committed = Dictionary(uniqueKeysWithValues: try files.load(key: key).map { ($0.id, $0) })
            for (i, photo) in copies.enumerated() {
                try check(token)
                progress = "Checking original \(i + 1) of \(copies.count)…"
                guard committed[photo.id] == photo else { throw VaultError("The verified copy is missing from the vault.") }
                try await files.verify(photo, against: original(photo), key: key)
            }
            try check(token)
            try await library.checkVaultDeletion(Set(copies.map(\.sourceID)))
            try check(token)
            let originals = try copies.map(original)
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(originals as NSArray) }
            if token == session { recent = []; notice = "Originals removed from Photos. Verified copies remain in your vault." }
        } catch {
            guard token == session else { return }
            let ns = error as NSError
            if ns.domain != PHPhotosErrorDomain || ns.code != PHPhotosError.Code.userCancelled.rawValue {
                notice = (error as? VaultError)?.errorDescription ?? "Could not delete the originals. Check Photos access and try again."
            }
        }
    }

    func export(_ photo: VaultPhoto) async {
        guard let key, !busy, photos.contains(photo) else { return }
        let token = session
        busy = true
        progress = "Restoring to Photos…"
        defer { busy = false; progress = "" }
        do {
            let allowed = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized ? PHAuthorizationStatus.authorized : await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard allowed == .authorized || allowed == .limited else { throw VaultError("Allow photo additions in iPhone Settings.") }
            try check(token)
            let work = try files.workFolder()
            defer { try? FileManager.default.removeItem(at: work) }
            let files = self.files
            let resources = try await Task.detached(priority: .userInitiated) {
                try files.exportFiles(photo, to: work, key: key)
            }.value
            try check(token)
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = photo.date
                request.isFavorite = photo.favorite
                if let lat = photo.latitude, let lon = photo.longitude { request.location = CLLocation(latitude: lat, longitude: lon) }
                for (type, resource, url) in resources {
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = resource.filename
                    options.uniformTypeIdentifier = resource.uti
                    request.addResource(with: type, fileURL: url, options: options)
                }
            }
            if token == session { notice = "Saved to Photos. Your vault copy stays here." }
        } catch {
            if token == session { notice = "Could not restore to Photos. Your vault copy is safe. " + ((error as? VaultError)?.errorDescription ?? "Check Photos access and available storage.") }
        }
    }
    func eraseCopy(_ photo: VaultPhoto) {
        guard unlocked, !busy, let key, photos.contains(photo) else { return }
        do {
            let updated = photos.filter { $0.id != photo.id }
            try files.save(updated, key: key)
            photos = updated
            recent.removeAll { $0.id == photo.id }
            try FileManager.default.removeItem(at: files.folder(photo.id))
        } catch { notice = "Could not finish removing the vault copy." }
    }
    func motion(_ photo: VaultPhoto) async throws -> VaultMotion {
        guard let key, photo.live, !busy else { throw CancellationError() }
        let token = session
        let files = self.files
        let folder = try files.workFolder()
        do {
            let resources = try await Task.detached(priority: .userInitiated) {
                try files.exportFiles(photo, to: folder, key: key)
            }.value
            try check(token)
            let preferred: (PHAssetResourceType, PHAssetResourceType)
            if resources.contains(where: { $0.0 == .fullSizePhoto }) && resources.contains(where: { $0.0 == .fullSizePairedVideo }) {
                preferred = (.fullSizePhoto, .fullSizePairedVideo)
            } else { preferred = (.photo, .pairedVideo) }
            guard let still = resources.first(where: { $0.0 == preferred.0 }),
                  let video = resources.first(where: { $0.0 == preferred.1 }) else { throw VaultError("The Live Photo pair is missing.") }
            let live: PHLivePhoto = try await withCheckedThrowingContinuation { c in
                PHLivePhoto.request(withResourceFileURLs: [still.2, video.2], placeholderImage: nil, targetSize: .zero,
                                    contentMode: .aspectFit) { live, info in
                    guard info[PHLivePhotoInfoIsDegradedKey] as? Bool != true else { return }
                    if let live { c.resume(returning: live) }
                    else { c.resume(throwing: VaultError("Could not play this Live Photo.")) }
                }
            }
            try check(token)
            try Task.checkCancellation()
            return VaultMotion(photo: live, folder: folder)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    func thumbnail(_ photo: VaultPhoto) async -> UIImage? {
        guard let key else { return nil }
        let token = session
        let files = self.files
        let result = await Task.detached(priority: .userInitiated) {
            try? files.open(files.folder(photo.id).appendingPathComponent("preview"), key: key, identity: photo.id)
        }.value
        guard token == session, let result else { return nil }
        return UIImage(data: result)
    }
}
