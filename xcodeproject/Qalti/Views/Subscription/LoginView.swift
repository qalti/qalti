import SwiftUI

struct APIKeyEntryView: View {
    @EnvironmentObject private var credentialsService: CredentialsService

    @State private var openRouterKey = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @FocusState private var isFocused: Bool
    
    var isSaveButtonDisabled: Bool {
        isLoading || openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Header
            VStack(spacing: 16) {
                // App Logo/Icon
                Image("qalti-logo-basic")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .tint(.primary)
                    .padding(.top, 16)

                // Title
                VStack(spacing: 4) {
                    Text("OpenRouter API Key")
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text("Add your OpenRouter API key to run Qalti tests")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.bottom, 32)
            
            // Open Router API Key Input
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenRouter API Key")
                        .font(.caption)
                        .foregroundColor(.label)
                        .fontWeight(.medium)
                    
                    Group {
                        if !isFocused && credentialsService.hasCredentials && openRouterKey.isEmpty {
                            // Show masked value when API key exists and field is not being edited
                            HStack {
                                Text(String(repeating: "•", count: 20))
                                    .foregroundColor(.label)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                            .onTapGesture {
                                isFocused = true
                            }
                        } else {
                            // Show SecureField when editing or no API key exists
                            SecureField(
                                credentialsService.hasCredentials ? "API key is set (tap to edit)" : "Enter your OpenRouter API key",
                                text: $openRouterKey
                            )
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .foregroundColor(.label)
                            .accentColor(.accentColor)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                            .shadow(color: Color.black.opacity(isFocused ? 0.3 : 0.1), radius: isFocused ? 4 : 12, x: 0, y: 2)
                            .animation(.bouncy(duration: 0.3), value: isFocused)
                            .onSubmit {
                                if !isSaveButtonDisabled {
                                    Task { await saveOpenRouterKey() }
                                }
                            }
                            .onChange(of: isFocused) { _, newValue in
                                // When field loses focus and API key exists, clear the visible text
                                if !newValue && credentialsService.hasCredentials {
                                    openRouterKey = ""
                                }
                            }
                        }
                    }
                }
                
                // Success Message
                if let successMessage = successMessage {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Error Message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Save Button
                Button(action: {
                    Task { await saveOpenRouterKey() }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        
                        Text("Save API Key")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .background(Color.secondarySystemBackground)
                .cornerRadius(12)
                .disabled(isSaveButtonDisabled)
                .shadow(color: Color.black.opacity(isSaveButtonDisabled ? 0.15 : 0.3), radius: isSaveButtonDisabled ? 8 : 6, x: 0, y: 4)
                .animation(.bouncy(duration: 0.3), value: isSaveButtonDisabled)
                
                // Clear Button (if API key exists)
                if credentialsService.hasCredentials {
                    Button(action: {
                        Task { await clearOpenRouterKey() }
                    }) {
                        Text("Clear API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 320)
            
            Spacer()
        }
        .frame(maxWidth: 600)
        .padding(.horizontal, 40)
        .background(Color.secondarySystemBackground)
        .onAppear {
            // Only auto-focus if no API key is set
            if !credentialsService.hasCredentials {
                isFocused = true
            }
            // Sync with stored value
            openRouterKey = credentialsService.openRouterKey ?? ""
        }
    }

    // MARK: - Actions
    
    @MainActor
    private func saveOpenRouterKey() async {
        guard !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        credentialsService.setOpenRouterKey(openRouterKey)
        successMessage = "✅ OpenRouter API key saved successfully"
        
        // Clear the input field after successful save
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            openRouterKey = ""
        }
        
        isLoading = false
    }
    
    @MainActor
    private func clearOpenRouterKey() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        credentialsService.removeOpenRouterKey()
        openRouterKey = ""
        successMessage = "OpenRouter API key cleared"
        
        isLoading = false
    }
}

#Preview {
    let credentials = PreviewServices.credentials
    let errorCapturer = PreviewServices.errorCapturer

    APIKeyEntryView()
        .environmentObject(credentials)
        .environmentObject(errorCapturer)
        .frame(width: 600, height: 750)
}
