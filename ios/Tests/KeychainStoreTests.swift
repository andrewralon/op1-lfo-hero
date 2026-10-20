import XCTest
@testable import op1_lfo_hero

/// Confirms the Keychain round-trip actually works on-device/on-simulator, since
/// SettingsMigrationTests only exercises `Settings`/`DeviceState` encoding and never touches
/// `KeychainStore` itself.
final class KeychainStoreTests: XCTestCase {
    private let account = "KeychainStoreTests.account"

    override func tearDown() {
        KeychainStore.delete(account: account)
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() {
        let data = Data("hello keychain".utf8)
        KeychainStore.save(data, account: account)
        XCTAssertEqual(KeychainStore.load(account: account), data)
    }

    func testSaveOverwritesExistingValue() {
        KeychainStore.save(Data("first".utf8), account: account)
        KeychainStore.save(Data("second".utf8), account: account)
        XCTAssertEqual(KeychainStore.load(account: account), Data("second".utf8))
    }

    func testDeleteRemovesValue() {
        KeychainStore.save(Data("gone soon".utf8), account: account)
        KeychainStore.delete(account: account)
        XCTAssertNil(KeychainStore.load(account: account))
    }

    func testLoadOfMissingAccountReturnsNil() {
        XCTAssertNil(KeychainStore.load(account: "KeychainStoreTests.neverSaved"))
    }
}
