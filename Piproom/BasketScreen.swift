import SwiftUI
import Photos

struct BasketScreen: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var preview: PreviewAsset?
    @State private var deletionTask: Task<Void, Never>?

    var body: some View {
        let queued = library.basket
        let ids = Set(queued.map(\.localIdentifier))
        let picked = selected.intersection(ids)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SmallPrint("Archive / Final review").foregroundStyle(Color.faded)
                Text("Review bin").font(.system(.largeTitle, design: .serif).bold())
                if library.paused || !library.hasAccess {
                    Text(library.paused ? "The bin is paused. Check your protected albums and Photos access." : "Allow Photos access to see the items you set aside.")
                } else if queued.isEmpty && library.loading {
                    ProgressView("Loading your bin…")
                } else if queued.isEmpty {
                    Image(systemName: "tray").font(.system(size: 56, weight: .light)).foregroundStyle(Color.paper).padding(.top, 30)
                    Text("Your bin is empty").font(.title.bold()).accessibilityIdentifier("emptyBin")
                    Text("Add items from Storage cleanup or swipe left during monthly review. It stays in Photos until you confirm deletion.")
                        .foregroundStyle(.secondary)
                    Button { dismiss() } label: { PrimaryLabel(text: "Done", icon: "checkmark") }.buttonStyle(.plain)
                } else {
                    Text("Select items to delete or keep. Tap a thumbnail to preview it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text("\(picked.count) of \(queued.count) selected").font(.subheadline.monospacedDigit())
                            .accessibilityIdentifier("binCount")
                        Spacer()
                        Button(picked == ids ? "Deselect all" : "Select all") { selected = picked == ids ? [] : ids }
                    }.font(.subheadline)
                    if !picked.isEmpty {
                        SelectedVolume(assets: queued.filter { picked.contains($0.localIdentifier) })
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 134), spacing: 10)], spacing: 10) {
                        ForEach(queued, id: \.localIdentifier) { asset in
                            let id = asset.localIdentifier
                            let marked = picked.contains(id)
                            ZStack(alignment: .topTrailing) {
                                Button { preview = PreviewAsset(asset: asset) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        AssetImage(asset: asset, allowNetwork: false).aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(alignment: .bottomLeading) { if asset.mediaType == .video { Image(systemName: "play.circle.fill").padding(5) } }
                                        Text(asset.creationDate?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "en_US"))) ?? "Undated")
                                            .font(.caption)
                                        Text(library.binSource(id)).font(.caption2).foregroundStyle(Color.faded)
                                    }
                                }.accessibilityLabel(asset.mediaType == .video ? "Play video" : "Open photo").accessibilityIdentifier("previewBinPhoto")
                                Button {
                                    if marked { selected.remove(id) } else { selected.insert(id) }
                                } label: {
                                    Image(systemName: marked ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 24, weight: .bold)).foregroundStyle(marked ? Color.paper : .white)
                                        .padding(4).background(.black.opacity(0.72), in: Circle()).padding(5)
                                        .frame(minWidth: 44, minHeight: 44)
                                }.accessibilityLabel(marked ? "Deselect photo" : "Select photo")
                                    .accessibilityIdentifier("selectBinPhoto")
                            }.buttonStyle(.plain)
                        }
                    }
                    Button("Keep all in Photos") { library.restore(ids); selected = [] }
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                }
            }.padding(18).frame(maxWidth: 580, alignment: .leading)
        }.frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            if !queued.isEmpty && !library.paused {
                VStack(spacing: 10) {
                    Text("With iCloud Photos on, deletions sync across your devices. You can usually recover items in Recently Deleted for 30 days.")
                        .font(.caption).foregroundStyle(.secondary)
                    if library.deleting { ProgressView("Checking your selection…").font(.caption) }
                    HStack {
                        Button("Keep (\(picked.count))") { library.restore(picked); selected = [] }
                            .buttonStyle(.bordered).accessibilityIdentifier("restoreSelected")
                        Spacer()
                        Button("Delete from Photos (\(picked.count))", role: .destructive) {
                            deletionTask = Task { await library.delete(picked) }
                        }.buttonStyle(.borderedProminent).tint(.enamel).accessibilityIdentifier("deleteSelected")
                    }.disabled(picked.isEmpty || library.loading || library.paused)
                }.padding().background(.bar)
            }
        }
        .disabled(library.deleting)
        .background(Color.felt).navigationBarTitleDisplayMode(.inline)
        .onChange(of: ids) { _, new in selected.formIntersection(new) }
        .onDisappear { deletionTask?.cancel() }
        .sheet(item: $preview) { PhotoPreview(asset: $0.asset) }
    }
}

private struct SelectedVolume: View {
    let assets: [PHAsset]
    @State private var size: String?

    var body: some View {
        Group {
            if let size { Text("Original size: " + size).font(.caption).foregroundStyle(.secondary) }
            else { Color.clear.frame(height: 0) }
        }
        .task(id: assets) {
            size = nil
            guard #available(iOS 27, *) else { return }
            let selected = assets
            let bytes = await Task.detached(priority: .utility) { () -> Int64? in
                var total: Int64 = 0
                for asset in selected {
                    let resources = PHAssetResource.assetResources(for: asset)
                    guard !resources.isEmpty else { return nil }
                    for resource in resources {
                        guard let bytes = resource.dataSize else { return nil }
                        total += Int64(bytes)
                    }
                }
                return total
            }.value
            if !Task.isCancelled, let bytes { size = bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US"))) }
        }
    }
}
