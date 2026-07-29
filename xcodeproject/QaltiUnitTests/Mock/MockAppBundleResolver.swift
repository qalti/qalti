//
//  MockAppBundleResolver.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import Foundation
@testable import Qalti


/// Identity stub: resolution is a no-op so `DeviceAdministration` tests can assert on the commands
/// they build without stubbing an app catalogue.
///
/// This is a test convenience, **not** a model of production behaviour — do not read the passthrough
/// below as evidence that echoing an unresolved name back as a bundle ID is acceptable. It is not:
/// doing that in production turned "app is not installed" into an opaque 60s request timeout. The
/// real resolver's contract is covered by `AppBundleResolverTests`.
class MockAppBundleResolver: AppBundleResolver {
    init() {
        let errorCapturer = MockErrorCapturer()
        let idbManager = MockIdbManager()
        super.init(deviceId: "dummy-id", idbManager: idbManager, errorCapturer: errorCapturer)
    }

    override func resolveBundle(for app: String) -> String {
        return app
    }

    override func resolve(_ app: String) -> AppBundleResolver.Resolution {
        return .resolved(bundleID: app)
    }
}
