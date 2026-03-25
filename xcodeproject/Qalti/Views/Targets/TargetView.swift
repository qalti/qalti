import SwiftUI
import UniformTypeIdentifiers
import IOSurface


struct TargetView: View {
    @StateObject private var viewModel: TargetViewModel
    @FocusState private var hasFocus: Bool
    @State private var isInstallWindowPresented: Bool = false
    @State private var isDragTargeted: Bool = false

    var body: some View {
        Group {
            VStack(alignment: .center) {
                Spacer()
                HStack(alignment: .center) {
                    Spacer()
                    ZStack {
                        // Calculate display dimensions with fallback
                        let displayWidth: CGFloat = {
                            if let ioSurface = viewModel.ioSurface {
                                return CGFloat(IOSurfaceGetWidth(ioSurface))
                            } else if let image = viewModel.image {
                                return image.size.width
                            } else {
                                return 300
                            }
                        }()
                        
                        let displayHeight: CGFloat = {
                            if let ioSurface = viewModel.ioSurface {
                                return CGFloat(IOSurfaceGetHeight(ioSurface))
                            } else if let image = viewModel.image {
                                return image.size.height
                            } else {
                                return 600
                            }
                        }()
                        
                        let aspectRatio = displayWidth / displayHeight
                        
                        // Main display content
                        if let ioSurface = viewModel.ioSurface {
                            IOSurfaceView(surface: ioSurface)
                                .aspectRatio(aspectRatio, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                        } else if let image = viewModel.image {
                            Image(platformImage: image)
                                .resizable()
                                .aspectRatio(aspectRatio, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                        } else {
                            ThreeDots()
                                .frame(width: displayWidth, height: displayHeight)
                        }
                        
                        // Common overlays (only show when we have content)
                        if viewModel.ioSurface != nil || viewModel.image != nil {
                            if viewModel.highlightsElement {
                                HierarchyOverlay(runtime: viewModel.runtime, selectedElement: $viewModel.heighlightedUIElement, referenceSize: $viewModel.referenceSize)
                                    .aspectRatio(aspectRatio, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                            }

                            Rectangle()
                                .foregroundStyle(Color(white: 0.0, opacity: hasFocus ? 0.0 : 0.3))
                                .aspectRatio(aspectRatio, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                            
                            // Dimming overlay for iPhone UI
                            ZStack {
                                if isInstallWindowPresented {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.4))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .transition(.opacity)

                                    VStack(spacing: 0) {
                                        Spacer()

                                        VStack(spacing: 0) {
                                            // Close button
                                            HStack {
                                                Spacer()
                                                Button {
                                                    withAnimation {
                                                        isInstallWindowPresented = false
                                                    }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.title2)
                                                        .foregroundColor(.label)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                            .padding(16)

                                            // Content with dashed border
                                            VStack(spacing: 16) {
                                                Image(systemName: "app.badge.checkmark")
                                                    .font(.system(size: 44, weight: .medium))
                                                    .foregroundColor(.blue)

                                                VStack(spacing: 8) {
                                                    Text("Install App")
                                                        .font(.title2)
                                                        .fontWeight(.semibold)

                                                    Text("Drop .app bundle for Simulator here to install")
                                                        .font(.subheadline)
                                                        .foregroundColor(.label.opacity(0.7))
                                                        .multilineTextAlignment(.center)
                                                }
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(24)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        Color.blue.opacity(0.5),
                                                        style: StrokeStyle(
                                                            lineWidth: 3,
                                                            dash: [8, 4]
                                                        )
                                                    )
                                            }
                                            .padding(.horizontal, 24)
                                            .padding(.bottom, 24)
                                        }
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -2)
                                        .padding(.horizontal, 8)
                                        .padding(.bottom, 8)
                                    }
                                    .transition(.move(edge: .bottom))
                                } else {
                                    Spacer()
                                }
                            }
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                    }
                    .overlay {
                        if !isInstallWindowPresented {
                            GeometryReader { proxy in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                viewModel.onMouseMove(value, viewSize: proxy.size)
                                            }
                                            .onEnded { value in
                                                viewModel.onMouseUp(value, viewSize: proxy.size)
                                            }
                                    )
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.secondarySystemBackground.opacity(0.6))
                            .shadow(
                                color: hasFocus ? Color.primary.opacity(0.5) : Color.secondarySystemBackground.opacity(0.3),
                                radius: hasFocus ? 8 : 2,
                                x: 0,
                                y: hasFocus ? 4 : 2
                            )
                    )
                    .animation(.easeInOut, value: hasFocus)
                    .legacy_focusable()
                    .focused($hasFocus)
                    .focusEffectDisabled()
                    Spacer()
                }
                .overlay(alignment: .bottom) {
                    VStack {
                        if viewModel.isInstallingApp || viewModel.installStatus != nil || viewModel.installError != nil {
                            VStack(spacing: 8) {
                                if viewModel.isInstallingApp {
                                    NotificationView(
                                        icon: "arrow.down.circle",
                                        iconColor: .blue,
                                        message: "Installing app..."
                                    )
                                }
                                
                                if let status = viewModel.installStatus {
                                    NotificationView(
                                        icon: "checkmark.circle.fill",
                                        iconColor: .green,
                                        message: status
                                    )
                                }
                                
                                if let error = viewModel.installError {
                                    NotificationView(
                                        icon: "exclamationmark.circle.fill",
                                        iconColor: .red,
                                        message: error
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                    }
                    .animation(.easeInOut, value: viewModel.isInstallingApp)
                    .animation(.easeInOut, value: viewModel.installStatus)
                    .animation(.easeInOut, value: viewModel.installError)
                }

                Spacer()

                // Bottom control buttons
                HStack(spacing: 10) {
                    VStack(spacing: 4) {
                        Button(action: {
                            viewModel.openHomeScreen()
                        }) {
                            Image(systemName: "house.fill")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Go to Home Screen")
                        
                        Text("Home")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70)
                    
                    VStack(spacing: 4) {
                        Button(action: {
                            viewModel.openAppSwitcher()
                        }) {
                            Image(systemName: "rectangle.stack")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Open App Switcher (Double tap home)")
                        
                        Text("App Switcher")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70)
                    
                    VStack(spacing: 4) {
                        Button(action: {
                            withAnimation {
                                isInstallWindowPresented.toggle()
                            }
                        }) {
                            Image(systemName: "plus.app")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Show install app area")
                        
                        Text("Install app")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70)
                    
                    VStack(spacing: 4) {
                        Button(action: {
                            viewModel.clearInputField()
                        }) {
                            Image(systemName: "clear")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Clear Input Field")
                        
                        Text("Clear Input")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70)
                }
                .padding(.bottom, 10)
                .padding(.horizontal, 10)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                return viewModel.handleDrop(providers: providers)
            }
            .legacy_onChange(of: isDragTargeted) { newValue in
                withAnimation {
                    isInstallWindowPresented = newValue
                }
            }
        }
        .onGlobalKeyPress() { characters, modifiers in
            // Only handle keypresses when the simulator has focus
            guard hasFocus else { return .ignored }
            
            if modifiers.contains(.control) {
                if characters == "h" {
                    viewModel.toggleHighlightsElement()
                    return .handled
                } else if characters == "t" {
                    viewModel.toggleAllowsTimeSaving()
                    return .handled
                } else {
                    return .ignored
                }
            }
            guard !modifiers.contains(.command) else { return .ignored }
            guard !modifiers.contains(.control) else { return .ignored }
            guard !modifiers.contains(.option) else { return .ignored }

            viewModel.onKeyPress(characters)

            return .handled
        }
        .onAppear {
            viewModel.onAppear()
            hasFocus = true
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }

    init(runtime: IOSRuntime, errorCapturer: ErrorCapturing, idbManager: IdbManaging) {
        _viewModel = StateObject(wrappedValue: TargetViewModel(
            runtime: runtime,
            errorCapturer: errorCapturer,
            idbManager: idbManager
        ))
    }
}

struct NotificationView: View {
    let icon: String
    let iconColor: Color
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
            Text(message)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .foregroundStyle(.background)
                .opacity(0.95)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        }
    }
}

#Preview {
    let credentials = PreviewServices.credentials
    let errorCapturer = PreviewServices.errorCapturer
    let idb = PreviewServices.fakeIdb

    TargetView(
        runtime: IOSRuntime(
            simulatorID: "",
            idbManager: idb,
            errorCapturer: errorCapturer
        ),
        errorCapturer: errorCapturer,
        idbManager: idb)
    .environmentObject(credentials)
    .environmentObject(errorCapturer)
}
