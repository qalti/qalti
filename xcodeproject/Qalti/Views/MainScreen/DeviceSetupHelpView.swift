//
//  DeviceSetupHelpView.swift
//  Qalti
//
//  Created by Assistant on 06.06.2025.
//

import SwiftUI
import Foundation

struct DeviceSetupHelpView: View {
    enum Source: String {
        case cross
        case gotIt = "got_it"
        case esc
    }
    
    let onClose: (_ source: Source) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("How to set up a real device")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { onClose(.cross) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        Text("1. Unlock the iPhone and keep it awake during \"Preparing device\" and the first launch.")
                        Text("2. On the iPhone, enable Developer Mode: Settings → Privacy & Security → Developer Mode → On (reboot if prompted).")
                        Text("3. On the iPhone, trust the developer certificate used to sign the runner: Settings → General → VPN & Device Management → Developer App → Trust Apple Development).")
                        Text("4. Plug the device into the Mac, open Xcode → Window → Devices & Simulators, select the phone and click \"Use for Development/Prepare\" so Xcode installs the right device support (for iOS 18.6.1).")
                        Text("5. Re-run the tests.")
                        Text("6. Temporarily set Auto-Lock to Never: Settings → Display & Brightness → Auto-Lock → Never (to prevent screen sleep during setup).")
                    }
                    .font(.callout)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            
            Divider()
                .padding(.top, 8)
            
            HStack {
                Spacer()
                Button(action: { onClose(.gotIt) }) {
                    Text("Got it")
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onEscapePressed { onClose(.esc) }
    }
}

#Preview {
    DeviceSetupHelpView(onClose: { _ in })
        .frame(width: 700, height: 600)
}
