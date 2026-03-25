//
//  TargetSelectorView.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 06.03.2025.
//

import SwiftUI
import Foundation

// MARK: - Target Model

/// Represents a device or simulator target with its associated state
struct Target: Identifiable {
    let id: String
    var targetInfo: TargetInfo
    var currentStatus: String?
    var error: String?
    var iosRuntime: IOSRuntime?
    var wasOpenWhenFirstSelected: Bool?
    
    init(targetInfo: TargetInfo) {
        self.id = targetInfo.udid
        self.targetInfo = targetInfo
        self.wasOpenWhenFirstSelected = nil
    }
    
    // Convenience accessors for TargetInfo properties
    var udid: String { targetInfo.udid }
    var name: String { targetInfo.name }
    var state: String? { targetInfo.state }
    var type: String { targetInfo.type }
    var osVersion: String? { targetInfo.osVersion }
}

struct TargetSelectorView: View {

    @EnvironmentObject private var errorCapturer: ErrorCapturerService
    @EnvironmentObject private var onboardingManager: OnboardingManager

    @StateObject private var viewModel: TargetSelectorViewModel

    @State private var navigateToTargetView = false
    @State private var timer: Timer?
    @State private var showLaunchConflictAlert = false
    @State private var pendingTargetSelection: TargetInfo?
    
    let onTargetViewAppear: () -> Void
    let onRuntimeChanged: (IOSRuntime?) -> Void
    let onShowDeviceSetupHelp: () -> Void
    let onShowDeviceSetupHelpFromLink: () -> Void
    let isXcodeSetupComplete: Bool

    init(
        onTargetViewAppear: @escaping () -> Void,
        onRuntimeChanged: @escaping (IOSRuntime?) -> Void,
        onShowDeviceSetupHelp: @escaping () -> Void,
        onShowDeviceSetupHelpFromLink: @escaping () -> Void,
        isXcodeSetupComplete: Bool,
        idbManager: IdbManaging,
        errorCapturer: ErrorCapturerService,
        onboardingManager: OnboardingManager
    ) {
        self.onTargetViewAppear = onTargetViewAppear
        self.onRuntimeChanged = onRuntimeChanged
        self.onShowDeviceSetupHelp = onShowDeviceSetupHelp
        self.onShowDeviceSetupHelpFromLink = onShowDeviceSetupHelpFromLink
        self.isXcodeSetupComplete = isXcodeSetupComplete

        _viewModel = StateObject(wrappedValue: TargetSelectorViewModel(
            idbManager: idbManager,
            errorCapturer: errorCapturer,
            onboardingManager: onboardingManager
        ))
    }

    var body: some View {
        rootContent
        .alert("Another Target Is Launching", isPresented: $showLaunchConflictAlert) {
            Button("Cancel", role: .cancel) {
                pendingTargetSelection = nil
                showLaunchConflictAlert = false
            }
            Button("Stop and Launch", role: .destructive) {
                guard let targetInfo = pendingTargetSelection else { return }
                showLaunchConflictAlert = false
                pendingTargetSelection = nil
                startLaunching(targetInfo, stopCurrentLaunch: true)
            }
        } message: {
            Text(launchConflictMessage)
        }
        .alert(
            "Connection Issue Detected",
            isPresented: $viewModel.showGhostTunnelAlert,
            presenting: viewModel.ghostTunnelInfo
        ) { info in
            Button("OK", role: .cancel) {}
            Button("Copy Fix Command") {
                let command = "xcrun devicectl manage unpair --device \(info.udid)"
#if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
#endif
            }
        } message: { info in
            Text("""
                Your Mac cannot communicate with the device. This is often a 'Ghost Tunnel' issue.
                        
                Device: \(info.udid)
                Reported IP: \(info.ip)
                
                To Fix:
                1. Unplug the iPhone.
                2. Run the copied command in Terminal.
                3. Plug the iPhone back in and wait ~15 seconds.
                
                Note: Use command 'xcrun devicectl list devices' to see actual devices
                """)
        }
        .onAppear {
            // Only load simulators if Xcode setup is complete
            if isXcodeSetupComplete {
                viewModel.loadTargets(isBackgroundRefresh: false)
            }
            startRefreshTimer()
        }
        .background(CloseAppOnWindowCloseManager())
        .onDisappear {
            stopRefreshTimer()
            // Shutdown the currently selected or last used simulator
            viewModel.selectedTarget?.iosRuntime?.runner.stopRunner()
            viewModel.shutdownSelectedSimulator()
        }
        .legacy_onChange(of: viewModel.selectedTarget?.iosRuntime) { newRuntime in
            onRuntimeChanged(newRuntime)
            if newRuntime != nil {
                withAnimation(.easeInOut(duration: 0.3)) {
                    navigateToTargetView = true
                }
            }
        }
        .legacy_onChange(of: navigateToTargetView) { _ in
            setupRefreshTimer()
        }
        .legacy_onChange(of: isXcodeSetupComplete) { xcodeSetupComplete in
            setupRefreshTimer()
        }
    }
    
    // MARK: - Extracted Computed Content
    private var rootContent: some View {
        ZStack {
            if !navigateToTargetView {
                targetSelectorView
            } else {
                simulatorView
            }
        }
    }
    
    private var targetSelectorView: some View {
        VStack {
            ZStack {
                loadingOverlay
                selectorScrollContent
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }
    
    private var loadingOverlay: some View {
        VStack {
            Spacer()
            Text("Loading simulators...")
            Spacer()
        }
        .opacity(viewModel.isLoading ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
    }
    
    private var selectorScrollContent: some View {
        ScrollView {
            LazyVStack {
                realDevicesSection
                simulatorsSection
            }
        }
        .refreshable {
            viewModel.loadTargets(isBackgroundRefresh: false)
        }
        .opacity(viewModel.isLoading ? 0.0 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
    }
    
    @ViewBuilder
    private var realDevicesSection: some View {
        Spacer(minLength: 16)
        HStack {
            Text("Real Devices").font(.system(size: 24, weight: .semibold))
                .padding(.horizontal, 16)
            Button(action: {
                onShowDeviceSetupHelp()
            }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 4)
            .help("Press for device setup instructions")
            Spacer()
        }
        .background(Color.systemBackground)
        Rectangle()
            .fill(Color.secondaryLabel.opacity(0.3))
            .frame(height: 1)
        
        if !viewModel.deviceTargets.isEmpty {
            deviceTargetsList
        } else {
            DevicePlaceholderView(
                onShowDeviceSetupHelp: onShowDeviceSetupHelp,
                onShowDeviceSetupHelpFromLink: onShowDeviceSetupHelpFromLink
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
    
    private var deviceTargetsList: some View {
        ForEach(viewModel.deviceTargets) { deviceTarget in
            TargetRow(
                target: deviceTarget,
                onShutdown: nil
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .onTapGesture {
                handleTargetTap(deviceTarget)
            }
            
            Rectangle()
                .fill(Color.secondaryLabel.opacity(0.1))
                .frame(height: 1)
        }
    }
    
    private var sortedOSVersions: [String] {
        viewModel.simulatorsByOSVersion.keys.sorted(by: >)
    }
    
    private func simulatorsFor(version: String) -> [Target] {
        viewModel.simulatorsByOSVersion[version] ?? []
    }
    
    @ViewBuilder
    private var simulatorsSection: some View {
        ForEach(Array(sortedOSVersions.enumerated()), id: \.element) { osIndex, osVersion in
            Spacer(minLength: 16)
            HStack {
                Text(osVersion).font(.system(size: 24, weight: .semibold))
                    .padding(.horizontal, 16)
                Spacer()
            }
            .background(Color.systemBackground)
            Rectangle()
                .fill(Color.secondaryLabel.opacity(0.3))
                .frame(height: 1)
            
            let simulatorTargets = Array(simulatorsFor(version: osVersion).enumerated())
            ForEach(simulatorTargets, id: \.element.id) { simulatorIndex, simulatorTarget in
                simulatorRow(simulatorTarget, isFirst: (osIndex == 0 && simulatorIndex == 0))
            }
        }
    }
    
    @ViewBuilder
    private func simulatorRow(_ simulatorTarget: Target, isFirst: Bool) -> some View {
        let row = TargetRow(
            target: simulatorTarget,
            onShutdown: { simulator in
                DispatchQueue.global().async {
                    viewModel.shutdownSimulator(simulator)
                }
            }
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .onTapGesture {
            handleTargetTap(simulatorTarget)
        }
        
        if isFirst {
            row.onboardingTip(.pickSimulator)
        } else {
            row
        }
    }
    
    private var simulatorView: some View {
        Group {
            if let runtime = viewModel.selectedTarget?.iosRuntime {
                VStack(spacing: 0) {
                    simulatorNavHeader
                    TargetView(
                        runtime: runtime,
                        errorCapturer: viewModel.errorCapturer,
                        idbManager: viewModel.idbManager
                    )
                    .onAppear { onTargetViewAppear() }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
    }
    
    private var launchConflictMessage: String {
        guard let pendingTargetSelection else {
            if let current = viewModel.launchingTarget {
                return "\(current.name) is still launching."
            } else {
                return "Another target is currently launching."
            }
        }
        
        let currentName = viewModel.launchingTarget?.name ?? "the current target"
        return "Stop launching \(currentName) and start \(pendingTargetSelection.name)?"
    }
    
    private func handleTargetTap(_ target: Target) {
        if viewModel.launchingTargetUdid == target.udid {
            return
        }
        
        if let launchingUdid = viewModel.launchingTargetUdid,
           launchingUdid != target.udid
        {
            pendingTargetSelection = target.targetInfo
            showLaunchConflictAlert = true
            return
        }
        
        startLaunching(target.targetInfo, stopCurrentLaunch: false)
    }
    
    private func startLaunching(_ targetInfo: TargetInfo, stopCurrentLaunch: Bool) {
        let currentlyLaunching = viewModel.launchingTargetUdid
        DispatchQueue.global().async {
            if stopCurrentLaunch,
               let current = currentlyLaunching,
               current != targetInfo.udid
            {
                viewModel.cancelLaunchingTarget(udid: current) {
                    DispatchQueue.global().async {
                        viewModel.handleTargetSelection(targetInfo)
                    }
                }
            } else {
                viewModel.handleTargetSelection(targetInfo)
            }
        }
    }
    
    private var simulatorNavHeader: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.selectedTarget?.iosRuntime?.runner.stopRunner()
                    navigateToTargetView = false
                    if let selectedTarget = viewModel.selectedTarget {
                        viewModel.updateTargetRuntime(udid: selectedTarget.udid, runtime: nil)
                        viewModel.updateTargetStatus(udid: selectedTarget.udid, status: nil)
                    }
                    viewModel.selectedTarget = nil
                    onRuntimeChanged(nil)
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.label)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Back to Targets")
            
            HStack(spacing: 8) {
                if let selectedTarget = viewModel.selectedTarget {
                    Text(selectedTarget.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let osVersion = selectedTarget.osVersion {
                        Text(osVersion)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                } else {
                    Text("Target")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color.secondarySystemBackground.opacity(0.95))
    }
    
    private func setupRefreshTimer() {
        if isXcodeSetupComplete, navigateToTargetView == false {
            startRefreshTimer()
        } else {
            stopRefreshTimer()
        }
    }
    
    private func startRefreshTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            viewModel.loadTargets(isBackgroundRefresh: true)
        }
    }
    
    private func stopRefreshTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct TargetSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        let credentials = PreviewServices.credentials
        let errorCapturer = PreviewServices.errorCapturer
        let onboarding = PreviewServices.onboarding
        let idb = PreviewServices.fakeIdb

        TargetSelectorView(
            onTargetViewAppear: {},
            onRuntimeChanged: { _ in },
            onShowDeviceSetupHelp: {},
            onShowDeviceSetupHelpFromLink: {},
            isXcodeSetupComplete: true,
            idbManager: idb,
            errorCapturer: errorCapturer,
            onboardingManager: onboarding
        )
        .environmentObject(credentials)
        .environmentObject(errorCapturer)
        .environmentObject(onboarding)
    }
}
