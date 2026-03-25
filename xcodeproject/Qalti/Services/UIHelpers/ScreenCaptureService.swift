import Foundation
import AVFoundation
import CoreMediaIO
import Metal
import IOSurface
import CoreVideo
import AppKit

enum ScreenCaptureServiceError: Error, LocalizedError {
    case notAuthorized
    case deviceNotFound(name: String)
    case enableScreenCaptureFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Camera access not authorized"
        case let .deviceNotFound(name):
            return "Capture device not found: \(name)"
        case let .enableScreenCaptureFailed(status):
            return "Failed to enable screen capture devices (status \(status))"
        }
    }
}

final class ScreenCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let deviceName: String
    private let onSurfaceReady: (IOSurface) -> Void

    // Capture
    private let session = AVCaptureSession()
    private var input: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "ScreenCaptureService.CaptureQueue")

    // Metal
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    
    // Captured/source pixel format tracking
    private var currentCVPixelFormat: OSType? = nil
    private var currentMTLPixelFormat: MTLPixelFormat? = nil
    private var currentBytesPerElement: Int = 4

    // Public single IOSurface + destination texture
    private(set) var publicSurface: IOSurface?
    private var publicTexture: MTLTexture?

    private var deviceObserver: NSObjectProtocol?

    init(deviceName: String, onSurfaceReady: @escaping (IOSurface) -> Void) {
        self.deviceName = deviceName
        self.onSurfaceReady = onSurfaceReady
        guard let dev = MTLCreateSystemDefaultDevice(), let cq = dev.makeCommandQueue() else {
            fatalError("Metal not available")
        }
        self.device = dev
        self.commandQueue = cq
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &textureCache)
    }

    // MARK: Public API
    func start() throws {
        // Ensure Camera permission (macOS requires NSCameraUsageDescription)
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let sem = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { _ in sem.signal() }
            sem.wait()
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw ScreenCaptureServiceError.notAuthorized
        }

        // Optional: allow CMIO screen capture devices (not strictly required for USB camera)
        try? Self.enableScreenCaptureDevices()
        try? Self.enableWirelessScreenCaptureDevices()

        findiOSCaptureDevice(named: deviceName, waitTimeout: 5) { [weak self] captureDevice in
            guard let self else { return }
            guard let captureDevice else { return }

            guard let deviceInput = try? AVCaptureDeviceInput(device: captureDevice) else { return }
            input = deviceInput

            session.beginConfiguration()
            if session.canAddInput(deviceInput) { session.addInput(deviceInput) }
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            videoOutput.connections.forEach { $0.isEnabled = true }

            session.commitConfiguration()

            session.startRunning()
        }
    }

    func stop() {
        session.stopRunning()
        if let input { session.removeInput(input) }
        session.removeOutput(videoOutput)
        input = nil
        publicTexture = nil
        publicSurface = nil
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Determine the CV and Metal pixel formats
        let cvFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let map = Self.mapPixelFormats(cvFormat: cvFormat)
        currentCVPixelFormat = cvFormat
        currentMTLPixelFormat = map.mtl
        currentBytesPerElement = map.bytesPerElement

        ensurePublicSurface(
            width: width,
            height: height,
            cvPixelFormat: cvFormat,
            mtlPixelFormat: map.mtl,
            bytesPerElement: map.bytesPerElement,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        blitToPublicSurface(from: pixelBuffer)
    }

    // MARK: - Helpers
    private func ensurePublicSurface(width: Int, height: Int, cvPixelFormat: OSType, mtlPixelFormat: MTLPixelFormat, bytesPerElement: Int, bytesPerRow: Int) {
        if let surface = publicSurface,
           IOSurfaceGetWidth(surface) == width,
           IOSurfaceGetHeight(surface) == height,
           IOSurfaceGetPixelFormat(surface) == cvPixelFormat,
           IOSurfaceGetBytesPerRow(surface) == bytesPerRow
        {
            return
        }

        let rowBytes = bytesPerRow
        let props: [CFString: Any] = [
            kIOSurfaceWidth: width,
            kIOSurfaceHeight: height,
            kIOSurfaceBytesPerElement: bytesPerElement,
            kIOSurfaceBytesPerRow: rowBytes,
            kIOSurfaceAllocSize: rowBytes * height,
            kIOSurfacePixelFormat: NSNumber(value: cvPixelFormat)
        ]
        guard let surface = IOSurfaceCreate(props as CFDictionary) else { return }
        publicSurface = surface

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mtlPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        publicTexture = device.makeTexture(descriptor: desc, iosurface: surface, plane: 0)

        if let surface = publicSurface {
            DispatchQueue.main.async { [weak self] in
                self?.onSurfaceReady(surface)
            }
        }
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let cvFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let map = Self.mapPixelFormats(cvFormat: cvFormat)
        let pixelFormat = map.mtl

        if let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            return device.makeTexture(descriptor: desc, iosurface: surfaceRef, plane: 0)
        }

        guard let cache = textureCache else { return nil }
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            pixelFormat,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0,
            &cvTex
        )
        guard status == kCVReturnSuccess, let cvTex, let metalTex = CVMetalTextureGetTexture(cvTex) else {
            return nil
        }
        return metalTex
    }

    private func blitToPublicSurface(from pixelBuffer: CVPixelBuffer) {
        guard let dst = publicTexture, let src = makeTexture(from: pixelBuffer) else { return }
        guard let cmdBuf = commandQueue.makeCommandBuffer(), let blit = cmdBuf.makeBlitCommandEncoder() else { return }

        let w = min(src.width, dst.width)
        let h = min(src.height, dst.height)
        let size = MTLSize(width: w, height: h, depth: 1)
        blit.copy(from: src, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0), sourceSize: size, to: dst, destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cmdBuf.commit()
    }

    // MARK: - Device discovery
    static func enableScreenCaptureDevices() throws {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            // Do not fix this warning, it's breaking the setup of screen capture devices
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout.size(ofValue: allow)),
            &allow
        )
        if status != 0 { throw ScreenCaptureServiceError.enableScreenCaptureFailed(status: status) }
    }

    static func enableWirelessScreenCaptureDevices() throws {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            // Do not fix this warning, it's breaking the setup of screen capture devices
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout.size(ofValue: allow)),
            &allow
        )
        if status != 0 { throw ScreenCaptureServiceError.enableScreenCaptureFailed(status: status) }
    }

    static func listDevices() -> [AVCaptureDevice] {
        let checkupSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        )
        return checkupSession.devices
    }

    // MARK: - Pixel format mapping
    private static func mapPixelFormats(cvFormat: OSType) -> (mtl: MTLPixelFormat, bytesPerElement: Int) {
        switch cvFormat {
        case kCVPixelFormatType_422YpCbCr8: // '2vuy' (UYVY)
            return (.bgrg422, 2)
        case kCVPixelFormatType_422YpCbCr8_yuvs: // 'yuvs' (YUY2)
            return (.gbgr422, 2)
        case kCVPixelFormatType_32RGBA:
            return (.rgba8Unorm, 4)
        case kCVPixelFormatType_32BGRA:
            fallthrough
        default:
            return (.bgra8Unorm, 4)
        }
    }

    private func findiOSCaptureDevice(named name: String, waitTimeout: TimeInterval, completion: @escaping (AVCaptureDevice?) -> Void) {
        // Warm up discovery so that the system starts emitting connection notifications
        if let existing = Self.listDevices().first(where: { $0.localizedName == name }) {
            completion(existing)
            return
        }

        deviceObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let device = notification.object as? AVCaptureDevice else { return }
            guard device.localizedName == name else { return }
            guard self?.input == nil else { return }

            // Discovery needs to run again after the notification before the device becomes usable.
            let refreshSession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .muxed,
                position: .unspecified
            )
            let match = refreshSession.devices.first(where: { $0.localizedName == name })
            completion(match)
            if match != nil, let deviceObserver = self?.deviceObserver {
                NotificationCenter.default.removeObserver(deviceObserver)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard self?.input == nil else { return }
            if let existing = Self.listDevices().first(where: { $0.localizedName == name }) {
                completion(existing)
            }
        }
    }

    // Opens System Settings → Privacy & Security → Camera
    static func openCameraPrivacyPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
 
