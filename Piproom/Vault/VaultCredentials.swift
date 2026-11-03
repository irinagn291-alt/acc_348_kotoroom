import CryptoKit
import CommonCrypto
import LocalAuthentication
import Security

/// The PIN unwraps a random vault key. The optional biometric copy has its own Keychain ACL.
struct VaultCredentials {
    private struct Envelope: Codable {
        let salt: Data
        let rounds: UInt32
        let wrapped: Data
        var failures = 0
        var nextAttempt = Date.distantPast
    }
    private let service: String
    init(root: URL, catalog: URL) throws {
        let marker = root.appendingPathComponent("installation")
        let id: UUID
        if FileManager.default.fileExists(atPath: marker.path) {
            let data = try Data(contentsOf: marker)
            guard let value = UUID(uuidString: String(decoding: data, as: UTF8.self)) else {
                throw VaultError("The vault identity could not be read.")
            }
            id = value
        } else {
            guard !FileManager.default.fileExists(atPath: catalog.path) else { throw VaultError("The vault identity is missing.") }
            id = UUID()
            try Data(id.uuidString.utf8).write(to: marker, options: [.atomic, .completeFileProtection])
        }
        service = "app.piproom.iphone.vault." + id.uuidString
    }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    private func read(_ account: String, context: LAContext? = nil) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        if let context { q[kSecUseAuthenticationContext as String] = context }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw VaultError("The device key is unavailable. Unlock this iPhone and try your vault PIN.")
        }
        return data
    }
    private func save(_ record: Envelope, create: Bool = false) throws {
        var q = query("pin")
        let value = try JSONEncoder().encode(record)
        let status: OSStatus
        if create {
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            q[kSecValueData as String] = value
            status = SecItemAdd(q as CFDictionary, nil)
        } else {
            status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        }
        guard status == errSecSuccess else { throw VaultError("Could not save the vault credential on this iPhone.") }
    }
    var configured: Bool { get throws { try read("pin") != nil } }
    private func wrappingKey(_ pin: String, salt: Data, rounds: UInt32) throws -> SymmetricKey {
        let digits = Array(pin.utf8)
        guard digits.count == 6, digits.allSatisfy({ (48...57).contains($0) }) else {
            throw VaultError("Enter all six digits of your Secret Folder PIN.")
        }
        var output = [UInt8](repeating: 0, count: 32)
        let status = digits.withUnsafeBytes { pass in
            salt.withUnsafeBytes { bytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.bindMemory(to: Int8.self).baseAddress!, digits.count,
                                     bytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds, &output, 32)
            }
        }
        guard status == kCCSuccess else { throw VaultError("Could not unlock the vault key.") }
        return SymmetricKey(data: Data(output))
    }
    func create(pin: String) throws -> SymmetricKey {
        let master = SymmetricKey(size: .bits256)
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let rounds: UInt32 = 600_000
        let wrap = try wrappingKey(pin, salt: salt, rounds: rounds)
        let bytes = master.withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(bytes, using: wrap, authenticating: Data(service.utf8))
        guard let wrapped = box.combined else { throw VaultError("Could not protect the vault key.") }
        try save(Envelope(salt: salt, rounds: rounds, wrapped: wrapped), create: true)
        return master
    }
    func unlock(pin: String) throws -> SymmetricKey {
        guard let encoded = try read("pin") else { throw VaultError("The PIN credential is unavailable.") }
        var record = try JSONDecoder().decode(Envelope.self, from: encoded)
        let wait = record.nextAttempt.timeIntervalSinceNow
        guard wait <= 0 else { throw VaultError("Too many attempts. Try again in \(Int(ceil(wait))) seconds.") }
        let key = try wrappingKey(pin, salt: record.salt, rounds: record.rounds)
        // Persist the attempt first so quitting mid-check does not reset the delay.
        record.failures = min(16, record.failures + 1)
        if record.failures >= 3 {
            record.nextAttempt = Date().addingTimeInterval(min(3600, 5 * pow(2, Double(record.failures - 3))))
        }
        try save(record)
        guard let master = try? AES.GCM.open(AES.GCM.SealedBox(combined: record.wrapped), using: key, authenticating: Data(service.utf8)), master.count == 32 else {
            throw VaultError("That PIN didn’t match. Try your Secret Folder PIN.")
        }
        record.failures = 0; record.nextAttempt = .distantPast
        try save(record)
        return SymmetricKey(data: master)
    }

    // Attribute-only lookup does not prompt for Face ID. The data lookup below does.
    var hasFaceKey: Bool {
        var q = query("face")
        q[kSecReturnAttributes as String] = true
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
    func disableFaceID() throws {
        let status = SecItemDelete(query("face") as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError("Could not change Face ID access.") }
    }
    func registerFaceID(_ key: SymmetricKey, context: LAContext) throws {
        var error: Unmanaged<CFError>?
        guard let acl = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error) else {
            throw VaultError("Face ID is unavailable. Use your PIN.")
        }
        try disableFaceID()
        var q = query("face")
        q[kSecAttrAccessControl as String] = acl
        q[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        q[kSecUseAuthenticationContext as String] = context
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw VaultError("Could not enable Face ID. Your PIN still works.") }
    }
    func unlockFaceID(context: LAContext) throws -> SymmetricKey {
        guard let data = try read("face", context: context), data.count == 32 else {
            throw VaultError("Face ID has changed. Unlock with your vault PIN to enable it again.")
        }
        return SymmetricKey(data: data)
    }
}
