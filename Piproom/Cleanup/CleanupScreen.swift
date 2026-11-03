import SwiftUI
import Photos

struct CleanupHome: View {
    @EnvironmentObject private var library: Library
    let openBin: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SmallPrint("Archive / Storage").foregroundStyle(Color.faded)
                Text("Storage cleanup").font(.system(.largeTitle, design: .serif).weight(.medium))
                if !library.hasAccess || library.paused {
                    Text("Check Photos access and your protected albums to continue.")
                } else {
                    PaperCard {
                        HStack { SmallPrint("Library inventory"); Spacer(); Die().frame(width: 30, height: 30) }
                        Text("Review by collection").font(.system(.title2, design: .serif))
                        Text("Set items aside here. Confirm any deletion in your review bin.").font(.subheadline)
                        if library.scanning {
                            ProgressView(value: Double(library.cleanup.checked), total: Double(max(library.cleanup.total, 1))).tint(.felt)
                            Text("Checking local originals…").font(.caption)
                        } else if !library.loading {
                            let count = Set(library.cleanup.sets.values.joined())
                                .union(library.screenshots.map(\.localIdentifier))
                                .union(library.recordings.map(\.localIdentifier))
                                .union(library.largeVideos.map(\.localIdentifier)).count
                            Text("Unique items across collections: \(count)").font(.caption.monospacedDigit())
                        }
                    }
                    if library.status == .limited {
                        Label("Only items shared with KOTOROOM are included.", systemImage: "eye").font(.footnote)
                    }
                    ForEach(CleanupKind.allCases) { kind in
                        NavigationLink(value: Page.collection(kind)) {
                            MenuRow(title: kind.title, note: kind.caption, icon: kind.icon, value: count(kind))
                        }.accessibilityIdentifier("category-" + kind.rawValue)
                        Divider().overlay(Color.faded.opacity(0.35))
                    }
                }
                Button(action: openBin) {
                    MenuRow(title: "Review bin", note: "Manage all selected items", icon: "tray", value: "\(library.basket.count)")
                }.accessibilityIdentifier("cleanupBin")
            }.padding(20).frame(maxWidth: 600)
        }.frame(maxWidth: .infinity).background(Felt()).navigationBarTitleDisplayMode(.inline)
    }
    private func count(_ kind: CleanupKind) -> String {
        if library.loading { return "…" }
        switch kind {
        case .duplicates: return library.cleanup.sets.count == 1 ? "1 set" : "\(library.cleanup.sets.count) sets"
        case .screenshots: return "\(library.screenshots.count)"
        case .recordings: return "\(library.recordings.count)"
        case .videos: return "\(library.largeVideos.count)"
        }
    }
}

private struct CleanupSection: Identifiable {
    let id: String
    let title: String
    let items: [PHAsset]
}

struct CleanupCollection: View {
    let kind: CleanupKind
    let openBin: () -> Void
    @EnvironmentObject private var library: Library
    @State private var selected: Set<String> = []
    @State private var preview: PreviewAsset?
    @State private var feedback: String?
    @State private var byDuration = false

    private var sections: [CleanupSection] {
        switch kind {
        case .duplicates:
            return library.cleanup.sets.keys.sorted().enumerated().map { index, sig in
                CleanupSection(id: sig, title: "Set \(index + 1)", items: library.preferred(library.cleanup.sets[sig] ?? []))
            }
        case .screenshots:
            let groups = Dictionary(grouping: library.screenshots) { PhotoMonth($0.creationDate, calendar: Calendar(identifier: .gregorian)) }
            return groups.keys.sorted(by: >).map { CleanupSection(id: $0.title, title: $0.title, items: groups[$0] ?? []) }
        case .videos: return [CleanupSection(id: "videos", title: "By file size", items: library.largeVideos)]
        case .recordings:
            let sizes = library.cleanup.videoBytes
            let items = library.recordings.sorted {
                if byDuration { return ($0.duration, $0.localIdentifier) > ($1.duration, $1.localIdentifier) }
                return (sizes[$0.localIdentifier] ?? -1, $0.localIdentifier) > (sizes[$1.localIdentifier] ?? -1, $1.localIdentifier)
            }
            return [CleanupSection(id: "recordings", title: byDuration ? "By duration" : "By file size", items: items)]
        }
    }
    private var unknown: [PHAsset] {
        let ids: Set<String>
        switch kind {
        case .duplicates: ids = library.cleanup.unverified
        case .videos: ids = library.cleanup.unknownSizes
        default: return []
        }
        return ids.sorted().compactMap(library.item)
    }

    var body: some View {
        let sections = sections
        let ids = Set(sections.flatMap { $0.items.map(\.localIdentifier) })
        let picked = selected.intersection(ids)
        let keepers = library.reservedKeepers
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 13) {
                SmallPrint("Storage / Collection").foregroundStyle(Color.faded)
                Text(kind.title).font(.system(.largeTitle, design: .serif).weight(.medium))
                Text(kind.caption).font(.subheadline).foregroundStyle(Color.faded)
                if library.loading || !library.hasAccess || library.paused {
                    Text(library.loading ? "Reading your library…" : "Review paused. Check Photos access and protected albums.")
                } else {
                    if kind == .recordings && !ids.isEmpty {
                        Picker("Sort recordings", selection: $byDuration) { Text("Size").tag(false); Text("Duration").tag(true) }.pickerStyle(.segmented)
                    }
                    if kind == .duplicates {
                        Text("Keep one copy from each set. Tap a thumbnail to compare.").font(.footnote)
                    }
                    if ids.isEmpty {
                        if library.scanning && (kind == .duplicates || kind == .videos) { ProgressView("Checking local originals…") }
                        else { Label("No matching items", systemImage: "tray").padding(.vertical, 12) }
                    } else {
                        Button(picked.isEmpty ? (kind == .duplicates ? "Select extra copies" : "Select suggested items") : "Clear selection") {
                            selected = picked.isEmpty ? library.allowedCleanupSelection(ids, automatic: true) : []
                            feedback = selected.isEmpty && picked.isEmpty ? "No suggested items. You can review each item individually." : nil
                        }.font(.subheadline.bold()).frame(minHeight: 44)
                        ForEach(sections) { section in
                            SmallPrint(section.title + "  ·  " + String(section.items.count)).foregroundStyle(Color.faded)
                            ForEach(section.items, id: \.localIdentifier) { item in
                                row(item, picked: picked, keepers: keepers, suggested: kind == .duplicates && section.items.first?.localIdentifier == item.localIdentifier)
                                Divider()
                            }
                        }
                    }
                    if !unknown.isEmpty {
                        SmallPrint(kind == .videos ? "Size unavailable" : "Unverified originals")
                        Text("Check individual originals to include files stored in iCloud.").font(.caption).foregroundStyle(Color.faded)
                        ForEach(unknown, id: \.localIdentifier) { item in
                            HStack {
                                thumbnail(item)
                                Text(date(item)).font(.caption)
                                Spacer()
                                Button("Check original") { library.startCleanup(cloudID: item.localIdentifier) }
                                    .disabled(library.scanning).font(.caption.bold())
                            }
                        }
                    }
                }
            }.padding(20)
        }.background(Felt()).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if let feedback { Text(feedback).font(.caption).accessibilityIdentifier("queueFeedback") }
                HStack(spacing: 14) {
                    Button(action: openBin) { Label("\(library.basket.count)", systemImage: "tray").padding(8) }
                        .accessibilityIdentifier("collectionBin")
                    Button {
                        let added = library.queueCleanup(picked, from: kind)
                        selected = []
                        feedback = added > 0 ? "Added to review bin: \(added)" : "The selection changed. Check the available items."
                    } label: {
                        Text("Add to bin (\(picked.count))").font(.headline).frame(maxWidth: .infinity)
                            .padding(12).foregroundStyle(Color.ink).background(Color.paper, in: RoundedRectangle(cornerRadius: 12))
                    }.disabled(picked.isEmpty || library.loading || library.paused || !library.hasAccess)
                        .opacity(picked.isEmpty ? 0.55 : 1).accessibilityIdentifier("queueCleanup")
                }
            }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
        }.onChange(of: ids) { _, available in selected.formIntersection(available) }
        .sheet(item: $preview) { PhotoPreview(asset: $0.asset) }
    }

    private func row(_ item: PHAsset, picked: Set<String>, keepers: Set<String>, suggested: Bool) -> some View {
        let id = item.localIdentifier
        let queued = library.choice(id) == .basket
        return HStack(spacing: 12) {
            thumbnail(item)
            VStack(alignment: .leading, spacing: 4) {
                Text(date(item)).font(.subheadline.bold())
                if item.mediaType == .video {
                    let seconds = Int(max(0, item.duration))
                    let size = library.cleanup.videoBytes[id].map { $0.formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US"))) }
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60) + " · " + (size ?? "Size unknown")).font(.caption.monospacedDigit())
                } else { Text(item.mediaSubtypes.contains(.photoLive) ? "Live Photo" : "\(item.pixelWidth) × \(item.pixelHeight)").font(.caption) }
                if queued { Text("In review bin").font(.caption2.bold()) }
                else if suggested {
                    let why = item.isFavorite ? "Favorite" : library.choice(id) == .keep ? "Marked Keep" : !item.canPerform(.delete) ? "Read-only" : "First in archive"
                    Text("Suggested keeper · " + why).font(.caption2.bold())
                } else if keepers.contains(id) { Text("Kept for a copy in the bin").font(.caption2) }
                else if item.isFavorite || library.choice(id) == .keep { Text(item.isFavorite ? "Favorite" : "Marked Keep").font(.caption2) }
            }
            Spacer()
            Button {
                feedback = nil
                if picked.contains(id) { selected.remove(id) }
                else {
                    let next = picked.union([id])
                    if library.allowedCleanupSelection(next) == next { selected = next }
                    else { feedback = "Keep one matching copy in Photos." }
                }
            } label: {
                Image(systemName: queued ? "tray.fill" : picked.contains(id) ? "checkmark.circle.fill" : "circle").font(.title2).frame(width: 44, height: 48)
            }.disabled(!library.canSelect(item, reserved: keepers, automatic: false))
                .accessibilityLabel(queued ? "In bin" : picked.contains(id) ? "Deselect item" : "Select item")
                .accessibilityIdentifier("cleanupSelect-" + id)
        }
    }
    private func date(_ asset: PHAsset) -> String {
        asset.creationDate?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "en_US"))) ?? "Undated"
    }
    private func thumbnail(_ item: PHAsset) -> some View {
        Button { preview = PreviewAsset(asset: item) } label: {
            AssetImage(asset: item, pixels: 220, allowNetwork: false).frame(width: 70, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { if item.mediaType == .video { Image(systemName: "play.circle.fill").shadow(radius: 2) } }
        }.accessibilityLabel(item.mediaType == .video ? "Play video" : "Open photo")
            .accessibilityIdentifier("cleanupPreview-" + item.localIdentifier)
    }
}
