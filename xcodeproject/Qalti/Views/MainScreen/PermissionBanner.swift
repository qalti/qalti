//
//  PermissionBanner.swift
//  Qalti
//
//  Created by Pavel Akhrameev on 05.03.26.
//

import SwiftUI
import Combine

/// A banner that appears in the FileTreeView when folder permissions are needed.
/// Provides guidance and a refresh button for users to resolve permission issues.
struct PermissionBanner: View {
    @EnvironmentObject private var permissionService: PermissionService

    let onRefresh: () -> Void

    @State private var isRefreshing = false

    private var resetInstruction: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("To reset this permission, run")

            Text("make reset-permission")
                .font(.system(size: 12, design: .monospaced))
                .bold()
                .padding(4)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)

            Text("in project root.\nThis will force to show permission popup on next launch.")
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .foregroundColor(.orange)
                    .font(.system(size: 20, weight: .medium))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Folder Access Required")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Qalti needs permission to access your Documents folder.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            resetInstruction

            Spacer()

            Button(action: handleRefresh) {
                HStack(spacing: 4) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 10, height: 10)
                            .tint(.secondary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                    }

                    Text("Check Again")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(BorderedButtonStyle())
            .disabled(isRefreshing)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
        )
        .cornerRadius(8)
        .onReceive(NotificationCenter.default.publisher(for: .documentsAccessGranted)) { _ in
            handlePermissionGranted()
        }
    }

    // MARK: - Private Methods

    private func handleRefresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        permissionService.refreshPermissionStatus()
        onRefresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isRefreshing = false
        }
    }

    private func handlePermissionGranted() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onRefresh()
        }
    }
}

// MARK: - Preview

#Preview("Permission Banner") {
    let fakeService = FakePermissionService()

    PermissionBanner(onRefresh: { print("Refresh tapped") })
        .environmentObject(fakeService)
        .padding()
        .frame(width: 350)
}
