import SwiftUI
import Logging

#if os(macOS)
import AppKit
import ObjectiveC
#endif

struct QaltiApp: App {
        #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        #endif

    @StateObject private var runStorage = RunStorage()
    @StateObject private var settingsService = SettingsService()
    @StateObject private var errorCapturer: ErrorCapturerService
    @StateObject private var credentialsService: CredentialsService
    @StateObject private var deviceService: DeviceService
    @StateObject private var onboardingManager: OnboardingManager
    @StateObject private var permissionService = PermissionService()

    init() {
        let errorCapturer = ErrorCapturerService()
        let credentials = CredentialsService(errorCapturer: errorCapturer)
        let deviceService = DeviceService(manager: IdbManager(errorCapturer: errorCapturer))
        let onboarding = OnboardingManager()

        _errorCapturer = StateObject(wrappedValue: errorCapturer)
        _credentialsService = StateObject(wrappedValue: credentials)
        _deviceService = StateObject(wrappedValue: deviceService)
        _onboardingManager = StateObject(wrappedValue: onboarding)
    }

    var body: some Scene {
        WindowGroup {
            MainScreen(
                runStorage: runStorage,
                errorCapturer: errorCapturer,
                credentialsService: credentialsService,
                idbManager: deviceService.manager,
                onboardingManager: onboardingManager
            )
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .environmentObject(runStorage)
            .environmentObject(settingsService)
            .environmentObject(credentialsService)
            .environmentObject(deviceService)
            .environmentObject(errorCapturer)
            .environmentObject(onboardingManager)
            .environmentObject(permissionService)
        }
        .legacy_defaultSize(width: 1200, height: 700)
        .platformHideTitleBar()
        .commands {
            #if os(macOS)
            CommandMenu("Recording") {
                Toggle("Record Video of Tests", isOn: $settingsService.isVideoRecordingEnabled)
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                Toggle("Delete Video of Successful Runs", isOn: $settingsService.shouldRemoveVideoOnSuccess)
                    .disabled(!settingsService.isVideoRecordingEnabled)
            }
            CommandMenu("Tools") {
                Button("Skip Onboarding") {
                    onboardingManager.skipOnboarding()
                }
                
                if AppConstants.isDebug {
                    Button("Reset Onboarding") {
                        onboardingManager.resetAllOnboardingProgress()
                    }
                    
                    Button("Export Default Prompts") {
                        exportDefaultPrompts()
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }

                Divider()

                Button("Open Logs Folder") {
                    let logsDir = AppLogging.logsDirectory
                    try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(logsDir)
                }
            }
            
            // Remove default options that allow creating new windows or tabs
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .windowList) {}
            // Remove the Services menu from the application menu
            CommandGroup(replacing: .systemServices) {}
            
            // Settings shortcut
            CommandGroup(after: .appInfo) {
                Button("Settings…") {
                    // Trigger callback to MainScreen to show settings overlay
                    onboardingManager.triggerShowSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
                
                Divider()
            }
            #endif

        }
    }
    
    // MARK: - Menu Actions
    
    /// Export all default prompts to .qalti/prompts directory
    private func exportDefaultPrompts() {
        let result = PromptExporter.shared.exportDefaultPrompts()
        
        DispatchQueue.main.async {
            switch result {
            case .success(let message, let exportedFiles, let directoryPath):
                showAlert(
                    title: "Prompts Exported Successfully", 
                    message: message,
                    informativeText: "Exported \(exportedFiles.count) prompt files. You can now customize them by editing the files directly."
                )
                
            case .failure(let error):
                showAlert(
                    title: "Export Failed", 
                    message: error,
                    informativeText: "Please check the error details and try again."
                )
            }
        }
    }

    
    /// Show an alert dialog
    private func showAlert(title: String, message: String, informativeText: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let informativeText = informativeText {
            alert.informativeText += "\n\n\(informativeText)"
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}


#if os(macOS)

class AppDelegate: NSObject, NSApplicationDelegate, Loggable {

    override init() {
        super.init()
        // Bootstrap logging as early as possible to ensure consistent formatting
        AppLogging.bootstrap(stderrLevel: AppConstants.isDebug ? .debug : .info, fileLevel: .debug)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows" : false])

        // Disable automatic tabbing support for all windows
        NSWindow.allowsAutomaticWindowTabbing = false

        // Swizzle NSToolbarView methods
        swizzleNSToolbarViewMethods()
        
        // Get all the application windows
        let allWindows = NSApplication.shared.windows
        
        // Find the main window (with TargetSelectorView)
        guard let mainWindow = allWindows.first else { return }

        // Disallow creating new tabs on the main window
        mainWindow.tabbingMode = .disallowed

        // Hide the Services menu
        NSApplication.shared.servicesMenu = nil

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.displayMode = .iconAndLabel
        toolbar.isVisible = false
        toolbar.allowsUserCustomization = false
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.titleVisibility = .hidden
        mainWindow.toolbar = toolbar

        try? ScreenCaptureService.enableScreenCaptureDevices()
        try? ScreenCaptureService.enableWirelessScreenCaptureDevices()

        _ = ScreenCaptureService.listDevices()
    }
    
    private func swizzleNSToolbarViewMethods() {
        guard let toolbarViewClass = NSClassFromString("NSToolbarView") else {
            logger.error("Failed to get NSToolbarView class")
            return
        }
        
        // Swizzle _shouldStealHitTestForCurrentEvent
        let shouldStealSelector = NSSelectorFromString("_shouldStealHitTestForCurrentEvent")
        let shouldStealMethod = class_getInstanceMethod(toolbarViewClass, shouldStealSelector)
        let shouldStealImplementation = imp_implementationWithBlock({ (self: AnyObject) -> Bool in
            return false
        } as @convention(block) (AnyObject) -> Bool)
        
        if let shouldStealMethod = shouldStealMethod {
            method_setImplementation(shouldStealMethod, shouldStealImplementation)
        }
        
        // Swizzle hitTest:
        let hitTestSelector = NSSelectorFromString("hitTest:")
        let hitTestMethod = class_getInstanceMethod(toolbarViewClass, hitTestSelector)
        let hitTestImplementation = imp_implementationWithBlock({ (self: AnyObject, point: CGPoint) -> NSView? in
            return nil
        } as @convention(block) (AnyObject, CGPoint) -> NSView?)
        
        if let hitTestMethod = hitTestMethod {
            method_setImplementation(hitTestMethod, hitTestImplementation)
        }
    }
}

#endif
