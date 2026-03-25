//
//  MockAppBundleResolver.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 17.12.25.
//

import Foundation
@testable import Qalti


class MockAppBundleResolver: AppBundleResolver {
    init() {
        let errorCapturer = MockErrorCapturer()
        let idbManager = MockIdbManager()
        super.init(deviceId: "dummy-id", idbManager: idbManager, errorCapturer: errorCapturer)
    }

    override func resolveBundle(for app: String) -> String {
        return app
    }
}
