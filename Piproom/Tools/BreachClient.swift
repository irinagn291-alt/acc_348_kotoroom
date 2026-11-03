import Foundation
import CryptoKit

enum BreachFailure: LocalizedError {
    case invalidEmail, invalidReply, unavailable, offline, limited(Int?)
    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Enter a complete email address."
        case .invalidReply: return "The response could not be verified. Try again later."
        case .unavailable: return "Email lookup is unavailable right now. Try again later or open Have I Been Pwned."
        case .offline: return "Couldn’t complete the check. Check your connection and try again."
        case .limited(let seconds):
            if let seconds { return "Too many checks. Try again in \(seconds) seconds." }
            return "Too many checks. Please try again later."
        }
    }
}

struct Exposure: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let title: String
    let date: String?
    let classes: [String]
}

private final class NoLookupRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct BreachClient {
    static let website = URL(string: "https://haveibeenpwned.com/")!
    static let live: Self = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: NoLookupRedirect(), delegateQueue: nil)
        return Self(session: session, emailRelay: configuredRelay(Bundle.main.object(forInfoDictionaryKey: "PiproomEmailRangeURL") as? String))
    }()

    let session: URLSession
    let emailRelay: URL?

    static func configuredRelay(_ value: String?) -> URL? {
        guard let value, let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        return parts.url
    }
    static func email(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pair = value.split(separator: "@", omittingEmptySubsequences: false)
        let punctuation = Set("!#$%&'*+-/=?^_`{|}~.")
        guard pair.count == 2, value.utf8.count <= 254, !pair[0].isEmpty, pair[0].utf8.count <= 64,
              pair[0].first != ".", pair[0].last != ".", !pair[0].contains(".."),
              pair[0].allSatisfy({ $0.isLetter || $0.isNumber || punctuation.contains($0) }),
              !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }),
              EmailNames.domain(String(pair[1])) == String(pair[1]) else { return nil }
        return value
    }
    static func digest(_ value: String) -> String {
        Insecure.SHA1.hash(data: Data(value.utf8)).map { String(format: "%02X", $0) }.joined()
    }
    private static func validSuffix(_ value: some StringProtocol, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }

    func passwordCount(_ password: String) async throws -> Int {
        guard !password.isEmpty else { throw BreachFailure.invalidReply }
        let digest = Self.digest(password)
        var request = URLRequest(url: URL(string: "https://api.pwnedpasswords.com/range/" + digest.prefix(5))!)
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        let data = try await send(request)
        guard let text = String(data: data, encoding: .utf8) else { throw BreachFailure.invalidReply }
        let rows = text.split(whereSeparator: \.isNewline)
        guard !rows.isEmpty else { throw BreachFailure.invalidReply }
        var count = 0
        for row in rows {
            let fields = row.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2, Self.validSuffix(fields[0], length: 35),
                  let n = Int(fields[1]), n >= 0 else { throw BreachFailure.invalidReply }
            if fields[0].uppercased() == digest.dropFirst(5) { count = n }
        }
        return count
    }

    private struct RangeRow: Decodable { let hashSuffix: String; let websites: [String] }
    private struct CatalogRow: Decodable { let Name, Title, BreachDate: String; let DataClasses: [String] }

    private func matchedNames(for digest: String, at url: URL) async throws -> [String] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["prefix": String(digest.prefix(6))])
        let data = try await send(request)
        guard let rows = try? JSONDecoder().decode([RangeRow].self, from: data) else { throw BreachFailure.invalidReply }
        var names = Set<String>()
        for row in rows {
            guard Self.validSuffix(row.hashSuffix, length: 34) else { throw BreachFailure.invalidReply }
            if row.hashSuffix.uppercased() == digest.dropFirst(6) {
                guard !row.websites.isEmpty, row.websites.allSatisfy({ !$0.isEmpty }) else { throw BreachFailure.invalidReply }
                names.formUnion(row.websites)
            }
        }
        return names.sorted()
    }
    func emailBreaches(_ input: String) async throws -> [Exposure] {
        guard let normalized = Self.email(input) else { throw BreachFailure.invalidEmail }
        guard let emailRelay else { throw BreachFailure.unavailable }
        let names = try await matchedNames(for: Self.digest(normalized), at: emailRelay)
        guard !names.isEmpty else { return [] }
        // Fetch the same public catalog for every match, without revealing which breaches matched.
        let url = URL(string: "https://haveibeenpwned.com/api/v3/breaches")!
        let data = try? await send(URLRequest(url: url))
        try Task.checkCancellation()
        let catalog = data.flatMap { try? JSONDecoder().decode([CatalogRow].self, from: $0) } ?? []
        return names.map { name in
            let entry = catalog.first { $0.Name == name }
            return Exposure(name: name, title: entry?.Title ?? name, date: entry?.BreachDate, classes: entry?.DataClasses ?? [])
        }
    }

    private func send(_ input: URLRequest) async throws -> Data {
        var request = input
        request.setValue("KOTOROOM-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw BreachFailure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw BreachFailure.invalidReply }
        switch http.statusCode {
        case 200: return data
        case 429: throw BreachFailure.limited(http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        case 401, 403, 503: throw input.url == emailRelay ? BreachFailure.unavailable : BreachFailure.invalidReply
        default: throw BreachFailure.invalidReply
        }
    }
}
