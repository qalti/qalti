//
//  DevicePlaceholderView.swift
//  Qalti
//
//  Created by k Slavnov on 20/10/2025.
//
import SwiftUI
import Foundation


// MARK: - Device Placeholder View

struct DevicePlaceholderView: View {
    let onShowDeviceSetupHelp: () -> Void
    let onShowDeviceSetupHelpFromLink: () -> Void
    
    var body: some View {
        container
    }
    
    // MARK: - Extracted Views
    private var container: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            instructionView
        }
        .padding(16)
        .background(containerBackground)
    }
    
    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("No Device Connected")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var instructionView: some View {
        let helpText: AttributedString = createInlineHelpAttributedText()
        return HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(helpText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .onOpenURL { url in
                    if url.scheme == "qalti", url.host == "device-setup-help" {
                        onShowDeviceSetupHelpFromLink()
                    }
                }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(instructionBackground)
    }
    
    private var instructionBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.blue.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func createInlineHelpAttributedText() -> AttributedString {
        var text = AttributedString("To use a real iPhone, plug it in via USB and set it up. For more info, see our guide.")
        if let range = text.range(of: "see our guide") {
            text[range].foregroundColor = .blue
            text[range].underlineStyle = .single
            text[range].link = URL(string: "qalti://device-setup-help")
        }
        return text
    }
}
