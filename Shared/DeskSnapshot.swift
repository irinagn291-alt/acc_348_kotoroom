import Foundation

struct MonthProgress: Codable, Equatable, Identifiable {
    let year: Int
    let month: Int
    let title: String
    let reviewed: Int
    let total: Int
    var id: String { "\(year)/\(month)" }
    var remaining: Int { max(0, total - reviewed) }
    var link: URL { URL(string: "piproom://month/\(id)")! }
}

struct DeskSnapshot: Codable, Equatable {
    static let widgetKind = "PiproomContactSheet"
    static let activity = "app.piproom.review"
    static let group = "group.app.piproom.iphone"
    static let home = URL(string: "piproom://desk")!
    static let empty = DeskSnapshot(focus: nil, candidates: [], binCount: 0)
    let focus: MonthProgress?
    let candidates: [MonthProgress]
    let binCount: Int

    static var sharedFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("desk-v1.json")
    }
    static func readShared() -> Self? {
        guard let url = sharedFile, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
