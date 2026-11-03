import SwiftUI
import Photos

struct PreviewAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct ReviewScreen: View {
    @EnvironmentObject private var library: Library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let month: PhotoMonth
    let basket: () -> Void
    let months: () -> Void
    @State private var loadedPhoto: String?
    @State private var drag: CGFloat = 0
    @State private var preview: PreviewAsset?
    private let threshold: CGFloat = 66

    var body: some View {
        let total = library.photos(month).count
        let left = library.remaining(month)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SmallPrint("Contact sheet / Review").foregroundStyle(Color.faded)
                Spacer()
                Button(action: basket) {
                    Label("\(library.basket.count)", systemImage: "tray").font(.subheadline.monospacedDigit().bold()).padding(8)
                }.accessibilityLabel("Review bin, \(library.basket.count)").accessibilityIdentifier("reviewBasket")
            }
            Text(month.title).font(.system(.largeTitle, design: .serif).weight(.medium))
            if library.paused || !library.hasAccess {
                Text("Review is paused. Check access to Photos and your protected albums.")
                Spacer()
            } else if let photo = library.next(in: month) {
                HStack {
                    Text("\(total-left) / \(total)").font(.subheadline.monospacedDigit()).accessibilityIdentifier("progress")
                    ContactMeter(reviewed: total-left, total: total, tint: .paper)
                }
                GeometryReader { frame in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)).padding(.horizontal, 12).offset(y: 5)
                        AssetImage(asset: photo, pixels: 1440, fit: true, didLoad: { loadedPhoto = $0 })
                            .overlay(alignment: .topLeading) {
                                if abs(drag) > 16 {
                                    Label(drag > 0 ? "Keep" : "Bin", systemImage: drag > 0 ? "checkmark" : "tray")
                                        .font(.headline).padding(10).background(drag > 0 ? Color.felt : Color.enamel, in: Capsule()).padding()
                                }
                            }.clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.paper.opacity(0.45)))
                            .offset(x: reduceMotion ? 0 : drag * 0.65)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 9)
                                .onChanged { point in
                                    guard abs(point.translation.width) > abs(point.translation.height) else { drag = 0; return }
                                    drag = min(max(point.translation.width, -frame.size.width), frame.size.width)
                                }
                                .onEnded { point in
                                    let dx = point.translation.width
                                    if loadedPhoto == photo.localIdentifier && abs(dx) >= threshold && abs(dx) > abs(point.translation.height) {
                                        library.choose(photo, dx > 0 ? .keep : .basket, in: month)
                                    }
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { drag = 0 }
                                })
                            .onTapGesture { preview = PreviewAsset(asset: photo) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Photo. Open preview")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { preview = PreviewAsset(asset: photo) }
                            .accessibilityIdentifier("photoCard")
                            .transition(reduceMotion ? .identity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                            .id(photo.localIdentifier)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: photo.localIdentifier)
                .sensoryFeedback(.selection, trigger: abs(drag) >= threshold) { _, crossed in crossed }
                Text(photo.creationDate?.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "en_US"))) ?? "Undated")
                    .font(.footnote).foregroundStyle(Color.faded)
                HStack {
                    Button { library.choose(photo, .basket, in: month) } label: {
                        Label("Bin", systemImage: "tray").frame(maxWidth: .infinity)
                            .padding(.vertical, 14).background(Color.enamel, in: RoundedRectangle(cornerRadius: 12))
                    }.accessibilityIdentifier("queue")
                    Button { library.choose(photo, .keep, in: month) } label: {
                        Label("Keep", systemImage: "checkmark").frame(maxWidth: .infinity)
                            .padding(.vertical, 14).foregroundStyle(Color.ink).background(Color.paper, in: RoundedRectangle(cornerRadius: 12))
                    }.accessibilityIdentifier("keep")
                }.font(.subheadline.bold()).disabled(loadedPhoto != photo.localIdentifier || library.loading || library.deleting)
                undo
            } else if library.loading {
                ProgressView("Reading your library…"); Spacer()
            } else {
                Spacer()
                PaperCard {
                    Die().frame(width: 64, height: 64)
                    Text("Month complete").font(.system(.title, design: .serif).bold()).accessibilityIdentifier("monthDone")
                    Text("Kept: \(library.count(month, .keep))   ·   In bin: \(library.count(month, .basket))")
                    Button(action: basket) { PrimaryLabel(text: "Open review bin", icon: "tray") }
                    Button("Back to months", action: months).frame(maxWidth: .infinity, minHeight: 44)
                }
                undo
                Spacer()
            }
        }.padding(.horizontal, 20).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.graphite.ignoresSafeArea()).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { PhotoPreview(asset: $0.asset) }
    }
    private var undo: some View {
        Button { library.undo(month) } label: {
            Label("Undo last swipe", systemImage: "arrow.uturn.backward")
                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
        }.disabled(library.lastSwipe(month) == nil || library.loading || library.deleting).accessibilityIdentifier("undo")
    }
}
