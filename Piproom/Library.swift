import SwiftUI
import Photos

struct PhotoMonth: Hashable, Comparable, Codable {
    let year: Int
    let month: Int
    init(_ date: Date?, calendar: Calendar) {
        let parts = date.map { calendar.dateComponents([.year, .month], from: $0) }
        year = parts?.year ?? 0
        month = parts?.month ?? 0
    }
    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
    static let names = ["Undated", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    var name: String { Self.names[month] }
    var title: String { year == 0 ? name : "\(name) \(year)" }
}

enum Choice: String, Codable { case keep, basket }
private struct Mark: Codable {
    let choice: Choice
    let sequence: Int?
    var source: CleanupKind? = nil
    var proof: DuplicateProof? = nil
}
private struct Journal: Codable {
    var marks: [String: Mark] = [:]
    var sequence = 0
    var lastMonth: PhotoMonth?
    var lastSwipeMonth: PhotoMonth?
    var lastSwipeAt: Date?
    var protectedAlbums: Set<String> = []
}

struct Album: Identifiable {
    let id: String
    let title: String
}

private struct Shelf {
    var albums: [Album] = []
    var excluded: Set<String> = []
    var byID: [String: PHAsset] = [:]
    var groups: [PhotoMonth: [PHAsset]] = [:]
    var screenshots = [PHAsset]()
    var videos = [PHAsset]()
    var recordings = [PHAsset]()
    var protectionUnavailable = false

    static func read(protecting ids: Set<String>, access: PHAuthorizationStatus) -> Shelf {
        var shelf = Shelf()
        guard access == .limited || access == .authorized else { return shelf }
        if access == .authorized {
            let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            albums.enumerateObjects { album, _, _ in
                shelf.albums.append(Album(id: album.localIdentifier, title: album.localizedTitle ?? "Album"))
                if ids.contains(album.localIdentifier) {
                    PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { photo, _, _ in
                        shelf.excluded.insert(photo.localIdentifier)
                    }
                }
            }
            shelf.albums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        if !ids.isSubset(of: Set(shelf.albums.map(\.id))) {
            shelf.protectionUnavailable = true
            return shelf
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        options.predicate = NSPredicate(format: "mediaType IN %@", [PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue])
        PHAsset.fetchAssets(with: options).enumerateObjects { photo, _, _ in
            #if DEBUG
            if StoreCaptureLaunch.isEnabled,
               !PHAssetResource.assetResources(for: photo).contains(where: { $0.originalFilename.hasPrefix("gf-kotoroom-") }) {
                return
            }
            #endif
            guard !shelf.excluded.contains(photo.localIdentifier) else { return }
            shelf.byID[photo.localIdentifier] = photo
            if photo.mediaType == .image {
                shelf.groups[PhotoMonth(photo.creationDate, calendar: calendar), default: []].append(photo)
                if CleanupKind.isScreenshot(photo.mediaType, photo.mediaSubtypes) { shelf.screenshots.append(photo) }
            } else {
                shelf.videos.append(photo)
                if CleanupKind.isRecording(photo.mediaType, photo.mediaSubtypes) { shelf.recordings.append(photo) }
            }
        }
        return shelf
    }
}

@MainActor
final class Library: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private var journal = Journal()
    @Published private var shelf = Shelf()
    @Published private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var loading = false
    @Published private(set) var deleting = false
    @Published var notice: String?
    private var loadTask: Task<Void, Never>?
    private var observing = false
    private let file = URL.applicationSupportDirectory.appending(path: "review-v1.json")
    private var storageReady = true
    private let publisher = DeskPublisher()
    @Published private(set) var cleanup = CleanupResult()
    @Published private(set) var scanning = false
    private let scanner = CleanupScanner()
    private var scanTask: Task<Void, Never>?
    private var cleanupActive = false

    override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
            }
        } catch {
            storageReady = false
            notice = "Your saved review could not be opened. Reopen KOTOROOM to try again."
        }
        reload()
    }

    var hasAccess: Bool { status == .authorized || status == .limited }
    var paused: Bool { shelf.protectionUnavailable || !storageReady }
    var months: [PhotoMonth] { shelf.groups.keys.sorted(by: >) }
    var unfinished: [PhotoMonth] { months.filter { next(in: $0) != nil } }
    var featured: PhotoMonth? {
        if let last = journal.lastMonth, next(in: last) != nil { return last }
        return unfinished.first ?? months.first
    }
    var albums: [Album] { shelf.albums }
    var protectedIDs: Set<String> { journal.protectedAlbums }
    var basket: [PHAsset] {
        journal.marks.compactMap { $0.value.choice == .basket ? shelf.byID[$0.key] : nil }
            .sorted { ($0.creationDate ?? .distantPast, $0.localIdentifier) > ($1.creationDate ?? .distantPast, $1.localIdentifier) }
    }
    func photos(_ month: PhotoMonth) -> [PHAsset] { shelf.groups[month] ?? [] }
    func count(_ month: PhotoMonth, _ choice: Choice) -> Int {
        photos(month).reduce(0) { $0 + (journal.marks[$1.localIdentifier]?.choice == choice ? 1 : 0) }
    }
    func remaining(_ month: PhotoMonth) -> Int {
        photos(month).reduce(0) { $0 + (journal.marks[$1.localIdentifier] == nil ? 1 : 0) }
    }
    func next(in month: PhotoMonth) -> PHAsset? { photos(month).first { journal.marks[$0.localIdentifier] == nil } }
    func roll() -> PhotoMonth? { unfinished.randomElement() }

    func request() async {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        reload()
        while loading, let pending = loadTask { await pending.value }
    }
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.reload() }
    }
    func reload() {
        loadTask?.cancel()
        scanTask?.cancel(); scanning = false
        cleanup = CleanupResult()
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard hasAccess else { shelf = Shelf(); loading = false; publishDesk(); return }
        if !observing { PHPhotoLibrary.shared().register(self); observing = true }
        let access = status, ids = protectedIDs
        loading = true
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) { Shelf.read(protecting: ids, access: access) }.value
            guard !Task.isCancelled else { return }
            apply(result, access: access)
            loading = false
            startCleanup()
            publishDesk()
        }
    }
    private func apply(_ result: Shelf, access: PHAuthorizationStatus) {
        shelf = result
        guard !result.protectionUnavailable else { return }
        var revised = journal
        var protectedFromDeletion = 0
        for (id, mark) in journal.marks {
            if result.excluded.contains(id) {
                if mark.choice == .basket {
                    revised.marks.removeValue(forKey: id)
                    protectedFromDeletion += 1
                }
            } else if access == .authorized && result.byID[id] == nil {
                revised.marks.removeValue(forKey: id)
            }
        }
        if revised.marks.count != journal.marks.count {
            if save(revised), protectedFromDeletion > 0 {
                notice = "Album protection removed \(protectedFromDeletion) from the bin."
            }
        }
    }
    @discardableResult private func save(_ next: Journal) -> Bool {
        guard storageReady else { return false }
        do {
            try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtection])
            let protectionChanged = next.protectedAlbums != journal.protectedAlbums
            journal = next
            if !loading && !deleting && !protectionChanged { publishDesk() }
            return true
        } catch {
            notice = "Changes could not be saved. Check your available storage and try again."
            return false
        }
    }
    func waitForShelf() async {
        while loading, let pending = loadTask { await pending.value }
    }

    #if DEBUG
    /// Capture-only progress references actual seeded Photos assets and stays in memory.
    func prepareStoreCapture() async {
        guard StoreCaptureLaunch.isEnabled else { return }
        await waitForShelf()
        await normalizeStoreCaptureDates()
        var captured = Journal()
        for (index, month) in months.enumerated() {
            let assets = photos(month)
            let reviewed = index == 0 ? min(3, max(0, assets.count - 1)) : index == 1 ? assets.count : index == 2 ? min(4, assets.count) : 0
            for (offset, asset) in assets.prefix(reviewed).enumerated() {
                captured.sequence += 1
                captured.marks[asset.localIdentifier] = Mark(choice: offset.isMultiple(of: 3) ? .basket : .keep, sequence: captured.sequence)
            }
        }
        captured.lastMonth = months.first
        journal = captured
        notice = nil
        if StoreCaptureLaunch.key == "storage-cleanup" {
            setCleanupActive(true)
            if let pending = scanTask { await pending.value }
        }
    }

    private func normalizeStoreCaptureDates() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let changes: [(PHAsset, Date)] = shelf.byID.values.compactMap { asset in
            guard let filename = PHAssetResource.assetResources(for: asset).first(where: { $0.originalFilename.hasPrefix("gf-kotoroom-") })?.originalFilename else { return nil }
            let parts = filename.split(separator: "-")
            guard parts.count >= 4, let month = Int(parts[2]), (1...12).contains(month),
                  let hour = Int(parts[3].split(separator: ".")[0]),
                  let date = calendar.date(from: DateComponents(year: 2026, month: month, day: month == 11 ? 2 : 8, hour: hour % 24)),
                  asset.creationDate.map({ abs($0.timeIntervalSince(date)) > 1 }) ?? true else { return nil }
            return (asset, date)
        }
        guard !changes.isEmpty else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for (asset, date) in changes { PHAssetChangeRequest(for: asset).creationDate = date }
            }
            reload()
            await waitForShelf()
        } catch {
            notice = "Capture seed dates could not be prepared: \(error.localizedDescription)"
        }
    }
    #endif

    private func publishDesk() {
        guard hasAccess, !paused else {
            publisher.publish(.empty)
            QuietReminders.shared.update(nil)
            return
        }
        let entries = months.map { month in
            let total = photos(month).count
            return MonthProgress(year: month.year, month: month.month, title: month.title, reviewed: total - remaining(month), total: total)
        }
        let unfinished = entries.filter { $0.remaining > 0 }
        func matches(_ value: MonthProgress, _ month: PhotoMonth?) -> Bool {
            value.year == month?.year && value.month == month?.month
        }
        let focus = unfinished.first { matches($0, journal.lastMonth) } ?? unfinished.first ?? entries.first
        publisher.publish(DeskSnapshot(focus: focus, candidates: Array(unfinished.prefix(240)), binCount: basket.count))
        if let last = journal.lastSwipeAt, let month = unfinished.first(where: { matches($0, journal.lastSwipeMonth) }), month.reviewed > 0 {
            QuietReminders.shared.update(ReviewReminder(month: month, lastSwipe: last))
        } else { QuietReminders.shared.update(nil) }
    }
    var screenshots: [PHAsset] { shelf.screenshots }
    var recordings: [PHAsset] { shelf.recordings }
    var largeVideos: [PHAsset] {
        shelf.videos.filter { (cleanup.videoBytes[$0.localIdentifier] ?? 0) >= CleanupScanner.largeVideoBytes }
            .sorted { (cleanup.videoBytes[$0.localIdentifier]!, $0.localIdentifier) > (cleanup.videoBytes[$1.localIdentifier]!, $1.localIdentifier) }
    }
    func item(_ id: String) -> PHAsset? { shelf.byID[id] }
    func choice(_ id: String) -> Choice? { journal.marks[id]?.choice }
    func binSource(_ id: String) -> String { journal.marks[id]?.source?.title ?? "Monthly review" }
    func setCleanupActive(_ active: Bool) {
        guard cleanupActive != active else { return }
        cleanupActive = active
        if active { startCleanup() }
        else { scanTask?.cancel(); scanning = false }
    }
    func startCleanup(cloudID: String? = nil) {
        guard cleanupActive, hasAccess, !paused, !loading else { return }
        if let cloudID, item(cloudID) == nil { return }
        scanTask?.cancel()
        scanning = true
        let assets = Array(shelf.byID.values)
        scanTask = Task {
            do {
                try await scanner.scan(assets, cloudID: cloudID) { [weak self] result in
                    await self?.acceptScan(result)
                }
            } catch { /* A new library snapshot or navigation canceled this scan. */ }
            if !Task.isCancelled { scanning = false }
        }
    }
    private func acceptScan(_ result: CleanupResult) {
        guard !Task.isCancelled else { return }
        cleanup = result
    }

    var reservedKeepers: Set<String> { Set(journal.marks.values.compactMap { $0.proof?.keeperID }) }

    func preferred(_ ids: [String]) -> [PHAsset] {
        func rank(_ a: PHAsset) -> Int {
            if choice(a.localIdentifier) == .basket { return 5 }
            if a.isFavorite { return 0 }
            if choice(a.localIdentifier) == .keep { return 1 }
            if !a.canPerform(.delete) { return 2 }
            return 3
        }
        return ids.compactMap(item).sorted {
            (rank($0), $0.creationDate ?? .distantFuture, $0.localIdentifier) < (rank($1), $1.creationDate ?? .distantFuture, $1.localIdentifier)
        }
    }
    func canSelect(_ asset: PHAsset, reserved: Set<String>, automatic: Bool) -> Bool {
        let id = asset.localIdentifier
        guard item(id) != nil, choice(id) != .basket, !reserved.contains(id), asset.canPerform(.delete) else { return false }
        return !automatic || (!asset.isFavorite && choice(id) != .keep && !asset.sourceType.contains(.typeCloudShared))
    }

    func allowedCleanupSelection(_ requested: Set<String>, automatic: Bool = false) -> Set<String> {
        let reserved = reservedKeepers
        var allowed = Set(requested.filter { id in item(id).map { canSelect($0, reserved: reserved, automatic: automatic) } == true })
        let signatures = Set(allowed.compactMap { cleanup.signatures[$0] })
        for sig in signatures {
            guard let ids = cleanup.sets[sig] else { continue }
            let available = preferred(ids).filter { choice($0.localIdentifier) != .basket }
            if let first = available.first, available.allSatisfy({ allowed.contains($0.localIdentifier) }) {
                allowed.remove(first.localIdentifier)
            }
        }
        return allowed
    }

    func queueCleanup(_ selected: Set<String>, from source: CleanupKind) -> Int {
        guard hasAccess, !loading, !deleting, !paused else { return 0 }
        let visible: Set<String>
        switch source {
        case .duplicates: visible = Set(cleanup.sets.values.joined())
        case .screenshots: visible = Set(screenshots.map(\.localIdentifier))
        case .recordings: visible = Set(recordings.map(\.localIdentifier))
        case .videos: visible = Set(largeVideos.map(\.localIdentifier))
        }
        let ids = allowedCleanupSelection(selected.intersection(visible))
        guard !ids.isEmpty else { return 0 }
        var next = journal
        var proofs: [String: DuplicateProof] = [:]
        for signature in Set(ids.compactMap { cleanup.signatures[$0] }) {
            guard let group = cleanup.sets[signature], let keeper = preferred(group).first(where: {
                !ids.contains($0.localIdentifier) && choice($0.localIdentifier) != .basket
            }) else { continue }
            proofs[signature] = DuplicateProof(signature: signature, keeperID: keeper.localIdentifier)
        }
        for id in ids {
            let proof = cleanup.signatures[id].flatMap { proofs[$0] }
            next.marks[id] = Mark(choice: .basket, sequence: nil, source: source, proof: proof)
        }
        return save(next) ? ids.count : 0
    }

    private func verifyExtraCopies(_ ids: Set<String>, shelf: Shelf) async throws -> [String: PHAsset] {
        var inspected = [String: PHAsset]()
        var signatures = [String: String]()
        for id in ids {
            guard let proof = journal.marks[id]?.proof else { continue }
            guard !ids.contains(proof.keeperID), choice(proof.keeperID) != .basket else { throw CleanupError.survivorChanged }
            for member in [id, proof.keeperID] {
                guard let asset = shelf.byID[member] else { throw CleanupError.survivorChanged }
                if signatures[member] == nil {
                    signatures[member] = try await CleanupScanner.inspect(asset, hash: true, cloud: false).signature
                    inspected[member] = asset
                }
                guard signatures[member] == proof.signature else { throw CleanupError.survivorChanged }
            }
        }
        return inspected
    }

    func begin(_ month: PhotoMonth) {
        var next = journal
        next.lastMonth = month
        save(next)
    }
    func choose(_ asset: PHAsset, _ choice: Choice, in month: PhotoMonth) {
        let id = asset.localIdentifier
        guard !loading, !paused, !deleting, next(in: month)?.localIdentifier == id else { return }
        if choice == .basket && reservedKeepers.contains(id) {
            notice = "This copy is being kept for a duplicate already in the bin."
            return
        }
        if choice == .basket && !asset.canPerform(.delete) {
            notice = "Photos does not allow this item to be deleted. Choose Keep to continue."
            return
        }
        var revised = journal
        revised.sequence += 1
        revised.marks[id] = Mark(choice: choice, sequence: revised.sequence)
        revised.lastMonth = month
        revised.lastSwipeMonth = month
        revised.lastSwipeAt = Date()
        save(revised)
    }
    func lastSwipe(_ month: PhotoMonth) -> String? {
        photos(month).compactMap { item -> (String, Int)? in
            let id = item.localIdentifier
            return journal.marks[id]?.sequence.map { (id, $0) }
        }.max(by: { $0.1 < $1.1 })?.0
    }
    func undo(_ month: PhotoMonth) {
        guard !loading, !paused, !deleting, let id = lastSwipe(month) else { return }
        var next = journal
        next.marks.removeValue(forKey: id)
        save(next)
    }
    func restore(_ ids: Set<String>) {
        guard !deleting, !loading, !paused else { return }
        var next = journal
        for id in ids where next.marks[id]?.choice == .basket {
            next.marks[id] = Mark(choice: .keep, sequence: nil)
        }
        save(next)
    }
    func toggleProtection(_ id: String) {
        guard status == .authorized, !loading, !deleting else { return }
        var revised = journal
        if revised.protectedAlbums.contains(id) { revised.protectedAlbums.remove(id) }
        else { revised.protectedAlbums.insert(id) }
        if save(revised) { reload() }
    }
    func canRemoveVaultSource(_ id: String) -> Bool {
        !paused && hasAccess && !loading && shelf.byID[id]?.canPerform(.delete) == true
    }

    // Use the same PhotoKit view of protected albums as monthly review.
    func checkVaultDeletion(_ ids: Set<String>) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let protected = protectedIDs
        guard storageReady, !deleting, status == .authorized || status == .limited else {
            throw VaultError("Check Photos access before removing the originals.")
        }
        let fresh = await Task.detached(priority: .userInitiated) { Shelf.read(protecting: protected, access: status) }.value
        guard !fresh.protectionUnavailable, protected == protectedIDs,
              status == PHPhotoLibrary.authorizationStatus(for: .readWrite),
              ids.allSatisfy({ fresh.byID[$0]?.canPerform(.delete) == true }) else {
            throw VaultError("An original is protected or no longer available. Check your selection. Your copies are safe.")
        }
    }
    func delete(_ ids: Set<String>) async {
        guard !ids.isEmpty, !loading, !paused, !deleting, ids.allSatisfy({ journal.marks[$0]?.choice == .basket }) else { return }
        deleting = true
        defer { deleting = false }
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard access == .authorized || access == .limited else { reload(); return }
        let protected = protectedIDs
        let fresh = await Task.detached(priority: .userInitiated) { Shelf.read(protecting: protected, access: access) }.value
        let items = ids.compactMap { fresh.byID[$0] }
        guard !fresh.protectionUnavailable, items.count == ids.count, items.allSatisfy({ $0.canPerform(.delete) }),
              ids.allSatisfy({ journal.marks[$0]?.choice == .basket }),
              access == PHPhotoLibrary.authorizationStatus(for: .readWrite) else {
            notice = "The bin or your Photos access has changed. Check the list again."
            reload()
            return
        }
        do {
            let inspected = try await verifyExtraCopies(ids, shelf: fresh)
            // Recheck after resource I/O; an album or a surviving copy can change while hashing.
            var final = items
            if !inspected.isEmpty {
                let now = await Task.detached(priority: .userInitiated) { Shelf.read(protecting: protected, access: access) }.value
                guard !now.protectionUnavailable, inspected.allSatisfy({ id, old in
                    guard let current = now.byID[id] else { return false }
                    return current.modificationDate == old.modificationDate
                }) else { throw CleanupError.survivorChanged }
                final = ids.compactMap { now.byID[$0] }
            }
            guard final.count == ids.count, final.allSatisfy({ $0.canPerform(.delete) }),
                  protected == protectedIDs, access == PHPhotoLibrary.authorizationStatus(for: .readWrite),
                  ids.allSatisfy({ choice($0) == .basket }) else { throw CleanupError.survivorChanged }
            try Task.checkCancellation()
            let confirmed = final
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(confirmed as NSArray) }
            var next = journal
            ids.forEach { next.marks.removeValue(forKey: $0) }
            save(next)
            reload()
        } catch is CancellationError {
            return
        } catch {
            let failure = error as NSError
            if !(failure.domain == PHPhotosErrorDomain && failure.code == PHPhotosError.Code.userCancelled.rawValue) {
                notice = (error as? CleanupError)?.errorDescription ?? "The items could not be deleted. Check Photos access and try again."
            }
            reload()
        }
    }
}
