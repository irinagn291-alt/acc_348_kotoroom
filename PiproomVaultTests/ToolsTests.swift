import XCTest
@testable import Piproom

final class ToolsTests: XCTestCase {
    func testOfflineRecipesFollowEverySwitch() {
        for length in [12, 20, 64] {
            for digits in [false, true] {
                for symbols in [false, true] {
                    let recipe = PasswordRecipe(length: length, digits: digits, symbols: symbols, omitSimilar: true)
                    for _ in 0..<12 {
                        let value = recipe.generate()
                        XCTAssertEqual(value.count, length)
                        XCTAssertTrue(value.contains(where: \.isLowercase))
                        XCTAssertTrue(value.contains(where: \.isUppercase))
                        XCTAssertEqual(value.contains(where: \.isNumber), digits)
                        XCTAssertEqual(value.contains { !$0.isLetter && !$0.isNumber }, symbols)
                        XCTAssertTrue(Set(value).isDisjoint(with: PasswordRecipe.confusing))
                    }
                }
            }
        }
        XCTAssertEqual(PasswordRecipe().generate().count, 20)
        for base in ["", " Marina !", "Марина", ".....", String(repeating: "z", count: 120)] {
            for style in NameStyle.allCases {
                let names = EmailNames.suggestions(base: base, style: style)
                XCTAssertEqual(Set(names).count, 5)
                for name in names {
                    XCTAssertEqual(BreachClient.email(name + "@example.com"), name + "@example.com")
                    if base == "Марина" { XCTAssertTrue(name.hasPrefix(style == .short ? "marin" : "marina")) }
                }
            }
        }
        XCTAssertEqual(EmailNames.domain(" Example.COM "), "example.com")
        XCTAssertNil(EmailNames.domain("bad..com"))
        XCTAssertNil(BreachClient.email("a b@example.com"))
        XCTAssertNil(BreachClient.configuredRelay("http://example.com/range"))
        XCTAssertNil(BreachClient.configuredRelay("https://secret@example.com/range"))
        XCTAssertNil(BreachClient.configuredRelay("$(PIPROOM_HIBP_PROXY_URL)"))
    }

    private let relay = URL(string: "https://relay.example/v1/email-range")!
    private func client(_ handler: @escaping (URLRequest) throws -> (Int, [String: String], String)) -> BreachClient {
        ToolsURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ToolsURLProtocol.self]
        return BreachClient(session: URLSession(configuration: config), emailRelay: relay)
    }

    func testPasswordRangeSendsOnlyFiveCharactersAndIgnoresPadding() async throws {
        let suffix = "1E4C9B93F3F0682250B6CF8331B7EE68FD8"
        for count in [0, 42] {
            let service = client { req in
                XCTAssertEqual(req.httpMethod, "GET")
                XCTAssertEqual(req.url?.absoluteString, "https://api.pwnedpasswords.com/range/5BAA6")
                XCTAssertEqual(req.value(forHTTPHeaderField: "Add-Padding"), "true")
                XCTAssertNil(req.httpBody); XCTAssertNil(req.httpBodyStream)
                XCTAssertNil(req.value(forHTTPHeaderField: "hibp-api-key"))
                return (200, [:], String(repeating: "0", count: 35) + ":0\r\n" + suffix + ":\(count)\r\n")
            }
            let result = try await service.passwordCount("password")
            XCTAssertEqual(result, count)
        }
    }

    func testEmailRangeMatchesLocallyAndAddsOnlyMatchingBreachDetails() async throws {
        let address = " Multiple-Breaches@hibp-integration-tests.com "
        let suffix = "C6C0AADE0C085843D66E4944E108C4A4CD"
        let endpoint = relay
        let service = client { req in
            if req.url == endpoint {
                XCTAssertEqual(req.httpMethod,"POST")
                let body = try JSONDecoder().decode([String: String].self, from: ToolsURLProtocol.body(req))
                XCTAssertEqual(body, ["prefix": "6B5917"])
                XCTAssertNil(req.value(forHTTPHeaderField: "hibp-api-key"))
                return (200, [:], """
                [{"hashSuffix":"\(suffix)","websites":["Adobe","CatalogMissing"]},{"hashSuffix":"\(String(repeating: "0", count: 34))","websites":["Unrelated"]}]
                """)
            }
            XCTAssertEqual(req.url?.absoluteString, "https://haveibeenpwned.com/api/v3/breaches")
            return (200, [:], #"[{"Name":"Adobe","Title":"Adobe","BreachDate":"2013-10-04","DataClasses":["Passwords"]}]"#)
        }
        let rows = try await service.emailBreaches(address)
        XCTAssertEqual(rows.map(\.name), ["Adobe", "CatalogMissing"])
        XCTAssertEqual(rows.first?.date, "2013-10-04")
        XCTAssertEqual(rows.first?.classes, ["Passwords"])
    }

    func testMissErrorsAndIncompleteRepliesRemainDistinct() async throws {
        let endpoint = relay
        let clean = client { req in
            XCTAssertEqual(req.url, endpoint)
            return (200, [:], "[{\"hashSuffix\":\"\(String(repeating: "0", count: 34))\",\"websites\":[\"Other\"]}]")
        }
        let result = try await clean.emailBreaches("nobody@example.com")
        XCTAssertTrue(result.isEmpty)
        let limited = client { _ in (429, ["Retry-After":"19"], "") }
        do { _ = try await limited.passwordCount("example"); XCTFail() }
        catch BreachFailure.limited(let seconds) { XCTAssertEqual(seconds,19) }
        let broken = client { _ in (200, [:], "broken:0") }
        do { _ = try await broken.passwordCount("example"); XCTFail() }
        catch BreachFailure.invalidReply {}
        let unauthorized = client { _ in (403, [:], "{}") }
        do { _ = try await unauthorized.emailBreaches("nobody@example.com"); XCTFail() }
        catch BreachFailure.unavailable {}
        let offline = client { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await offline.passwordCount("example"); XCTFail() }
        catch BreachFailure.offline {}
    }
}

private final class ToolsURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String:String], String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, headers, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func body(_ req: URLRequest) -> Data {
        if let body = req.httpBody { return body }
        guard let stream = req.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 256)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
