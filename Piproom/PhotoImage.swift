import SwiftUI
import PhotosUI
import AVKit

struct AssetImage: View {
    let asset: PHAsset
    var pixels: CGFloat = 480
    var fit = false
    var allowNetwork = true
    var didLoad: ((String) -> Void)?
    @State private var image: UIImage?
    @State private var request: PHImageRequestID?
    @State private var token = UUID()
    @State private var unavailable = false

    var body: some View {
        GeometryReader { frame in
            ZStack {
                Color.graphite
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                } else if unavailable {
                    VStack(spacing: 6) {
                        Image(systemName: "icloud.slash").accessibilityLabel("Preview unavailable")
                        if fit {
                            Button("Try again", action: load).buttonStyle(.bordered)
                        }
                    }
                } else { ProgressView().tint(.paper) }
            }.frame(width: frame.size.width, height: frame.size.height).clipped()
        }
        .onAppear { load() }
        .onChange(of: asset.localIdentifier) { load() }
        .onChange(of: asset.modificationDate) { load() }
        .onDisappear { cancel() }
    }
    private func cancel() {
        token = UUID()
        if let request { PHImageManager.default().cancelImageRequest(request); self.request = nil }
    }
    private func load() {
        cancel()
        let key = token
        image = nil
        unavailable = false
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        options.resizeMode = .fast
        request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels),
                           contentMode: fit ? .aspectFit : .aspectFill, options: options) { result, info in
            DispatchQueue.main.async {
                guard token == key else { return }
                if let result { image = result; didLoad?(asset.localIdentifier) }
                else if (info?[PHImageResultIsDegradedKey] as? Bool) != true { unavailable = true }
            }
        }
    }
}

struct PhotoPreview: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    var body: some View {
        NavigationStack {
            Group {
                if asset.mediaType == .video { ClipPreview(asset: asset) }
                else {
                    AssetImage(asset: asset, pixels: 2400, fit: true)
                        .scaleEffect(zoom)
                        .gesture(MagnifyGesture().onChanged { zoom = min(max($0.magnification, 1), 4) }.onEnded { _ in zoom = 1 })
                        .onTapGesture(count: 2) { zoom = zoom == 1 ? 2 : 1 }
                        .clipped()
                }
            }.navigationTitle(asset.mediaType == .video ? "Video preview" : "Photo preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }.preferredColorScheme(.dark)
    }
}

struct PickerAnchor: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private struct ClipPreview: View {
    let asset: PHAsset
    @State private var player: AVPlayer?
    @State private var request: PHImageRequestID?
    @State private var generation = UUID()
    @State private var failed = false
    var body: some View {
        Group {
            if let player { VideoPlayer(player: player).accessibilityIdentifier("clipPlayer") }
            else if failed { ContentUnavailableView("Video unavailable", systemImage: "icloud.slash") }
            else { ProgressView("Loading video…") }
        }.onAppear {
            let token = UUID()
            generation = token
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            request = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                DispatchQueue.main.async {
                    guard generation == token else { return }
                    player = item.map(AVPlayer.init(playerItem:))
                    failed = item == nil
                }
            }
        }.onDisappear {
            generation = UUID()
            if let request { PHImageManager.default().cancelImageRequest(request) }
            player?.pause(); player = nil
        }
    }
}
