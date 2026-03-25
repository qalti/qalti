//
//  TargetSelectorViewModel.swift
//  Qalti
//
//  Created by k Slavnov on 20/10/2025.
//
import SwiftUI
import Foundation


class TargetSelectorViewModel: ObservableObject {
    @Published var targets: [String: Target] = [:]
    @Published var simulatorTargets: [Target] = []
    @Published var deviceTargets: [Target] = []
    @Published var simulatorsByOSVersion: [String: [Target]] = [:]
    @Published var isLoading = false
    @Published var selectedTarget: Target? = nil
    @Published private(set) var launchingTargetUdid: String? = nil
    @Published private(set) var launchingRuntime: IOSRuntime? = nil
    @Published var showGhostTunnelAlert: Bool = false
    @Published var ghostTunnelInfo: (ip: String, udid: String)? = nil

    let idbManager: IdbManaging
    let errorCapturer: ErrorCapturing
    let onboardingManager: OnboardingManager

    private var connectedUdid: String? = nil
    
    var launchingTarget: Target? {
        guard let launchingTargetUdid else { return nil }
        return targets[launchingTargetUdid]
    }
    
    // Convenience computed properties for backward compatibility
    var simulators: [TargetInfo] {
        simulatorTargets.map(\.targetInfo)
    }
    
    var devices: [TargetInfo] {
        deviceTargets.map(\.targetInfo)
    }

    init(
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturing,
        onboardingManager: OnboardingManager
    ) {
        self.idbManager = idbManager
        self.errorCapturer = errorCapturer
        self.onboardingManager = onboardingManager
    }

    private func setLaunchingTarget(_ udid: String?) {
        if Thread.isMainThread {
            launchingTargetUdid = udid
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.launchingTargetUdid = udid
            }
        }
    }
    
    private func clearLaunchingTargetIfMatches(_ udid: String) {
        performOnMain { [weak self] in
            guard let self else { return }
            if launchingTargetUdid == udid {
                launchingTargetUdid = nil
            }
        }
    }
    
    func cancelLaunchingTarget(udid: String, completion: @escaping () -> Void) {
        clearLaunchingTargetIfMatches(udid)
        
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }

            if let runtime = targets[udid]?.iosRuntime ?? launchingRuntime {
                runtime.runner.stopRunner()
                DispatchQueue.main.async { [weak self] in
                    self?.updateTargetRuntime(udid: udid, runtime: nil)
                }
            }

            var launchCancellingTargetError: Error?

            do {
                if idbManager.isConnected(udid: udid) {
                    try idbManager.disconnect(udid: udid)
                }
            } catch {
                launchCancellingTargetError = error
                errorCapturer.capture(error: error)
            }

            if let target = targets[udid], target.targetInfo.targetType == .simulator {
                do {
                    try idbManager.shutdownSimulator(udid: udid)
                } catch {
                    errorCapturer.capture(error: error)
                    launchCancellingTargetError = error
                }
            }
            
            if connectedUdid == udid {
                connectedUdid = nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if selectedTarget?.udid == udid {
                    selectedTarget = nil
                }
                if let launchCancellingTargetError {
                    updateTargetError(udid: udid, error: launchCancellingTargetError.localizedDescription)
                } else {
                    clearTargetStatus(udid: udid)
                }

                completion()
            }
        }
    }
    
    func loadTargets(isBackgroundRefresh: Bool = false) {
        if !isBackgroundRefresh {
            setLoading(true)
        }

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            do {
                let targetInfos = try idbManager.listTargets()

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    
                    // Update existing targets and add new ones
                    var updatedTargets = targets
                    
                    // Add or update targets
                    for targetInfo in targetInfos {
                        if var existingTarget = updatedTargets[targetInfo.udid] {
                            // Update the target info while preserving other state
                            existingTarget.targetInfo = targetInfo
                            updatedTargets[targetInfo.udid] = existingTarget
                        } else {
                            // Create new target
                            updatedTargets[targetInfo.udid] = Target(targetInfo: targetInfo)
                        }
                    }
                    
                    // Remove targets that no longer exist
                    let currentUdids = Set(targetInfos.map(\.udid))
                    updatedTargets = updatedTargets.filter { currentUdids.contains($0.key) }
                    
                    targets = updatedTargets
                    
                    // Update filtered and grouped collections for UI performance
                    updateTargetCollections()
                    
                    if !isBackgroundRefresh {
                        isLoading = false
                    }
                }
            } catch {
                errorCapturer.capture(error: error)
                DispatchQueue.main.async { [weak self] in
                    if !isBackgroundRefresh {
                        self?.isLoading = false
                    }
                }
            }
        }
    }

    /// Updates the filtered and grouped target collections for UI performance
    private func updateTargetCollections() {
        performOnMain { [weak self] in
            guard let self else { return }
            // Filter simulators and devices
            let allTargets = Array(targets.values)
            
            simulatorTargets = allTargets
                .filter { $0.targetInfo.targetType == .simulator && $0.targetInfo.isSupported() }
                .sorted { $0.name < $1.name }
            
            deviceTargets = allTargets
                .filter { $0.targetInfo.targetType == .device && $0.targetInfo.isSupported() }
                .sorted { $0.name < $1.name }
            
            // Group simulators by OS version and device family (iPhone/iPad)
            var groups: [String: [Target]] = [:]
            
            for simulatorTarget in simulatorTargets {
                let os = simulatorTarget.osVersion ?? "Unknown"
                let family = simulatorTarget.targetInfo.isIPad() ? "iPad" : "iPhone"
                let key = "\(os) (\(family))"
                if groups[key] == nil {
                    groups[key] = []
                }
                groups[key]?.append(simulatorTarget)
            }

            // Sort simulators within each group by name
            for (key, targets) in groups {
                groups[key] = targets.sorted { $0.name < $1.name }
            }
            
            simulatorsByOSVersion = groups
        }
    }

    // MARK: - Status Management
    
    func updateTargetStatus(udid: String, status: String?) {
        performOnMain { [weak self] in
            guard let self else { return }
            if var target = targets[udid] {
                target.currentStatus = status
                target.error = nil
                targets[udid] = target
                updateTargetCollections()
                
                // Also update selectedTarget if it matches this UDID
                if selectedTarget?.udid == udid {
                    selectedTarget = target
                }
            }
        }
    }
    
    func updateTargetError(udid: String, error: String) {
        performOnMain { [weak self] in
            guard let self else { return }
            if var target = targets[udid] {
                target.error = error
                target.currentStatus = nil
                targets[udid] = target
                updateTargetCollections()
                clearLaunchingTargetIfMatches(udid)
                
                // Also update selectedTarget if it matches this UDID
                if selectedTarget?.udid == udid {
                    selectedTarget = target
                }
            }
        }
    }
    
    func updateTargetRuntime(udid: String, runtime: IOSRuntime?) {
        performOnMain { [weak self] in
            guard let self else { return }
            if var target = targets[udid] {
                target.iosRuntime = runtime
                targets[udid] = target
                updateTargetCollections()
                
                // Also update selectedTarget if it matches this UDID
                if selectedTarget?.udid == udid {
                    selectedTarget = target
                }
            }
        }
    }
    
    func clearTargetStatus(udid: String) {
        performOnMain { [weak self] in
            guard let self else { return }
            if var target = targets[udid] {
                target.currentStatus = nil
                target.error = nil
                targets[udid] = target
                updateTargetCollections()
                
                // Also update selectedTarget if it matches this UDID
                if selectedTarget?.udid == udid {
                    selectedTarget = target
                }
            }
        }
    }

    func handleTargetSelection(_ target: TargetInfo, retryCount: Int = 0) {
        setLaunchingTarget(target.udid)

        // Record initial boot state on first selection since app launch
        performOnMain { [weak self] in
            guard let self else { return }
            if var storedTarget = targets[target.udid], storedTarget.wasOpenWhenFirstSelected == nil {
                storedTarget.wasOpenWhenFirstSelected = target.state?.lowercased() == "booted"
                targets[target.udid] = storedTarget
                updateTargetCollections()
            }
        }

        // Store the selected target for display in the header
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let target = targets[target.udid] {
                selectedTarget = target
            }
            // Notify onboarding manager that a simulator was chosen
            onboardingManager.complete(.pickSimulator)
        }

        // Start the setup sequence
        handleTargetPreparation(target, retryCount: retryCount)
    }

    private func handleTargetPreparation(_ target: TargetInfo, retryCount: Int) {
        do {
            // 1. Disconnect and shutdown previous simulator if connected
            if let previousUdid = connectedUdid, previousUdid != target.udid {
                updateTargetStatus(udid: target.udid, status: "Disconnecting from previous simulator...")
                // Stop any running processes
                if let previousTarget = targets[previousUdid] {
                    previousTarget.iosRuntime?.runner.stopRunner()
                } else if let launchingRuntime {
                    launchingRuntime.runner.stopRunner()
                }
                updateTargetRuntime(udid: previousUdid, runtime: nil)
                try idbManager.disconnect(udid: previousUdid)
                if simulatorTargets.contains(where: { $0.udid == connectedUdid }) &&
                    (targets[previousUdid]?.wasOpenWhenFirstSelected != true) {
                    updateTargetStatus(udid: target.udid, status: "Shutting down previous simulator...")
                    try idbManager.shutdownSimulator(udid: previousUdid)
                }
                connectedUdid = nil
            }
            
            // 2. Boot simulator if not already booted
            if target.state?.lowercased() != "booted" {
                DispatchQueue.main.async { [weak self] in
                    self?.updateTargetStatus(udid: target.udid, status: "Setting up \(target.name), this may take a few minutes...")
                }
                try idbManager.bootSimulator(udid: target.udid, verify: true)
            }

            guard launchingTargetUdid == target.udid else { return }

            // 3. Connect to simulator
            DispatchQueue.main.async { [weak self] in
                self?.updateTargetStatus(udid: target.udid, status: "Connecting to \(target.name)...")
            }
            if connectedUdid != target.udid {
                let isSim = target.targetType == .simulator
                _ = try idbManager.connect(udid: target.udid, isSimulator: isSim)
                connectedUdid = target.udid
            }

            guard launchingTargetUdid == target.udid else { return }

            // 4. Launch runner with new pipeline
            launchRunner(target: target, retryCount: retryCount)
            
        } catch {
            errorCapturer.capture(error: error)
            retryOrFail(target.udid, "Preparation failed", error, at: retryCount) { [weak self] in
                self?.handleTargetPreparation(target, retryCount: retryCount + 1)
            }
        }
    }

    private func launchRunner(target: TargetInfo, retryCount: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.updateTargetStatus(udid: target.udid, status: "Starting the agent...")
        }

        let runtime: IOSRuntime?

        do {
            runtime = try IOSRuntime(
                target: target,
                idbManager: idbManager,
                errorCapturer: errorCapturer
            )
        } catch let error as IOSRuntimeError {
            if case .ghostTunnelDetected(let ip, let udid) = error {
                DispatchQueue.main.async { [weak self] in
                    self?.ghostTunnelInfo = (ip, udid)
                    self?.showGhostTunnelAlert = true
                    self?.updateTargetError(udid: target.udid, error: "Connection Failed: Ghost Tunnel")
                }
                return // Stop execution
            }
            // Handle other runtime errors
            DispatchQueue.main.async { [weak self] in
                self?.updateTargetError(udid: target.udid, error: error.localizedDescription)
            }
            return
        } catch {
            // Handle generic errors
            DispatchQueue.main.async { [weak self] in
                self?.updateTargetError(udid: target.udid, error: error.localizedDescription)
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.launchingRuntime = runtime
        }

        guard let runtime else {
            // If creating IOSRuntime for a real device failed, try to determine specific reason using Result
            let runtimeUtils = IOSRuntimeUtils(errorCapturer: errorCapturer)

            let ipResult = runtimeUtils.getIphoneIP(for: target.udid)
            DispatchQueue.main.async { [weak self] in
                switch ipResult {
                case .failure(let error):
                    self?.updateTargetError(udid: target.udid, error: error.localizedDescription)
                case .success:
                    if target.device?.isPaired == false {
                        self?.updateTargetError(udid: target.udid, error: "Press 'Trust' on the iPhone")
                    } else {
                        let error = NSError(domain: "Device connectivity", code: -1)
                        self?.retryOrFail(target.udid, "Could't connect to the device", error, at: retryCount) { [weak self] in
                            self?.launchRunner(target: target, retryCount: retryCount + 1)
                        }
                    }
                }
            }
            return
        }

        // Use the new launchRunner method with status updates
        runtime.runner.launchRunner { [weak self] status in
            guard let self else { return }

            guard targets[target.udid] != nil else {
                runtime.runner.stopRunner()
                return
            }

            switch status {
            case .error(let error):
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    retryOrFail(target.udid, "Failed to launch agent", error, at: retryCount) { [weak self] in
                        self?.launchRunner(target: target, retryCount: retryCount + 1)
                    }
                }
                
            case .waitingForUnlock:
                DispatchQueue.main.async { [weak self] in
                    self?.updateTargetStatus(udid: target.udid, status: "Please unlock the device to continue...")
                }
                
            case .status(let update):
                switch update {
                case .waitingForConnection:
                    DispatchQueue.main.async { [weak self] in
                        self?.updateTargetStatus(udid: target.udid, status: "Waiting for connection...")
                    }
                    
                case .deviceConnected:
                    DispatchQueue.main.async { [weak self] in
                        self?.updateTargetStatus(udid: target.udid, status: "Device connected, starting agent...")
                    }
                    
                case .deviceUnlocked:
                    DispatchQueue.main.async { [weak self] in
                        self?.updateTargetStatus(udid: target.udid, status: "Device unlocked, initializing... If asked to enter the device passcode, please do it.")
                    }
                    
                case .testsRunning:
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        updateTargetStatus(udid: target.udid, status: "Connected to the \(target.type.lowercased())")
                        updateTargetRuntime(udid: target.udid, runtime: runtime)
                        setLaunchingTarget(nil)
                        launchingRuntime = nil

                        // Refresh simulator list to update states
                        loadTargets()
                    }
                }
            }
        }
    }

    private func retryOrFail(_ udid: String, _ message: String, _ error: Error, at count: Int, _ retry: @escaping () -> Void) {
        let isCancelled: Bool
        if case .cancelled = (error as? RunnerManager.Status.RunnerError) {
            isCancelled = true
        } else {
            isCancelled = false
        }
        if count == 3 || isCancelled {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let errorString = (error as? LocalizedError)?.localizedDescription ?? error.localizedDescription
                clearLaunchingTargetIfMatches(udid)
                updateTargetError(udid: udid, error: "\(message): \(errorString)")
            }
        } else {
            retry()
        }
    }

    private func setLoading(_ loading: Bool) {
        performOnMain { [weak self] in
            self?.isLoading = loading
        }
    }
    
    func shutdownSimulator(_ simulator: TargetInfo) {
        guard simulator.targetType == .simulator else { return }
        clearLaunchingTargetIfMatches(simulator.udid)
        updateTargetStatus(udid: simulator.udid, status: "Shutting down \(simulator.name)...")
            
        do {
            // Stop runtime if exists
            if let target = targets[simulator.udid], let runtime = target.iosRuntime {
                runtime.runner.stopRunner()
                updateTargetRuntime(udid: simulator.udid, runtime: nil)
            }
            
            // Disconnect if connected
            if idbManager.isConnected(udid: simulator.udid) {
                try idbManager.disconnect(udid: simulator.udid)
            }

            // Shutdown the simulator
            try idbManager.shutdownSimulator(udid: simulator.udid)

            // Update connected UDID if this was the connected simulator
            if connectedUdid == simulator.udid {
                connectedUdid = nil
            }

            // Clear selection if this was the selected target
            if selectedTarget?.udid == simulator.udid {
                DispatchQueue.main.async { [weak self] in
                    self?.selectedTarget = nil
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.clearTargetStatus(udid: simulator.udid)
            }
        } catch {
            errorCapturer.capture(error: error)
            DispatchQueue.main.async { [weak self] in
                self?.updateTargetError(udid: simulator.udid, error: "Failed to shutdown simulator: \(error.localizedDescription)")
            }
        }
    }
    
    func shutdownSelectedSimulator() {
        if let selectedTarget = selectedTarget {
            shutdownSimulator(selectedTarget.targetInfo)
        } else if let connectedUdid = connectedUdid {
            // If no selected target but we have a connected UDID, find and shutdown that simulator
            if let simulatorTarget = simulatorTargets.first(where: { $0.udid == connectedUdid }) {
                shutdownSimulator(simulatorTarget.targetInfo)
            }
        }
    }
}
