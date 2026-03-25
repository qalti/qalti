//
//  TestControlPanel.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 28.06.2025.
//

import SwiftUI

struct TestControlPanel<RunState: TestRunStateProviding>: View {
    @ObservedObject var runState: RunState
    @ObservedObject var viewModel: MainScreenViewModel
    let hasRuntime: Bool
    let selectedFile: URL?
    let isSuiteRunning: Bool
    let onRunTest: (URL?, TestRunner.AvailableModel) -> Void
    let onStop: () -> Void
    @State private var viewWidth: CGFloat = 0

    @Environment(\.openURL) private var openURL

    @EnvironmentObject private var onboardingManager: OnboardingManager


    private var backgroundTint: Color {
        if runState.testError != nil {
            return Color.red.opacity(0.15)
        } else if runState.testStatus != nil {
            return Color.blue.opacity(0.1)
        } else {
            return Color.clear
        }
    }

    private var shouldShowErrorOverlay: Bool {
        runState.testError != nil && viewWidth < 350
    }

    var body: some View {
        VStack(spacing: 8) {
            // Contact us button (positioned above main bar)
            HStack {
                Spacer()
                Button(action: {
                    if let url = URL(string: "mailto:hi@qalti.com") {
                        openURL(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope")
                            .font(.caption)
                        Text("Something wrong?")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.blue.opacity(0.1))
                            )
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.separator.opacity(1.0), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Error overlay (appears above main bar when width < 250)
            if shouldShowErrorOverlay {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(runState.testError ?? "")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(backgroundTint)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.separator.opacity(1.0), lineWidth: 1)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: shouldShowErrorOverlay)
            }

            // Main control bar
            HStack(spacing: 0) {
                // Left side - Status information
                HStack(spacing: 8) {

                    // Status display - only show error inline if width >= 250
                    if let error = runState.testError, !shouldShowErrorOverlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    } else if let status = runState.testStatus {
                        Image(systemName: "gear")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        // Placeholder to maintain consistent height
                        if !hasRuntime {
                            Text("No runtime selected")
                                .font(.caption)
                                .foregroundColor(.tertiaryLabel)
                        } else {
                            Text("Ready")
                                .font(.caption)
                                .foregroundColor(.tertiaryLabel)
                        }
                    }
                }
                .padding(.leading, 5)

                Spacer()

                // Model selection dropdown
                HStack(spacing: 8) {
                    // Separator
                    Rectangle()
                        .fill(Color.separator.opacity(0.3))
                        .frame(width: 1, height: 16)

                    Menu {
                        ForEach(TestRunner.AvailableModel.allCases, id: \.self) { model in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.updateSelectedModel(model)
                                    onboardingManager.complete(.chooseModel)
                                }
                            }) {
                                HStack {
                                    Text(model.displayName)
                                    if viewModel.selectedModel == model {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.caption)
                            Text(viewModel.selectedModel.displayName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Rectangle()
                                .fill(Color.purple.opacity(1.0))
                                .blur(radius: 5)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: true, vertical: false)
                    .onboardingTip(.chooseModel)
                }

                // Right side - Run/Stop button integrated into the bar
                HStack(spacing: 8) {
                    // Separator
                    Rectangle()
                        .fill(Color.separator.opacity(0.3))
                        .frame(width: 1, height: 16)

                    let isRulesFile = (selectedFile?.lastPathComponent == ".qaltirules")
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if runState.isTestRunning {
                                onStop()
                            } else {
                                onRunTest(
                                    selectedFile,
                                    viewModel.selectedModel
                                )
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(runState.isTestRunning ? "Stop" : "Run")
                                .font(.caption.weight(.medium))
                            Image(systemName: runState.isTestRunning ? "stop.fill" : "play.fill")
                                .font(.caption)
                        }
                        .foregroundColor(runState.isTestRunning ? .red : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 14,
                                topTrailingRadius: 14
                            )
                            .fill((runState.isTestRunning ? Color.red : Color.green).opacity(0.3))
                            .blur(radius: 5)
                            .animation(.easeInOut(duration: 0.3), value: runState.isTestRunning)
                        )
                        .opacity((!hasRuntime || isSuiteRunning || isRulesFile) ? 0.5 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: hasRuntime && !isSuiteRunning && !isRulesFile)
                    }
                    .buttonStyle(.plain)
                    .onboardingTip(.runFirstTest)
                    .disabled(!hasRuntime || isSuiteRunning || isRulesFile)
                }
                .padding(.trailing, 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(backgroundTint)
                            .animation(.easeInOut(duration: 0.4), value: backgroundTint)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.separator.opacity(1.0), lineWidth: 1)
            )
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            viewWidth = geometry.size.width
                        }
                        .onChange(of: geometry.size.width) { newWidth in
                            viewWidth = newWidth
                        }
                }
            )
        }
        .padding(.horizontal, 0)
        .padding(.bottom, 8)
    }
}

// MARK: - Preview Helpers

final class MockRunState: TestRunStateProviding {
    @Published var testStatus: String?
    @Published var testError: String?
    @Published var isTestRunning: Bool = false
}

private func makeMockRunner(testError: String? = nil, isTestRunning: Bool = false) -> MockRunState {
    let runner = MockRunState()
    runner.testError = testError
    runner.isTestRunning = isTestRunning
    return runner
}

class MockMainScreenViewModel: MainScreenViewModel {
    @Published var mockSelectedModel: TestRunner.AvailableModel = .gpt5nano
    
    override var selectedModel: TestRunner.AvailableModel {
        get { mockSelectedModel }
        set {}
    }
    
    override func updateSelectedModel(_ model: TestRunner.AvailableModel) {
        mockSelectedModel = model
    }
}

// MARK: - Previews

#Preview("Normal Width - No Error") {
    let errorCapturer = PreviewServices.errorCapturer
    let onboarding = PreviewServices.onboarding

    TestControlPanel(
        runState: MockRunState(),
        viewModel: MockMainScreenViewModel(errorCapturer: errorCapturer),
        hasRuntime: true,
        selectedFile: nil,
        isSuiteRunning: false,
        onRunTest: { _, _ in },
        onStop: {}
    )
    .environmentObject(errorCapturer)
    .environmentObject(onboarding)
    .frame(width: 500)
    .padding()
}

#Preview("Normal Width - With Error") {
    let mockRunner = makeMockRunner(testError: "Test failed with assertion error")
    let errorCapturer = PreviewServices.errorCapturer
    let onboarding = PreviewServices.onboarding

    TestControlPanel(
        runState: mockRunner,
        viewModel: MockMainScreenViewModel(errorCapturer: errorCapturer),
        hasRuntime: true,
        selectedFile: nil,
        isSuiteRunning: false,
        onRunTest: { _, _ in },
        onStop: {}
    )
    .environmentObject(errorCapturer)
    .environmentObject(onboarding)
    .frame(width: 500)
    .padding()
}

#Preview("Small Width - With Error Overlay") {
    let mockRunner = makeMockRunner(
        testError: "Test failed with assertion error - this is a longer error message that should wrap"
    )
    let errorCapturer = PreviewServices.errorCapturer
    let onboarding = PreviewServices.onboarding

    TestControlPanel(
        runState: mockRunner,
        viewModel: MockMainScreenViewModel(errorCapturer: errorCapturer),
        hasRuntime: true,
        selectedFile: nil,
        isSuiteRunning: true,
        onRunTest: { _, _ in },
        onStop: {}
    )
    .environmentObject(errorCapturer)
    .environmentObject(onboarding)
    .frame(width: 300)
    .padding()
}

#Preview("Small Width - Running State") {
    let mockRunner = makeMockRunner(isTestRunning: true)
    let errorCapturer = PreviewServices.errorCapturer
    let onboarding = PreviewServices.onboarding

    TestControlPanel(
        runState: mockRunner,
        viewModel: MockMainScreenViewModel(errorCapturer: errorCapturer),
        hasRuntime: true,
        selectedFile: nil,
        isSuiteRunning: false,
        onRunTest: { _, _ in },
        onStop: {}
    )
    .environmentObject(errorCapturer)
    .environmentObject(onboarding)
    .frame(width: 300)
    .padding()
}
