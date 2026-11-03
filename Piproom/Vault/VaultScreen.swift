import SwiftUI
import PhotosUI

struct VaultScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var library: Library
    @Environment(\.openURL) private var openURL
    @State private var picker = false
    @State private var detail: VaultPhoto?
    @State private var anchor = UIViewController()
    @State private var pin = ""
    @State private var firstPIN: String?
    @State private var confirmErase = false
    @State private var showNotice = false
    @Environment(\.scenePhase) private var scene
    private let storageNote = "This folder has no backup. Losing this iPhone or deleting KOTOROOM can permanently erase your photos. Keep your PIN safe. Restore photos before changing devices."
    private let deletionNote = "With iCloud Photos, removal syncs across your devices. Originals stay in Recently Deleted for up to 30 days."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SmallPrint("KOTOROOM / Private collection").foregroundStyle(Color.faded)
                if !vault.unlocked { locked }
                else if let photo = detail { detailView(photo) }
                else { collection }
            }.padding(20).frame(maxWidth: 580, alignment: .leading)
        }
        .frame(maxWidth: .infinity).background(Felt())
        .navigationTitle("Secret Folder").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vault.unlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vault.lock() } label: { Label("Lock folder", systemImage: "lock.fill") }
                        .accessibilityIdentifier("lockVault")
                }
            }
        }
        .background(PickerAnchor(controller: anchor).frame(width: 0, height: 0))
        .onDisappear { pin = ""; firstPIN = nil; vault.lock() }
        .onChange(of: scene) { _, phase in
            if phase == .background { pin = ""; firstPIN = nil; picker = false; detail = nil; confirmErase = false }
        }
        .onChange(of: vault.unlocked) { _, open in if !open { picker = false; detail = nil } }
        .sheet(isPresented: $picker) { VaultPicker { assets in
            picker = false
            vault.startImport(assets)
        } }
        .onChange(of: vault.notice) { _, text in showNotice = text != nil }
        .alert("Secret Folder", isPresented: $showNotice) {
            Button("Done") { vault.notice = nil }
        } message: { Text(vault.notice ?? "") }
    }
    private var locked: some View {
        PaperCard {
            HStack {
                SmallPrint("Private archive")
                Spacer()
                Image(systemName: "lock.rectangle.stack").font(.title2)
            }
            Text(vault.configured ? "Sealed collection" : "Secret Folder")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
            Text(vault.configured ? "Unlock with your six-digit Secret Folder PIN." : storageNote)
                .font(.subheadline)
            let prompt = vault.configured ? "Vault PIN" : (firstPIN == nil ? "Create a six-digit PIN" : "Confirm your PIN")
            SecureField(prompt, text: $pin, prompt: Text(prompt).foregroundColor(.ink.opacity(0.74)))
                .keyboardType(.numberPad)
                .accessibilityIdentifier("vaultPIN")
                .onChange(of: pin) { _, value in
                    let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if digits != value { pin = digits }
                }
                .padding(14).foregroundStyle(Color.ink).tint(.felt)
                .background(Color.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            Button {
                let entry = pin
                pin = ""
                if vault.configured { Task { await vault.enter(pin: entry, creating: false) } }
                else if let firstPIN {
                    self.firstPIN = nil
                    guard entry == firstPIN else { vault.notice = "The PINs didn’t match. Choose your PIN again."; return }
                    Task { await vault.enter(pin: entry, creating: true) }
                } else { firstPIN = entry }
            } label: {
                PrimaryLabel(text: vault.configured ? "Unlock folder" : firstPIN == nil ? "Continue" : "Create folder", icon: "lock.open")
            }.disabled(pin.count != 6 || vault.busy).accessibilityIdentifier("submitVaultPIN")
            if vault.faceEnabled && vault.supportsFaceID {
                Button { Task { await vault.faceID(enroll: false) } } label: {
                    Label("Unlock with Face ID", systemImage: "faceid").frame(maxWidth: .infinity, minHeight: 44)
                }.disabled(vault.busy).accessibilityIdentifier("unlockVault")
            }
        }
    }
    private var collection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("My collection").font(.system(.largeTitle, design: .serif).weight(.medium))
            if vault.usedPIN && vault.supportsFaceID {
                Button {
                    if vault.faceEnabled { vault.turnOffFaceID() }
                    else { Task { await vault.faceID(enroll: true) } }
                } label: { Label(vault.faceEnabled ? "Turn off Face ID" : "Enable Face ID", systemImage: "faceid") }
                .disabled(vault.busy).accessibilityIdentifier("configureFace")
            }
            Button {
                Task {
                    if library.status == .notDetermined { await library.request() }
                    if library.hasAccess { picker = true }
                    else if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } label: { PrimaryLabel(text: "Add from Photos", icon: "plus") }
                .buttonStyle(.plain).disabled(vault.busy).accessibilityIdentifier("addToVault")
            if library.status == .limited {
                Button("Manage photo access") {
                    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: anchor) { _ in Task { @MainActor in library.reload() } }
                }
            }
            if vault.busy { ProgressView(vault.progress).frame(maxWidth: .infinity) }
            if !vault.recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Verified copies · \(vault.recent.count)", systemImage: "checkmark.shield")
                        .font(.headline).accessibilityIdentifier("verifiedCopies")
                    Text("The originals are still in Photos. " + deletionNote).font(.caption)
                    let candidates = vault.recent.filter { library.canRemoveVaultSource($0.sourceID) }
                    if candidates.count < vault.recent.count { Text("Protected or unavailable originals will stay in Photos.").font(.caption) }
                    if !candidates.isEmpty {
                        Button("Remove originals from Photos (\(candidates.count))", role: .destructive) {
                            Task { await vault.deleteOriginals(candidates, library: library) }
                        }.accessibilityIdentifier("deleteVaultOriginals")
                    }
                    Button("Keep originals") { vault.dismissReceipt() }
                }.padding(16).background(Color.table, in: RoundedRectangle(cornerRadius: 16)).disabled(vault.busy)
            }
            if vault.photos.isEmpty {
                Text("Add your first photos. After verification, you can remove their originals from Photos.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(vault.photos) { photo in
                        Button { detail = photo } label: {
                            VaultImage(photo: photo, fill: true).frame(height: 150)
                                .overlay(alignment: .bottomLeading) {
                                    Label(photo.live ? "Live Photo" : "Photo", systemImage: photo.live ? "livephoto" : "photo")
                                        .font(.caption.bold()).padding(6).background(.black.opacity(0.72), in: Capsule()).padding(6)
                                }.clipShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(vault.busy)
                            .accessibilityIdentifier(photo.live ? "vaultLiveTile" : "vaultPhotoTile")
                    }
                }
            }
        }
    }
    private func detailView(_ photo: VaultPhoto) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button("All photos", systemImage: "chevron.left") { detail = nil }
            Text(photo.live ? "Live Photo" : "Photo").font(.title.bold())
            if photo.live { VaultMotionPlayer(photo: photo).frame(height: 270) }
            else { VaultImage(photo: photo, fill: false).frame(height: 270) }
            if let date = photo.date { Text(date.formatted(.dateTime.month(.wide).day().year().hour().minute().locale(Locale(identifier: "en_US")))).font(.caption) }
            Button { Task { await vault.export(photo) } } label: {
                PrimaryLabel(text: "Restore to Photos", icon: "square.and.arrow.up")
            }.buttonStyle(.plain).accessibilityIdentifier("exportVaultPhoto")
            Text("A copy will appear in Photos. Your vault copy stays here.").font(.caption).foregroundStyle(.secondary)
            if library.canRemoveVaultSource(photo.sourceID) {
                Divider()
                Text(deletionNote).font(.caption).foregroundStyle(.secondary)
                Button("Remove original from Photos", role: .destructive) { Task { await vault.deleteOriginals([photo], library: library) } }
            }
            Divider()
            Button("Delete vault copy", role: .destructive) { confirmErase = true }
                .confirmationDialog("Delete this private copy?", isPresented: $confirmErase, titleVisibility: .visible) {
                    Button("Delete vault copy", role: .destructive) {
                        vault.eraseCopy(photo)
                        if !vault.photos.contains(photo) { detail = nil }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This permanently removes the copy in Secret Folder. Save it to Photos first if you want to keep it.") }
            if vault.busy { ProgressView(vault.progress) }
        }.disabled(vault.busy)
    }
}

struct VaultImage: View {
    @EnvironmentObject private var vault: VaultStore
    let photo: VaultPhoto
    let fill: Bool
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { bounds in
            ZStack {
                Color.table
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
                } else { Image(systemName: "photo") }
            }.frame(width: bounds.size.width, height: bounds.size.height).clipped()
        }.task(id: photo.id) { image = await vault.thumbnail(photo) }
    }
}

private struct VaultPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var sections: [PhotoMonth: [PHAsset]] = [:]
    @State private var fetching = true
    let importSelection: ([PHAsset]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose photos or Live Photos. Originals in iCloud may take longer to download.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if sections.isEmpty {
                        Text(fetching ? "Loading photos…" : "No photos available").padding(.vertical)
                    }
                    ForEach(sections.keys.sorted(by: >), id: \.self) { month in
                        Text("\(month.name) \(String(month.year))").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                            ForEach(sections[month] ?? [], id: \.localIdentifier) { asset in
                                let id = asset.localIdentifier
                                Button {
                                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                                } label: {
                                    AssetImage(asset: asset, pixels: 300).frame(height: 108)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selected.contains(id) ? Color.paper : .white).padding(5)
                                                .background(.black.opacity(0.6), in: Circle()).padding(4)
                                        }
                                        .overlay(alignment: .bottomLeading) {
                                            if asset.mediaSubtypes.contains(.photoLive) { Image(systemName: "livephoto").padding(4) }
                                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityLabel(asset.mediaSubtypes.contains(.photoLive) ? "Live Photo" : "Photo")
                                    .accessibilityAddTraits(selected.contains(id) ? .isSelected : []).accessibilityIdentifier("pick-" + id)
                            }
                        }
                    }
                }.padding(16)
            }.navigationTitle("Add to vault").navigationBarTitleDisplayMode(.inline)
            .task {
                sections = await Task.detached(priority: .userInitiated) {
                    let options = PHFetchOptions()
                    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                    var groups = [PhotoMonth: [PHAsset]]()
                    let calendar = Calendar(identifier: .gregorian)
                    PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
                        groups[PhotoMonth(asset.creationDate, calendar: calendar), default: []].append(asset)
                    }
                    return groups
                }.value
                fetching = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selected.count))") {
                        importSelection(sections.keys.sorted(by: >).flatMap { sections[$0] ?? [] }.filter { selected.contains($0.localIdentifier) })
                    }.disabled(selected.isEmpty).accessibilityIdentifier("importVaultSelection")
                }
            }
        }
    }
}
