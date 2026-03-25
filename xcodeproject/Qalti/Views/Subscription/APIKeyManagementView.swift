import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var credentialsService: CredentialsService
    @EnvironmentObject private var errorCapturer: ErrorCapturerService

    let openReason: SettingsOpenReason
    let onClose: (() -> Void)?
    
    init(openReason: SettingsOpenReason = .manual, onClose: (() -> Void)? = nil) {
        self.openReason = openReason
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content - show API key entry and S3 settings
            ScrollView {
                VStack(spacing: 24) {
                    // Open Router API Key Section
                    APIKeyEntryView()
                        .environmentObject(credentialsService)
                        .environmentObject(errorCapturer)
                    
                    // S3 Settings Section
                    S3ConfigView()
                        .environmentObject(credentialsService)
                        .environmentObject(errorCapturer)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .overlay(
            HeaderView(
                showCloseButton: true,
                onClose: onClose
            ), alignment: .top
        )
        .background(Color.secondarySystemBackground)
        .onEscapePressed {
            onClose?()
        }
    }
}

// MARK: - S3 Config View

private struct S3ConfigView: View {
    @EnvironmentObject private var credentialsService: CredentialsService
    @EnvironmentObject private var errorCapturer: ErrorCapturerService

    @State private var accessKeyId: String = ""
    @State private var secretAccessKey: String = ""
    @State private var region: String = ""
    @State private var bucket: String = ""
    @State private var presignTTLSeconds: Int = S3Settings.defaultPresignTTLSeconds
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("AWS S3")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                if credentialsService.s3Settings != nil {
                    Text("Saved")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Access Key ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("AKIA...", text: $accessKeyId)
                    .textFieldStyle(.roundedBorder)

                Text("Secret Access Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("••••••••", text: $secretAccessKey)
                    .textFieldStyle(.roundedBorder)

                Text("Region")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("us-east-1", text: $region)
                    .textFieldStyle(.roundedBorder)

                Text("Bucket")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("my-bucket", text: $bucket)
                    .textFieldStyle(.roundedBorder)

                Text("Presign TTL (seconds)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("3600", value: $presignTTLSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Save") {
                        saveSettings()
                    }
                    .buttonStyle(.bordered)

                    Button("Remove") {
                        removeSettings()
                    }
                    .buttonStyle(.bordered)
                    .disabled(credentialsService.s3Settings == nil && accessKeyId.isEmpty && secretAccessKey.isEmpty)

                    Spacer()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Presigned URLs are used to upload and share screenshots. It makes LLM requests much faster.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondarySystemFill.opacity(0.33))
        .cornerRadius(12)
        .onAppear { syncFromStore() }
        .onChange(of: credentialsService.s3Settings) { _ in syncFromStore() }
    }

    private func syncFromStore() {
        if let settings = credentialsService.s3Settings {
            accessKeyId = settings.accessKeyId
            secretAccessKey = settings.secretAccessKey
            region = settings.region
            bucket = settings.bucket
            presignTTLSeconds = settings.presignTTLSeconds
        } else {
            accessKeyId = ""
            secretAccessKey = ""
            region = ""
            bucket = ""
            presignTTLSeconds = S3Settings.defaultPresignTTLSeconds
        }
        errorMessage = nil
    }

    private func saveSettings() {
        let trimmedAccessKeyId = accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecretAccessKey = secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAccessKeyId.isEmpty else {
            errorMessage = "Access Key ID cannot be empty."
            return
        }
        guard !trimmedSecretAccessKey.isEmpty else {
            errorMessage = "Secret Access Key cannot be empty."
            return
        }
        guard !trimmedRegion.isEmpty else {
            errorMessage = "Region cannot be empty."
            return
        }
        guard !trimmedBucket.isEmpty else {
            errorMessage = "Bucket cannot be empty."
            return
        }

        errorMessage = nil
        let settings = S3Settings(
            accessKeyId: trimmedAccessKeyId,
            secretAccessKey: trimmedSecretAccessKey,
            region: trimmedRegion,
            bucket: trimmedBucket,
            presignTTLSeconds: presignTTLSeconds
        )
        credentialsService.setS3Settings(settings)
    }

    private func removeSettings() {
        errorMessage = nil
        credentialsService.removeS3Settings()
    }
}

// MARK: - Header View

private struct HeaderView: View {
    let showCloseButton: Bool
    let onClose: (() -> Void)?
    
    var body: some View {
        HStack {
            if showCloseButton {
                Button(action: {
                    onClose?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    // Add hover effect if needed
                }
            }
            Text("Settings")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
            
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.systemBackground.opacity(0))
    }
}

#Preview {
    let credentials = PreviewServices.credentials
    let errorCapturer = PreviewServices.errorCapturer

    return SettingsView(openReason: .manual) {
        print("Close button tapped")
    }
    .environmentObject(credentials)
    .environmentObject(errorCapturer)
}
