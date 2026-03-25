//  PopoverTips.swift
//  Qalti
//
//  Created by AI Assistant on 02.07.2025.
//

import SwiftUI

// MARK: - Text Extensions

extension Text {
    /// Creates a Text view with markdown parsing that preserves whitespace
    init(markdown: String) {
        let attributedString = (try? AttributedString(
            markdown: markdown, 
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
        
        self.init(attributedString)
    }
}

// MARK: - Popover Tip View Modifiers

extension View {
    /// Shows a popover tip for the specified onboarding tip type
    func onboardingTip(_ tipType: TipType) -> some View {
        self.modifier(PopoverTipModifier(tipType: tipType))
    }
}

// MARK: - Popover Tip Modifier

private struct PopoverTipModifier: ViewModifier {
    let tipType: TipType

    @EnvironmentObject private var onboardingManager: OnboardingManager

    private var isPresented: Binding<Bool> {
        return Binding(
            get: { 
                // Hide tips when blocking overlays are shown
                guard !onboardingManager.hasBlockingOverlays else { return false }
                return onboardingManager.currentTipType == tipType 
            },
            set: { _ in /* No-op, tips are controlled by the onboarding flow */ }
        )
    }
    
    private var arrowEdge: Edge {
        switch tipType {
        case .xcodeSetup:
            return .bottom
        case .createFirstTest:
            return .leading
        case .testArea:
            return .leading
        case .pickSimulator:
            return .trailing
        case .chooseModel:
            return .bottom
        case .runFirstTest:
            return .bottom
        case .chatReplay:
            return .trailing
        }
    }
    
    func body(content: Content) -> some View {
        content
            .popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                TipPopoverContent(tipType: tipType)
                    .interactiveDismissDisabled()
            }
    }
}

// MARK: - Tip Popover Content

private struct TipPopoverContent: View {
    let tipType: TipType
    @EnvironmentObject var onboardingManager: OnboardingManager

    private var content: TipContent {
        TipContent.content(for: tipType)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack(spacing: 8) {
                Image(systemName: content.systemImage)
                    .foregroundColor(.label)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(content.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            // Message content
            Text(markdown: content.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)

            // Conditional "Got it" button for specific tips
            if shouldShowGotItButton {
                HStack {
                    Spacer()
                    
                    Button("Got it!") {
                        handleGotItAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: 300) // Add max height constraint
    }
    
    private var shouldShowGotItButton: Bool {
        switch tipType {
        case TipType.testArea, TipType.chatReplay, TipType.chooseModel:
            return true
        default:
            return false
        }
    }
    
    private func handleGotItAction() {
        onboardingManager.complete(tipType)
    }

}

// MARK: - Convenience Views

/// A view that shows multiple tips in sequence - useful for testing
struct OnboardingTipsPreview: View {
    @EnvironmentObject private var onboardingManager: OnboardingManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Onboarding Tips Preview")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Test the different tip behaviors")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Action-Driven Tips (Unskippable)
            VStack(alignment: .leading, spacing: 12) {
                Text("Action-Driven Tips (Unskippable)")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach(
                        [
                            TipType.xcodeSetup, TipType.createFirstTest, TipType.pickSimulator, TipType.chooseModel,
                            TipType.runFirstTest
                        ],
                        id: \.self
                    ) { tipType in
                        TipTestButton(tipType: tipType, onboardingManager: onboardingManager)
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            
            // Dismissible Tips (With "Got it!" Button)
            VStack(alignment: .leading, spacing: 12) {
                Text("Dismissible Tips (With \"Got it!\" Button)")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach([TipType.testArea, TipType.chatReplay], id: \.self) { tipType in
                        TipTestButton(tipType: tipType, onboardingManager: onboardingManager)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // Controls
            VStack(spacing: 12) {
                Button("Reset All Onboarding") {
                    resetOnboarding()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Show Current Status") {
                    showCurrentStatus()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func resetOnboarding() {
        onboardingManager.resetAllOnboardingProgress()
    }
    
    private func showCurrentStatus() {
        let status = """
        Current Onboarding Status:
        - Current Step Index: \(onboardingManager.currentStepIndex)
        - Current Tip: \(onboardingManager.currentTipType?.rawValue ?? "completed")
        - Is Completed: \(onboardingManager.isOnboardingCompleted)
        """
        print(status)
    }
}

// MARK: - Tip Test Button

private struct TipTestButton: View {
    let tipType: TipType
    @ObservedObject var onboardingManager: OnboardingManager
    
    private var content: TipContent {
        TipContent.content(for: tipType)
    }
    
    private var isActive: Bool {
        return onboardingManager.currentTipType == tipType
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Main tip button - tappable when active
            Button(action: {
                if isActive {
                    completeAction()
                }
            }) {
                HStack {
                    Image(systemName: content.systemImage)
                        .font(.caption)
                    
                    Text(content.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(8)
                .background(isActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                .cornerRadius(6)
            }
            .disabled(!isActive)
            .buttonStyle(.plain)
            .modifier(PopoverTipModifier(tipType: tipType))
            
            // Alternative action button when tip is active
            if isActive {
                Button(actionDescription) {
                    completeAction()
                }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
        private var actionDescription: String {
        switch tipType {
        case .xcodeSetup:
            return "✓ Complete Xcode Setup"
        case .createFirstTest:
            return "✓ Create First Test"
        case .testArea:
            return "✓ View Editor"
        case .pickSimulator:
            return "✓ Choose Runtime"
        case .chooseModel:
            return "✓ Choose Model"
        case .runFirstTest:
            return "✓ Run First Test"
        case .chatReplay:
            return "✓ View Replay"
        }
    }
    

    
    private func completeAction() {
        onboardingManager.complete(tipType)
    }
}

#Preview {
    let onboarding = PreviewServices.onboarding

    OnboardingTipsPreview()
        .environmentObject(onboarding)
}
