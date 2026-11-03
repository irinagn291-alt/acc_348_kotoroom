import Foundation

struct PasswordRecipe: Equatable {
    static let lengths = 12...64
    static let confusing = Set("Il1O0o|")
    var length = 20
    var digits = true
    var symbols = true
    var omitSimilar = true

    func generate() -> String {
        var groups = ["abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"]
        if digits { groups.append("0123456789") }
        if symbols { groups.append("!#$%&*+-=?@^_~|") }
        let pools = groups.map { group in group.filter { !omitSimilar || !Self.confusing.contains($0) } }
        let alphabet = Array(pools.joined())
        let count = min(max(length, Self.lengths.lowerBound), Self.lengths.upperBound)
        var rng = SystemRandomNumberGenerator()
        // Rejection keeps the distribution uniform over passwords satisfying every enabled group.
        while true {
            let candidate = (0..<count).map { _ in alphabet.randomElement(using: &rng)! }
            let used = Set(candidate)
            if pools.allSatisfy({ !used.isDisjoint(with: $0) }) { return String(candidate) }
        }
    }
}

enum NameStyle: String, CaseIterable { case business = "Business", short = "Short", random = "Random" }

enum EmailNames {
    private static let words = ["atlas", "cedar", "folio", "orbit", "maple", "ember", "wren", "drift", "cove", "lumen", "opal", "fern", "brook", "lark", "birch", "reef"]
    private static let business = ["mail", "notes", "desk", "studio", "office", "post", "work", "contact", "letters", "inbox"]

    static func suggestions(base: String, style: NameStyle) -> [String] {
        let latin = (String(base.prefix(80)).applyingTransform(.toLatin, reverse: false) ?? base)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let stem = String(latin.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(24))
        var output = [String]()
        while output.count < 5 {
            let root = stem.isEmpty ? words.randomElement()! : stem
            let idea: String
            switch style {
            case .business: idea = root + "." + business.randomElement()!
            case .short: idea = String(root.prefix(5)) + String(Int.random(in: 10...99))
            case .random: idea = root + "." + words.randomElement()! + String(Int.random(in: 10...999))
            }
            if !output.contains(idea) { output.append(idea) }
        }
        return output
    }

    static func domain(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, value.utf8.count <= 253, labels.allSatisfy({ part in
            !part.isEmpty && part.utf8.count <= 63 && part.first != "-" && part.last != "-" &&
            part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { return nil }
        return value
    }
}
