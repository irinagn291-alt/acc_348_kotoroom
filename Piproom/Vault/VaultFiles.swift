import CryptoKit
import UniformTypeIdentifiers
import AVFoundation
import Photos
import UIKit
import ImageIO

struct VaultError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct VaultResource: Codable, Equatable {
    let id: String
    let type: Int
    let filename: String
    let uti: String
    let integrity: ArchiveIntegrity
}

struct VaultPhoto: Codable, Identifiable, Equatable {
    let id: String
    let sourceID: String
    let modification: Date?
    let date: Date?
    let live: Bool
    let favorite: Bool
    let latitude: Double?
    let longitude: Double?
    let resources: [VaultResource]
}

struct VaultFiles {
    let root: URL
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PrivateVault", isDirectory: true)) {
        self.root = root
    }
    var scratch: URL { root.appendingPathComponent("Work", isDirectory: true) }
    var catalog: URL { root.appendingPathComponent("collection.sealed") }

    func prepare() throws {
        try makeFolder(root)
        var folder = root
        var options = URLResourceValues()
        options.isExcludedFromBackup = true
        try folder.setResourceValues(options)
        if FileManager.default.fileExists(atPath: scratch.path) { try FileManager.default.removeItem(at: scratch) }
        try makeFolder(scratch)
    }
    func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
    }
    func workFolder() throws -> URL {
        let url = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try makeFolder(url)
        return url
    }
    func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func save(_ photos: [VaultPhoto], key: SymmetricKey) throws {
        let encoded = try JSONEncoder().encode(photos)
        try seal(encoded, at: catalog, key: key, identity: "collection.v1")
    }
    func load(key: SymmetricKey) throws -> [VaultPhoto] {
        try JSONDecoder().decode([VaultPhoto].self, from: open(catalog, key: key, identity: "collection.v1"))
    }
    func seal(_ data: Data, at url: URL, key: SymmetricKey, identity: String) throws {
        let box = try AES.GCM.seal(data, using: key, authenticating: Data(identity.utf8))
        guard let bytes = box.combined else { throw VaultError("Could not encrypt the data.") }
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
    }
    func open(_ url: URL, key: SymmetricKey, identity: String) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        return try AES.GCM.open(box, using: key, authenticating: Data(identity.utf8))
    }

    private func requireSpace(for bytes: Int64) throws {
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let available, available < bytes + 2_097_152 {
            throw VaultError("There isn’t enough space to make a verified copy. Free up space on this iPhone and try again.")
        }
    }

    // Work from the original PhotoKit resources, including both halves of a Live Photo.
    func archive(_ asset: PHAsset, key: SymmetricKey) async throws -> VaultPhoto {
        let resources = PHAssetResource.assetResources(for: asset)
        let live = asset.mediaSubtypes.contains(.photoLive)
        guard asset.mediaType == .image, resources.contains(where: { $0.type == .photo }),
              !live || resources.contains(where: { $0.type == .pairedVideo }),
              PHAssetCreationRequest.supportsAssetResourceTypes(resources.map { NSNumber(value: $0.type.rawValue) }) else {
            throw VaultError("The complete set needed for export is unavailable. The original is still in Photos.")
        }
        let stills = resources.filter { $0.type == .photo }
        let videos = resources.filter { $0.type == .pairedVideo }
        guard stills.count == 1, videos.count == (live ? 1 : 0),
              resources.count == stills.count + videos.count,
              let kind = UTType(stills[0].uniformTypeIdentifier),
              [UTType.jpeg, .png, .heic, .heif].contains(where: { kind.conforms(to: $0) }) else {
            throw VaultError("Choose an unedited JPEG, HEIC, PNG or Live Photo. This format stays in Photos.")
        }
        if #available(iOS 27, *) {
            let sizes = resources.compactMap { $0.dataSize.map { Int64($0) } }
            if sizes.count == resources.count {
                try requireSpace(for: sizes.reduce(0, +) + (sizes.max() ?? 0))
            }
        }
        let work = try workFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let id = UUID().uuidString
        let destination = folder(id)
        try makeFolder(destination)
        do {
            var saved: [VaultResource] = []
            for resource in resources {
                try Task.checkCancellation()
                let resourceID = UUID().uuidString
                let raw = work.appendingPathComponent(resourceID).appendingPathExtension(URL(fileURLWithPath: resource.originalFilename).pathExtension)
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: raw, options: options)
                try Task.checkCancellation()
                let sourceSize = try raw.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try requireSpace(for: Int64(sourceSize))
                let url = destination.appendingPathComponent(resourceID)
                let integrity = try EncryptedArchive.encrypt(input: raw, output: url, key: key, identity: resourceID)
                guard integrity.bytes > 0 else { throw VaultError("One original is empty.") }
                try EncryptedArchive.decrypt(input: url, output: nil, key: key, identity: resourceID, expected: integrity)
                saved.append(VaultResource(id: resourceID, type: resource.type.rawValue,
                                           filename: resource.originalFilename, uti: resource.uniformTypeIdentifier, integrity: integrity))
                if resource.type == .photo {
                    guard let source = CGImageSourceCreateWithURL(raw as CFURL, nil) else {
                        throw VaultError("The still image could not be opened.")
                    }
                    let attributes = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 1100] as CFDictionary
                    if let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, attributes),
                       let jpeg = UIImage(cgImage: preview).jpegData(compressionQuality: 0.84) {
                        try seal(jpeg, at: destination.appendingPathComponent("preview"), key: key, identity: id)
                    } else { throw VaultError("The still image could not be decoded.") }
                } else if resource.type == .pairedVideo {
                    let movie = AVURLAsset(url: raw)
                    guard try await movie.load(.isPlayable), !(try await movie.loadTracks(withMediaType: .video)).isEmpty else {
                        throw VaultError("The Live Photo motion could not be opened.")
                    }
                }
                try FileManager.default.removeItem(at: raw)
            }
            return VaultPhoto(id: id, sourceID: asset.localIdentifier, modification: asset.modificationDate,
                              date: asset.creationDate, live: live, favorite: asset.isFavorite,
                              latitude: asset.location?.coordinate.latitude, longitude: asset.location?.coordinate.longitude,
                              resources: saved)
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }

    func verify(_ photo: VaultPhoto, against asset: PHAsset, key: SymmetricKey) async throws {
        let resources = PHAssetResource.assetResources(for: asset)
        var expected = photo.resources
        for resource in resources {
            try Task.checkCancellation()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            let digest = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                var hash = SHA256()
                PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                    hash.update(data: data)
                } completionHandler: { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: hash.finalize().map { String(format: "%02x", $0) }.joined()) }
                }
            }
            guard let i = expected.firstIndex(where: { $0.type == resource.type.rawValue && $0.integrity.sha256 == digest }) else {
                throw VaultError("The original changed. Import its new version first.")
            }
            let copy = expected.remove(at: i)
            try EncryptedArchive.decrypt(input: folder(photo.id).appendingPathComponent(copy.id), output: nil,
                                         key: key, identity: copy.id, expected: copy.integrity)
        }
        guard expected.isEmpty else { throw VaultError("The original resources changed. Deletion was canceled.") }
    }

    func exportFiles(_ photo: VaultPhoto, to work: URL, key: SymmetricKey) throws -> [(PHAssetResourceType, VaultResource, URL)] {
        try requireSpace(for: photo.resources.reduce(0) { $0 + $1.integrity.bytes })
        return try photo.resources.map { resource in
            try Task.checkCancellation()
            guard let type = PHAssetResourceType(rawValue: resource.type) else { throw VaultError("Unrecognized resource format.") }
            let ext = URL(fileURLWithPath: resource.filename).pathExtension
            let url = work.appendingPathComponent(resource.id).appendingPathExtension(ext)
            try EncryptedArchive.decrypt(input: folder(photo.id).appendingPathComponent(resource.id), output: url,
                                         key: key, identity: resource.id, expected: resource.integrity)
            return (type, resource, url)
        }
    }
}
