import SwiftUI

// MARK: - Enhanced Floating Split View with more advanced features

struct AdvancedFloatingSplitView<LeftContent: View, MiddleContent: View, AssistantContent: View, RightContent: View>: View {

    let leftContent: () -> LeftContent
    let middleContent: () -> MiddleContent
    let assistantContent: (() -> AssistantContent)?
    let rightContent: () -> RightContent
    
    @State private var leftViewWidth: CGFloat = 250
    @State private var assistantViewWidth: CGFloat = 300
    @State private var rightViewWidth: CGFloat = 350
    @State private var showAssistantView: Bool = true
    @State private var showRightView: Bool = true
    @State private var isResizingLeft: Bool = false
    @State private var isResizingAssistant: Bool = false
    @State private var isResizingRight: Bool = false
    @State private var assistantDragStartWidth: CGFloat = 300
    @State private var assistantDragStartLocation: CGPoint = .zero
    @State private var rightDragStartWidth: CGFloat = 350
    @State private var rightDragStartLocation: CGPoint = .zero
    @State private var leftDragStartWidth: CGFloat = 250
    @State private var leftDragStartLocation: CGPoint = .zero
    
    // Tracked dimensions for the panes
    @State private var assistantPaneFrame: CGRect = .zero
    @State private var assistantPaneSize: CGSize = .zero
    @State private var rightPaneFrame: CGRect = .zero
    @State private var rightPaneSize: CGSize = .zero
    
    private let minLeftWidth: CGFloat = 200
    private let maxLeftWidth: CGFloat = 500
    private let minAssistantWidth: CGFloat = 250
    private let maxAssistantWidth: CGFloat = 500
    private let minRightWidth: CGFloat = 250
    private let maxRightWidth: CGFloat = 700
    private let resizeHandleWidth: CGFloat = 10
    
    init(@ViewBuilder leftContent: @escaping () -> LeftContent,
         @ViewBuilder middleContent: @escaping () -> MiddleContent,
         assistantContent: (() -> AssistantContent)? = nil,
         @ViewBuilder rightContent: @escaping () -> RightContent) {
        self.leftContent = leftContent
        self.middleContent = middleContent
        self.assistantContent = assistantContent
        self.rightContent = rightContent
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left column (non-hidable, resizable)
            leftContent()
                .frame(width: leftViewWidth)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.secondarySystemBackground,
                                    Color.secondarySystemBackground.opacity(0.95)
                                ],
                                startPoint: .topTrailing,
                                endPoint: .bottomLeading
                            )
                        )
                        .shadow(
                            color: Color.black.opacity(0.12),
                            radius: 20,
                            x: -6,
                            y: 2
                        )
                        .shadow(
                            color: Color.black.opacity(0.08),
                            radius: 8,
                            x: -2,
                            y: 1
                        )
                        .shadow(
                            color: Color.black.opacity(0.04),
                            radius: 2,
                            x: -1,
                            y: 0
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                )
                .padding(.leading, 8)
                .padding(.vertical, 8)

            // Left resize handle
            createResizeHandle(
                isResizing: $isResizingLeft,
                onDragChanged: { value in
                    if !isResizingLeft {
                        isResizingLeft = true
                        #if os(macOS)
                        NSCursor.resizeLeftRight.set()
                        #endif
                        leftDragStartWidth = leftViewWidth
                        leftDragStartLocation = value.startLocation
                    }

                    let totalDeltaX = value.location.x - leftDragStartLocation.x
                    let newWidth = leftDragStartWidth + totalDeltaX
                    leftViewWidth = max(minLeftWidth, min(maxLeftWidth, newWidth))
                },
                onDragEnded: {
                    isResizingLeft = false
                    #if os(macOS)
                    NSCursor.arrow.set()
                    #endif
                }
            )

            // Middle content area
            middleContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Assistant pane (optional)
            if assistantContent != nil {
                // Assistant resize handle
                if showAssistantView {
                    createResizeHandle(
                        isResizing: $isResizingAssistant,
                        onDragChanged: { value in
                            if !isResizingAssistant {
                                isResizingAssistant = true
                                #if os(macOS)
                                NSCursor.resizeLeftRight.set()
                                #endif
                                assistantDragStartWidth = assistantViewWidth
                                assistantDragStartLocation = value.startLocation
                            }
                            
                            let totalDeltaX = value.location.x - assistantDragStartLocation.x
                            let newWidth = assistantDragStartWidth - totalDeltaX
                            assistantViewWidth = max(minAssistantWidth, min(maxAssistantWidth, newWidth))
                        },
                        onDragEnded: {
                            isResizingAssistant = false
                            #if os(macOS)
                            NSCursor.arrow.set()
                            #endif
                        }
                    )
                }
                
                // Assistant pane space tracker
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .onAppear {
                            assistantPaneFrame = geometry.frame(in: .global)
                            assistantPaneSize = geometry.size
                        }
                        .legacy_onChange(of: geometry.size) { size in
                            assistantPaneSize = size
                        }
                        .legacy_onChange(of: geometry.frame(in: .global)) { frame in
                            assistantPaneFrame = frame
                        }
                }
                .frame(width: assistantViewWidth)
                .padding(.horizontal, 2)
                .padding(.vertical, 8)
            }

            // Right pane resize handle
            if showRightView {
                createResizeHandle(
                    isResizing: $isResizingRight,
                    onDragChanged: { value in
                        if !isResizingRight {
                            isResizingRight = true
                            #if os(macOS)
                            NSCursor.resizeLeftRight.set()
                            #endif
                            rightDragStartWidth = rightViewWidth
                            rightDragStartLocation = value.startLocation
                        }
                        
                        let totalDeltaX = value.location.x - rightDragStartLocation.x
                        let newWidth = rightDragStartWidth - totalDeltaX
                        rightViewWidth = max(minRightWidth, min(maxRightWidth, newWidth))
                    },
                    onDragEnded: {
                        isResizingRight = false
                        #if os(macOS)
                        NSCursor.arrow.set()
                        #endif
                    }
                )
                
                // Right pane space tracker
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .onAppear {
                            rightPaneFrame = geometry.frame(in: .global)
                            rightPaneSize = geometry.size
                        }
                        .legacy_onChange(of: geometry.size) { size in
                            rightPaneSize = size
                        }
                        .legacy_onChange(of: geometry.frame(in: .global)) { frame in
                            rightPaneFrame = frame
                        }
                }
                .frame(width: rightViewWidth)
                .padding(.leading, 2)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Assistant content overlay (if provided)
            if let assistantContent = assistantContent {
                HStack {
                    Spacer()
                    createFloatingPane(
                        content: assistantContent,
                        showPane: $showAssistantView,
                        paneSize: assistantPaneSize,
                        trailingPadding: calculateAssistantTrailingPadding()
                    )
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // Right content overlay
            HStack {
                Spacer()
                createFloatingPane(
                    content: rightContent,
                    showPane: $showRightView,
                    paneSize: rightPaneSize,
                    trailingPadding: calculateRightTrailingPadding()
                )
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Helper Methods
    
    private func calculateAssistantTrailingPadding() -> CGFloat {
        let rightTrailingPadding = calculateRightTrailingPadding()
        
        if showRightView {
            // Right content is visible (expanded) - position assistant to the left of it
            return rightPaneSize.width + 10 + 4 + rightTrailingPadding
        } else if showAssistantView {
            return 8
        } else {
            return 27 + 16
        }
    }
    
    private func calculateRightTrailingPadding() -> CGFloat {
        if assistantContent != nil && showAssistantView, !showRightView {
            // Assistant is visible (expanded) - position right content to the left of assistant
            return assistantPaneSize.width + 18
        } else {
            // Assistant is either nil or minimized - use base padding
            return 8
        }
    }
    
    @ViewBuilder
    private func createResizeHandle(
        isResizing: Binding<Bool>,
        onDragChanged: @escaping (DragGesture.Value) -> Void,
        onDragEnded: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .center) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: resizeHandleWidth)
                .contentShape(Rectangle())

            // Visual resize indicator
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(isResizing.wrappedValue ? 0.6 : 0.2))
                .frame(width: 2, height: 30)
                .scaleEffect(isResizing.wrappedValue ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isResizing.wrappedValue)
        }
        .onHover { hovering in
            if hovering {
                #if os(macOS)
                NSCursor.resizeLeftRight.set()
                #endif
            } else if !isResizing.wrappedValue {
                #if os(macOS)
                NSCursor.arrow.set()
                #endif
            }
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged(onDragChanged)
                .onEnded { _ in onDragEnded() }
        )
    }
    
    private func createFloatingPane<Content: View>(
        content: () -> Content,
        showPane: Binding<Bool>,
        paneSize: CGSize,
        trailingPadding: CGFloat
    ) -> some View {
        let baseContent = content()
            .frame(
                width: paneSize.width,
                height: paneSize.height
            )
            .scaleEffect(showPane.wrappedValue ? 1.0 : 0.1)
            .frame(
                width: showPane.wrappedValue ? paneSize.width : 27,
                height: showPane.wrappedValue ? paneSize.height : 48
            )
            .clipShape(RoundedRectangle(cornerRadius: showPane.wrappedValue ? 16 : 4))
        
        let backgroundView = RoundedRectangle(cornerRadius: showPane.wrappedValue ? 16 : 4)
            .fill(
                showPane.wrappedValue ? 
                LinearGradient(
                    colors: [
                        Color.secondarySystemBackground,
                        Color.secondarySystemBackground.opacity(0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) :
                LinearGradient(
                    colors: [Color.secondarySystemBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(
                color: Color.black.opacity(showPane.wrappedValue ? 0.12 : 0.3),
                radius: showPane.wrappedValue ? 20 : 8,
                x: showPane.wrappedValue ? -6 : 0,
                y: showPane.wrappedValue ? 2 : 2
            )
            .shadow(
                color: Color.black.opacity(showPane.wrappedValue ? 0.08 : 0),
                radius: showPane.wrappedValue ? 8 : 0,
                x: showPane.wrappedValue ? -2 : 0,
                y: showPane.wrappedValue ? 1 : 0
            )
            .shadow(
                color: Color.black.opacity(showPane.wrappedValue ? 0.04 : 0),
                radius: showPane.wrappedValue ? 2 : 0,
                x: showPane.wrappedValue ? -1 : 0,
                y: showPane.wrappedValue ? 0 : 0
            )
        
        let strokeView = RoundedRectangle(cornerRadius: showPane.wrappedValue ? 16 : 4)
            .stroke(
                Color.primary.opacity(showPane.wrappedValue ? 0.1 : 0.0),
                lineWidth: 1
            )
        
        let closeButton = Group {
            if showPane.wrappedValue {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                showPane.wrappedValue = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.title3)
                                .background(
                                    Circle()
                                        .fill(Color.secondarySystemBackground)
                                        .shadow(radius: 2)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Minimize Panel")
                        .padding(.trailing, 12)
                        .padding(.top, 12)
                    }
                    Spacer()
                }
            }
        }
        
        let expandButton = Group {
            if !showPane.wrappedValue {
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        showPane.wrappedValue = true
                    }
                }) {
                    Color.white.opacity(1.0 / 255.0)
                }
                .frame(width: 27, height: 48)
                .buttonStyle(PlainButtonStyle())
                .help("Expand Panel")
            }
        }
        
        return baseContent
            .background(backgroundView)
            .overlay(strokeView)
            .overlay(closeButton)
            .overlay(expandButton)
            .padding(.trailing, trailingPadding)
            .padding(.top, 10)
    }
}

// MARK: - Convenience initializers for backwards compatibility

extension AdvancedFloatingSplitView where AssistantContent == EmptyView {
    init(@ViewBuilder leftContent: @escaping () -> LeftContent,
         @ViewBuilder middleContent: @escaping () -> MiddleContent,
         @ViewBuilder rightContent: @escaping () -> RightContent) {
        self.leftContent = leftContent
        self.middleContent = middleContent
        self.assistantContent = nil
        self.rightContent = rightContent
    }
}

// MARK: - Preview

struct FloatingSplitView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            
            // Advanced floating split view with assistant
            AdvancedFloatingSplitView {
                // Left column content
                VStack(alignment: .leading, spacing: 12) {
                    Text("Left Column")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    Text("Non-hidable but resizable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<8) { index in
                            Text("Item \(index + 1)")
                                .font(.caption)
                                .padding(.vertical, 2)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            } middleContent: {
                // Middle content area
                VStack {
                    Text("Main Content")
                        .font(.title)
                    Text("Four-column advanced floating split view")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } assistantContent: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Assistant Panel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("AI Assistant panel that can be collapsed and resized.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<80) { index in
                                HStack {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                    Text("Assistant Item \(index + 1) aldkfjhasldfjalksdjfpoasdjfoiasjdfilaskdfjasdlkfjaslkdjfalksdjfalksjdfklasjdf")
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            } rightContent: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector Panel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Enhanced floating panel with gradient background, multiple shadows, and smooth animations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<10) { index in
                                HStack {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                    Text("Item \(index + 1)")
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .previewDisplayName("Advanced Floating Split View with Assistant")
        }
        .frame(width: 1200, height: 600)
    }
}
