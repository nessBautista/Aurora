import XCTest
import Security
@testable import AuroraKeychain

// MARK: - Pure helpers — no I/O, no setUp/tearDown

final class KeychainQueryBuilderTests: XCTestCase {
    
    // identity ------------------------------------------------------
    
    func testIdentityQueryHasGenericPasswordClass() {
        let q = Keychain.makeIdentityQuery(service: "svc", account: "acct")
        XCTAssertEqual(q[kSecClass as String] as? String, kSecClassGenericPassword as String)
    }
    
    func testIdentityQueryCarriesServiceAndAccount() {
        let q = Keychain.makeIdentityQuery(service: "svc", account: "acct")
        XCTAssertEqual(q[kSecAttrService as String] as? String, "svc")
        XCTAssertEqual(q[kSecAttrAccount as String] as? String, "acct")
    }
    
    func testIdentityQueryIsMinimal() {
        // class + service + account, nothing else.
        let q = Keychain.makeIdentityQuery(service: "svc", account: "acct")
        XCTAssertEqual(q.count, 3)
    }
    
    // add -----------------------------------------------------------
    
    func testAddQueryIncludesValueDataAndLabel() {
        let value = Data("secret".utf8)
        let q = Keychain.makeAddQuery(service: "svc", account: "acct", value: value)
        XCTAssertEqual(q[kSecValueData as String] as? Data, value)
        XCTAssertEqual(q[kSecAttrLabel as String] as? String, "Aurora: acct")
    }
    
    func testAddQuerySetsAccessibilityClass() {
        // Items are accessible while the device is unlocked, never synced,
        // never included in iCloud backups.
        let q = Keychain.makeAddQuery(service: "svc", account: "acct", value: Data())
        XCTAssertEqual(
            q[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }
    
    func testAddQueryComposesOnIdentity() {
        let q = Keychain.makeAddQuery(service: "svc", account: "acct", value: Data())
        XCTAssertEqual(q[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(q[kSecAttrService as String] as? String, "svc")
        XCTAssertEqual(q[kSecAttrAccount as String] as? String, "acct")
    }
    
    // update --------------------------------------------------------
    
    func testUpdateAttributesContainValueAndLabel() {
        let value = Data("x".utf8)
        let attrs = Keychain.makeUpdateAttributes(account: "acct", value: value)
        XCTAssertEqual(attrs[kSecValueData as String] as? Data, value)
        XCTAssertEqual(attrs[kSecAttrLabel as String] as? String, "Aurora: acct")
    }
    
    func testUpdateAttributesDoNotContainIdentityKeys() {
        // The update attrs are the "SET" clause; the identity goes in the
        // WHERE clause separately. Mixing them would be a logic error.
        let attrs = Keychain.makeUpdateAttributes(account: "acct", value: Data())
        XCTAssertNil(attrs[kSecClass as String])
        XCTAssertNil(attrs[kSecAttrService as String])
        XCTAssertNil(attrs[kSecAttrAccount as String])
    }
    
    // read ----------------------------------------------------------
    
    func testReadQueryRequestsDataAndSingleMatch() {
        let q = Keychain.makeReadQuery(service: "svc", account: "acct")
        XCTAssertEqual(q[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(q[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
    }
    
    func testReadQueryComposesOnIdentity() {
        let q = Keychain.makeReadQuery(service: "svc", account: "acct")
        XCTAssertEqual(q[kSecAttrService as String] as? String, "svc")
        XCTAssertEqual(q[kSecAttrAccount as String] as? String, "acct")
    }
    
    // exists --------------------------------------------------------
    
    func testExistsQuerySuppressesAuthenticationUI() {
        let q = Keychain.makeExistsQuery(service: "svc", account: "acct")
        XCTAssertEqual(
            q[kSecUseAuthenticationUI as String] as? String,
            kSecUseAuthenticationUISkip as String,
            "exists probe must not trigger biometry"
        )
    }
    
    func testExistsQueryDoesNotRequestData() {
        let q = Keychain.makeExistsQuery(service: "svc", account: "acct")
        XCTAssertEqual(q[kSecReturnData as String] as? Bool, false)
    }
}

final class KeychainInterpretReadTests: XCTestCase {
    
    func testSuccessWithUTF8BytesReturnsString() throws {
        let payload = Data("sk-1234".utf8) as CFTypeRef
        XCTAssertEqual(try Keychain.interpretRead(errSecSuccess, payload: payload), "sk-1234")
    }
    
    func testSuccessWithNonUTF8BytesThrows() {
        let bad = Data([0xFF]) as CFTypeRef
        XCTAssertThrowsError(try Keychain.interpretRead(errSecSuccess, payload: bad)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .readFailed(errSecSuccess))
        }
    }
    
    func testSuccessWithNilPayloadThrows() {
        XCTAssertThrowsError(try Keychain.interpretRead(errSecSuccess, payload: nil)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .readFailed(errSecSuccess))
        }
    }
    
    func testItemNotFoundReturnsNil() throws {
        XCTAssertNil(try Keychain.interpretRead(errSecItemNotFound, payload: nil))
    }
    
    func testUserCanceledThrowsUserCancelled() {
        XCTAssertThrowsError(try Keychain.interpretRead(errSecUserCanceled, payload: nil)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .userCancelled)
        }
    }
    
    func testInteractionNotAllowedThrowsLocked() {
        XCTAssertThrowsError(try Keychain.interpretRead(errSecInteractionNotAllowed, payload: nil)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .locked)
        }
    }
    
    func testUnknownStatusThrowsReadFailed() {
        let madeUp: OSStatus = -99999
        XCTAssertThrowsError(try Keychain.interpretRead(madeUp, payload: nil)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .readFailed(madeUp))
        }
    }
}

final class KeychainInterpretAddTests: XCTestCase {
    
    func testSuccessReturnsNormally() throws {
        try Keychain.interpretAdd(errSecSuccess)
    }
    
    func testInteractionNotAllowedThrowsLocked() {
        XCTAssertThrowsError(try Keychain.interpretAdd(errSecInteractionNotAllowed)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .locked)
        }
    }
    
    func testOtherStatusThrowsStoreFailed() {
        XCTAssertThrowsError(try Keychain.interpretAdd(errSecDuplicateItem)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .storeFailed(errSecDuplicateItem))
        }
    }
}

final class KeychainInterpretUpdateTests: XCTestCase {
    
    func testSuccessReturnsUpdated() throws {
        XCTAssertEqual(try Keychain.interpretUpdate(errSecSuccess), .updated)
    }
    
    func testItemNotFoundReturnsItemMissing() throws {
        // This is the routing hint: the orchestrator falls through to add.
        XCTAssertEqual(try Keychain.interpretUpdate(errSecItemNotFound), .itemMissing)
    }
    
    func testInteractionNotAllowedThrowsLocked() {
        XCTAssertThrowsError(try Keychain.interpretUpdate(errSecInteractionNotAllowed)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .locked)
        }
    }
    
    func testUnknownStatusThrowsStoreFailed() {
        let madeUp: OSStatus = -99999
        XCTAssertThrowsError(try Keychain.interpretUpdate(madeUp)) { error in
            XCTAssertEqual(error as? Keychain.KeychainError, .storeFailed(madeUp))
        }
    }
}

final class KeychainInterpretExistsTests: XCTestCase {
    
    func testSuccessReturnsTrue() {
        XCTAssertTrue(Keychain.interpretExists(errSecSuccess))
    }
    
    func testInteractionNotAllowedReturnsTrue() {
        // Item exists but keychain is locked — still "exists" semantically.
        XCTAssertTrue(Keychain.interpretExists(errSecInteractionNotAllowed))
    }
    
    func testItemNotFoundReturnsFalse() {
        XCTAssertFalse(Keychain.interpretExists(errSecItemNotFound))
    }
    
    func testUnknownStatusReturnsFalse() {
        XCTAssertFalse(Keychain.interpretExists(-99999))
    }
}

// MARK: - Integration — real keychain, unique service per test

final class KeychainIntegrationTests: XCTestCase {
    
    private var testService: String = ""
    private let testAccount = "test-account"
    
    override func setUp() {
        super.setUp()
        testService = "aurora-test-\(UUID().uuidString)"
    }
    
    override func tearDown() {
        Keychain.clear(service: testService, account: testAccount)
        super.tearDown()
    }
    
    func testExistsReturnsFalseForMissingItem() {
        XCTAssertFalse(Keychain.exists(service: testService, account: testAccount))
    }
    
    func testSetThenExistsReturnsTrue() throws {
        try Keychain.set(service: testService, account: testAccount, value: "secret")
        XCTAssertTrue(Keychain.exists(service: testService, account: testAccount))
    }
    
    func testSetOverwritesExistingItemIdempotently() throws {
        try Keychain.set(service: testService, account: testAccount, value: "first")
        try Keychain.set(service: testService, account: testAccount, value: "second")
        XCTAssertTrue(Keychain.exists(service: testService, account: testAccount))
    }
    
    func testClearIsIdempotent() {
        Keychain.clear(service: testService, account: testAccount)
        Keychain.clear(service: testService, account: testAccount)
        XCTAssertFalse(Keychain.exists(service: testService, account: testAccount))
    }
    
    func testClearAfterSetRemovesItem() throws {
        try Keychain.set(service: testService, account: testAccount, value: "secret")
        Keychain.clear(service: testService, account: testAccount)
        XCTAssertFalse(Keychain.exists(service: testService, account: testAccount))
    }
}
