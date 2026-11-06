import Security
import XCTest
@testable import SearcheXtra

final class VaultProtocolTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "vault-protocol-\(getpid())", 1)
        super.setUp()
    }

    func testSameAccountOverHTTPAndHTTPSKeepsSeparateSecrets() throws {
        guard Store.testing else { throw XCTSkip("Requires an isolated test world") }
        let host = "vault-\(UUID().uuidString).example", user = "fixture"
        defer {
            Vault.forget(host: host, user: user, clear: false)
            Vault.forget(host: host, user: user, clear: true)
        }
        guard Vault.save(host: host, user: user, password: "secure", clear: false),
              Vault.save(host: host, user: user, password: "plain", clear: true) else {
            throw XCTSkip("The test process cannot write to its keychain")
        }
        let rows = Vault.kept(for: host)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
        for row in rows {
            XCTAssertEqual(Vault.secret(of: row), row.clear ? "plain" : "secure")
        }
        // Manually-created metadata has no persistent reference either.
        XCTAssertEqual(Vault.secret(of: Kept(host: host, user: user, used: nil, clear: true)), "plain")
        XCTAssertEqual(Vault.secret(of: Kept(host: host, user: user, used: nil)), "secure")
        Vault.forget(host: host, user: user, clear: true)
        XCTAssertEqual(Vault.kept(for: host).count, 1)
        XCTAssertEqual(Vault.login(try XCTUnwrap(Vault.kept(for: host).first))?.password, "secure")
    }

    func testOlderProtocolLessItemIsReadByItsExactReference() throws {
        guard Store.testing, let world = Store.world else { throw XCTSkip("Requires an isolated test world") }
        let host = "legacy-vault-\(UUID().uuidString).example"
        let identity: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: "fixture",
            kSecAttrLabel as String: "Search (\(world))",
        ]
        defer { SecItemDelete(identity as CFDictionary) }
        var record = identity
        record[kSecValueData as String] = Data("legacy".utf8)
        guard SecItemAdd(record as CFDictionary, nil) == errSecSuccess else {
            throw XCTSkip("The test process cannot write to its keychain")
        }
        let kept = try XCTUnwrap(Vault.kept(for: host).first)
        XCTAssertNotNil(kept.reference)
        XCTAssertFalse(kept.clear)
        XCTAssertEqual(Vault.secret(of: kept), "legacy")
        Vault.touch(try XCTUnwrap(Vault.login(kept)))
        XCTAssertEqual(Vault.kept(for: host).count, 1, "Touching a legacy item must not create an HTTPS duplicate")
        XCTAssertTrue(Vault.forget(kept))
        XCTAssertTrue(Vault.kept(for: host).isEmpty)
    }
}
