//
//  SimulatorRow.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 24.07.2025.
//

import SwiftUI

struct TargetRow: View {
    let target: Target?
    let onShutdown: ((TargetInfo) -> Void)?

    /// Creates a SimulatorRow that displays the target's information and status
    /// - Parameters:
    ///   - target: The Target containing device/simulator info and current status
    ///   - onShutdown: Optional callback when shutdown button is tapped
    init(target: Target?, onShutdown: ((TargetInfo) -> Void)? = nil) {
        self.target = target
        self.onShutdown = onShutdown
    }

    // Convenience computed properties for easy access to target data
    private var simulator: TargetInfo? { target?.targetInfo }
    private var currentStatus: String? { target?.currentStatus }
    private var error: String? { target?.error }

    var body: some View {
        VStack(spacing: 0) {
            // Main content card
            VStack(alignment: .leading, spacing: 12) {
                // Header section with device info and state
                HStack(alignment: .center, spacing: 12) {
                    // Device icon
                    Image(systemName: deviceIcon)
                        .font(.title2)
                        .foregroundColor(deviceIconColor)
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Device name
                        Text(simulator?.name ?? "Unknown Device")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // State and shutdown button
                    HStack(spacing: 8) {
                        // State pill
                        if let state = simulator?.state {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(stateColor)
                                    .frame(width: 6, height: 6)
                                
                                Text(state.capitalized)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(stateColor.opacity(0.15))
                            .foregroundColor(stateColor)
                            .cornerRadius(12)
                        }
                        
                        // Shutdown button - only show for booted simulators
                        if simulator?.state?.lowercased() == "booted", let onShutdown, let simulator = simulator {
                            Button(action: {
                                onShutdown(simulator)
                            }) {
                                Image(systemName: "power")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.red)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Shutdown Simulator")
                        }
                    }
                }
                
                // Status section
                if let status = currentStatus {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Text(status)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            
            // Error section (separate from main card)
            if let error = error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Text("Error")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        
                        Spacer()
                    }
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed Properties
    
    private var deviceIcon: String {
        guard let name = simulator?.name.lowercased() else { return "iphone" }
        
        if name.contains("ipad") {
            return "ipad"
        } else if name.contains("watch") {
            return "applewatch"
        } else if name.contains("tv") {
            return "appletv"
        } else {
            return "iphone"
        }
    }
    
    private var deviceIconColor: Color {
        guard let state = simulator?.state?.lowercased() else { return .gray }
        switch state {
        case "booted": return .green
        case "shutdown": return .gray
        default: return .orange
        }
    }

    private var stateColor: Color {
        guard let state = simulator?.state?.lowercased() else { return .gray }
        switch state {
        case "booted": return .green
        case "shutdown": return .gray
        default: return .orange
        }
    }
}
