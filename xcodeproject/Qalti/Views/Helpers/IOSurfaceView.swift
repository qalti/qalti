import AppKit
import MetalKit
import IOSurface
import SwiftUI
import simd
import CoreVideo

/// A MTKView subclass that shows an IOSurface with aspect-fit scaling.
final class IOSurfaceMetalView: MTKView, MTKViewDelegate {

    // MARK: - GPU resources
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState!
    private var ioSurface: IOSurface?
    private var texture: MTLTexture?
    private var yuvMode: UInt32 = 0 // 0=RGBA/BGRA, 1=YUV422 packed
    private var videoRange: UInt32 = 1 // 1=video-range (16..235/240), 0=full-range

    // MARK: - Init
    init() {
        let dev = MTLCreateSystemDefaultDevice()!
        commandQueue = dev.makeCommandQueue()!
        super.init(frame: .zero, device: dev)

        // Render to sRGB so we can output linear color from the shader
        colorPixelFormat = .bgra8Unorm_srgb
        framebufferOnly = false
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60
        delegate = self
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)

        makePipeline(device: dev)
    }

    required init(coder: NSCoder) { fatalError() }

    // MARK: - Public API
    func update(surface: IOSurface?) {
        ioSurface = surface
        if let ioSurface {
            texture = makeTexture(from: ioSurface)
        } else {
            texture = nil
        }
        draw()
    }

    // MARK: - MTKViewDelegate
    /// Required but empty – nothing to rebuild on resize in this sample.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let src      = texture,
              let cmdBuf   = commandQueue.makeCommandBuffer(),
              let encoder  = cmdBuf.makeRenderCommandEncoder(
                    descriptor: currentRenderPassDescriptor!) else { return }

        // — aspect-fit scale factors —
        let viewW  = Float(drawableSize.width)
        let viewH  = Float(drawableSize.height)
        let texW   = Float(src.width)
        let texH   = Float(src.height)

        let scale  = min(viewW/texW, viewH/texH)
        let scaled = simd_float2(texW * scale / viewW,
                                 texH * scale / viewH)      // NDC units (-1…1)

        var uniforms = AspectUniform(scale: scaled, mode: yuvMode, videoRange: videoRange)

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms,
                               length: MemoryLayout<AspectUniform>.stride,
                               index: 1)
        encoder.setFragmentBytes(&uniforms,
                                  length: MemoryLayout<AspectUniform>.stride,
                                  index: 1)
        encoder.setFragmentTexture(src, index: 0)

        // single full-screen triangle (no vertex buffer needed)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Helpers
    private func makePipeline(device: MTLDevice) {
        let libSrc = """
        #include <metal_stdlib>
        using namespace metal;

        struct AspectUniform { float2 scale; uint mode; uint videoRange; };

        struct VOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VOut vert(uint vid [[vertex_id]],
                         constant AspectUniform &u [[buffer(1)]])
        {
            float2 pos = float2((vid == 1) ? 3.0 : -1.0,
                                (vid == 2) ? 3.0 : -1.0);

            // scale to aspect-fit quad inside NDC
            pos *= u.scale;

            VOut o;
            o.position = float4(pos, 0, 1);
            o.uv       = float2((vid == 1) ? 2.0 : 0.0,
                                (vid == 2) ? 2.0 : 0.0);
            return o;
        }

        // sRGB inverse transfer function (IEC 61966-2-1)
        inline half srgb_to_linear(half c)
        {
            return (c <= 0.04045h) ? (c / 12.92h)
                                   : pow((c + 0.055h) / 1.055h, 2.8h);
        }

        fragment float4 frag(VOut in [[stage_in]],
                             texture2d<half> tex [[texture(0)]],
                             constant AspectUniform &u [[buffer(1)]])
        {
            constexpr sampler s_linear(address::clamp_to_edge, filter::linear);
            constexpr sampler s_nearest(address::clamp_to_edge, filter::nearest);
            float2 uv = float2(in.uv.x, 1.0 - in.uv.y);

            if (u.mode == 0u) {
                // RGBA/BGRA sampled as sRGB textures to get linear in-shader
                return float4(tex.sample(s_linear, uv));
            }

            // Y'CbCr 4:2:2 packed formats (Metal layout: Cr, Y', Cb, 1)
            // Y' uses IEC sRGB transfer function; Y'CbCr matrix is ITU-R BT.709.
            half4 v = tex.sample(s_nearest, uv);
            half Yp = v.g;           // nominal Y'
            half Cb = v.b - 0.5h;    // center chroma
            half Cr = v.r - 0.5h;

            // Range scaling for video-range 8-bit signals
            if (u.videoRange == 1u) {
                // Scale Y' from [16,235] to [0,1]
                const half inv219 = half(255.0/219.0);
                Yp = clamp((Yp - half(16.0/255.0)) * inv219, 0.0h, 1.0h);
                // Scale Cb/Cr from [16,240] centered at 0.5 → [-0.5,0.5] with gain
                const half inv224 = half(255.0/224.0);
                Cb *= inv224;
                Cr *= inv224;
            }

            // BT.709 (full-range) Y'CbCr -> R'G'B' conversion
            half Rp = clamp(Yp + 1.5748h * Cr, 0.0h, 1.0h);
            half Gp = clamp(Yp - 0.187324h * Cb - 0.468124h * Cr, 0.0h, 1.0h);
            half Bp = clamp(Yp + 1.8556h * Cb, 0.0h, 1.0h);

            // Convert R'G'B' (sRGB gamma) to linear for sRGB render target
            half R = srgb_to_linear(Rp);
            half G = srgb_to_linear(Gp);
            half B = srgb_to_linear(Bp);

            return float4(R, G, B, 1.0);
        }
        """;

        let lib    = try! device.makeLibrary(source: libSrc, options: nil)
        let desc   = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = lib.makeFunction(name: "vert")
        desc.fragmentFunction = lib.makeFunction(name: "frag")
        desc.colorAttachments[0].pixelFormat = colorPixelFormat

        pipeline = try! device.makeRenderPipelineState(descriptor: desc)
    }

    private func makeTexture(from s: IOSurface) -> MTLTexture? {
        guard let dev = device else { return nil }
        let width = IOSurfaceGetWidth(s)
        let height = IOSurfaceGetHeight(s)
        let cvFormat = IOSurfaceGetPixelFormat(s)

        let (mtlFormat, mode): (MTLPixelFormat, UInt32)
        switch cvFormat {
        case kCVPixelFormatType_422YpCbCr8: // '2vuy' (UYVY)
            (mtlFormat, mode) = (.bgrg422, 1)
        case kCVPixelFormatType_422YpCbCr8_yuvs: // 'yuvs' (YUY2)
            (mtlFormat, mode) = (.gbgr422, 1)
        case kCVPixelFormatType_32RGBA:
            (mtlFormat, mode) = (.bgra8Unorm_srgb, 0)
        case kCVPixelFormatType_32BGRA:
            fallthrough
        default:
            (mtlFormat, mode) = (.bgra8Unorm_srgb, 0)
        }
        yuvMode = mode

        // Detect range using IOSurface component range metadata (if present)
        // Default to video-range for YUV if unknown.
        if mode == 1 {
            let rangeY = IOSurfaceGetRangeOfComponentOfPlane(s, 0, 0)
            switch rangeY {
            case .fullRange, .unknown, .wideRange:
                videoRange = 0
            case .videoRange:
                videoRange = 1
            @unknown default:
                videoRange = 0
            }
        } else {
            videoRange = 0
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mtlFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        return dev.makeTexture(descriptor: desc, iosurface: s, plane: 0)
    }
}

// MARK: - Uniforms
struct AspectUniform { var scale: SIMD2<Float>; var mode: UInt32; var videoRange: UInt32 }

/// SwiftUI wrapper for IOSurfaceNSView
struct IOSurfaceView: NSViewRepresentable {
    let surface: IOSurface?
    
    func makeNSView(context: Context) -> IOSurfaceMetalView {
        let view = IOSurfaceMetalView()
        view.update(surface: surface)
        return view
    }
    
    func updateNSView(_ nsView: IOSurfaceMetalView, context: Context) {
        nsView.update(surface: surface)
    }
} 
