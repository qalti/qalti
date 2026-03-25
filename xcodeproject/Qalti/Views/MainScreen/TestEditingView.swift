//
//  TestEditingView.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 03.06.2025.
//


import SwiftUI

#if os(macOS)
import AppKit
import Foundation
import Logging

struct TestEditingView: View {
    @EnvironmentObject private var suiteRunner: TestSuiteRunner
    @EnvironmentObject private var errorCapturer: ErrorCapturerService

    @StateObject private var textViewController: ActionTextViewController
    @State private var showReadOnlyWarning = false
    let fileURL: URL?
    let setUpdateFileURLCallback: ((@escaping (URL) -> Void) -> Void)?
    let setSaveFileCallback: ((@escaping () -> Void) -> Void)?
    let onReportRunHistoryChanged: ((RunHistory?) -> Void)?
    @Binding var showTestEditor: Bool
    @Binding var errorMessage: String?
    @Binding var isTestRun: Bool

    init(fileURL: URL?,
         showTestEditor: Binding<Bool>,
         errorMessage: Binding<String?>,
         isTestRun: Binding<Bool>,
         errorCapturer: ErrorCapturing,
         setUpdateFileURLCallback: ((@escaping (URL) -> Void) -> Void)? = nil,
         setSaveFileCallback: ((@escaping () -> Void) -> Void)? = nil,
         onReportRunHistoryChanged: ((RunHistory?) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self._showTestEditor = showTestEditor
        self._errorMessage = errorMessage
        self._isTestRun = isTestRun
        self.setUpdateFileURLCallback = setUpdateFileURLCallback
        self.setSaveFileCallback = setSaveFileCallback
        self.onReportRunHistoryChanged = onReportRunHistoryChanged
        self._textViewController = StateObject(wrappedValue: ActionTextViewController(
            errorCapturer: errorCapturer
        ))
    }

    var body: some View {
        ZStack {
            ActionTextEditor(controller: textViewController)
                .onAppear {
                    textViewController.setRunStateProvider { [weak suiteRunner] in
                        guard let runner = suiteRunner else { return false }
                        return runner.isTestRunning || runner.isRunning
                    }
                    textViewController.setBindings(showTestEditor: $showTestEditor, errorMessage: $errorMessage, isTestRun: $isTestRun)
                    textViewController.setReportHistoryUpdateHandler { history in
                        onReportRunHistoryChanged?(history)
                    }
                    textViewController.setFileURL(fileURL)
                    textViewController.setupInitialContent()

                    // Set up callback for read-only warning
                    textViewController.setReadOnlyWarningCallback {
                        guard showReadOnlyWarning == false else { return }
                        withAnimation {
                            showReadOnlyWarning = true
                        }
                        // Auto-dismiss after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                showReadOnlyWarning = false
                            }
                        }
                    }

                    // Provide the callback function to the parent
                    setUpdateFileURLCallback? { [textViewController] newURL in
                        textViewController.updateFileURL(newURL)
                    }

                    setSaveFileCallback? { [textViewController] in
                        textViewController.saveActions()
                    }
                }
                .legacy_onChange(of: fileURL) { newFileURL in
                    textViewController.setFileURL(newFileURL)
                }
                .onDisappear {
                    textViewController.saveActions()
                }

            // Read-only warning overlay
            ZStack {
                if showReadOnlyWarning {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 16, weight: .medium))

                                    Text("Read-Only Mode")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                }

                                Text("This is a test run recording and cannot be edited")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(16)
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            Spacer()
                        }
                        .padding(12)
                        Spacer()
                    }
                    .transition(.move(edge: .top))
                }
            }
        }
    }
}

struct ActionTextEditor: NSViewRepresentable {
    let controller: ActionTextViewController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = controller.scrollView

        // Ensure the scroll view can become first responder
        DispatchQueue.main.async {
            if let window = scrollView.window {
                window.makeFirstResponder(controller.textView)
            }
        }

        controller.textView.drawsBackground = false
        controller.textView.backgroundColor = .clear
        controller.textView.clipsToBounds = true

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Updates handled by the controller
    }

    class Coordinator: NSObject {
        let controller: ActionTextViewController

        init(controller: ActionTextViewController) {
            self.controller = controller
        }
    }
}

// MARK: - Custom NSTextView with Cmd+S handling
class ActionTextView: NSTextView {
    weak var actionController: ActionTextViewController?

    override func keyDown(with event: NSEvent) {
        // Check for Cmd+S
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
            actionController?.saveActions()
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // Check if the text view is not editable and trigger warning
        if !isEditable {
            actionController?.triggerReadOnlyWarning()
        }

        super.mouseDown(with: event)
    }
    
    override func paste(_ sender: Any?) {
        // Always strip styles from pasted content
        super.pasteAsPlainText(sender)
    }
}

class ActionTextViewController: NSObject, ObservableObject, Loggable {
    let scrollView = NSScrollView()
    lazy var textView: ActionTextView = {
        // This will be set properly in setupScrollView
        return ActionTextView()
    }()
    private let lineNumberView = LineNumberRulerView()
    private let errorCapturer: ErrorCapturing
    private let testFileLoader: TestFileLoader

    private var isUpdatingFormatting = false
    private var suppressTextDidChangeHandling = false
    private var actionChangeCallback: ((String, String) -> Void)?
    private var fileURL: URL?
    private var didLoadSuccessfully = false
    private var showTestEditorBinding: Binding<Bool>?
    private var errorMessageBinding: Binding<String?>?
    private var isTestRunBinding: Binding<Bool>?
    private var readOnlyWarningCallback: (() -> Void)?
    private var isRunInProgressProvider: (() -> Bool)?
    private var displayedFileUpdateCallback: ((URL) -> Void)?
    private var reportHistoryUpdateHandler: ((RunHistory?) -> Void)?
    private var currentContentIsReadOnlyReport = false

    init(errorCapturer: ErrorCapturing, fileManager: FileSystemManaging = FileManager.default) {
        self.errorCapturer = errorCapturer
        self.testFileLoader = TestFileLoader(errorCapturer: errorCapturer, fileManager: fileManager)
        super.init()
        setupScrollView()
        setupTextView()
    }

    func setBindings(showTestEditor: Binding<Bool>, errorMessage: Binding<String?>, isTestRun: Binding<Bool>) {
        self.showTestEditorBinding = showTestEditor
        self.errorMessageBinding = errorMessage
        self.isTestRunBinding = isTestRun
    }

    func setRunStateProvider(_ provider: @escaping () -> Bool) {
        isRunInProgressProvider = provider
    }

    func setDisplayedFileUpdateCallback(_ callback: @escaping (URL) -> Void) {
        displayedFileUpdateCallback = callback
    }

    func setReportHistoryUpdateHandler(_ handler: @escaping (RunHistory?) -> Void) {
        reportHistoryUpdateHandler = handler
    }


    private var isRunInProgress: Bool {
        isRunInProgressProvider?() ?? false
    }

    func setReadOnlyWarningCallback(_ callback: @escaping () -> Void) {
        self.readOnlyWarningCallback = callback
    }

    func triggerReadOnlyWarning() {
        readOnlyWarningCallback?()
    }

    private func setupScrollView() {
        // Copy the configuration from the helper-created scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        if scrollView.responds(to: NSSelectorFromString("allowedPocketEdges")) {
            scrollView.setValue(Int32(0), forKey: "allowedPocketEdges")
        }
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 28, left: 0, bottom: 0, right: 0)

        scrollView.documentView = textView

        // Configure line number ruler
        lineNumberView.ruleThickness = 50  // Set a fixed width for the ruler
        lineNumberView.textView = textView

        // Add line number ruler
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // Ensure proper layout
        scrollView.autoresizingMask = [.width, .height]
    }

    private func setupTextView() {
        // Configure the text view properties
        textView.delegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.clear
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.actionController = self

        // Make cursor and selection visible with explicit colors
        textView.insertionPointColor = NSColor.textColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.3),
            .foregroundColor: NSColor.textColor
        ]

        // Set up consistent line height for all lines (including empty ones)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.minimumLineHeight = 17 // Slightly larger than font size for better readability
        paragraphStyle.maximumLineHeight = 17

        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]

        // Layout configuration like the working example
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        // Ensure no text container margins that could clip text
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 0)

        // Additional configuration to ensure selection visibility
        textView.usesFindBar = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.displaysLinkToolTips = false
    }

    func setupInitialContent() {
        updateTextViewEditability()

        // Make the text view first responder to show cursor
        DispatchQueue.main.async { [weak self] in
            self?.textView.window?.makeFirstResponder(self?.textView)
        }
    }

    private func updateTextViewEditability() {
        // Disable text editing for test reports, but keep scrolling and selection enabled
        let isTestRun = isTestRunBinding?.wrappedValue ?? false
        textView.isEditable = !isTestRun
    }

    func focusTextView() {
        textView.window?.makeFirstResponder(textView)
    }

    func setFileURL(_ url: URL?) {
        let oldURL = fileURL
        fileURL = url
        if let url {
            handleFileSelection(oldURL, url)
        }
    }

    func updateFileURL(_ newURL: URL) {
        // Update only the file URL without affecting the editor content
        fileURL = newURL
        logger.debug("Updated file URL to: \(newURL.path)")
    }

    func saveActions() {
        guard let fileURL else { return }
        saveActions(to: fileURL)
    }

    func saveActions(to fileURL: URL) {
        guard didLoadSuccessfully else {
            print("Preventing save because initial file load failed.")
            return
        }

        guard !currentContentIsReadOnlyReport else { return }

        do {
            try saveAsPlainText(to: fileURL)

            // Show success feedback
            DispatchQueue.main.async { [weak self] in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    self?.textView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.2).cgColor
                } completionHandler: {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        self?.textView.layer?.backgroundColor = NSColor.clear.cgColor
                    }
                }
            }

            logger.debug("Actions saved to file: \(fileURL.path)")
        } catch {
            // Show error feedback
            DispatchQueue.main.async { [weak self] in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    self?.textView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
                } completionHandler: {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        self?.textView.layer?.backgroundColor = NSColor.clear.cgColor
                    }
                }
            }

            logger.error("Failed to save actions: \(error.localizedDescription)")
        }
    }


    private func handleFileSelection(_ oldURL: URL?, _ fileURL: URL) {
        if let oldURL, oldURL != fileURL, textView.string.count > 0, didLoadSuccessfully {
            saveActions(to: oldURL)
        }

        displayedFileUpdateCallback?(fileURL)
        errorMessageBinding?.wrappedValue = nil
        didLoadSuccessfully = false
        currentContentIsReadOnlyReport = false

        let fileExtension = fileURL.pathExtension.lowercased()

        // Check if it's a supported file type
        let isRulesFile = fileURL.lastPathComponent == ".qaltirules"
        guard TestFileLoader.isSupportedExtension(fileExtension) || isRulesFile else {
            // Not a supported file - clear actions and hide editor
            setEditorText("")
            isTestRunBinding?.wrappedValue = false
            updateTextViewEditability()
            showTestEditorBinding?.wrappedValue = false
            currentContentIsReadOnlyReport = false
            return
        }

        // Parse using shared file loader
        do {
            try loadTestFile(fileURL)
            didLoadSuccessfully = true
        } catch {
            errorCapturer.capture(error: error)
            // Parsing failed - clear actions and show error
            setEditorText("")
            reportHistoryUpdateHandler?(nil)
            isTestRunBinding?.wrappedValue = false
            updateTextViewEditability()
            showTestEditorBinding?.wrappedValue = false
            currentContentIsReadOnlyReport = false
            errorMessageBinding?.wrappedValue = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func loadTestFile(_ fileURL: URL) throws {
        // Special-case .qaltirules as plain text
        if fileURL.lastPathComponent == ".qaltirules" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            setEditorText(content)
            handleTestChanged(trackEdit: false)
            showTestEditorBinding?.wrappedValue = true
            isTestRunBinding?.wrappedValue = false
            reportHistoryUpdateHandler?(nil)
            updateTextViewEditability()
            currentContentIsReadOnlyReport = false
            return
        }
        
        let loadResult = try testFileLoader.load(from: fileURL)
        setEditorText(loadResult.test)
        handleTestChanged(trackEdit: false)
        showTestEditorBinding?.wrappedValue = true

        switch loadResult.source {
        case .jsonRun:
            isTestRunBinding?.wrappedValue = true
            currentContentIsReadOnlyReport = true
            if let testRun = loadResult.testRun {
                let runHistory = RunHistory()
                RunHistoryTranscript(messages: testRun.runHistory).apply(to: runHistory)
                reportHistoryUpdateHandler?(runHistory)
            } else {
                reportHistoryUpdateHandler?(nil)
            }
            updateTextViewEditability()

            if let testRun = loadResult.testRun {
                if let error = testRun.runFailureReason {
                    errorMessageBinding?.wrappedValue = "Loaded test report (Failed: \(error))"
                } else {
                    errorMessageBinding?.wrappedValue = "Loaded test report (Success)"
                }
            } else {
                errorMessageBinding?.wrappedValue = "Loaded test report"
            }

        case .jsonActions:
            isTestRunBinding?.wrappedValue = false
            reportHistoryUpdateHandler?(nil)
            updateTextViewEditability()
            currentContentIsReadOnlyReport = false

        case .plainText:
            isTestRunBinding?.wrappedValue = false
            reportHistoryUpdateHandler?(nil)
            updateTextViewEditability()
            currentContentIsReadOnlyReport = false
            errorMessageBinding?.wrappedValue = "Loaded test file"
        }
    }

    private func saveAsPlainText(to fileURL: URL) throws {
        try textView.string.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func handleTestChanged(trackEdit: Bool = true) {
        guard !isUpdatingFormatting else { return }

        if Thread.isMainThread {
            updateFormatting(trackEdit: trackEdit)
            lineNumberView.needsDisplay = true
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateFormatting(trackEdit: trackEdit)
                self?.lineNumberView.needsDisplay = true
            }
        }
    }

    private func setEditorText(_ text: String) {
        suppressTextDidChangeHandling = true
        defer { suppressTextDidChangeHandling = false }
        textView.string = text
    }

    private func updateFormatting(trackEdit: Bool) {
        isUpdatingFormatting = true
        defer { isUpdatingFormatting = false }

        let attributedString = NSMutableAttributedString()
        let selectedRanges = textView.selectedRanges

        // Set up consistent paragraph style for all text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.minimumLineHeight = 17
        paragraphStyle.maximumLineHeight = 17

        let lines = textView.string.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let attributedLine = createAttributedStringForLine(String(line), paragraphStyle: paragraphStyle)
            attributedString.append(attributedLine)

            // Add newline except for the last action
            if index < lines.count - 1 {
                let newlineRange = NSRange(location: attributedString.length, length: 1)
                attributedString.append(NSAttributedString(string: "\n"))
                // Apply paragraph style to newline as well
                attributedString.addAttributes([.paragraphStyle: paragraphStyle], range: newlineRange)
            }
        }

        textView.textStorage?.setAttributedString(attributedString)

        // Ensure selection attributes are properly set after content update with explicit colors
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.3),
            .foregroundColor: NSColor.textColor
        ]

        // Restore selection/caret position (clamp ranges in case of bounds mismatch)
        let textLength = attributedString.length
        let clampedRanges = selectedRanges.compactMap { value -> NSValue? in
            var range = value.rangeValue
            guard range.location != NSNotFound else { return nil }
            if range.location > textLength {
                range.location = textLength
                range.length = 0
            } else if range.location + range.length > textLength {
                range.length = max(0, textLength - range.location)
            }
            return NSValue(range: range)
        }
        textView.selectedRanges = clampedRanges

        // Reset typing attributes to ensure proper font when typing
        resetTypingAttributes()

        lineNumberView.needsDisplay = true
        textView.needsDisplay = true
    }

    // Helper function to find common prefix length between two strings
    private func commonPrefixLength(_ str1: String, _ str2: String) -> Int {
        let chars1 = Array(str1)
        let chars2 = Array(str2)
        var count = 0
        let maxCount = min(chars1.count, chars2.count)

        while count < maxCount && chars1[count] == chars2[count] {
            count += 1
        }
        return count
    }

    // Helper function to find common suffix length between two strings
    private func commonSuffixLength(_ str1: String, _ str2: String) -> Int {
        let chars1 = Array(str1)
        let chars2 = Array(str2)
        var count = 0
        let maxCount = min(chars1.count, chars2.count)

        while count < maxCount &&
                chars1[chars1.count - 1 - count] == chars2[chars2.count - 1 - count] {
            count += 1
        }
        return count
    }

    private func applyFormattingToHighlightedText(_ highlightedText: NSMutableAttributedString, paragraphStyle: NSParagraphStyle) {
        let fullRange = NSRange(location: 0, length: highlightedText.length)
        highlightedText.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        highlightedText.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: fullRange)
    }

    private func createAttributedStringForLine(_ text: String, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .paragraphStyle: paragraphStyle
        ]

        // Try to parse and syntax highlight the command
        do {
            let parseResult = try IOSRuntime.parseCommand(from: text)
            let highlightedText = parseResult.formattedCommand.mutableCopy() as! NSMutableAttributedString

            applyFormattingToHighlightedText(highlightedText, paragraphStyle: paragraphStyle)

            return highlightedText
        } catch {
            // Fallback to simple syntax highlighting
            return applyFallbackSyntaxHighlighting(to: text, baseAttributes: baseAttributes)
        }
    }

    private func applyFallbackSyntaxHighlighting(to text: String, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let fullRange = NSRange(location: 0, length: text.count)

        // Set base text color
        attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        // Tone down comments first so URL styling can override overlapping ranges
        let commentPattern = #"(//|#).*$"#
        if let commentRegex = try? NSRegularExpression(pattern: commentPattern, options: [.anchorsMatchLines]) {
            commentRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: matchRange)
                attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: matchRange)
            }
        }
        
        // Highlight URLs last (including deep links) so they remain distinct even inside comments
        let urlPattern = #"(?:https?://|[a-zA-Z][a-zA-Z0-9+.-]*://)[^\s<>"{}|\\^`\[\]]*"#
        if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
            urlRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: matchRange)
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            }
        }

        return attributedString
    }
}

// MARK: - NSTextViewDelegate
extension ActionTextViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !suppressTextDidChangeHandling else { return }
        handleTestChanged()
    }


    private func resetTypingAttributes() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.minimumLineHeight = 17
        paragraphStyle.maximumLineHeight = 17

        if Thread.isMainThread {
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle
            ]
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.textView.typingAttributes = [
                    .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: paragraphStyle
                ]
            }
        }
    }

    private func getCurrentLineText(in text: NSString, at location: Int) -> String {
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        return text.substring(with: lineRange).trimmingCharacters(in: .newlines)
    }

    private func getPreviousLineText(in text: NSString, at location: Int) -> String {
        guard location > 0 else { return "" }
        let previousLocation = location - 1
        let lineRange = text.lineRange(for: NSRange(location: previousLocation, length: 0))
        return text.substring(with: lineRange).trimmingCharacters(in: .newlines)
    }

    private func getNextLineText(in text: NSString, at location: Int) -> String {
        guard location + 1 < text.length else { return "" }
        let lineRange = text.lineRange(for: NSRange(location: location + 1, length: 0))
        return text.substring(with: lineRange).trimmingCharacters(in: .newlines)
    }
}

// MARK: - Line Number Ruler View
class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        self.clientView = scrollView?.documentView
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Don't call super.draw to avoid drawing the default background
        // Only draw our custom content
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView, let layoutManager = textView.layoutManager else { return }

        let visibleRect = rect
        let text = textView.string as NSString
        var lineNumber = 0
        var charIndex = 0
        var lastLineHeight: CGFloat = 17.0 // Default line height as fallback
        var lastYPosition: CGFloat = scrollView?.contentInsets.top ?? (lastLineHeight * 1.5) // Track last Y position

        // Iterate through all logical lines (newline-separated)
        while charIndex < text.length {
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))

            // Gather all visual fragments (wraps) for this logical line
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)

            var firstFragmentY: CGFloat? = nil
            var firstFragmentHeight: CGFloat = 0

            // Track union across all wrapped fragments to draw one continuous highlight
            var minYForLine: CGFloat? = nil
            var maxYForLine: CGFloat = 0

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, _, _ in
                // Save last non-zero height for empty-line rendering
                if fragmentRect.height > 0 {
                    lastLineHeight = fragmentRect.height
                }

                // Convert to ruler coords
                let rectInRuler = self.convert(fragmentRect, from: textView)
                let y = rectInRuler.origin.y

                // Track top of the logical line for number/icon placement and empty-line math
                if firstFragmentY == nil {
                    firstFragmentY = y
                    firstFragmentHeight = fragmentRect.height
                }
                // Track last Y across fragments
                lastYPosition = y

                // Track union only; defer drawing until after enumeration to ensure full multi-line coverage
                if minYForLine == nil {
                    minYForLine = y
                } else {
                    minYForLine = min(minYForLine!, y)
                }
                maxYForLine = max(maxYForLine, y + fragmentRect.height)
            }

            // Draw line number and status icons once at the top fragment
            if let yTop = firstFragmentY {
                if yTop >= visibleRect.minY - 20 && yTop <= visibleRect.maxY + 20 {
                    let numberString = "\(lineNumber + 1)"
                    let numberRect = NSRect(x: 5, y: yTop + 2, width: ruleThickness - 10, height: firstFragmentHeight)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                    numberString.draw(in: numberRect, withAttributes: attributes)

                    // TODO: Add drawing status icons for the line here
                }
            }

            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }

        // Handle final empty line if text ends with newline
        if text.length > 0 && text.hasSuffix("\n") || text.length == 0 {
            // Get the line fragment rect for the final empty line
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: text.length, effectiveRange: nil)


            // Use the saved line height if the empty line has zero height
            let effectiveHeight = lineRect.height > 0 ? lineRect.height : lastLineHeight

            // Calculate the effective Y position for the empty line
            let effectiveYPosition = text.length == 0 ? lastYPosition : (lastYPosition + lastLineHeight)

            // Check if this line is visible in the ruler view
            if effectiveYPosition >= visibleRect.minY - 20 && effectiveYPosition <= visibleRect.maxY + 20 {
                // Draw line number for the empty line
                let numberString = "\(lineNumber + 1)"
                let numberRect = NSRect(x: 5, y: effectiveYPosition + 2, width: ruleThickness - 10, height: effectiveHeight)

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]

                numberString.draw(in: numberRect, withAttributes: attributes)
            }
        }
    }

    private func drawStatusIcon(at point: NSPoint, color: NSColor, symbol: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: color
        ]

        symbol.draw(at: point, withAttributes: attributes)
    }
}

private extension Action {
    var displayText: String { parsedAction ?? action }
}


struct TestEditingUsageExample: View {
    @EnvironmentObject private var errorCapturer: ErrorCapturerService

    @State private var showTestEditor = true
    @State private var errorMessage: String? = nil
    @State private var isTestRun = true

    var body: some View {
        VStack {
            HStack {
                Button("Toggle Test Report Mode") {
                    isTestRun.toggle()
                }
                Spacer()
            }
            .padding()

            TestEditingView(
                fileURL: nil,
                showTestEditor: $showTestEditor,
                errorMessage: $errorMessage,
                isTestRun: $isTestRun,
                errorCapturer: errorCapturer,
                setUpdateFileURLCallback: nil,
                setSaveFileCallback: nil
            )
        }
    }
}

#Preview {
    HStack {
        let suiteRunner = PreviewServices.makeSuiteRunner()
        let errorCapturer = PreviewServices.errorCapturer

        TestEditingUsageExample()
            .environmentObject(suiteRunner)
            .environmentObject(errorCapturer)
            .frame(width: 500, height: 600)
    }
}

#else
struct TestEditingView: View {
    let fileURL: URL?
    @Binding var showTestEditor: Bool
    @Binding var errorMessage: String?
    @Binding var isTestRun: Bool

    init(fileURL: URL?,
         showTestEditor: Binding<Bool>,
         errorMessage: Binding<String?>,
         isTestRun: Binding<Bool>,
         setUpdateFileURLCallback: ((@escaping (URL) -> Void) -> Void)? = nil,
         setSaveFileCallback: ((@escaping () -> Void) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self._showTestEditor = showTestEditor
        self._errorMessage = errorMessage
        self._isTestRun = isTestRun
    }

    var body: some View {
        Text("Placeholder in non-macOS builds")
    }
}
#endif
