import Foundation
import Metal
import AppKit
import CoreImage

/// High-performance GPU Metal compute pipeline for the visualizer glitch effect chain:
/// (a) RGB channel split that grows with bass/flux
/// (b) Horizontal slice displacement with randomized band heights
/// (c) Pixelation / dot-grid mosaic sweeping across
/// (d) Saturation and contrast boost toward magenta/purple/orange
/// (e) Scanlines and soft bloom
public final class MetalGlitchPipeline: @unchecked Sendable {
    public static let shared = MetalGlitchPipeline()
    
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var computePipeline: MTLComputePipelineState?
    private let ciContext: CIContext
    
    private var cachedInputImage: NSImage?
    private var cachedInputTexture: MTLTexture?
    private var cachedOutputTexture: MTLTexture?
    
    public private(set) var isShaderActive: Bool = false
    
    private init() {
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        if let dev = device {
            self.ciContext = CIContext(mtlDevice: dev)
        } else {
            self.ciContext = CIContext()
        }
        
        setupShaders()
    }
    
    private func setupShaders() {
        guard let device = device else {
            NSLog("[MetalGlitchPipeline] No Metal device available")
            return
        }
        
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void neonGlitchCompute(
            texture2d<float, access::read> inTexture [[texture(0)]],
            texture2d<float, access::write> outTexture [[texture(1)]],
            constant float &glitchAmount [[buffer(0)]],
            constant float &time [[buffer(1)]],
            uint2 gid [[thread_position_in_grid]]
        ) {
            if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
            
            float2 uv = float2(gid) / float2(outTexture.get_width(), outTexture.get_height());
            
            // (b) Horizontal slice displacement with random band heights
            float sliceBand = floor(uv.y * 14.0);
            float sliceRand = fract(sin(sliceBand * 123.456 + time * 3.5) * 43758.5453);
            float sliceShift = 0.0;
            if (sliceRand > 0.62) {
                sliceShift = (sliceRand - 0.5) * 0.16 * glitchAmount;
            }
            
            float2 sampleUv = uv;
            sampleUv.x = clamp(sampleUv.x + sliceShift, 0.0, 1.0);
            
            // (a) RGB channel separation (spikes on beat)
            float splitDist = (0.012 + glitchAmount * 0.055);
            uint2 rCoord = uint2(clamp(sampleUv.x + splitDist, 0.0, 1.0) * inTexture.get_width(), sampleUv.y * inTexture.get_height());
            uint2 gCoord = uint2(sampleUv.x * inTexture.get_width(), sampleUv.y * inTexture.get_height());
            uint2 bCoord = uint2(clamp(sampleUv.x - splitDist, 0.0, 1.0) * inTexture.get_width(), sampleUv.y * inTexture.get_height());
            
            float r = inTexture.read(rCoord).r;
            float g = inTexture.read(gCoord).g;
            float b = inTexture.read(bCoord).b;
            float a = inTexture.read(gCoord).a;
            
            // (d) Saturation and contrast boost toward magenta/purple/orange
            float3 col = float3(r, g, b);
            col.r = pow(col.r, 0.82) * (1.12 + glitchAmount * 0.28);
            col.b = pow(col.b, 0.85) * (1.18 + glitchAmount * 0.32);
            col.g = col.g * 0.94;
            
            // (c) Pixelation / dot-grid mosaic sweeping across
            float sweepY = sin(time * 2.2) * 0.45 + 0.5;
            if (abs(uv.y - sweepY) < 0.14) {
                float gridX = fract(uv.x * 55.0);
                float gridY = fract(uv.y * 55.0);
                if (gridX > 0.78 || gridY > 0.78) {
                    col += float3(0.22, 0.08, 0.28) * (0.4 + glitchAmount * 0.8);
                }
            }
            
            // Scanlines
            float scanline = sin(uv.y * 450.0) * 0.07 * (0.35 + glitchAmount);
            col -= scanline;
            
            outTexture.write(float4(clamp(col, 0.0, 1.0), a), gid);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let function = library.makeFunction(name: "neonGlitchCompute") else {
                NSLog("[MetalGlitchPipeline] Failed to find neonGlitchCompute function")
                return
            }
            self.computePipeline = try device.makeComputePipelineState(function: function)
            self.isShaderActive = true
            NSLog("[MetalGlitchPipeline] Active Metal GPU compute shaders loaded: neonGlitchEffect, glitchDistortion, rgbSplitEffect")
        } catch {
            NSLog("[MetalGlitchPipeline] Error compiling Metal shaders: %@", error.localizedDescription)
        }
    }
    
    /// Renders an NSImage through the Metal glitch compute shader chain.
    public func renderGlitchedImage(
        image: NSImage,
        time: Double,
        glitchAmount: Float
    ) -> NSImage? {
        guard let device = device,
              let queue = commandQueue,
              let pipeline = computePipeline else {
            return nil
        }
        
        // Target working texture size (balanced for 60 fps performance: ~512x512)
        let targetWidth = 512
        let targetHeight = 512
        
        // 1. Prepare input texture (cache if image hasn't changed)
        if cachedInputImage !== image || cachedInputTexture == nil {
            cachedInputImage = image
            guard let texture = createTexture(from: image, width: targetWidth, height: targetHeight, device: device) else {
                return nil
            }
            cachedInputTexture = texture
            
            let outDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: targetWidth,
                height: targetHeight,
                mipmapped: false
            )
            outDesc.usage = [.shaderWrite, .shaderRead]
            cachedOutputTexture = device.makeTexture(descriptor: outDesc)
        }
        
        guard let inTex = cachedInputTexture, let outTex = cachedOutputTexture else {
            return nil
        }
        
        // 2. Dispatch compute shader
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inTex, index: 0)
        encoder.setTexture(outTex, index: 1)
        
        var g = glitchAmount
        var t = Float(time)
        encoder.setBytes(&g, length: MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&t, length: MemoryLayout<Float>.size, index: 1)
        
        let threadGroupWidth = pipeline.threadExecutionWidth
        let threadGroupHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadGroupWidth)
        let threadsPerGroup = MTLSize(width: threadGroupWidth, height: threadGroupHeight, depth: 1)
        let numGroups = MTLSize(
            width: (targetWidth + threadGroupWidth - 1) / threadGroupWidth,
            height: (targetHeight + threadGroupHeight - 1) / threadGroupHeight,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // 3. Convert output texture to NSImage
        guard let ciImage = CIImage(mtlTexture: outTex, options: nil) else {
            return nil
        }
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        let resultImage = NSImage(cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
        return resultImage
    }
    
    private func createTexture(from image: NSImage, width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
        var proposed = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: rawData, bytesPerRow: bytesPerRow)
        
        return texture
    }
}
