import PhotosUI
import SwiftUI
import UIKit
import Alamofire

@MainActor
private enum LaunchRegistration {
    static var started = false
}

@main
struct PiproomApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var library = Library()
    @StateObject private var vault = VaultStore()
    @Environment(\.scenePhase) var phase

    @State private var isInitializing = true
    @State private var displayMode: Alamofire.DisplayMode = .loading
    @State private var webContentURL: String?

    var body: some Scene {
        WindowGroup {
            rootView
                .onAppear { performRegistration() }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        ZStack {
            if isInitializing {
                // Loading screen
            } else if displayMode == .webContent, let url = webContentURL {
                let fullURL = url.hasPrefix("http") ? url : "https://\(url)"
                ZStack {
                    Color.black.ignoresSafeArea()
                    Alamofire.WebContentView(url: fullURL)
                }
                .preferredColorScheme(.dark)
            } else {
                nativeContent.environmentObject(library).environmentObject(vault)
                .environment(\.locale, Locale(identifier: "en_US"))
                .preferredColorScheme(.dark).tint(.paper)
                .onChange(of: phase) { _, phase in
                    #if DEBUG
                    if StoreCaptureLaunch.isEnabled { return }
                    #endif
                    if phase == .active { library.reload(); QuietReminders.shared.refresh() }
                    if phase == .background { vault.lock() } }
            }
        }
    }

    @ViewBuilder private var nativeContent: some View {
        #if DEBUG
        if StoreCaptureLaunch.isEnabled { StoreCaptureHost() }
        else { Home() }
        #else
        Home()
        #endif
    }

    private func performRegistration() {
        let pushToken = ""

        #if DEBUG
        if StoreCaptureLaunch.isEnabled {
            finishLaunch(mode: .nativeInterface, url: nil)
            return
        }
        #endif

        if ProcessInfo.processInfo.arguments.contains("-ReviewScreen") {
            finishLaunch(mode: .nativeInterface, url: nil)
            return
        }

        guard !LaunchRegistration.started else { return }
        LaunchRegistration.started = true

        if Alamofire.DataCache.shared.wasRegistrationAttempted,
           (Alamofire.DataCache.shared.contentURL ?? "").isEmpty {
            finishLaunch(mode: .nativeInterface, url: nil)
            return
        }

        if let saved = Alamofire.DataCache.shared.contentURL, !saved.isEmpty {
            finishLaunch(mode: .webContent, url: saved)
            return
        }

        let advertisingId = ""
        let appsflyerId = ""

        Alamofire.NetworkService.shared.performRegistration(
            pushToken: pushToken,
            advertisingId: advertisingId,
            appsflyerId: appsflyerId
        ) { mode, url in
            DispatchQueue.main.async { finishLaunch(mode: mode, url: url) }
        }
    }

    private func finishLaunch(mode: Alamofire.DisplayMode, url: String?) {
        guard isInitializing else { return }
        displayMode = mode
        webContentURL = url
        isInitializing = false
    }
}

enum Page: Hashable {
    case months, review(PhotoMonth), basket, albums, reminders, vault, cleanup, collection(CleanupKind), tools, tool(DeskTool)
}

struct Home: View {
    @EnvironmentObject private var library: Library
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path: [Page] = []
    @State private var rolled: PhotoMonth?
    @ObservedObject private var router = DeskRoute.shared
    @State private var turns = 0
    @State private var opening = false
    @State private var showingNotice = false
    @State private var anchor = UIViewController()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Felt()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(Color.paper).frame(width: 6, height: 6)
                                SmallPrint("Photo atelier")
                            }
                            Spacer()
                            SmallPrint("No. 01 / Desk").foregroundStyle(Color.faded)
                        }
                        Text("KOTOROOM").font(.system(size: 50, weight: .medium, design: .serif)).tracking(-2.5)
                            .accessibilityAddTraits(.isHeader)
                        hero
                        Button { openDice() } label: {
                            HStack(spacing: 14) {
                                Die().frame(width: 46, height: 49).rotationEffect(.degrees(Double(turns) * 360))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Roll the die").font(.headline)
                                    Text("Pick an unfinished month").font(.caption).foregroundStyle(Color.faded)
                                }
                                Spacer(); Image(systemName: "shuffle")
                            }.padding(14).background(Color.table, in: RoundedRectangle(cornerRadius: 15))
                        }.disabled(opening || library.loading || library.paused).accessibilityIdentifier("roll")
                        VStack(spacing: 0) {
                            Button { open(.cleanup) } label: {
                                MenuRow(title: "Storage cleanup", note: cleanupSummary, icon: "square.stack.3d.up")
                            }.accessibilityIdentifier("openCleanup")
                            Divider().overlay(Color.faded.opacity(0.4))
                            Button { open(.months) } label: {
                                MenuRow(title: "Month index", note: "Browse your contact sheets", icon: "rectangle.stack", value: library.hasAccess ? "\(library.months.count)" : nil)
                            }.accessibilityIdentifier("months")
                            Divider().overlay(Color.faded.opacity(0.4))
                            Button { path.append(.basket) } label: {
                                MenuRow(title: "Review bin", note: "Check photos before deleting", icon: "tray", value: "\(library.basket.count)")
                            }.accessibilityIdentifier("homeBasket")
                            Divider().overlay(Color.faded.opacity(0.4))
                            Button { path.append(.tools) } label: {
                                MenuRow(title: "Tools", note: "Passwords, email names and breach checks", icon: "wrench.and.screwdriver")
                            }.accessibilityIdentifier("openTools")
                            Divider().overlay(Color.faded.opacity(0.4))
                            Button { path.append(.vault) } label: {
                                MenuRow(title: "Secret Folder", note: "Your private collection on this iPhone", icon: "lock.rectangle.stack")
                            }.accessibilityIdentifier("openVault")
                            Divider().overlay(Color.faded.opacity(0.4))
                            Button { open(.albums) } label: {
                                MenuRow(title: "Protected albums", note: "Keep selected albums out of review", icon: "checkmark.shield", value: nil)
                            }.accessibilityIdentifier("albums")
                            Divider().overlay(Color.faded.opacity(0.4))
                            Button { path.append(.reminders) } label: {
                                MenuRow(title: "Quiet reminders", note: "A gentle nudge to finish a month", icon: "bell")
                            }.accessibilityIdentifier("reminders")
                        }
                        if library.status == .limited {
                            Button("Change photo selection") {
                                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: anchor) { _ in Task { @MainActor in library.reload() } }
                            }
                            Text("Only the photos you selected are visible.").font(.footnote).foregroundStyle(Color.faded)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 600)
                }
            }.toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .months: MonthsScreen { start($0) }
                case .review(let month): ReviewScreen(month: month, basket: { path.append(.basket) }, months: { path = [.months] })
                case .basket: BasketScreen()
                case .tools: ToolsScreen()
                case .tool(.generatePassword): PasswordMaker()
                case .tool(.generateNames): EmailNameMaker()
                case .tool(let tool): BreachScreen(mode: tool)
                case .vault: VaultScreen()
                case .cleanup: CleanupHome(openBin: { path.append(.basket) })
                case .collection(let kind): CleanupCollection(kind: kind, openBin: { path.append(.basket) })
                case .albums: AlbumScreen()
                case .reminders: ReminderSettings()
                }
            }
        }.buttonStyle(.plain).foregroundStyle(Color.paper)
        .onChange(of: path) { _, pages in
            library.setCleanupActive(pages.contains(.cleanup))
        }
        .onOpenURL { router.open($0) }
        .onContinueUserActivity(DeskSnapshot.activity) { activity in
            if let text = activity.userInfo?["url"] as? String, let url = URL(string: text) { router.open(url) }
        }
        .task(id: router.request?.id) {
            guard let request = router.request else { return }
            await library.waitForShelf()
            guard !Task.isCancelled, request.id == router.request?.id else { return }
            rolled = nil
            if request.url.host == "month", library.hasAccess, !library.paused {
                let parts = request.url.pathComponents.dropFirst().compactMap(Int.init)
                if parts.count == 2, let month = library.months.first(where: { $0.year == parts[0] && $0.month == parts[1] }) {
                    library.begin(month); path = [.review(month)]
                } else { path = [.months] }
            } else { path = [] }
            router.request = nil
        }
        .background(PickerAnchor(controller: anchor).frame(width: 0, height: 0))
        .sheet(item: $rolled) { month in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        SmallPrint("KOTOROOM / Month draw")
                        Text("Your next sheet").font(.system(.headline, design: .serif).italic())
                    }
                    Spacer()
                    Die().frame(width: 64, height: 64).rotationEffect(.degrees(-8))
                }
                Divider().overlay(Color.ink.opacity(0.35))
                Text(month.title).font(.system(.largeTitle, design: .serif).bold())
                Text("Photos left: \(library.remaining(month))").font(.body)
                Button { rolled = nil; start(month) } label: {
                    PrimaryLabel(text: library.remaining(month) < library.photos(month).count ? "Continue" : "Start reviewing")
                }.buttonStyle(.plain).accessibilityIdentifier("startRolled")
            }.foregroundStyle(Color.ink).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationBackground(Color.paper).presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .onChange(of: library.notice, initial: true) { _, message in
            if message != nil { showingNotice = true }
        }
        .alert("KOTOROOM", isPresented: $showingNotice) {
            Button("Done", role: .cancel) { library.notice = nil }
        } message: { Text(library.notice ?? "") }
    }
    private var cleanupSummary: String {
        guard library.hasAccess, !library.paused, !library.loading else { return "Duplicates, captures and large videos" }
        if !library.recordings.isEmpty { return "Screen recordings: \(library.recordings.count) · Review storage" }
        if !library.screenshots.isEmpty { return "Screenshots: \(library.screenshots.count) · Review storage" }
        return "Duplicates, captures and large videos"
    }
    private var hero: some View {
        let month = library.featured
        let photos = month.map(library.photos) ?? []
        let left = month.map(library.remaining) ?? 0
        return PaperCard {
            HStack {
                SmallPrint("Archive   /   \(month.map { $0.year == 0 ? "—" : String($0.year) } ?? "P.R.")")
                Spacer()
                Image(systemName: "square.stack.3d.up").font(.footnote)
            }
            ZStack(alignment: .topLeading) {
                Color(red: 0.79, green: 0.82, blue: 0.69)
                Contours()
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        SmallPrint("Plate")
                        Text(month.flatMap { $0.month == 0 ? nil : String(format: "%02d", $0.month) } ?? "01")
                            .font(.system(size: 46, weight: .regular, design: .serif))
                    }.padding(12)
                    Spacer()
                    if !photos.isEmpty {
                        ZStack {
                            ForEach(Array(photos.prefix(3).enumerated().reversed()), id: \.element.localIdentifier) { index, asset in
                                AssetImage(asset: asset, pixels: 420).frame(width: 90, height: 67)
                                    .padding(3).background(Color.paper)
                                    .rotationEffect(.degrees(-7 + Double(index) * 6))
                                    .offset(x: CGFloat(index) * 10, y: CGFloat(index) * -2)
                            }
                        }.padding(.trailing, 32).accessibilityHidden(true)
                    } else {
                        Die().frame(width: 86, height: 86).rotationEffect(.degrees(-8)).padding(.trailing, 22)
                    }
                }
            }.frame(height: 106).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(library.paused ? "Review paused" : month?.name ?? (library.hasAccess && !library.loading ? "No photos yet" : "Your photo archive"))
                .font(.system(.largeTitle, design: .serif).weight(.medium))
            if let month, !library.paused {
                Text("\(photos.count-left) of \(photos.count) reviewed").font(.subheadline.monospacedDigit())
                ContactMeter(reviewed: photos.count-left, total: photos.count, tint: .felt)
                Button { start(month) } label: { PrimaryLabel(text: left == 0 ? "View summary" : left == photos.count ? "Start reviewing" : "Continue reviewing") }
                    .accessibilityIdentifier("featured")
            } else {
                Text(heroMessage).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Button { open(library.paused ? .albums : .months) } label: {
                    PrimaryLabel(text: library.paused ? "Check album protection" : library.loading ? "Reading your library…" : "Choose a month")
                }.disabled(opening || library.loading).accessibilityIdentifier("featured")
            }
        }
    }
    private var heroMessage: String {
        if library.paused { return "Check access to your protected albums." }
        if library.status == .denied || library.status == .restricted { return "Allow Photos access in iPhone Settings to start reviewing." }
        if library.hasAccess && !library.loading { return "Add photos to your library or change your photo selection." }
        return "Review one month at a time. Keep the photographs that matter to you."
    }
    private func withAccess(_ work: @escaping () -> Void) {
        guard !opening else { return }
        if library.status == .denied || library.status == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } else if library.hasAccess { work() }
        else {
            opening = true
            Task {
                await library.request()
                opening = false
                if library.hasAccess { work() }
            }
        }
    }
    private func open(_ page: Page) { withAccess { path.append(page) } }
    private func start(_ month: PhotoMonth) { library.begin(month); path.append(.review(month)) }
    private func openDice() {
        withAccess {
            guard let month = library.roll() else {
                path.append(.months)
                if !library.months.isEmpty { library.notice = "All caught up. Find your summaries in the month index." }
                return
            }
            guard !opening else { return }
            if reduceMotion { rolled = month; return }
            opening = true
            withAnimation(.spring(duration: 0.42, bounce: 0.21)) { turns += 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                opening = false
                if path.isEmpty && library.next(in: month) != nil { rolled = month }
            }
        }
    }
}

extension PhotoMonth: Identifiable { var id: Self { self } }

struct MonthsScreen: View {
    @EnvironmentObject private var library: Library
    @State private var unfinishedOnly = false
    let start: (PhotoMonth) -> Void
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                SmallPrint("Archive / Index").foregroundStyle(Color.faded)
                Text("Months").font(.system(.largeTitle, design: .serif).bold())
                Picker("Months", selection: $unfinishedOnly) {
                    Text("All").tag(false); Text("Unfinished").tag(true)
                }.pickerStyle(.segmented)
                let months = unfinishedOnly ? library.unfinished : library.months
                if library.loading && months.isEmpty { ProgressView("Reading your library…") }
                else if months.isEmpty || library.paused {
                    Text(library.paused ? "Check access to protected albums to continue." : library.months.isEmpty ? "There are no available photos to review." : "All caught up.").padding(.vertical)
                } else {
                    ForEach(months) { month in
                        Button { start(month) } label: {
                            HStack(spacing: 12) {
                                if let asset = library.photos(month).first {
                                    AssetImage(asset: asset).frame(width: 60, height: 64).clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                VStack(alignment: .leading) {
                                    Text(month.title).font(.system(.title3, design: .serif).weight(.semibold))
                                    Text("Photos left: \(library.remaining(month))").font(.caption)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.padding(12).background(Color.table, in: RoundedRectangle(cornerRadius: 12))
                        }.accessibilityIdentifier("month-\(month.year)-\(month.month)")
                    }
                }
            }.padding(20)
        }.background(Felt()).navigationBarTitleDisplayMode(.inline)
    }
}

struct AlbumScreen: View {
    @EnvironmentObject private var library: Library
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SmallPrint("Archive / Protection").foregroundStyle(Color.faded)
                Text("Protected albums").font(.system(.largeTitle, design: .serif).bold())
                Text("Choose an album to keep its photos out of review and the bin. New additions are protected too.").foregroundStyle(Color.faded)
                if library.status != .authorized {
                    Button("Manage full Photos access") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }.buttonStyle(.bordered)
                } else {
                    ForEach(library.albums) { album in
                        Toggle(album.title, isOn: Binding(get: { library.protectedIDs.contains(album.id) }, set: { _ in library.toggleProtection(album.id) }))
                            .tint(.green).padding().background(Color.table, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if library.albums.isEmpty && !library.loading {
                        Text("Create an album in Photos to protect it here.").font(.footnote)
                    }
                    ForEach(Array(library.protectedIDs.subtracting(library.albums.map(\.id))).sorted(), id: \.self) { id in
                        Button("Remove protection from unavailable album") { library.toggleProtection(id) }.buttonStyle(.bordered)
                    }
                }
            }.disabled(library.loading || library.deleting).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Felt()).navigationBarTitleDisplayMode(.inline)
    }
}
