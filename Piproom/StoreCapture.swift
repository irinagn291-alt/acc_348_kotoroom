#if DEBUG
import SwiftUI
import UIKit

/// Mount existing destinations directly so iPad never captures a pending push.
struct StoreCaptureHost: View {
    @EnvironmentObject private var library: Library
    @State private var ready = false

    var body: some View {
        ZStack {
            Felt()
            if ready {
                VStack(spacing: 0) {
                    if StoreCaptureLaunch.key != "photo-desk" {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("KOTOROOM").font(.subheadline)
                            Spacer()
                        }.padding(.horizontal, 20).padding(.vertical, 9)
                    }
                    destination
                }
                .frame(maxWidth: StoreCaptureLaunch.key == "monthly-review" ? 780 : 720, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.paper)
        .transaction { $0.disablesAnimations = true }
        .task {
            UIView.setAnimationsEnabled(false)
            await library.prepareStoreCapture()
            ready = true
        }
    }

    @ViewBuilder private var destination: some View {
        switch StoreCaptureLaunch.key {
        case "photo-desk":
            Home()
        case "month-index":
            MonthsScreen(start: { _ in })
        case "monthly-review":
            if let month = library.featured {
                ReviewScreen(month: month, basket: {}, months: {})
            } else {
                Text("Seed Photos before capturing monthly-review.")
            }
        case "storage-cleanup":
            CleanupHome(openBin: {})
        case "review-bin":
            BasketScreen()
        case "password-generator":
            PasswordMaker()
        default:
            Text("Unknown review route: \(StoreCaptureLaunch.key)")
        }
    }
}
#endif
