import XCTest
import CryptoKit
@testable import Piproom

final class ArchiveTests: XCTestCase {
    func testArchiveFailsClosedForCorruptMissingOrMisidentifiedChunks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = VaultFiles(root: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        try files.prepare()
        XCTAssertEqual(try dir.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let raw = dir.appendingPathComponent("original"), copy = dir.appendingPathComponent("sealed")
        let output = dir.appendingPathComponent("restore")
        let key = SymmetricKey(size: .bits256)
        let source = Data(repeating: 88, count: EncryptedArchive.chunkSize + 14)
        try source.write(to: raw)
        let integrity = try EncryptedArchive.encrypt(input: raw, output: copy, key: key, identity: "resource")
        try EncryptedArchive.decrypt(input: copy, output: output, key: key, identity: "resource", expected: integrity)
        XCTAssertEqual(try Data(contentsOf: output), source)
        try FileManager.default.removeItem(at: output)
        let encoded = try Data(contentsOf: copy)
        XCTAssertNil(encoded.range(of: source))
        XCTAssertThrowsError(try EncryptedArchive.decrypt(input: copy, output: output, key: key, identity: "another", expected: integrity))
        var altered = encoded
        altered[100] ^= 1
        for damaged in [altered, Data(encoded.dropLast()), Data(encoded.prefix(4 + EncryptedArchive.chunkSize + 28))] {
            try damaged.write(to: copy)
            XCTAssertThrowsError(try EncryptedArchive.decrypt(input: copy, output: output, key: key, identity: "resource", expected: integrity))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testPINThrottleSurvivesNewCredentialInstance() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = VaultFiles(root: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        try files.prepare()
        let credentials = try VaultCredentials(root: dir, catalog: files.catalog)
        let master = try credentials.create(pin: "682357")
        XCTAssertEqual(try credentials.unlock(pin: "682357"), master)
        for _ in 0..<3 { XCTAssertThrowsError(try credentials.unlock(pin: "000000")) }
        let reopened = try VaultCredentials(root: dir, catalog: files.catalog)
        XCTAssertThrowsError(try reopened.unlock(pin: "682357")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Too many attempts"))
        }
    }
}
