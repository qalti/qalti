//
//  TargetViewModel.swift
//  Qalti
//
//  Created by Vyacheslav Gilevich on 19.03.2025.
//

import SwiftUI
import Foundation
import Logging
import UniformTypeIdentifiers
import simd
import IOSurface
import CoreVideo
import CoreImage

@MainActor
class TargetViewModel: ObservableObject, Loggable {

    enum Constants {
        static let deceleration: Float = 0.2
        static let twoFrameDeceleration: Float = 1.0 - (1.0 - deceleration) * (1.0 - deceleration)
    }
    
    enum Errors: LocalizedError, CustomNSError {
        case deviceNameResolutionFailed(udid: String)
        case noFramesReceived(udid: String, deviceName: String)

        static var errorDomain: String { "ScreenCapture" }

        var errorCode: Int {
            switch self {
            case .deviceNameResolutionFailed:
                return 1001
            case .noFramesReceived:
                return 1002
            }
        }

        var errorUserInfo: [String : Any] {
            switch self {
            case .deviceNameResolutionFailed(let udid):
                return [
                    NSLocalizedDescriptionKey: "Failed to resolve device name for UDID",
                    "udid": udid
                ]
            case .noFramesReceived(let udid, let deviceName):
                return [
                    NSLocalizedDescriptionKey: "No frames received after starting screen capture",
                    "udid": udid,
                    "deviceName": deviceName
                ]
            }
        }

        var errorDescription: String? {
            switch self {
            case .deviceNameResolutionFailed:
                return "Failed to resolve device name for UDID"
            case .noFramesReceived:
                return "No frames received after starting screen capture"
            }
        }
    }
    // Dependencies
    let runtime: IOSRuntime
    private let errorCapturer: ErrorCapturing
    private let idbManager: IdbManaging

    // Published properties (state)
    @Published var image: PlatformImage?
    @Published var initialImage: PlatformImage?
    @Published var tappedElementImage: PlatformImage?
    @Published var unsavedAction: String?
    @Published var requestsInFlight: Int = 0
    @Published var requestIndex: Int = 0
    @Published var consecutiveFailedRequests: Int = 0
    @Published var presentedIndex: Int = 0
    @Published var highlightsElement: Bool = false
    @Published var allowsTimeSaving: Bool = false
    @Published var heighlightedUIElement: UIElement?
    @Published var referenceSize: CGSize = .zero
    @Published var tappedUIElement: UIElement?
    @Published var isInstallingApp = false
    @Published var installStatus: String? = nil
    @Published var installError: String? = nil
    @Published var isDecelerating: Bool = false
    @Published var ioSurface: IOSurface? = nil {
        didSet {
            TargetSurfaceRegistry.shared.update(surface: ioSurface)
        }
    }
    @Published var screenScale: CGFloat = 3.0
    
    // Real device capture
    private var screenCapture: ScreenCaptureService?

    // Private properties
    private var timer: Timer?
    private var lastKeyPress = Date()
    private var charBuffer: String = ""
    private var isInputRequestInFlight: Bool = false

    private var targetPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var lastRegisteredMouseMove: Date = Date()
    private var recordedActions: [Action] = []
    private var isRecording: Bool = false

    // Initialization
    init(runtime: IOSRuntime, errorCapturer: ErrorCapturing, idbManager: IdbManaging) {
        self.runtime = runtime
        self.errorCapturer = errorCapturer
        self.idbManager = idbManager
    }

    // MARK: - Public Methods

    func onAppear() {
        // Simulators: prefer IOSurface; Real devices: use AVFoundation screen capture
        if runtime.isRealDevice {
            startScreenCaptureIfPossible()
        } else {
            tryGetIOSurface()
        }
        
        restartTimer()

        runtime.fetchScreenScale { [weak self] scale in
            DispatchQueue.main.async { [weak self] in
                if let scale, scale >= 1.0 { self?.screenScale = scale }
            }
        }
    }

    func onDisappear() {
        timer?.invalidate()
        timer = nil
        screenCapture?.stop()
        screenCapture = nil
        ioSurface = nil
    }

    func toggleHighlightsElement() {
        highlightsElement.toggle()
    }

    func toggleAllowsTimeSaving() {
        allowsTimeSaving.toggle()
    }

    func onMouseMove(_ value: DragGesture.Value, viewSize: CGSize) {
        // Get the display size (either from IOSurface or image)
        let displaySize: CGSize
        if let ioSurface = ioSurface {
            displaySize = CGSize(width: CGFloat(IOSurfaceGetWidth(ioSurface)), height: CGFloat(IOSurfaceGetHeight(ioSurface)))
        } else if let image = image {
            displaySize = image.size
        } else {
            return
        }
        
        guard !isDecelerating else { return }
        saveAction()

        let mappedPoint = convertToImageCoordinates(
            touchLocation: value.location,
            inViewSize: viewSize,
            forImageSize: displaySize
        ).clamped(to: displaySize, eps: 1.0)

        let initialMappedPoint = convertToImageCoordinates(
            touchLocation: value.startLocation,
            inViewSize: viewSize,
            forImageSize: displaySize
        ).clamped(to: displaySize, eps: 1.0)

        let constrainedPoint = constrainLocationIfNeeded(current: mappedPoint, initial: initialMappedPoint)

        targetPoint = constrainedPoint
        if currentPoint == nil {
            currentPoint = targetPoint
        }

        guard let targetPoint, let currentPoint else { return }

        let newPoint = currentPoint.simd.mixed(with: targetPoint.simd, Constants.deceleration).cgPoint

        self.currentPoint = newPoint

        if !runtime.isRealDevice {
            try? performTouch(runtime.deviceId, at: newPoint, scale: screenScale, up: false)
        }
        lastRegisteredMouseMove = Date()

        if initialImage == nil {
            initialImage = getLastImage()
            tappedUIElement = heighlightedUIElement
            tappedElementImage = tappedUIElement.flatMap { element in
                guard let image = getLastImage() else { return nil }
                let scale = image.size.width / referenceSize.width
                let x = element.frame.origin.x * scale
                let y = element.frame.origin.y * scale
                let width = element.frame.width * scale
                let height = element.frame.height * scale

                let elementRect = CGRect(x: x, y: y, width: width, height: height)

                // Ensure the rect is within the image bounds
                let validRect = elementRect.intersection(CGRect(origin: .zero, size: image.size))

                // Crop the image to the element's frame
                return image.cropped(to: validRect)
            }
        }
    }

    func onMouseUp(_ value: DragGesture.Value, viewSize: CGSize) {
        guard !isDecelerating, (ioSurface != nil || image != nil), initialImage != nil else { return }

        let displaySize = (ioSurface != nil) ? CGSize(width: IOSurfaceGetWidth(ioSurface!), height: IOSurfaceGetHeight(ioSurface!)) : image!.size
        let mappedPoint = convertToImageCoordinates(touchLocation: value.location, inViewSize: viewSize, forImageSize: displaySize).clamped(to: displaySize, eps: 1.0)
        let initialMappedPoint = convertToImageCoordinates(touchLocation: value.startLocation, inViewSize: viewSize, forImageSize: displaySize).clamped(to: displaySize, eps: 1.0)
        let constrainedPoint = constrainLocationIfNeeded(current: mappedPoint, initial: initialMappedPoint)

        guard let _ = targetPoint, let currentPoint else { return }

        let runtime = runtime
        let idbManager = idbManager
        let screenScale = screenScale

        isDecelerating = true

        Task {
            await performMouseUpGesture(
                initialPoint: initialMappedPoint,
                finalPoint: constrainedPoint,
                currentPoint: currentPoint,
                tapPoint: mappedPoint,
                runtime: runtime,
                idbManager: idbManager,
                screenScale: screenScale
            )
        }
    }

    func onKeyPress(_ characters: String) {
        var newAction: String

        let character = characters.replacingOccurrences(of: "'", with: "\\'")

        if unsavedAction == nil {
            newAction = "input('\(character)')"
            initialImage = getLastImage()
        } else if let unsavedAction, unsavedAction.starts(with: "input(") == true {
            newAction = unsavedAction
            newAction.removeLast(2)
            newAction = newAction + character + "')"
        } else {
            saveAction()
            newAction = "input('\(character)')"
            initialImage = getLastImage()
        }

        unsavedAction = newAction

        lastKeyPress = Date()
        charBuffer += characters

        if !isInputRequestInFlight {
            sendBuffer()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, unsavedAction == newAction else { return }
            saveAction(checkLastKeyPress: true)
        }
    }

    private func sendBuffer() {
        guard !charBuffer.isEmpty else { return }
        
        let textToSend = charBuffer
        charBuffer = ""
        isInputRequestInFlight = true
        
        runtime.input(text: textToSend) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isInputRequestInFlight = false
                self?.sendBuffer()
            }
        }
    }

    func saveAction(checkLastKeyPress: Bool = false) {
        guard let unsavedAction else { return }

        guard isRecording else {
            self.unsavedAction = nil
            self.initialImage = nil
            tappedElementImage = nil
            return
        }

        if checkLastKeyPress, Date().timeIntervalSince(lastKeyPress) <= 2.99, unsavedAction.starts(with: "input(") {
            return
        }

        if let initialImage, let image = getLastImage() {
            let newAction = Action(
                action: unsavedAction,
                startImage: initialImage,
                endImage: image,
                elementImage: tappedElementImage
            )
            recordedActions.append(newAction)
            
            self.unsavedAction = nil
            self.initialImage = nil
            tappedElementImage = nil
        } else {
        }
    }

    func saveAndCreateNewAction(_ action: String) {
        saveAction()
        unsavedAction = action
        initialImage = getLastImage()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, unsavedAction == action else { return }
            saveAction()
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return false
        }

        setInstalling(true)

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] (item, error) in
            DispatchQueue.main.async {
                self?.processDroppedItem(item, error: error)
            }
        }
        return true
    }

    func reset() {
        recordedActions = []
        unsavedAction = nil
        initialImage = nil
    }

    func openHomeScreen() {
        saveAndCreateNewAction("open_app('com.apple.springboard')")
        runtime.openApp(name: "com.apple.springboard") { _ in }
    }

    func openAppSwitcher() {
        saveAndCreateNewAction("press('home', 2)")
        runtime.press(button: "home", amount: 2)
    }

    func clearInputField() {
        saveAndCreateNewAction("clear_input_field()")
        runtime.clearInputField() { _ in }
    }

    // MARK: - Private Methods

    nonisolated private func performMouseUpGesture(
        initialPoint: CGPoint,
        finalPoint: CGPoint,
        currentPoint: CGPoint,
        tapPoint: CGPoint,
        runtime: IOSRuntime,
        idbManager: IdbManaging,
        screenScale: CGFloat
    ) async {
        var currentPoint = currentPoint
        do {
            if !runtime.isRealDevice {
                while length(finalPoint.simd - currentPoint.simd) > screenScale.float {
                    currentPoint = currentPoint.simd.mixed(with: finalPoint.simd, Constants.deceleration).cgPoint
                    try await performTouch(runtime.deviceId, at: currentPoint, scale: screenScale, up: false)
                    try await Task.sleep(nanoseconds: 15_000_000)
                }
                for _ in 0..<5 {
                    try await performTouch(runtime.deviceId, at: finalPoint, scale: screenScale, up: false)
                    try await Task.sleep(nanoseconds: 15_000_000)
                }
            }
            await finalizeMouseUpAction(initialPoint: initialPoint, finalPoint: finalPoint, tapPoint: tapPoint)
        } catch {
            await handleGestureError(error)
        }
    }

    @MainActor
    private func finalizeMouseUpAction(initialPoint: CGPoint, finalPoint: CGPoint, tapPoint: CGPoint) async {
        targetPoint = nil
        self.currentPoint = nil
        isDecelerating = false

        let diffX = finalPoint.x - initialPoint.x
        let diffY = finalPoint.y - initialPoint.y
        let length = sqrt(diffX * diffX + diffY * diffY)

        let newAction: String
        if length > 30 {
            let (x, y) = (Int(initialPoint.x), Int(initialPoint.y))
            let direction = (abs(diffX) > abs(diffY)) ? (diffX > 0 ? "right" : "left") : (diffY > 0 ? "down" : "up")
            let alignedLength = (abs(diffX) > abs(diffY)) ? Int(abs(diffX)) : Int(abs(diffY))

            newAction = "creep(\(x),\(y),'\(direction)',\(alignedLength))"

            if runtime.isRealDevice {
                runtime.creep(location: (x, y), direction: direction, amount: alignedLength) { _ in }
            } else {
                try? performTouch(runtime.deviceId, at: finalPoint, scale: screenScale, up: true)
            }
        } else {
            newAction = "tap(\(tapPoint.x.int),\(tapPoint.y.int))"
            if runtime.isRealDevice {
                runtime.tapScreen(location: (tapPoint.x.int, tapPoint.y.int)) { _ in }
            } else {
                try? performTouch(runtime.deviceId, at: tapPoint, scale: screenScale, up: true)
            }
        }

        unsavedAction = newAction
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.unsavedAction == newAction {
                self?.saveAction()
            }
        }
    }

    @MainActor
    private func handleGestureError(_ error: Error) async {
        isDecelerating = false
        errorCapturer.capture(error: error)
    }

    @MainActor
    private func processDroppedItem(_ item: NSSecureCoding?, error: Error?) {
        if let error {
            handleInstallError("Failed to load app: \(error.localizedDescription)")
            return
        }
        guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
            handleInstallError("Invalid URL data")
            return
        }
        guard url.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: url.path) else {
            handleInstallError("Invalid app bundle")
            return
        }

        idbManager.installApp(appPath: url.path, udid: runtime.deviceId, makeDebuggable: false) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleInstallResult(result, appName: url.lastPathComponent)
            }
        }
    }

    @MainActor
    private func handleInstallResult(_ result: Result<String, Error>, appName: String) {
        switch result {
        case .success:
            setStatus("Successfully installed \(appName)")
            setInstalling(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.setStatus(nil) }
        case .failure(let error):
            handleInstallError("Installation failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func handleInstallError(_ message: String) {
        setError(message)
        setInstalling(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.setError(nil) }
    }

    private func getLastImage() -> PlatformImage? {
         if let ioSurface {
            let generatedImage = createImageFromIOSurface(ioSurface)
            return generatedImage
        } else if let image {
            // Check if timer is working when using image fallback
            assert(timer != nil && timer!.isValid, "Timer is not working - timer is nil or invalid")
            return image
        }
        return nil
    }
    
    private func createImageFromIOSurface(_ surface: IOSurface) -> PlatformImage? {
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)
        
        IOSurfaceLock(surface, IOSurfaceLockOptions.readOnly, nil)
        defer { IOSurfaceUnlock(surface, IOSurfaceLockOptions.readOnly, nil) }
        
        let baseAddress = IOSurfaceGetBaseAddress(surface)
        
        // Get color space from IOSurface properties if available
        let colorSpace: CGColorSpace
        if let colorSpaceValue = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace) as? String {
            colorSpace = CGColorSpace(name: colorSpaceValue as CFString) ?? CGColorSpaceCreateDeviceRGB()
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }
        
        // Infer bitmap info from IOSurface pixel format
        let pixelFormat = IOSurfaceGetPixelFormat(surface)
        let bitmapInfo: UInt32

        // Handle YUV422 formats via CoreImage with Rec.709 + sRGB
        if pixelFormat == kCVPixelFormatType_422YpCbCr8 || pixelFormat == kCVPixelFormatType_422YpCbCr8_yuvs {
            var unmanagedPB: Unmanaged<CVPixelBuffer>?
            let status = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &unmanagedPB)
            guard status == kCVReturnSuccess, let unwrapped = unmanagedPB else { return nil }
            let pb: CVPixelBuffer = unwrapped.takeRetainedValue()

            // Attach matrix/primaries/transfer function hints
            CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey as CFString, kCVImageBufferYCbCrMatrix_ITU_R_709_2 as CFTypeRef, .shouldPropagate)
            CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey as CFString, kCVImageBufferColorPrimaries_ITU_R_709_2 as CFTypeRef, .shouldPropagate)
            CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey as CFString, kCVImageBufferTransferFunction_sRGB as CFTypeRef, .shouldPropagate)

            let ciImage = CIImage(cvPixelBuffer: pb)
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)
            let context = CIContext(options: [
                .workingColorSpace: srgb as Any,
                .outputColorSpace: srgb as Any
            ])
            guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else { return nil }
            return PlatformImage(cgImage: cgImage, scale: 1.0 / screenScale)
        }

        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        case kCVPixelFormatType_32RGBA:
            bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        case kCVPixelFormatType_24RGB:
            bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.none.rawValue
        default:
            // Default fallback
            bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        }
        
        guard let context = CGContext(
            data: baseAddress,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: Int(bytesPerRow),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        guard let cgImage = context.makeImage() else { return nil }

        return PlatformImage(cgImage: cgImage, scale: 1.0 / screenScale)
    }

    private func tryGetIOSurface() {
        guard !runtime.isRealDevice else { return }
        guard idbManager.isConnected(udid: runtime.deviceId) else { return }
        
        idbManager.displayIOSurface(udid: runtime.deviceId) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let surface):
                    self.ioSurface = surface
                    // Stop the screenshot timer since we have live IOSurface
                    // The IOSurface contents will update automatically at 30fps
                    self.timer?.invalidate()
                    self.timer = nil
                case .failure(let error):
                    logger.error("Failed to get IOSurface: \(error)")
                    // Fall back to screenshot timer
                    self.ioSurface = nil
                }
            }
        }
    }

    private func startScreenCaptureIfPossible() {
        guard runtime.isRealDevice else { return }

        Task.detached(priority: .userInitiated) {
            await self.performScreenCaptureSetup()
        }
    }

    private func performScreenCaptureSetup() async {
        let deviceName: String?
        do {
            let targets = try idbManager.listTargets()
            deviceName = targets.first(where: { $0.udid == runtime.deviceId })?.name
        } catch {
            errorCapturer.capture(error: error)
            deviceName = nil
        }

        guard let deviceName = deviceName else {
            errorCapturer.capture(error: Errors.deviceNameResolutionFailed(udid: runtime.deviceId))
            return
        }

        let service = ScreenCaptureService(deviceName: deviceName) { [weak self] surface in
            DispatchQueue.main.async {
                self?.handleCapturedSurface(surface)
            }
        }

        do {
            try service.start()
            await MainActor.run {
                self.didStartScreenCapture(service, deviceName: deviceName)
            }
        } catch {
            errorCapturer.capture(error: error)
            logger.error("Failed to start screen capture: \(error.localizedDescription)")
            ScreenCaptureService.openCameraPrivacyPane()
        }
    }

    @MainActor
    private func handleCapturedSurface(_ surface: IOSurface?) {
        timer?.invalidate()
        timer = nil
        ioSurface = surface
        image = nil
    }

    @MainActor
    private func didStartScreenCapture(_ service: ScreenCaptureService, deviceName: String) {
        screenCapture = service
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.screenCapture != nil && self.ioSurface == nil {
                let error = Errors.noFramesReceived(udid: self.runtime.deviceId, deviceName: deviceName)
                errorCapturer.capture(error: error)
            }
        }
    }

    private func restartTimer() {
        // Don't start timer if we have IOSurface or screen capture running
        guard ioSurface == nil, screenCapture == nil else { return }
        
        timer?.invalidate()
        timer = Timer(timeInterval: 0.03333, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleTimerTick()
            }
        }

        guard let timer else { return }
        RunLoop.current.add(timer, forMode: .common)
    }

    @MainActor
    private func handleTimerTick() {
        handleScreenshotUpdate()
        handleMouseMoveContinuation()
    }

    @MainActor
    private func handleScreenshotUpdate() {
        guard requestsInFlight < 5 else { return }
        requestIndex += 1
        guard consecutiveFailedRequests < 5 || requestIndex % 10 == 0 else { return }
        requestsInFlight += 1

        let presentationIndex = requestIndex
        runtime.takeScreenshot { [weak self] platformImage in
            DispatchQueue.main.async {
                self?.handleScreenshotResponse(platformImage, presentationIndex: presentationIndex)
            }
        }
    }

    @MainActor
    private func handleScreenshotResponse(_ platformImage: PlatformImage?, presentationIndex: Int) {
        requestsInFlight -= 1
        if platformImage == nil {
            consecutiveFailedRequests += 1
        } else {
            consecutiveFailedRequests = 0
        }
        guard presentedIndex < presentationIndex else { return }
        image = platformImage
        presentedIndex = presentationIndex
    }

    @MainActor
    private func handleMouseMoveContinuation() {
        guard let targetPoint, let currentPoint, !isDecelerating,
              Date().timeIntervalSince(lastRegisteredMouseMove) > 0.03333 else { return }

        let newPoint = currentPoint.simd.mixed(with: targetPoint.simd, Constants.twoFrameDeceleration).cgPoint
        self.currentPoint = newPoint

        if !runtime.isRealDevice {
            try? performTouch(runtime.deviceId, at: newPoint, scale: screenScale, up: false)
        }
    }

    private func convertToImageCoordinates(touchLocation: CGPoint, inViewSize viewSize: CGSize, forImageSize imageSize: CGSize) -> CGPoint {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        let scale: CGFloat
        let offset: CGPoint

        if viewAspect > imageAspect {
            scale = viewSize.height / imageSize.height
            let scaledImageWidth = imageSize.width * scale
            offset = CGPoint(x: (viewSize.width - scaledImageWidth) / 2.0, y: 0)
        } else {
            scale = viewSize.width / imageSize.width
            let scaledImageHeight = imageSize.height * scale
            offset = CGPoint(x: 0, y: (viewSize.height - scaledImageHeight) / 2.0)
        }

        let imageX = (touchLocation.x - offset.x) / scale
        let imageY = (touchLocation.y - offset.y) / scale

        return CGPoint(x: imageX, y: imageY)
    }

    private func setInstalling(_ installing: Bool) {
        isInstallingApp = installing
        if installing {
            installError = nil
        }
    }

    private func setStatus(_ status: String?) {
        installStatus = status
    }

    private func setError(_ error: String?) {
        installError = error
    }

    private func constrainLocationIfNeeded(current: CGPoint, initial: CGPoint) -> CGPoint {
        let diffX = current.x - initial.x
        let diffY = current.y - initial.y
        let distance = sqrt(diffX * diffX + diffY * diffY)
        
        // If distance is less than 50, return the original point
        if distance < 50 {
            return current
        }
        
        // Determine dominant axis and constrain to that axis only
        if abs(diffX) > abs(diffY) {
            // X-axis dominant, keep only X difference
            return CGPoint(x: current.x, y: initial.y)
        } else {
            // Y-axis dominant, keep only Y difference
            return CGPoint(x: initial.x, y: current.y)
        }
    }

    private func performTouch(_ udid: String, at point: CGPoint, scale: CGFloat, up: Bool) throws {
        // Convert point to integers expected by the protocol
        let x = Int32(point.x / scale)
        let y = Int32(point.y / scale)
        try idbManager.touch(udid: udid, x: x, y: y, up: up)
    }
}

extension CGFloat {
    var float: Float {
        return Float(self)
    }

    var int: Int {
        return Int(self)
    }
}

extension Float {
    var cgFloat: CGFloat {
        return CGFloat(self)
    }

    var int: Int {
        return Int(self)
    }
}

extension CGSize {
    var simd: simd_float2 {
        return simd_float2(x: Float(width), y: Float(height))
    }
}

extension CGPoint {
    var simd: simd_float2 {
        return simd_float2(x: Float(x), y: Float(y))
    }

    func isInside(size: CGSize) -> Bool {
        return x >= 0 && y >= 0 && x <= size.width && y <= size.height
    }

    func isInside(rect: CGRect) -> Bool {
        return x >= rect.minX && y >= rect.minY && x <= rect.maxX && y <= rect.maxY
    }

    func clamped(to size: CGSize, eps: CGFloat = 0) -> CGPoint {
        return clamped(to: CGRect(origin: .zero, size: size), eps: eps)
    }

    func clamped(to rect: CGRect, eps: CGFloat = 0) -> CGPoint {
        return CGPoint(
            x: min(max(rect.minX + eps, x), rect.maxX - eps),
            y: min(max(rect.minY + eps, y), rect.maxY - eps)
        )
    }
}

extension simd_float2 {
    var cgPoint: CGPoint {
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
    var cgSize: CGSize {
        return CGSize(width: CGFloat(x), height: CGFloat(y))
    }
    var length: Float {
        return simd_length(self)
    }

    func mixed(with other: simd_float2, _ coeff: Float) -> simd_float2 {
        return self * (1.0 - coeff) + other * coeff
    }
}
