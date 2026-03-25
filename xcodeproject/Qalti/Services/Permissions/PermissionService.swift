//
//  PermissionService.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.03.26.
//

import Foundation
import Combine
import Logging
import AppKit

/// Manages folder access permission monitoring and detection.
///
/// This service monitors whether the app has access to the Documents/Qalti folder
/// and provides reactive updates when permissions are granted or revoked.
/// It is designed as an `ObservableObject` to be injected into the SwiftUI environment.
final class PermissionService: PermissionServicing, Loggable {

    // MARK: - Published Properties

    @Published var hasDocumentsAccess: Bool = false
    @Published var isMonitoringPermissions: Bool = false
    @Published var qaltiFolderPath: String = ""

    // MARK: - Protocol Conformance: Publishers

    var hasDocumentsAccessPublisher: AnyPublisher<Bool, Never> {
        $hasDocumentsAccess.eraseToAnyPublisher()
    }

    var isMonitoringPermissionsPublisher: AnyPublisher<Bool, Never> {
        $isMonitoringPermissions.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private var permissionTimer: Timer?
    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupQaltiFolderPath()
        checkInitialPermissions()
        logger.info("PermissionService initialized")
    }

    deinit {
        stopPermissionMonitoring()
    }

    // MARK: - Public Methods

    func startPermissionMonitoring() {
        guard !isMonitoringPermissions else {
            logger.debug("Permission monitoring already active")
            return
        }

        logger.info("Starting permission monitoring for Documents folder")
        isMonitoringPermissions = true

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermissionChanges()
        }
    }

    func stopPermissionMonitoring() {
        guard isMonitoringPermissions else { return }

        logger.info("Stopping permission monitoring")
        isMonitoringPermissions = false
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    func refreshPermissionStatus() {
        logger.debug("Manually refreshing permission status")
        checkPermissionStatus()
    }

    func openPrivacySettings() {
        // This URL scheme opens the Privacy & Security settings pane.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    func checkDocumentsAccess() -> Bool {
        let qaltiURL = URL(fileURLWithPath: qaltiFolderPath)

        // Atempting to access the directory is what triggers the prompt
        // the *first* time. If permission is denied, this will just fail.
        do {
            _ = try fileManager.contentsOfDirectory(at: qaltiURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            logger.debug("Documents/Qalti folder is accessible")
            return true
        } catch {
            logger.debug("Documents/Qalti folder access failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Methods

    private func setupQaltiFolderPath() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        qaltiFolderPath = (documentsPath as NSString).appendingPathComponent("Qalti")
        logger.debug("Qalti folder path set to: \(qaltiFolderPath)")
    }

    private func checkInitialPermissions() {
        // Attempting an initial read is what should trigger the prompt.
        // If the view appears before this check completes, the banner shows.
        refreshPermissionStatus()
    }

    private func checkPermissionChanges() {
        let previousAccess = hasDocumentsAccess
        checkPermissionStatus()

        if !previousAccess && hasDocumentsAccess {
            logger.info("Documents access granted - stopping permission monitoring")
            stopPermissionMonitoring()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .documentsAccessGranted, object: nil)
            }
        }
    }

    private func checkPermissionStatus() {
        // Run check on a background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hasAccess = self?.checkDocumentsAccess() ?? false
            DispatchQueue.main.async {
                self?.hasDocumentsAccess = hasAccess
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let documentsAccessGranted = Notification.Name("documentsAccessGranted")
}
