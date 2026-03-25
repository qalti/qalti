//
//  NSFloatingSplitView.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 24.06.2025.
//

#if os(macOS)
import AppKit

class NSFloatingSplitView: NSView {
    
    // MARK: - Properties
    
    private var leftView: NSView?
    private var middleView: NSView?
    private var assistantView: NSView?
    private var rightView: NSView?
    
    // Shadow views
    private var leftShadowView: NSView?
    private var assistantShadowView: NSView?
    private var rightShadowView: NSView?

    private lazy var backgroundOverlayView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        return view
    }()

    private var leftResizeHandle: NSView?
    private var assistantResizeHandle: NSView?
    private var rightResizeHandle: NSView?
    
    private var leftMinimizeButton: NSButton?
    private var assistantMinimizeButton: NSButton?
    private var rightMinimizeButton: NSButton?
    
    // Layout properties
    private var leftWidth: CGFloat = 250
    private var assistantWidth: CGFloat = 300
    private var rightWidth: CGFloat = 350
    
    private let minLeftWidth: CGFloat = 200
    private let maxLeftWidth: CGFloat = 500
    private let minAssistantWidth: CGFloat = 250
    private let maxAssistantWidth: CGFloat = 500
    private let minRightWidth: CGFloat = 250
    private let maxRightWidth: CGFloat = 700
    private let resizeHandleWidth: CGFloat = 10
    private let cornerRadius: CGFloat = 16
    private let padding: CGFloat = 8
    
    // State
    private var isLeftMinimized = false
    private var isAssistantMinimized = false
    private var isRightMinimized = false
    private var isDraggingLeft = false
    private var isDraggingAssistant = false
    private var isDraggingRight = false
    private var dragStartPoint: NSPoint = .zero
    private var dragStartWidth: CGFloat = 0
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        
        // Create and configure NSVisualEffectView background
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        // Add as background view
        addSubview(visualEffectView, positioned: .below, relativeTo: nil)
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Add a semi-transparent overlay above the visual effect background
        addSubview(backgroundOverlayView, positioned: .above, relativeTo: visualEffectView)
        backgroundOverlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundOverlayView.topAnchor.constraint(equalTo: topAnchor),
            backgroundOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateBackgroundOverlayAppearance()
        
        setupResizeHandles()
        setupMinimizeButtons()
        
        // Enable tracking area for cursor changes
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundOverlayAppearance()
    }

    private func updateBackgroundOverlayAppearance() {
        guard let layer = backgroundOverlayView.layer else { return }
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        let baseColor: NSColor
        switch match {
        case .some(.darkAqua), .some(.vibrantDark):
            baseColor = .black
        default:
            baseColor = .white
        }
        layer.backgroundColor = baseColor.withAlphaComponent(0.35).cgColor
    }

    private func setupResizeHandles() {
        // Left resize handle
        leftResizeHandle = createResizeHandle()
        addSubview(leftResizeHandle!)
        
        // Assistant resize handle
        assistantResizeHandle = createResizeHandle()
        addSubview(assistantResizeHandle!)
        
        // Right resize handle
        rightResizeHandle = createResizeHandle()
        addSubview(rightResizeHandle!)
    }
    
    private func createResizeHandle() -> NSView {
        let handle = NSView()
        handle.wantsLayer = true
        handle.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Create visual subview that's half the width for better appearance
        let visualHandle = NSView()
        visualHandle.wantsLayer = true
        visualHandle.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        visualHandle.layer?.cornerRadius = 2.5
        
        handle.addSubview(visualHandle)
        
        // Position the visual handle centered within the interaction area
        visualHandle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            visualHandle.centerXAnchor.constraint(equalTo: handle.centerXAnchor),
            visualHandle.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
            visualHandle.widthAnchor.constraint(equalToConstant: resizeHandleWidth / 2),
            visualHandle.heightAnchor.constraint(equalTo: handle.heightAnchor)
        ])
        
        return handle
    }
    
    private func createShadowView() -> NSView {
        let shadowView = NSView()
        shadowView.wantsLayer = true
        shadowView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        shadowView.layer?.cornerRadius = cornerRadius
        shadowView.layer?.cornerCurve = .continuous
        shadowView.shadow = NSShadow()
        shadowView.clipsToBounds = false
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        shadowView.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadowView.shadow?.shadowBlurRadius = 5.0
        shadowView.layer?.shadowRadius = 5.0
        return shadowView
    }
    
    private func setupMinimizeButtons() {
        // Left minimize button
        leftMinimizeButton = createMinimizeButton { [weak self] in
            self?.toggleLeftMinimized()
        }
        leftMinimizeButton?.isHidden = true // Initially hidden
        addSubview(leftMinimizeButton!)
        
        // Assistant minimize button
        assistantMinimizeButton = createMinimizeButton { [weak self] in
            self?.toggleAssistantMinimized()
        }
        assistantMinimizeButton?.isHidden = true // Initially hidden
        addSubview(assistantMinimizeButton!)
        
        // Right minimize button
        rightMinimizeButton = createMinimizeButton { [weak self] in
            self?.toggleRightMinimized()
        }
        rightMinimizeButton?.isHidden = true // Initially hidden
        addSubview(rightMinimizeButton!)
    }
    
    private func createMinimizeButton(action: @escaping () -> Void) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.wantsLayer = true
        button.image = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil)
        button.target = self
        button.action = #selector(minimizeButtonClicked(_:))
        
        // Store action closure
        button.tag = minimizeButtons.count
        minimizeButtons.append(action)
        
        return button
    }
    
    private func updateButtonForState(_ button: NSButton, isMinimized: Bool, targetFrame: NSRect) {
        if isMinimized {
            button.frame = targetFrame
            button.image = nil
        } else {
            // Expanded state - button acts as minimize trigger
            button.frame = NSRect(
                x: targetFrame.maxX - 36,
                y: targetFrame.maxY - 36,
                width: 24,
                height: 24
            )
            button.image = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: nil)
        }
    }
    
    private var minimizeButtons: [() -> Void] = []
    
    @objc private func minimizeButtonClicked(_ sender: NSButton) {
        if sender.tag < minimizeButtons.count {
            minimizeButtons[sender.tag]()
        }
    }
    
    // MARK: - Public Interface
    
    func setLeftView(_ view: NSView) {
        leftView?.removeFromSuperview()
        leftShadowView?.removeFromSuperview()
        
        leftView = view
        leftShadowView = createShadowView()
        
        // Reset minimized state when setting new view
        isLeftMinimized = false

        // Add shadow view first, then content view
        if let leftShadowView {
            addSubview(leftShadowView, positioned: .below, relativeTo: leftResizeHandle)
        }
        addSubview(view, positioned: .below, relativeTo: leftResizeHandle)
        layoutViews()
    }
    
    func setMiddleView(_ view: NSView) {
        middleView?.removeFromSuperview()
        middleView = view
        // Middle view should be at the back
        addSubview(view, positioned: .below, relativeTo: leftResizeHandle)
        layoutViews()
    }
    
    func setAssistantView(_ view: NSView?) {
        assistantView?.removeFromSuperview()
        assistantShadowView?.removeFromSuperview()
        
        assistantView = view
        
        // Reset minimized state when setting new view
        isAssistantMinimized = false
        
        if let view {
            assistantShadowView = createShadowView()
            // Add shadow view first, then content view
            if let assistantShadowView {
                addSubview(assistantShadowView, positioned: .below, relativeTo: assistantMinimizeButton)
            }
            addSubview(view, positioned: .below, relativeTo: assistantMinimizeButton)
        } else {
            assistantShadowView = nil
        }
        assistantMinimizeButton?.isHidden = assistantView == nil
        layoutViews()
    }
    
    func setRightView(_ view: NSView) {
        rightView?.removeFromSuperview()
        rightShadowView?.removeFromSuperview()
        
        rightView = view
        rightShadowView = createShadowView()
        
        // Reset minimized state when setting new view
        isRightMinimized = false
        
        // Add shadow view first, then content view
        if let rightShadowView {
            addSubview(rightShadowView, positioned: .below, relativeTo: rightMinimizeButton)
        }
        addSubview(view, positioned: .below, relativeTo: rightMinimizeButton)
        rightMinimizeButton?.isHidden = false
        layoutViews()
    }
    
    // MARK: - Layout
    
    override func layout() {
        super.layout()
        layoutViews()
    }
    
    private func layoutViews() {
        layoutViews(animated: false)
    }
    
    private func layoutViews(animated: Bool) {
        let totalWidth = bounds.width
        let totalHeight = bounds.height

        performMainLayoutPass(totalWidth: totalWidth, totalHeight: totalHeight)
        applyMiniatureTransforms(totalWidth: totalWidth, totalHeight: totalHeight)
    }
    
    private func performMainLayoutPass(totalWidth: CGFloat, totalHeight: CGFloat) {
        // Left view
        if let leftView = leftView {
            let leftFrame = NSRect(
                x: padding,
                y: padding,
                width: leftWidth,
                height: totalHeight - 2 * padding
            )
            leftView.frame = leftFrame
            styleFloatingView(leftView)
            
            // Update shadow view frame
            leftShadowView?.frame = leftFrame
            leftMinimizeButton?.isHidden = false
        }
        
        // Left resize handle
        leftResizeHandle?.frame = NSRect(
            x: padding + leftWidth,
            y: totalHeight / 2 - 15,
            width: resizeHandleWidth,
            height: 30
        )
        leftResizeHandle?.isHidden = isLeftMinimized
        
        // Calculate middle width - only account for non-minimized views for stretching
        var leftSideWidth: CGFloat
        if isLeftMinimized {
            // When minimized, leave space for the miniature panel plus padding
            let miniatureSize: CGFloat = 60
            let scale = miniatureSize / max(miniatureSize, totalHeight)
            let minimizedWidth = leftView?.frame.width ?? leftWidth
            // Round to avoid fractional widths that cause NSTextView layout feedback loops
            leftSideWidth = round(padding + minimizedWidth * scale + padding)
        } else {
            leftSideWidth = padding + leftWidth + resizeHandleWidth
        }
        
        var rightSideWidth: CGFloat = isAssistantMinimized && isRightMinimized ? 0 : padding
        if assistantView != nil && !isAssistantMinimized {
            rightSideWidth += assistantWidth + resizeHandleWidth
        }
        if rightView != nil && !isRightMinimized {
            rightSideWidth += rightWidth + resizeHandleWidth
        }
        
        // Ensure we never assign a negative (or zero) width which can trigger layout feedback loops
        // Round to whole-point values; fractional widths in the text-editor column
        // can provoke AppKit into a resize feedback-loop that ultimately crashes.
        let rawMiddleWidth = totalWidth - (leftSideWidth + rightSideWidth)
        let middleWidth = max(1, round(rawMiddleWidth))

        // Middle view - stretches to fill available space
        if let middleView = middleView {
            middleView.frame = NSRect(
                x: round(leftSideWidth),
                y: 0,
                width: middleWidth, // Already rounded above
                height: totalHeight
            )
        }
        
        // Assistant view and handle - always positioned in normal layout
        if let assistantView = assistantView {
            // Assistant resize handle
            assistantResizeHandle?.frame = NSRect(
                x: totalWidth - padding - rightWidth - resizeHandleWidth - assistantWidth - resizeHandleWidth,
                y: totalHeight / 2 - 15,
                width: resizeHandleWidth,
                height: 30
            )
            assistantResizeHandle?.isHidden = false

            let assistantFrame = NSRect(
                x: totalWidth - padding - rightWidth - resizeHandleWidth - assistantWidth,
                y: padding,
                width: assistantWidth,
                height: totalHeight - 2 * padding
            )
            assistantView.frame = assistantFrame
            styleFloatingView(assistantView)
        } else {
            assistantResizeHandle?.isHidden = true
        }
        
        // Right resize handle
        if rightView != nil {
            rightResizeHandle?.frame = NSRect(
                x: totalWidth - padding - rightWidth - resizeHandleWidth,
                y: totalHeight / 2 - 15,
                width: resizeHandleWidth,
                height: 30
            )
            rightResizeHandle?.isHidden = false
        } else {
            rightResizeHandle?.isHidden = true
        }
        
        // Right view - always positioned in normal layout
        if let rightView = rightView {
            let rightFrame = NSRect(
                x: totalWidth - padding - rightWidth,
                y: padding,
                width: rightWidth,
                height: totalHeight - 2 * padding
            )
            rightView.frame = rightFrame
            styleFloatingView(rightView)
        }
    }

    private func getLeftViewTargetFrame(totalWidth: CGFloat, totalHeight: CGFloat) -> NSRect? {
        let miniatureSize: CGFloat = 60
        let scale = miniatureSize / max(miniatureSize, totalHeight)
        
        guard let leftView else { return nil }
        if isLeftMinimized {
            // Position below window controls (traffic lights) with extra margin
            let windowControlsHeight: CGFloat = 40
            // Round to avoid fractional coordinates that can cause layout issues
            return NSRect(
                x: round(padding),
                y: round(totalHeight - windowControlsHeight - leftView.frame.height * scale),
                width: round(leftView.frame.width * scale),
                height: round(leftView.frame.height * scale)
            )
        } else {
            return leftView.frame
        }
    }

    private func getRightViewTargetFrame(totalWidth: CGFloat, totalHeight: CGFloat) -> NSRect? {
        let miniatureSize: CGFloat = 60
        let scale = miniatureSize / max(miniatureSize, totalHeight)

        guard let rightView else { return nil }
        if isRightMinimized {
            if isAssistantMinimized || assistantView == nil {
                return NSRect(
                    x: totalWidth - padding - rightView.frame.width * scale,
                    y: totalHeight - padding - rightView.frame.height * scale,
                    width: rightView.frame.width * scale,
                    height: rightView.frame.height * scale
                )
            } else {
                return NSRect(
                    x: totalWidth - padding - assistantWidth - padding - rightView.frame.width * scale,
                    y: totalHeight - padding - rightView.frame.height * scale,
                    width: rightView.frame.width * scale,
                    height: rightView.frame.height * scale
                )
            }
        } else {
            return rightView.frame
        }
    }

    private func getAssistantViewTargetFrame(totalWidth: CGFloat, totalHeight: CGFloat) -> NSRect? {
        let miniatureSize: CGFloat = 60
        let scale = miniatureSize / max(miniatureSize, totalHeight)
        
        guard let assistantView else { return nil }
        if isAssistantMinimized {
            if let rightView, isRightMinimized {
                return NSRect(
                    x: totalWidth - padding - (rightView.frame.width + assistantView.frame.width) * scale - resizeHandleWidth,
                    y: totalHeight - padding - assistantView.frame.height * scale,
                    width: assistantView.frame.width * scale,
                    height: assistantView.frame.height * scale
                )
            } else {
                return NSRect(
                    x: totalWidth - padding - (rightView?.frame.width ?? 0) - padding - assistantView.frame.width * scale - resizeHandleWidth,
                    y: totalHeight - padding - assistantView.frame.height * scale,
                    width: assistantView.frame.width * scale,
                    height: assistantView.frame.height * scale
                )
            }
        } else {
            if isRightMinimized, rightView != nil {
                return NSRect(
                    x: assistantView.frame.origin.x + rightWidth + resizeHandleWidth,
                    y: assistantView.frame.origin.y,
                    width: assistantView.frame.width,
                    height: assistantView.frame.height
                )
            } else {
                return assistantView.frame
            }
        }
    }

    private func applyMiniatureTransforms(totalWidth: CGFloat, totalHeight: CGFloat) {
        let miniatureSize: CGFloat = 60

        // Handle left view transformation
        if let leftView, let targetFrame = getLeftViewTargetFrame(totalWidth: totalWidth, totalHeight: totalHeight) {
            let scale = targetFrame.height / leftView.frame.height
            let translateX = (targetFrame.origin.x - leftView.frame.minX) / scale
            let translateY = (targetFrame.origin.y - leftView.frame.minY) / scale
            leftView.layer?.setAffineTransform(
                .identity.scaledBy(x: scale, y: scale).translatedBy(x: translateX, y: translateY)
            )
            
            // Update shadow view frame
            leftShadowView?.frame = targetFrame

            leftResizeHandle?.layer?.setAffineTransform(
                .identity
                    .scaledBy(x: isLeftMinimized ? 0 : 1, y: 1)
            )
            if let leftMinimizeButton {
                leftMinimizeButton.isHidden = false
                updateButtonForState(leftMinimizeButton, isMinimized: isLeftMinimized, targetFrame: targetFrame)
            }
        } else {
            leftView?.layer?.setAffineTransform(.identity)
            leftResizeHandle?.layer?.setAffineTransform(.identity)
            leftMinimizeButton?.isHidden = true
        }

        if let rightView, let targetFrame = getRightViewTargetFrame(totalWidth: totalWidth, totalHeight: totalHeight) {
            let scale = targetFrame.height / rightView.frame.height
            let translateX = (targetFrame.origin.x - rightView.frame.minX) / scale
            let translateY = (targetFrame.origin.y - rightView.frame.minY) / scale
            rightView.layer?.setAffineTransform(
                .identity.scaledBy(x: scale, y: scale).translatedBy(x: translateX, y: translateY)
            )
            
            // Update shadow view frame
            rightShadowView?.frame = targetFrame

            rightResizeHandle?.layer?.setAffineTransform(
                .identity
                    .translatedBy(x: isRightMinimized ? resizeHandleWidth + rightWidth : 0, y: 0)
                    .scaledBy(x: isRightMinimized ? 0 : 1, y: 1)
            )
            if let rightMinimizeButton {
                rightMinimizeButton.isHidden = false
                updateButtonForState(rightMinimizeButton, isMinimized: isRightMinimized, targetFrame: targetFrame)
            }
        } else {
            rightView?.layer?.setAffineTransform(.identity)
            rightResizeHandle?.layer?.setAffineTransform(.identity)
            rightMinimizeButton?.isHidden = true
        }

        if let assistantView,
            let targetFrame = getAssistantViewTargetFrame(totalWidth: totalWidth, totalHeight: totalHeight)
        {
            let scale = targetFrame.height / assistantView.frame.height
            let translateX = (targetFrame.origin.x - assistantView.frame.minX) / scale
            let translateY = (targetFrame.origin.y - assistantView.frame.minY) / scale
            assistantView.layer?.setAffineTransform(
                .identity.scaledBy(x: scale, y: scale).translatedBy(x: translateX, y: translateY)
            )
            // Update shadow view frame
            assistantShadowView?.frame = targetFrame

            let offset = targetFrame.origin.x - assistantView.frame.origin.x

            assistantShadowView?.frame = targetFrame

            assistantResizeHandle?.layer?.setAffineTransform(
                .identity
                    .translatedBy(x: offset, y: 0)
                    .scaledBy(x: isAssistantMinimized ? 0 : 1, y: 1)
            )

            if let assistantMinimizeButton {
                assistantMinimizeButton.isHidden = false
                updateButtonForState(assistantMinimizeButton, isMinimized: isAssistantMinimized, targetFrame: targetFrame)
            }
        }

        let scale = miniatureSize / max(miniatureSize, totalHeight)
        leftView?.layer?.cornerRadius = isLeftMinimized ? 0.5 * cornerRadius / scale : cornerRadius
        rightView?.layer?.cornerRadius = isRightMinimized ? 0.5 * cornerRadius / scale : cornerRadius
        assistantView?.layer?.cornerRadius = isAssistantMinimized ? 0.5 * cornerRadius / scale : cornerRadius
    }

    private func styleFloatingView(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Border
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.1).cgColor
        view.layer?.borderWidth = 1
    }
    
    // MARK: - Minimize/Expand
    
    private func toggleLeftMinimized() {
        isLeftMinimized.toggle()
        animateMinimizationTransition()
    }
    
    private func toggleAssistantMinimized() {
        isAssistantMinimized.toggle()
        animateMinimizationTransition()
    }
    
    private func toggleRightMinimized() {
        isRightMinimized.toggle()
        animateMinimizationTransition()
    }
    
    private func animateMinimizationTransition() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            
            // Use layout() for consistent frame and transform updates
            self.layoutViews(animated: true)
        }
    }
    
    // MARK: - Mouse Handling
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        if let leftHandle = leftResizeHandle, 
           leftHandle.frame.contains(location),
           isLeftMinimized == false
        {
            startDragging(.left, at: location)
        } else if let assistantHandle = assistantResizeHandle,
                  assistantHandle.frame.contains(location),
                  isRightMinimized == false,
                  isAssistantMinimized == false
        {
            startDragging(.assistant, at: location)
        } else if let rightHandle = rightResizeHandle,
                  rightHandle.frame.contains(location),
                  isRightMinimized == false
        {
            startDragging(.right, at: location)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        if isDraggingLeft {
            let deltaX = location.x - dragStartPoint.x
            // Snap to whole-point values; fractional widths in the text-editor column
            // can provoke AppKit into a resize feedback-loop that ultimately crashes.
            let candidate = max(minLeftWidth, min(maxLeftWidth, dragStartWidth + deltaX))
            leftWidth = round(candidate)
            layoutViews()
        } else if isDraggingAssistant {
            let deltaX = location.x - dragStartPoint.x
            let candidate = max(minAssistantWidth, min(maxAssistantWidth, dragStartWidth - deltaX))
            assistantWidth = round(candidate)
            layoutViews()
        } else if isDraggingRight {
            let deltaX = location.x - dragStartPoint.x
            let candidate = max(minRightWidth, min(maxRightWidth, dragStartWidth - deltaX))
            rightWidth = round(candidate)
            layoutViews()
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        stopDragging()
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        let isOverLeftResizeHandle = (leftResizeHandle?.frame.contains(location) == true) && isLeftMinimized == false
        let isOverRightResizeHandle = (rightResizeHandle?.frame.contains(location) == true) && isRightMinimized == false
        let isOverAssistantResizeHandle = isRightMinimized == false &&
            isAssistantMinimized == false &&
            (assistantResizeHandle?.frame.contains(location) == true)

        let isOverResizeHandle = isOverLeftResizeHandle || isOverRightResizeHandle || isOverAssistantResizeHandle

        if isOverResizeHandle {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    private enum DragType {
        case left, assistant, right
    }
    
    private func startDragging(_ type: DragType, at point: NSPoint) {
        dragStartPoint = point
        
        switch type {
        case .left:
            isDraggingLeft = true
            dragStartWidth = leftWidth
        case .assistant:
            isDraggingAssistant = true
            dragStartWidth = assistantWidth
        case .right:
            isDraggingRight = true
            dragStartWidth = rightWidth
        }
        
        NSCursor.resizeLeftRight.set()
    }
    
    private func stopDragging() {
        isDraggingLeft = false
        isDraggingAssistant = false
        isDraggingRight = false
        NSCursor.arrow.set()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove old tracking areas
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        
        // Add new tracking area
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

struct NSFloatingSplitViewRepresentable: NSViewRepresentable {
    let leftContent: () -> NSView
    let middleContent: () -> NSView
    let assistantContent: (() -> NSView)?
    let rightContent: () -> NSView
    
    // Store SwiftUI builders for coordinator updates
    private let leftSwiftUIBuilder: (() -> AnyView)?
    private let middleSwiftUIBuilder: (() -> AnyView)?
    private let assistantSwiftUIBuilder: (() -> AnyView)?
    private let rightSwiftUIBuilder: (() -> AnyView)?
    
    // Coordinator to manage hosting view references
    class Coordinator {
        weak var splitView: NSFloatingSplitView?
        var leftHosting: NSHostingView<AnyView>?
        var middleHosting: NSHostingView<AnyView>?
        var assistantHosting: NSHostingView<AnyView>?
        var rightHosting: NSHostingView<AnyView>?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // Drop-in replacement for AdvancedFloatingSplitView
    init<LeftContent: View, MiddleContent: View, AssistantContent: View, RightContent: View>(
        @ViewBuilder leftContent: @escaping () -> LeftContent,
        @ViewBuilder middleContent: @escaping () -> MiddleContent,
        assistantContent: (() -> AssistantContent)? = nil,
        @ViewBuilder rightContent: @escaping () -> RightContent
    ) {
        // Store SwiftUI builders for updates
        self.leftSwiftUIBuilder = { AnyView(leftContent()) }
        self.middleSwiftUIBuilder = { AnyView(middleContent()) }
        self.assistantSwiftUIBuilder = assistantContent != nil ? { AnyView(assistantContent!()) } : nil
        self.rightSwiftUIBuilder = { AnyView(rightContent()) }
        
        // Keep NSView builders for compatibility, but they won't be used in coordinator mode
        self.leftContent = { NSHostingView(rootView: leftContent()) }
        self.middleContent = { NSHostingView(rootView: middleContent()) }
        self.assistantContent = assistantContent != nil ? { NSHostingView(rootView: assistantContent!()) } : nil
        self.rightContent = { NSHostingView(rootView: rightContent()) }
    }
    
    // NSView convenience initializers (existing functionality)
    init(
        leftContent: @escaping () -> NSView,
        middleContent: @escaping () -> NSView,
        assistantContent: (() -> NSView)? = nil,
        rightContent: @escaping () -> NSView
    ) {
        self.leftContent = leftContent
        self.middleContent = middleContent
        self.assistantContent = assistantContent
        self.rightContent = rightContent
        
        // No SwiftUI builders for NSView mode
        self.leftSwiftUIBuilder = nil
        self.middleSwiftUIBuilder = nil
        self.assistantSwiftUIBuilder = nil
        self.rightSwiftUIBuilder = nil
    }
    
    func makeNSView(context: Context) -> NSFloatingSplitView {
        let splitView = NSFloatingSplitView()
        context.coordinator.splitView = splitView
        
        // Create hosting views if we have SwiftUI builders (coordinator mode)
        if let leftBuilder = leftSwiftUIBuilder,
           let middleBuilder = middleSwiftUIBuilder,
           let rightBuilder = rightSwiftUIBuilder {
            
            let leftHosting = NSHostingView(rootView: leftBuilder())
            let middleHosting = NSHostingView(rootView: middleBuilder())
            let rightHosting = NSHostingView(rootView: rightBuilder())
            let assistantHosting = assistantSwiftUIBuilder.map { NSHostingView(rootView: $0()) }
            
            context.coordinator.leftHosting = leftHosting
            context.coordinator.middleHosting = middleHosting
            context.coordinator.rightHosting = rightHosting
            context.coordinator.assistantHosting = assistantHosting
            
            splitView.setLeftView(leftHosting)
            splitView.setMiddleView(middleHosting)
            if let assistantHosting = assistantHosting {
                splitView.setAssistantView(assistantHosting)
            }
            splitView.setRightView(rightHosting)
        } else {
            // Fallback to NSView mode for compatibility
            splitView.setLeftView(leftContent())
            splitView.setMiddleView(middleContent())
            if let assistantContent = assistantContent {
                splitView.setAssistantView(assistantContent())
            }
            splitView.setRightView(rightContent())
        }
        
        return splitView
    }
    
    func updateNSView(_ nsView: NSFloatingSplitView, context: Context) {
        // Update hosting views with fresh SwiftUI content via coordinator
        if let leftBuilder = leftSwiftUIBuilder {
            context.coordinator.leftHosting?.rootView = leftBuilder()
        }
        
        if let middleBuilder = middleSwiftUIBuilder {
            context.coordinator.middleHosting?.rootView = middleBuilder()
        }
        
        if let rightBuilder = rightSwiftUIBuilder {
            context.coordinator.rightHosting?.rootView = rightBuilder()
        }
        
        // Handle assistant panel creation/removal/update dynamically
        switch (assistantSwiftUIBuilder, context.coordinator.assistantHosting) {
            
        // 1️⃣ present & present → refresh
        case let (builder?, hosting?):
            hosting.rootView = builder()
            
        // 2️⃣ present & missing → create + attach
        case let (builder?, nil):
            let hosting = NSHostingView(rootView: builder())
            context.coordinator.assistantHosting = hosting
            context.coordinator.splitView?.setAssistantView(hosting)
            
        // 3️⃣ missing & present → detach + clean up
        case (nil, let hosting?):
            context.coordinator.splitView?.setAssistantView(nil)
            context.coordinator.assistantHosting = nil
            hosting.removeFromSuperview()
            
        default:
            break
        }
    }
}

// MARK: - SwiftUI Helper Extensions

extension NSView {
    static func fromSwiftUI<Content: View>(_ content: Content) -> NSView {
        let hostingView = NSHostingView(rootView: content)
        return hostingView
    }
}

// MARK: - Convenience Extension for Drop-in Replacement

extension NSFloatingSplitViewRepresentable {
    // Convenience initializer when no assistant content is needed (matches AdvancedFloatingSplitView)
    init<LeftContent: View, MiddleContent: View, RightContent: View>(
        @ViewBuilder leftContent: @escaping () -> LeftContent,
        @ViewBuilder middleContent: @escaping () -> MiddleContent,
        @ViewBuilder rightContent: @escaping () -> RightContent
    ) {
        // Store SwiftUI builders for updates
        self.leftSwiftUIBuilder = { AnyView(leftContent()) }
        self.middleSwiftUIBuilder = { AnyView(middleContent()) }
        self.assistantSwiftUIBuilder = nil
        self.rightSwiftUIBuilder = { AnyView(rightContent()) }
        
        // Keep NSView builders for compatibility
        self.leftContent = { NSHostingView(rootView: leftContent()) }
        self.middleContent = { NSHostingView(rootView: middleContent()) }
        self.assistantContent = nil
        self.rightContent = { NSHostingView(rootView: rightContent()) }
    }
}

// MARK: - Preview

struct NSFloatingSplitView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Drop-in replacement for AdvancedFloatingSplitView - with assistant content
            NSFloatingSplitViewRepresentable(
                leftContent: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Left Column")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Text("Non-hidable but resizable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(0..<8, id: \.self) { index in
                                Text("Item \(index + 1)")
                                    .font(.caption)
                                    .padding(.vertical, 2)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                },
                middleContent: {
                    VStack {
                        Text("Main Content")
                            .font(.title)
                        Text("Drop-in replacement for AdvancedFloatingSplitView")
                            .foregroundColor(.secondary)
                        Text("AppKit-based with identical SwiftUI API")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                },
                assistantContent: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Assistant Panel")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("AI Assistant panel that can be collapsed and resized using AppKit controls.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(0..<20, id: \.self) { index in
                                    HStack {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 8, height: 8)
                                        Text("Assistant Item \(index + 1)")
                                            .font(.caption)
                                            .lineLimit(2)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.green)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                },
                rightContent: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Inspector Panel")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("AppKit-based floating panel with manual frame layout, resize handles, and transform-based minimization.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(0..<15, id: \.self) { index in
                                    HStack {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 8, height: 8)
                                        Text("Inspector Item \(index + 1)")
                                            .font(.caption)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            )
            .frame(width: 1200, height: 600)
            .previewDisplayName("With Assistant Content")
            
            // Drop-in replacement for AdvancedFloatingSplitView - without assistant content  
            NSFloatingSplitViewRepresentable(
                leftContent: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Left Column")
                            .font(.headline)
                        Text("Three-pane layout")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                },
                middleContent: {
                    VStack {
                        Text("Main Content")
                            .font(.title)
                        Text("No assistant panel")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                },
                rightContent: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Inspector Only")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue)
                }
            )
            .frame(width: 1000, height: 500)
            .previewDisplayName("Without Assistant Content")
        }
        .ignoresSafeArea()
    }
}

#else
typealias NSFloatingSplitViewRepresentable = AdvancedFloatingSplitView
#endif
