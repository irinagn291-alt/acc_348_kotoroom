import CryptoKit
import Foundation
import Photos

enum CleanupKind: String, Codable, CaseIterable, Identifiable {
    case duplicates, screenshots, videos, recordings
    var id: Self { self }
    var title: String {
        switch self {
        case .duplicates: "Exact duplicates"
        case .screenshots: "Screenshots"
        case .videos: "Large videos"
        case .recordings: "Screen recordings"
        }
    }
    var icon: String {
        switch self {
        case .duplicates: "square.on.square"
        case .screenshots: "viewfinder"
        case .videos: "film.stack"
        case .recordings: "record.circle"
        }
    }
    var caption: String {
        switch self {
        case .duplicates: "Verified copies, including Live Photo motion"
        case .screenshots: "Screen captures, arranged by month"
        case .videos: "100 MB or larger, biggest first"
        case .recordings: "Recordings made on your screen"
        }
    }
    static func isScreenshot(_ type: PHAssetMediaType, _ subtypes: PHAssetMediaSubtype) -> Bool {
        type == .image && subtypes.contains(.photoScreenshot)
    }
    static func isRecording(_ type: PHAssetMediaType, _ subtypes: PHAssetMediaSubtype) -> Bool {
        type == .video && subtypes.contains(.videoScreenRecording)
    }
}

struct CleanupResult {
    var sets = [String: [String]]()
    var signatures = [String: String]()
    var videoBytes = [String: Int64]()
    var unverified = Set<String>()
    var unknownSizes = Set<String>()
    var checked = 0
    var total = 0
}

struct DuplicateProof: Codable {
    let signature: String
    let keeperID: String
}

enum CleanupError: LocalizedError {
    case unavailable, survivorChanged
    var errorDescription: String? {
        switch self {
        case .unavailable: "An original could not be checked. Open it in Photos and try again."
        case .survivorChanged: "The matching copy to keep has changed or is unavailable. Keep the items in Photos and check the duplicate set again."
        }
    }
}

actor CleanupScanner {
    static let largeVideoBytes: Int64 = 100_000_000

    private struct Bucket: Hashable {
        let type, width, height: Int
        let live: Bool
        init(_ asset: PHAsset) {
            type = asset.mediaType.rawValue
            width = asset.pixelWidth
            height = asset.pixelHeight
            live = asset.mediaSubtypes.contains(.photoLive)
        }
    }
    private struct Cached {
        let modified: Date
        let bytes: Int64
        let signature: String?
    }
    private var cache = [String: Cached]()

    func scan(_ assets: [PHAsset], cloudID: String?, publish: @Sendable (CleanupResult) async -> Void) async throws {
        let visible = Set(assets.map(\.localIdentifier))
        cache = cache.filter { visible.contains($0.key) }
        let buckets = Dictionary(grouping: assets, by: Bucket.init)
        var result = CleanupResult()
        var firstMatch = [String: String]()
        result.total = assets.count
        await publish(result)
        var lastUpdate = Date.now
        var candidates = Set<String>()
        // Distinct known byte totals already rule out a match. If any size is missing,
        // keep the entire geometry bucket eligible to avoid overlooking an iCloud copy.
        for group in buckets.values {
            try Task.checkCancellation()
            var sizes = [Int64: [String]]()
            var unknown = false
            for item in group where group.count > 1 || item.mediaType == .video {
                try Task.checkCancellation()
                if let bytes = Self.metadataSize(item) {
                    sizes[bytes, default: []].append(item.localIdentifier)
                    if item.mediaType == .video { result.videoBytes[item.localIdentifier] = bytes }
                } else { unknown = true }
            }
            if group.count > 1 {
                if unknown { candidates.formUnion(group.map(\.localIdentifier)) }
                else { for ids in sizes.values where ids.count > 1 { candidates.formUnion(ids) } }
            }
            if Date.now.timeIntervalSince(lastUpdate) >= 0.35 { await publish(result); lastUpdate = .now }
        }
        await publish(result)
        for asset in assets {
            try Task.checkCancellation()
            let id = asset.localIdentifier
            let hash = candidates.contains(id)
            if (asset.mediaType == .video && result.videoBytes[id] == nil) || hash {
                do {
                    let info: (signature: String?, bytes: Int64)
                    if let hit = cache[id], let date = asset.modificationDate, hit.modified == date,
                       !hash || hit.signature != nil {
                        info = (hit.signature, hit.bytes)
                    } else {
                        info = try await Self.inspect(asset, hash: hash, cloud: cloudID == id)
                        try Task.checkCancellation()
                        if let date = asset.modificationDate {
                            cache[id] = Cached(modified: date, bytes: info.bytes, signature: info.signature)
                        }
                    }
                    if asset.mediaType == .video { result.videoBytes[id] = info.bytes }
                    if let signature = info.signature {
                        result.signatures[id] = signature
                        if let first = firstMatch[signature] {
                            result.sets[signature, default: [first]].append(id)
                        } else { firstMatch[signature] = id }
                    }
                } catch {
                    try Task.checkCancellation()
                    if hash { result.unverified.insert(id) }
                    if asset.mediaType == .video {
                        if let bytes = Self.metadataSize(asset) { result.videoBytes[id] = bytes }
                        else { result.unknownSizes.insert(id) }
                    }
                }
            }
            result.checked += 1
            if Date.now.timeIntervalSince(lastUpdate) >= 0.35 {
                await publish(result); lastUpdate = .now
            }
        }
        try Task.checkCancellation()
        await publish(result)
    }

    private static func metadataSize(_ asset: PHAsset) -> Int64? {
        guard #available(iOS 27, *) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        let sizes = resources.compactMap(\.dataSize)
        guard !resources.isEmpty, sizes.count == resources.count, sizes.allSatisfy({ $0 > 0 }) else { return nil }
        return sizes.reduce(Int64(0)) { $0 + Int64($1) }
    }

    // Hash each resource separately. Resource roles, types and multiplicity form part of the identity.
    static func inspect(_ asset: PHAsset, hash: Bool, cloud: Bool) async throws -> (signature: String?, bytes: Int64) {
        if !hash, let bytes = metadataSize(asset) { return (nil, bytes) }
        let resources = PHAssetResource.assetResources(for: asset)
        let roles = Set(resources.map(\.type))
        guard roles.contains(asset.mediaType == .video ? .video : .photo),
              !roles.contains(.photoProxy),
              !roles.contains(.adjustmentData) || roles.contains(asset.mediaType == .video ? .fullSizeVideo : .fullSizePhoto),
              !asset.mediaSubtypes.contains(.photoLive) || !roles.contains(.adjustmentData) || roles.contains(.fullSizePairedVideo),
              !asset.mediaSubtypes.contains(.photoLive) || roles.contains(.pairedVideo) else { throw CleanupError.unavailable }
        var parts = [String]()
        var size: Int64 = 0
        for resource in resources {
            try Task.checkCancellation()
            let stream = ContentRead()
            let result = try await stream.read(resource, hash: hash, cloud: cloud)
            guard result.bytes > 0 else { throw CleanupError.unavailable }
            size += result.bytes
            if hash { parts.append("\(resource.type.rawValue):\(resource.uniformTypeIdentifier):\(result.bytes):\(result.digest)") }
        }
        return (hash ? "\(asset.mediaType.rawValue)/" + parts.sorted().joined(separator: "/") : nil, size)
    }
}

private final class ContentRead: @unchecked Sendable {
    private let lock = NSLock()
    private var request: PHAssetResourceDataRequestID?
    private var cancelled = false

    func read(_ resource: PHAssetResource, hash: Bool, cloud: Bool) async throws -> (digest: String, bytes: Int64) {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { c in
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = cloud
                var hasher = SHA256()
                var bytes: Int64 = 0
                let id = PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
                    bytes += Int64(data.count)
                    if hash { hasher.update(data: data) }
                } completionHandler: { error in
                    if let error { c.resume(throwing: error) }
                    else { c.resume(returning: (hash ? Data(hasher.finalize()).base64EncodedString() : "", bytes)) }
                }
                lock.lock()
                request = id
                let cancelNow = cancelled
                lock.unlock()
                if cancelNow { PHAssetResourceManager.default().cancelDataRequest(id) }
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let id = self.request
            self.lock.unlock()
            if let id { PHAssetResourceManager.default().cancelDataRequest(id) }
        }
    }
}
