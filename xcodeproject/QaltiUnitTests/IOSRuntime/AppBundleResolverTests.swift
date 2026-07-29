//
//  AppBundleResolverTests.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 29.07.26.
//

import XCTest
@testable import Qalti

/// Regression cover for app-name resolution.
///
/// Context: `resolveBundle(for:)` used to return its input verbatim when lookup failed, so the
/// runner received a nonexistent "bundle ID" and the request hung until a 60s URLRequest timeout.
/// A missing app therefore looked identical to a broken device. These tests pin the behaviour that
/// replaced it — a missing app must be reported as missing, and it must say what *is* installed.
final class AppBundleResolverTests: XCTestCase {

    // MARK: - Properties

    private var mockIdb: MockIdbManager!
    private var mockErrorCapturer: MockErrorCapturer!

    // MARK: - Test Lifecycle

    override func setUp() {
        super.setUp()
        mockIdb = MockIdbManager()
        mockErrorCapturer = MockErrorCapturer()
    }

    override func tearDown() {
        mockIdb = nil
        mockErrorCapturer = nil
        super.tearDown()
    }

    private func makeResolver(idbManager: IdbManaging? = nil) -> AppBundleResolver {
        AppBundleResolver(
            deviceId: "SIM-123",
            idbManager: idbManager ?? mockIdb,
            errorCapturer: mockErrorCapturer
        )
    }

    /// Unwraps `.resolved`, failing the test with a readable message for the other cases.
    private func resolvedBundleID(
        _ resolution: AppBundleResolver.Resolution,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        guard case .resolved(let bundleID) = resolution else {
            XCTFail("Expected .resolved, got: \(resolution)", file: file, line: line)
            throw XCTSkip("not resolved")
        }
        return bundleID
    }

    // MARK: - Resolving by display name

    func test_resolve_byDisplayName_returnsBundleID() throws {
        mockIdb.stubbedApps = [(name: "SyncUps", bundleID: "co.kslavnov.SyncUps")]

        let resolution = makeResolver().resolve("SyncUps")

        XCTAssertEqual(try resolvedBundleID(resolution), "co.kslavnov.SyncUps")
    }

    func test_resolve_byDisplayName_isCaseAndSpaceInsensitive() throws {
        mockIdb.stubbedApps = [(name: "Sync Ups", bundleID: "co.kslavnov.SyncUps")]

        let resolver = makeResolver()

        XCTAssertEqual(try resolvedBundleID(resolver.resolve("sync ups")), "co.kslavnov.SyncUps")
        XCTAssertEqual(try resolvedBundleID(resolver.resolve("SYNCUPS")), "co.kslavnov.SyncUps")
    }

    /// `normalizeAppKey` strips a trailing "app", so both spellings must resolve.
    func test_resolve_byDisplayName_toleratesTrailingAppSuffix() throws {
        mockIdb.stubbedApps = [(name: "AegirProxyApp", bundleID: "com.apple.AegirProxyApp")]

        let resolver = makeResolver()

        XCTAssertEqual(try resolvedBundleID(resolver.resolve("AegirProxyApp")), "com.apple.AegirProxyApp")
        XCTAssertEqual(try resolvedBundleID(resolver.resolve("AegirProxy")), "com.apple.AegirProxyApp")
    }

    // MARK: - Resolving by bundle ID

    func test_resolve_byBundleID_returnsCanonicalBundleID() throws {
        mockIdb.stubbedApps = [(name: "Reminders", bundleID: "com.apple.reminders")]

        let resolution = makeResolver().resolve("com.apple.reminders")

        XCTAssertEqual(try resolvedBundleID(resolution), "com.apple.reminders")
    }

    /// Bundle IDs are indexed separately from names precisely because `normalizeAppKey` would
    /// truncate a trailing "App" — `com.apple.DocumentsApp` must not become `com.apple.Documents`.
    func test_resolve_byBundleID_endingInApp_isNotTruncated() throws {
        mockIdb.stubbedApps = [(name: "Files", bundleID: "com.apple.DocumentsApp")]

        let resolution = makeResolver().resolve("com.apple.DocumentsApp")

        XCTAssertEqual(try resolvedBundleID(resolution), "com.apple.DocumentsApp")
    }

    func test_resolve_byBundleID_isCaseInsensitive() throws {
        mockIdb.stubbedApps = [(name: "SyncUps", bundleID: "co.kslavnov.SyncUps")]

        let resolution = makeResolver().resolve("CO.KSLAVNOV.SYNCUPS")

        XCTAssertEqual(try resolvedBundleID(resolution), "co.kslavnov.SyncUps")
    }

    // MARK: - Missing apps

    func test_resolve_unknownApp_reportsNotInstalledWithAvailableApps() {
        mockIdb.stubbedApps = [
            (name: "SyncUps", bundleID: "co.kslavnov.SyncUps"),
            (name: "Contacts", bundleID: "com.apple.MobileAddressBook")
        ]

        let resolution = makeResolver().resolve("Notes")

        guard case .notInstalled(let requested, let available) = resolution else {
            return XCTFail("Expected .notInstalled, got: \(resolution)")
        }
        XCTAssertEqual(requested, "Notes")
        XCTAssertTrue(available.contains("SyncUps"))
        XCTAssertTrue(available.contains("Contacts"))
    }

    /// The message is what reaches the agent as a tool response, so it must name the app *and*
    /// list the alternatives — that is what turns a 60s mystery timeout into a one-iteration fix.
    func test_resolve_unknownApp_failureMessageNamesAppAndAlternatives() throws {
        mockIdb.stubbedApps = [(name: "SyncUps", bundleID: "co.kslavnov.SyncUps")]

        let message = try XCTUnwrap(makeResolver().resolve("Notes").failureMessage)

        XCTAssertTrue(message.contains("Notes"), "message should name the requested app: \(message)")
        XCTAssertTrue(message.contains("not installed"), "message should say it is not installed: \(message)")
        XCTAssertTrue(message.contains("SyncUps"), "message should list installed apps: \(message)")
    }

    func test_resolve_resolvedApp_hasNoFailureMessage() {
        mockIdb.stubbedApps = [(name: "SyncUps", bundleID: "co.kslavnov.SyncUps")]

        XCTAssertNil(makeResolver().resolve("SyncUps").failureMessage)
    }

    // MARK: - Device unavailable

    func test_resolve_whenAppListUnavailable_isDistinctFromNotInstalled() throws {
        let resolution = makeResolver(idbManager: ThrowingIdbManager()).resolve("SyncUps")

        guard case .listUnavailable(let requested) = resolution else {
            return XCTFail("Expected .listUnavailable, got: \(resolution)")
        }
        XCTAssertEqual(requested, "SyncUps")

        // A device problem must not be reported as "this app is not installed".
        let message = try XCTUnwrap(resolution.failureMessage)
        XCTAssertFalse(message.contains("not installed"), "message conflates device failure with a missing app: \(message)")
    }

    func test_resolve_whenAppListUnavailable_capturesUnderlyingError() {
        _ = makeResolver(idbManager: ThrowingIdbManager()).resolve("SyncUps")

        XCTAssertEqual(mockErrorCapturer.captureCount, 1)
        XCTAssertNotNil(mockErrorCapturer.capturedError)
    }

    // MARK: - System app fallback

    func test_resolve_systemApp_worksWhenIdbReportsNothing() throws {
        mockIdb.stubbedApps = []

        let resolution = makeResolver().resolve("Reminders")

        XCTAssertEqual(try resolvedBundleID(resolution), "com.apple.reminders")
    }

    func test_resolve_idbEntryWins_overSystemAppFallback() throws {
        mockIdb.stubbedApps = [(name: "Settings", bundleID: "com.example.CustomSettings")]

        let resolution = makeResolver().resolve("Settings")

        XCTAssertEqual(try resolvedBundleID(resolution), "com.example.CustomSettings")
    }

    // MARK: - Legacy lenient API

    /// `resolveBundle(for:)` intentionally keeps the old passthrough for the `DeviceAdministration`
    /// call sites. This test documents that it is a deliberate, contained fallback — callers that
    /// can surface an error to the user must use `resolve(_:)` instead.
    func test_resolveBundle_stillEchoesInputOnMiss() {
        mockIdb.stubbedApps = []

        XCTAssertEqual(makeResolver().resolveBundle(for: "NoSuchApp"), "NoSuchApp")
    }

    func test_resolveBundle_returnsBundleIDOnHit() {
        mockIdb.stubbedApps = [(name: "SyncUps", bundleID: "co.kslavnov.SyncUps")]

        XCTAssertEqual(makeResolver().resolveBundle(for: "SyncUps"), "co.kslavnov.SyncUps")
    }

    // MARK: - listApps

    func test_listApps_returnsNilWhenDeviceUnavailable() {
        XCTAssertNil(makeResolver(idbManager: ThrowingIdbManager()).listApps())
    }
}
