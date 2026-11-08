#if DEBUG
import Foundation

/// The single capture route shared by the iOS and Watch targets.
enum StoreCaptureLaunch {
    static let keys = ["photo-desk", "month-index", "monthly-review", "storage-cleanup", "review-bin", "password-generator"]

    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-ReviewScreen") || args.contains("-AppStoreScreenshots") || env["APPSTORE_SCREENSHOTS"] == "1"
    }

    static var key: String {
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-ReviewScreen"), args.indices.contains(flag + 1) {
            return args[flag + 1]
        }
        let index: Int
        if let flag = args.firstIndex(of: "-AppStoreScreenshotScreen"), args.indices.contains(flag + 1) {
            index = Int(args[flag + 1]) ?? 0
        } else {
            index = Int(ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOT_SCREEN"] ?? "") ?? 0
        }
        return keys.indices.contains(index) ? keys[index] : "unknown-\(index)"
    }
}
#endif
