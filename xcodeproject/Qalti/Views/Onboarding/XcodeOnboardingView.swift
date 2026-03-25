//
//  XcodeOnboarding.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 28.06.2025.
//

import SwiftUI
import AppKit

struct XcodeOnboardingView: View {
    @EnvironmentObject private var errorCapturer: ErrorCapturerService
    @EnvironmentObject private var onboardingManager: OnboardingManager

    @StateObject private var xcodeDetector = XcodeDetector(errorCapturer: nil)

    @State private var setupStatus: XcodeSetupStatus?
    @State private var isLoading = false
    @State private var currentError: String?
    @State private var errorTimer: Timer?
    @State private var isDownloadingRuntime = false
    @State private var isSettingUpXcodeSelect = false
    @State private var isAcceptingLicense = false
    @State private var selectedXcodePath: String?
    @State private var xcodeSelectCommand: String?
    @State private var refreshTimer: Timer?
    @State private var downloadProgress: Double = 0.0
    @State private var downloadSizeInfo: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                        
                        Text("Xcode Setup")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    
                    Text("Let's make sure your development environment is ready")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 16)
                
                // Error Display
                if let error = currentError {
                    ErrorView(error: error) {
                        copyToClipboard(error)
                    } onDismiss: {
                        dismissError()
                    }
                }
                
                // Checklist
                VStack(alignment: .leading, spacing: 16) {
                    // Xcode Installation Check
                    ChecklistItem(
                        title: "Xcode Installation",
                        subtitle: xcodeInstallationSubtitle,
                        status: xcodeInstallationStatus,
                        isLoading: isLoading
                    ) {
                        Button("Open App Store") {
                            xcodeDetector.openXcodeInAppStore()
                        }
                        .disabled(xcodeInstallationStatus == .completed)
                    }
                    
                    // Xcode-select Setup
                    ChecklistItem(
                        title: "Xcode Command Line Tools",
                        subtitle: xcodeSelectSubtitle,
                        status: xcodeSelectStatus,
                        isLoading: isSettingUpXcodeSelect,
                        isDisabled: !isXcodeInstallationComplete
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let command = xcodeSelectCommand {
                                HStack {
                                    Text(command)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                    
                                    Button("Copy") {
                                        copyToClipboard(command)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!isXcodeInstallationComplete)
                                }
                            }
                            
                            Button("Run it for me") {
                                runXcodeSelect()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isXcodeInstallationComplete || isSettingUpXcodeSelect || xcodeSelectStatus == .completed)
                        }
                    }
                    
                    // Xcode License Check
                    ChecklistItem(
                        title: "Xcode License Agreement",
                        subtitle: licenseSubtitle,
                        status: licenseStatus,
                        isLoading: isAcceptingLicense,
                        isDisabled: !isXcodeSelectComplete
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("sudo xcodebuild -license accept")
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                                
                                Button("Copy") {
                                    copyToClipboard("sudo xcodebuild -license accept")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!isXcodeSelectComplete)
                            }
                            
                            Button("Run it for me") {
                                acceptXcodeLicense()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isXcodeSelectComplete || isAcceptingLicense || licenseStatus == .completed)
                        }
                    }
                    
                    // Simulator Runtimes Check
                    ChecklistItem(
                        title: "iOS Simulator Runtimes",
                        subtitle: simulatorRuntimesSubtitle,
                        status: simulatorRuntimesStatus,
                        isLoading: isDownloadingRuntime,
                        isDisabled: !areAllPreviousStepsComplete
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Download & Install Latest iOS Runtime") {
                                downloadSimulatorRuntime()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!areAllPreviousStepsComplete || isDownloadingRuntime || simulatorRuntimesStatus == .completed)
                            
                            if isDownloadingRuntime {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Downloading and installing runtime... This may take several minutes.")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    
                                    ProgressView(value: downloadProgress)
                                        .progressViewStyle(.linear)
                                    
                                    HStack {
                                        Text("\(Int(downloadProgress * 100))%")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        
                                        Spacer()
                                        
                                        if !downloadSizeInfo.isEmpty {
                                            Text(downloadSizeInfo)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Overall Status
                OverallStatusView(
                    isFullySetup: setupStatus?.isFullySetup ?? false,
                    isLoading: isLoading
                )
                
                Spacer(minLength: 32)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            xcodeDetector.setErrorCapturer(errorCapturer)

            refreshStatus()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
    
    // MARK: - Computed Properties
    
    private var xcodeInstallationStatus: CheckStatus {
        guard let status = setupStatus else { return .loading }
        return status.hasXcode ? .completed : .pending
    }
    
    private var isXcodeInstallationComplete: Bool {
        xcodeInstallationStatus == .completed
    }
    
    private var isXcodeSelectComplete: Bool {
        isXcodeInstallationComplete && xcodeSelectStatus == .completed
    }
    
    private var isLicenseComplete: Bool {
        isXcodeSelectComplete && licenseStatus == .completed
    }
    
    private var areAllPreviousStepsComplete: Bool {
        isXcodeInstallationComplete && isXcodeSelectComplete && isLicenseComplete
    }
    
    private var xcodeInstallationSubtitle: String {
        guard let status = setupStatus else { return "Checking..." }
        
        if status.hasXcode {
            let installations = status.xcodeInstallations.compactMap { $0.displayName }
            return "Found: \(installations.joined(separator: ", "))"
        } else {
            return "Xcode not found in Applications or Downloads"
        }
    }
    
    private var xcodeSelectStatus: CheckStatus {
        guard let status = setupStatus else { return .loading }
        return status.isXcodeSelectSetup ? .completed : .pending
    }
    
    private var xcodeSelectSubtitle: String {
        guard let status = setupStatus else { return "Checking..." }
        
        if status.isXcodeSelectSetup {
            return "Configured: \(status.xcodeSelectSetup.currentPath ?? "Unknown")"
        } else if let error = status.xcodeSelectSetup.error {
            return "Error: \(error)"
        } else {
            return "Command line tools not configured"
        }
    }
    
    private var licenseStatus: CheckStatus {
        guard let status = setupStatus else { return .loading }
        return status.isLicenseAccepted ? .completed : .pending
    }
    
    private var licenseSubtitle: String {
        guard let status = setupStatus else { return "Checking..." }
        
        if status.isLicenseAccepted {
            return "License agreement accepted"
        } else if let error = status.licenseAccepted.error {
            return "Error: \(error)"
        } else {
            return "Xcode license agreement not accepted"
        }
    }
    
    private var simulatorRuntimesStatus: CheckStatus {
        guard let status = setupStatus else { return .loading }
        return status.hasSimulatorRuntimes ? .completed : .pending
    }
    
    private var simulatorRuntimesSubtitle: String {
        guard let status = setupStatus else { return "Checking..." }
        
        if status.hasSimulatorRuntimes {
            let availableRuntimes = status.simulatorRuntimes.filter { $0.isAvailable }
            return "Found \(availableRuntimes.count) available runtime(s)"
        } else if let error = status.runtimeError {
            return "Error: \(error)"
        } else {
            return "No simulator runtimes available"
        }
    }
    
    // MARK: - Actions
    
    private func refreshStatus(showLoading: Bool = true) {
        if showLoading {
            isLoading = true
        }
        xcodeDetector.performCompleteCheck { status in
            DispatchQueue.main.async {
                let previousStatus = self.setupStatus
                self.setupStatus = status
                if showLoading {
                    self.isLoading = false
                }
                
                // Trigger callback if setup is now complete
                if status.isFullySetup {
                    onboardingManager.triggerXcodeSetupCompleted()
                }
            }
        }
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            // Only auto-refresh if not currently performing manual operations
            if !isSettingUpXcodeSelect && !isAcceptingLicense && !isDownloadingRuntime {
                refreshStatus(showLoading: false)
                
                // Update xcode-select command if we have Xcode but haven't passed the xcode-select check
                if isXcodeInstallationComplete && !isXcodeSelectComplete {
                    loadXcodeSelectCommand()
                }
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func loadXcodeSelectCommand() {
        xcodeDetector.getRecommendedXcodeSelectCommand { command in
            DispatchQueue.main.async {
                self.xcodeSelectCommand = command
            }
        }
    }
    
    private func runXcodeSelect() {
        guard let command = xcodeSelectCommand else {
            showError("No Xcode installation found to configure")
            return
        }
        
        isSettingUpXcodeSelect = true
        
        // Extract path from command
        let components = command.components(separatedBy: " ")
        guard components.count >= 3 else {
            showError("Invalid xcode-select command")
            isSettingUpXcodeSelect = false
            return
        }
        
        let path = components[2]
        
        xcodeDetector.setupXcodeSelect(path: path) { success, error in
            DispatchQueue.main.async {
                self.isSettingUpXcodeSelect = false
                
                if success {
                    self.refreshStatus(showLoading: true)
                } else {
                    self.showError(error ?? "Failed to setup xcode-select")
                }
            }
        }
    }
    
    private func acceptXcodeLicense() {
        isAcceptingLicense = true
        
        xcodeDetector.acceptXcodeLicense { success, error in
            DispatchQueue.main.async {
                self.isAcceptingLicense = false
                
                if success {
                    self.refreshStatus(showLoading: true)
                } else {
                    self.showError(error ?? "Failed to accept Xcode license")
                }
            }
        }
    }
    
    private func downloadSimulatorRuntime() {
        isDownloadingRuntime = true
        downloadProgress = 0.0
        downloadSizeInfo = ""
        
        xcodeDetector.downloadSimulatorRuntime(
            platform: "iOS",
            progressCallback: { progress, sizeInfo in
                self.downloadProgress = progress
                self.downloadSizeInfo = sizeInfo
            }
        ) { success, error in
            DispatchQueue.main.async {
                self.isDownloadingRuntime = false
                self.downloadProgress = 0.0
                self.downloadSizeInfo = ""
                
                if success {
                    self.refreshStatus(showLoading: true)
                } else {
                    self.showError(error ?? "Failed to download and install simulator runtime")
                }
            }
        }
    }
    
    private func showError(_ message: String) {
        currentError = message
        
        // Cancel existing timer
        errorTimer?.invalidate()
        
        // Set new timer for 10 seconds
        errorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            DispatchQueue.main.async {
                self.dismissError()
            }
        }
    }
    
    private func dismissError() {
        currentError = nil
        errorTimer?.invalidate()
        errorTimer = nil
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
}

// MARK: - Supporting Views

enum CheckStatus {
    case loading
    case pending
    case completed
    case error
}

struct ChecklistItem<Content: View>: View {
    let title: String
    let subtitle: String
    let status: CheckStatus
    let isLoading: Bool
    let isDisabled: Bool
    @ViewBuilder let content: Content
    
    init(title: String, subtitle: String, status: CheckStatus, isLoading: Bool, isDisabled: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Status Icon
                Group {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: statusIcon)
                            .foregroundColor(statusColor)
                            .font(.title2)
                    }
                }
                .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Action Content
            HStack {
                Spacer().frame(width: 36) // Align with text
                content
                Spacer()
            }
        }
        .padding(16)
        .background(Color.gray.opacity(isDisabled ? 0.02 : 0.05))
        .cornerRadius(12)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
    
    private var statusIcon: String {
        switch status {
        case .loading:
            return "clock"
        case .pending:
            return "circle"
        case .completed:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .loading:
            return .orange
        case .pending:
            return .gray
        case .completed:
            return .green
        case .error:
            return .red
        }
    }
}

struct ErrorView: View {
    let error: String
    let onCopy: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Error")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Button("Copy Error") {
                        onCopy()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Dismiss") {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

struct OverallStatusView: View {
    let isFullySetup: Bool
    let isLoading: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isFullySetup ? "checkmark.circle.fill" : "clock.circle")
                .font(.title)
                .foregroundColor(isFullySetup ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(isFullySetup ? "Setup Complete!" : "Setup in Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(isFullySetup ? 
                     "Your Xcode environment is ready for AI-powered testing" :
                     "Complete the steps above to finish setup")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFullySetup ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFullySetup ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    let errorCapturer = PreviewServices.errorCapturer
    let onboarding = PreviewServices.onboarding

    XcodeOnboardingView()
        .environmentObject(errorCapturer)
        .environmentObject(onboarding)
        .frame(width: 600, height: 800)
}
