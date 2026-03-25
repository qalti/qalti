//  OnboardingManager.swift
//  Qalti
//
//  Created by AI Assistant on 02.07.2025.
//

import Foundation
import Logging
import SwiftUI

// MARK: - Tip Types

public enum TipType: String, CaseIterable {
    case xcodeSetup
    case createFirstTest
    case testArea
    case pickSimulator
    case chooseModel
    case runFirstTest
    case chatReplay
}

// MARK: - Tip Content

public struct TipContent {
    public let title: String
    public let message: String
    public let systemImage: String
    
    public init(title: String, message: String, systemImage: String) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }
    
    public static func content(for tipType: TipType) -> TipContent {
        switch tipType {
        case .xcodeSetup:
            return TipContent(title: "", message: "", systemImage: "hammer.fill")
        case .createFirstTest:
            return TipContent(
                title: "Create your first test",
                message: """
                Right-click the **Tests** folder and
                choose **+ Add new test**.
                
                A tutorial template will appear
                automatically to get you started.
                """,
                systemImage: "doc.badge.plus"
            )
        case .testArea:
            return TipContent(
                title: "Meet the test editor",
                message: """
                This is where you write your tests!
                
                Each line is a human-readable action
                that the AI agent will execute.
                
                The tutorial shows you the basics.
                """,
                systemImage: "doc.text"
            )
        case .pickSimulator:
            return TipContent(
                title: "Pick a simulator to test on",
                message: """
                Choose any booted device or start
                a new one – the agent will run inside it.
                """,
                systemImage: "iphone"
            )
        case .chooseModel:
            return TipContent(
                title: "Choose your AI model",
                message: """
                We recommend **GPT-4.1** for
                balanced speed & accuracy.
                
                You can change it any time.
                """,
                systemImage: "brain"
            )
        case .runFirstTest:
            return TipContent(
                title: "Ready to see magic happen?",
                message: """
                Hit **Run** to watch the AI
                agent execute your test.
                """,
                systemImage: "play.fill"
            )
        case .chatReplay:
            return TipContent(
                title: "Explore what happened",
                message: """
                After the test runs, this **Chat Replay**
                panel shows you every prompt, response,
                and screenshot.
                
                It's like watching the AI think!
                """,
                systemImage: "bubble.left.and.bubble.right"
            )
        }
    }
}

/// Centralised helper that takes care of first-run product onboarding.
/// Manages popover presentation states and tracks user progress through onboarding steps.
@MainActor
public final class OnboardingManager: ObservableObject, Loggable {
    // MARK: - Onboarding State
    
    /// Current onboarding step index (0-based)
    @Published public var currentStepIndex: Int = 0
    
    /// Whether blocking overlays are currently shown (tips should be hidden)
    @Published public var hasBlockingOverlays: Bool = false

    /// Sequential list of onboarding tips
    public static let onboardingSteps: [TipType] = [
        .xcodeSetup,                    // 0
        .createFirstTest,               // 1
        .testArea,                      // 2
        .pickSimulator,                 // 3
        .chooseModel,                   // 4
        .runFirstTest,                  // 5
        .chatReplay,                    // 6
    ]
    
    /// Total number of onboarding steps
    public static let totalSteps = onboardingSteps.count

    // MARK: - Callback System
    
    /// Callbacks for settings requests
    private var showSettingsCallbacks: [CallbackToken: () -> Void] = [:]
    
    /// Callbacks for Xcode setup completion
    private var xcodeSetupCompletedCallbacks: [CallbackToken: () -> Void] = [:]
    
    init() {
        // Load current step from UserDefaults
        currentStepIndex = UserDefaults.standard.integer(forKey: "onboardingStepIndex")
        logger.debug("Initialized - currentStepIndex: \(currentStepIndex), currentTip: \(currentTipType?.rawValue ?? "completed")")
    }
    
    // MARK: - Computed Properties
    
    /// Whether onboarding is completed
    public var isOnboardingCompleted: Bool {
        currentStepIndex >= Self.totalSteps
    }
    
    /// Current tip type (nil if onboarding completed)
    public var currentTipType: TipType? {
        guard currentStepIndex < Self.totalSteps else { return nil }
        return Self.onboardingSteps[currentStepIndex]
    }
    
    /// Advances to the next onboarding step
    private func advanceToNextStep() {
        let completedStep = currentStepIndex
        let completedTip = currentTipType?.rawValue ?? "none"

        objectWillChange.send()
        currentStepIndex += 1
        UserDefaults.standard.set(currentStepIndex, forKey: "onboardingStepIndex")
        UserDefaults.standard.synchronize()
        
        logger.debug("Advanced from step \(completedStep) (\(completedTip)) to step \(currentStepIndex) (\(currentTipType?.rawValue ?? "completed"))")
    }
    
    /// Resets all onboarding progress - useful for debugging
    public func resetAllOnboardingProgress() {
        logger.debug("Resetting all onboarding progress...")
        
        let previousStep = currentStepIndex
        
        objectWillChange.send()
        currentStepIndex = 0
        
        UserDefaults.standard.set(0, forKey: "onboardingStepIndex")
        UserDefaults.standard.synchronize()
        
        logger.debug("Reset complete - currentStepIndex: \(currentStepIndex), currentTip: \(currentTipType?.rawValue ?? "none")")
    }
    
    /// Skips all onboarding progress by completing all steps - useful for debugging
    public func skipOnboarding() {
        logger.info("Skipping onboarding...")
        
        objectWillChange.send()
        currentStepIndex = Self.totalSteps
        
        UserDefaults.standard.set(Self.totalSteps, forKey: "onboardingStepIndex")
        UserDefaults.standard.synchronize()
        
        logger.debug("Skip complete - currentStepIndex: \(currentStepIndex), onboarding completed: \(isOnboardingCompleted)")
    }
    
    // MARK: - Action Handlers
    
    /// Complete the specified onboarding tip, advancing to the next step if the tip is currently active
    /// This prevents misclicks and ensures proper progression through the onboarding flow
    public func complete(_ tip: TipType) {
        guard currentTipType == tip else {
            logger.debug("Ignoring completion of \(tip.rawValue) - current tip is \(currentTipType?.rawValue ?? "none")")
            return
        }
        
        logger.debug("Completing tip: \(tip.rawValue)")
        advanceToNextStep()
    }
    
    // MARK: - Manual Tip Control
    
    public func dismissTip(_ tipType: TipType) {
        logger.debug("Dismissing tip: \(tipType.rawValue)")
        complete(tipType)
    }

    // MARK: - Callback Management
    
    /// Registers a callback for settings requests
    /// Returns a token that can be used to remove the callback
    @discardableResult
    public func addShowSettingsCallback(_ callback: @escaping () -> Void) -> CallbackToken {
        let token = CallbackToken()
        showSettingsCallbacks[token] = callback
        logger.debug("Added showSettings callback (token: \(token.id))")
        return token
    }
    
    /// Registers a callback for Xcode setup completion
    /// Returns a token that can be used to remove the callback
    @discardableResult
    public func addXcodeSetupCompletedCallback(_ callback: @escaping () -> Void) -> CallbackToken {
        let token = CallbackToken()
        xcodeSetupCompletedCallbacks[token] = callback
        logger.debug("Added xcodeSetupCompleted callback (token: \(token.id))")
        return token
    }
    
    /// Removes a callback using its token
    public func removeCallback(_ token: CallbackToken) {
        let removedSettings = showSettingsCallbacks.removeValue(forKey: token) != nil
        let removedXcode = xcodeSetupCompletedCallbacks.removeValue(forKey: token) != nil
        
        if removedSettings || removedXcode {
            logger.debug("Removed callback (token: \(token.id))")
        }
    }
    
    /// Triggers all registered settings callbacks
    public func triggerShowSettings() {
        logger.debug("Triggering showSettings callbacks (\(showSettingsCallbacks.count) registered)")
        for callback in showSettingsCallbacks.values {
            callback()
        }
    }
    
    /// Triggers all registered Xcode setup completed callbacks
    public func triggerXcodeSetupCompleted() {
        logger.debug("Triggering xcodeSetupCompleted callbacks (\(xcodeSetupCompletedCallbacks.count) registered)")
        for callback in xcodeSetupCompletedCallbacks.values {
            callback()
        }
    }
    
    /// Clears all registered callbacks - useful for cleanup
    public func clearAllCallbacks() {
        logger.debug("Clearing all callbacks")
        showSettingsCallbacks.removeAll()
        xcodeSetupCompletedCallbacks.removeAll()
    }
    
    // MARK: - Overlay State Management
    
    /// Updates the blocking overlay state to hide/show tips appropriately
    public func updateBlockingOverlayState(_ hasOverlays: Bool) {
        guard hasBlockingOverlays != hasOverlays else { return }
        
        hasBlockingOverlays = hasOverlays
        logger.debug("Updated blocking overlay state: \(hasOverlays ? "overlays shown, tips hidden" : "overlays hidden, tips shown")")
    }
}
