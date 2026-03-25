//
//  MainScreen.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 02.06.2025.
//

import SwiftUI
import Foundation
import Logging

enum SettingsOpenReason {
    case manual               // Opened via menu
    case credentialsRequired  // Opened due to missing credentials
    case testRunRequested     // Opened because user tried to run test but needs credentials

    var stringValue: String {
        switch self {
        case .manual: return "manual"
        case .credentialsRequired: return "credentials_required"
        case .testRunRequested: return "test_run_requested"
        }
    }
}

struct MainScreen: View, Loggable {
    @ObservedObject private var runStorage: RunStorage
    @EnvironmentObject private var settingsService: SettingsService
    @EnvironmentObject private var credentialsService: CredentialsService
    @EnvironmentObject private var deviceService: DeviceService
    @EnvironmentObject private var errorCapturer: ErrorCapturerService
    @EnvironmentObject private var onboardingManager: OnboardingManager

    @StateObject private var viewModel: MainScreenViewModel
    @StateObject private var suiteRunner: TestSuiteRunner
    @StateObject private var xcodeDetector: XcodeDetector
    @StateObject private var chatReplayViewModel = ChatReplayViewModel()
    @State private var selectedFile: URL?
    @State private var hasRuntime = false
    @StateObject private var replayState = ReplayState()
    @State private var showingXcodeOnboarding = false
    @State private var isCheckingXcodeSetup = true
    @State private var showingSettings = false
    @State private var settingsOpenReason: SettingsOpenReason = .manual
    @State private var updateFileURLCallback: ((URL) -> Void)?
    @State private var saveFileCallback: (() -> Void)?
    @State private var credentialsCallbackTokens: [CallbackToken] = []
    @State private var onboardingCallbackTokens: [CallbackToken] = []
    @State private var selectedReportHistory: RunHistory?
    @State private var isTestRunOpened = false
    @State private var pinnedRunHistory: RunHistory?
    @State private var pinnedRunFileURL: URL?
    @State private var lastLiveRunHistory: RunHistory?
    @State private var lastLiveRunFileURL: URL?
    @State private var showingDeviceSetupHelp = false
    @State private var actionsCallbackInstalled = false

    init(
        runStorage: RunStorage,
        errorCapturer: ErrorCapturerService,
        credentialsService: CredentialsService,
        idbManager: IdbManaging,
        onboardingManager: OnboardingManager
    ) {
        let initializedViewModel = MainScreenViewModel(errorCapturer: errorCapturer)
        let suiteRunner = TestSuiteRunner(
            documentsURL: initializedViewModel.documentsURL,
            runStorage: runStorage,
            credentialsService: credentialsService,
            idbManager: idbManager,
            errorCapturer: errorCapturer
        )
        _runStorage = ObservedObject(wrappedValue: runStorage)
        _viewModel = StateObject(wrappedValue: initializedViewModel)
        _suiteRunner = StateObject(wrappedValue: suiteRunner)
        _xcodeDetector = StateObject(wrappedValue: XcodeDetector(errorCapturer: errorCapturer))
    }

    // MARK: - Computed Properties

    /// Whether any blocking overlay is currently shown (tips should be hidden)
    private var hasBlockingOverlays: Bool {
        showingXcodeOnboarding || showingSettings || showingDeviceSetupHelp
    }

    private var effectiveRunHistory: RunHistory? {
        if isTestRunOpened {
            return selectedReportHistory
        }

        return suiteRunner.currentRunHistory ?? pinnedRunHistory
    }

    var body: some View {
        let currentLiveRunHistory = suiteRunner.currentRunHistory
        let chatRunHistory = effectiveRunHistory
        let shouldShowAssistant = chatRunHistory != nil
        let chatFileURL: URL? = {
            if isTestRunOpened {
                return selectedFile
            }

            if currentLiveRunHistory != nil {
                return lastLiveRunFileURL ?? runStorage.currentTestURL()
            }

            if pinnedRunHistory != nil {
                return pinnedRunFileURL
            }

            return nil
        }()
        let assistantContent = shouldShowAssistant ? chatRunHistory.map { history in
            {
                ChatReplayView(
                    fileURL: chatFileURL,
                    viewModel: chatReplayViewModel,
                    runHistory: history,
                    replayState: replayState,
                    errorCapturer: errorCapturer
                )
                .id(ObjectIdentifier(history))
                .ignoresSafeArea()
                .onboardingTip(.chatReplay)
            }
        } : nil

        return NSFloatingSplitViewRepresentable(
            leftContent: {
                // Left column - Sidebar
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    // File Tree
                    FileTreeView(
                        rootURL: viewModel.documentsURL,
                    errorCapturer: errorCapturer,
                        onboardingManager: onboardingManager,
                        statusProvider: { fileURL in
                            fileRunStatus(for: fileURL)
                        },
                        onFileSelected: { selectedURL in
                            selectedFile = selectedURL

                            pinnedRunHistory = nil
                            pinnedRunFileURL = nil

                            viewModel.selectedFileName = selectedURL.lastPathComponent
                            viewModel.errorMessage = nil

                            let fileExtension = selectedURL.pathExtension.lowercased()
                            let isJSON = fileExtension == "json"
                            let isTest = fileExtension == "test"
                            let isPromptFile = fileExtension == "txt"
                            let isRules = selectedURL.lastPathComponent == ".qaltirules"

                            viewModel.showTestEditor = isJSON || isTest || isPromptFile || isRules

                            if isJSON {
                                isTestRunOpened = true
                                selectedReportHistory = RunHistory()
                            } else {
                                isTestRunOpened = false
                                selectedReportHistory = nil
                            }
                        },
                        onFileRenamed: { oldURL, newURL in
                            // Only update if the renamed file is the currently selected file
                            if selectedFile == oldURL {
                                selectedFile = newURL
                                updateFileURLCallback?(newURL)
                                viewModel.selectedFileName = newURL.lastPathComponent
                            }
                        },
                        onRunFolder: { folderURL in
                            runSuiteWithCredentialsCheck(folderURL: folderURL)
                        }
                    )
                }
                .ignoresSafeArea()
            },
            middleContent: {
                // Middle content - Test Editor or Placeholder
                Group {
                    if viewModel.showTestEditor {
                        TestEditingView(
                            fileURL: selectedFile,
                            showTestEditor: $viewModel.showTestEditor,
                            errorMessage: $viewModel.errorMessage,
                            isTestRun: $isTestRunOpened,
                            errorCapturer: errorCapturer,
                            setUpdateFileURLCallback: { callback in
                                updateFileURLCallback = callback
                            },
                            setSaveFileCallback: { callback in
                                saveFileCallback = callback
                            },
                            onReportRunHistoryChanged: { history in
                                guard selectedFile?.pathExtension.lowercased() == "json" else { return }
                                selectedReportHistory = history
                            }
                        )
                        .environmentObject(suiteRunner)
                        .onboardingTip(.testArea)
                    } else {
                        ContentPlaceholderView(
                            selectedFileName: viewModel.selectedFileName,
                            errorMessage: viewModel.errorMessage
                        )
                    }
                }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    if viewModel.showTestEditor && !isTestRunOpened {
                        TestControlPanel(
                            runState: suiteRunner,
                            viewModel: viewModel,
                            hasRuntime: hasRuntime,
                            selectedFile: selectedFile,
                            isSuiteRunning: suiteRunner.isRunning && suiteRunner.totalCount > 1,
                            onRunTest: runTestWithCredentialsCheck,
                            onStop: { suiteRunner.stopCurrentRun() }
                        )
                    }
                }
            },
            assistantContent: assistantContent,
            rightContent: {
                // Right floating panel - Simulator/Real Device
                TargetSelectorView(
                    onTargetViewAppear: {
                        // Callback for when target view appears, if needed
                    },
                    onRuntimeChanged: { runtime in
                        suiteRunner.setRuntime(runtime)
                        hasRuntime = runtime != nil
                        if runtime != nil {
                            onboardingManager.complete(.pickSimulator)
                        }
                    },
                    onShowDeviceSetupHelp: {
                        showDeviceSetupHelp(source: "question_mark_button")
                    },
                    onShowDeviceSetupHelpFromLink: {
                        showDeviceSetupHelp(source: "placeholder_link")
                    },
                    isXcodeSetupComplete: !showingXcodeOnboarding && !isCheckingXcodeSetup,
                    idbManager: deviceService.manager,
                    errorCapturer: errorCapturer,
                    onboardingManager: onboardingManager
                )
                .overlay(
                    Group {
                        if let screenshot = replayState.screenshot {
                            ReplayOverlayView(screenshot: screenshot, markers: replayState.markers)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
                .ignoresSafeArea()
            }
        )
        .ignoresSafeArea()
        .legacy_containerBackground(.thick)
        .overlay(
            // Blocking overlays
            Group {
                if showingXcodeOnboarding {
                    ZStack {
                        // Semi-transparent background that blocks interaction
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        // Onboarding view
                        XcodeOnboardingView()
                            .frame(maxWidth: 800, maxHeight: 600)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(12)
                            .shadow(radius: 20)
                    }
                    .background(.thinMaterial)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showingXcodeOnboarding)
                } else if showingSettings {
                    GeometryReader { geometry in
                        ZStack {
                            // Semi-transparent background that blocks interaction
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()

                            // Settings view
                            SettingsView(
                                openReason: settingsOpenReason,
                                onClose: hideSettings
                            )
                            .frame(maxWidth: 600, maxHeight: min(750, geometry.size.height - 40))
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(12)
                            .shadow(radius: 20)
                        }
                    }
                    .background(.thinMaterial)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showingSettings)
                } else if showingDeviceSetupHelp {
                    GeometryReader { geometry in
                        ZStack {
                            // Semi-transparent background that blocks interaction
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()

                            DeviceSetupHelpView { _ in
                                showingDeviceSetupHelp = false
                            }
                                .frame(maxWidth: 700, maxHeight: min(650, geometry.size.height - 40))
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(12)
                                .shadow(radius: 20)
                        }
                    }
                    .background(.thinMaterial)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showingDeviceSetupHelp)
                }
            }
        )
        .onAppear {
            viewModel.createQaltiFolderIfNeeded()

            // Check Xcode setup first
            checkXcodeSetup()

            hasRuntime = suiteRunner.hasRuntime

            // Setup settings listeners
            setupSettingsListeners()

            // Setup Xcode setup completion listener
            let xcodeToken = onboardingManager.addXcodeSetupCompletedCallback {
                DispatchQueue.main.async {
                    self.checkXcodeSetup()
                }
            }
            onboardingCallbackTokens.append(xcodeToken)

            // Initialize blocking overlay state
            onboardingManager.updateBlockingOverlayState(hasBlockingOverlays)
        }
        .onFocusChange { isFocused in
            if !isFocused {
                saveFileCallback?()
            }
        }
        .onReceive(suiteRunner.$currentRunHistory) { history in
            if let history {
                lastLiveRunHistory = history
                lastLiveRunFileURL = runStorage.currentTestURL()
                return
            }

            guard !isTestRunOpened else { return }

            pinnedRunHistory = lastLiveRunHistory
            pinnedRunFileURL = lastLiveRunFileURL
        }
        .onDisappear {
            cleanupSettingsListeners()

            // Reset blocking overlay state
            onboardingManager.updateBlockingOverlayState(false)
        }
        .onChange(of: hasBlockingOverlays) { _, newValue in
            onboardingManager.updateBlockingOverlayState(newValue)
        }
    }

    // MARK: - Xcode Setup Management

    private func checkXcodeSetup() {
        isCheckingXcodeSetup = true

        xcodeDetector.performCompleteCheck { status in
            DispatchQueue.main.async {
                self.isCheckingXcodeSetup = false

                if !status.isFullySetup {
                    self.showingXcodeOnboarding = true
                } else {
                    self.showingXcodeOnboarding = false

                    // If we're on the xcodeSetup tip and Xcode is fully set up, advance to next tip
                    if onboardingManager.currentTipType == .xcodeSetup {
                        onboardingManager.complete(.xcodeSetup)
                    }
                }
            }
        }
    }

    // MARK: - Settings Overlay

    private func setupSettingsListeners() {
        // Clear any existing tokens first
        cleanupSettingsListeners()

        // Listen for credentials required callbacks
        let credentialsRequiredToken = credentialsService.addCredentialsRequiredCallback {
            DispatchQueue.main.async {
                self.showSettings(reason: .credentialsRequired)
            }
        }
        credentialsCallbackTokens.append(credentialsRequiredToken)

        // triggerInsufficientBalance() also routes through notifyCredentialsRequired(),
        // so both auth and balance issues are handled by this callback.

        // Listen for CredentialsService changes to auto-hide settings overlay
        let credentialsChangedToken = credentialsService.addCredentialsChangedCallback {
            DispatchQueue.main.async {
                guard self.showingSettings else { return }

                if self.settingsOpenReason == .testRunRequested {
                    // API key was set after trying to run a test - auto run the selected test
                    self.hideSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard let fileURL = self.selectedFile else {
                            self.suiteRunner.presentUserError("Select a test file before running.")
                            return
                        }
                        self.suiteRunner.runTests(
                            at: [fileURL],
                            model: self.viewModel.selectedModel,
                            recordVideo: self.settingsService.isVideoRecordingEnabled,
                            deleteSuccessfulVideo: self.settingsService.shouldRemoveVideoOnSuccess
                        )
                        onboardingManager.complete(.runFirstTest)
                    }
                } else if self.settingsOpenReason == .credentialsRequired {
                    // Regular credentials issue - just hide after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.hideSettings()
                    }
                }
            }
        }
        credentialsCallbackTokens.append(credentialsChangedToken)

        // Listen for manual settings requests from menu via OnboardingManager
        let settingsToken = onboardingManager.addShowSettingsCallback {
            DispatchQueue.main.async {
                self.showSettings(reason: .manual)
            }
        }
        onboardingCallbackTokens.append(settingsToken)
    }

    private func cleanupSettingsListeners() {
        for token in credentialsCallbackTokens {
            credentialsService.removeCallback(token)
        }
        credentialsCallbackTokens.removeAll()

        for token in onboardingCallbackTokens {
            onboardingManager.removeCallback(token)
        }
        onboardingCallbackTokens.removeAll()
    }

    private func showSettings(reason: SettingsOpenReason = .manual) {
        settingsOpenReason = reason
        showingSettings = true
    }

    private func hideSettings() {
        showingSettings = false
    }

    // MARK: - Test Running with Credentials Check

    /// Attempts to run a test, checking credentials first
    /// If credentials are required, shows the settings overlay
    /// and will auto-run the test once credentials are provided
    func runTestWithCredentialsCheck(fileURL: URL?, model: TestRunner.AvailableModel) {
        guard let fileURL else {
            suiteRunner.presentUserError("Select a test file before running.")
            return
        }
        // Check if credentials exist first
        if !credentialsService.hasCredentials {
            // Show settings with test run reason
            showSettings(reason: .testRunRequested)
            return
        }

        // Credentials are available, run the test directly
        saveFileCallback?()
        suiteRunner.runTests(
            at: [fileURL],
            model: model,
            recordVideo: settingsService.isVideoRecordingEnabled,
            deleteSuccessfulVideo: settingsService.shouldRemoveVideoOnSuccess
        )

        if onboardingManager.currentTipType == .runFirstTest {
            onboardingManager.complete(.runFirstTest)
        }
    }

    func runSuiteWithCredentialsCheck(folderURL: URL) {
        guard !suiteRunner.isRunning else {
            suiteRunner.presentUserError("Another suite run is already in progress.")
            return
        }

        if !credentialsService.hasCredentials {
            showSettings(reason: .testRunRequested)
            return
        }

        startSuiteRun(folderURL: folderURL)
    }

    private func startSuiteRun(folderURL: URL) {
        saveFileCallback?()
        suiteRunner.runTests(
            at: [folderURL],
            model: viewModel.selectedModel,
            recordVideo: settingsService.isVideoRecordingEnabled,
            deleteSuccessfulVideo: settingsService.shouldRemoveVideoOnSuccess
        )

        if onboardingManager.currentTipType == .runFirstTest {
            onboardingManager.complete(.runFirstTest)
        }
    }

    // MARK: - File Status Indicators

    private func fileRunStatus(for fileURL: URL) -> RunIndicatorStatus? {
        if let state = runStorage.status(for: fileURL) {
            return RunIndicatorStatus(state: state)
        }
        if let finishedState = runStorage.finishedStatuses[fileURL.standardizedFileURL] {
            return RunIndicatorStatus(state: finishedState)
        }
        return nil
    }

    // MARK: - Device Setup Help

    private func showDeviceSetupHelp(source: String) {
        showingDeviceSetupHelp = true
    }
}

struct ContentPlaceholderView: View {
    let selectedFileName: String?
    let errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let selectedFileName = selectedFileName {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text(selectedFileName)
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        Text("This file type is not supported for test editing.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "testtube.2")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("Select a JSON file to edit tests")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text("Choose a test file from the sidebar to start editing")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}




@MainActor
class MainScreenViewModel: ObservableObject, Loggable {
    @Published var selectedFileName: String?
    @Published var showTestEditor = false
    @Published var errorMessage: String?
    @Published var selectedModel: TestRunner.AvailableModel = .gpt41

    private let errorCapturer: ErrorCapturing
    private(set) var documentsURL: URL
    private let selectedModelKey = "aiqa_selected_model"

    private var runsURL: URL {
        return documentsURL.appendingPathComponent("Runs")
    }

    init(errorCapturer: ErrorCapturing) {
        self.errorCapturer = errorCapturer

        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.documentsURL = documentsPath.appendingPathComponent("Qalti")

        // Load saved model from UserDefaults
        loadSelectedModel()
    }

    private func loadSelectedModel() {
        if let savedModelString = UserDefaults.standard.string(forKey: selectedModelKey),
           let savedModel = TestRunner.AvailableModel(rawValue: savedModelString) {
            selectedModel = savedModel
        }
    }

    func updateSelectedModel(_ model: TestRunner.AvailableModel) {
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: selectedModelKey)
    }

    func createQaltiFolderIfNeeded() {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: documentsURL.path) {
            do {
                try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
                logger.debug("Created Qalti folder at: \(documentsURL.path)")
            } catch {
                errorCapturer.capture(error: error)
                logger.error("Failed to create Qalti folder: \(error)")
            }
        }

        if !fileManager.fileExists(atPath: documentsURL.appendingPathComponent("Tests").path) {
            do {
                try fileManager.createDirectory(at: documentsURL.appendingPathComponent("Tests"), withIntermediateDirectories: true, attributes: nil)
                logger.debug("Created Tests folder at: \(documentsURL.appendingPathComponent("Tests").path)")
            } catch {
                errorCapturer.capture(error: error)
                logger.error("Failed to create Tests folder: \(error)")
            }
        }

        if !fileManager.fileExists(atPath: runsURL.path) {
            do {
                try fileManager.createDirectory(at: runsURL, withIntermediateDirectories: true, attributes: nil)
                logger.debug("Created Runs folder at: \(runsURL.path)")
            } catch {
                errorCapturer.capture(error: error)
                logger.error("Failed to create Runs folder: \(error)")
            }
        }
    }
}

#Preview {
    let runStorage = PreviewServices.mockRunStorage
    let settings = PreviewServices.mockSettings
    let errorCapturer = PreviewServices.errorCapturer
    let credentials = PreviewServices.credentials
    let onboarding = PreviewServices.onboarding
    let suiteRunner = PreviewServices.makeSuiteRunner()
    let idb = PreviewServices.fakeIdb

    let deviceService = DeviceService(manager: idb)

    MainScreen(
        runStorage: runStorage,
        errorCapturer: errorCapturer,
        credentialsService: credentials,
        idbManager: idb,
        onboardingManager: onboarding
    )
    .environmentObject(runStorage)
    .environmentObject(settings)
    .environmentObject(credentials)
    .environmentObject(errorCapturer)
    .environmentObject(onboarding)
    .environmentObject(suiteRunner)
    .environmentObject(deviceService)
    .frame(width: 1200, height: 800)
}
