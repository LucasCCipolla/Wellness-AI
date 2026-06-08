import SwiftUI
import MetalKit
import CoreMotion
import Combine

struct MetalAmbientBackground: UIViewRepresentable {
    let intensity: Double // 0-1 (e.g. stress level normalized)
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isOpaque = false
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 30
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateIntensity(intensity)
    }
    
    func makeCoordinator() -> AmbientRenderer {
        AmbientRenderer(intensity: intensity)
    }
}

class AmbientRenderer: NSObject, MTKViewDelegate {
    var device: MTLDevice?
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    
    private var intensity: Double
    private var startTime: Date
    
    struct AmbientUniforms {
        var color: simd_float4
        var resolution: simd_float2
        var time: Float
        var intensity: Float
        var tilt: simd_float2
    }
    
    init(intensity: Double) {
        self.intensity = intensity
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        self.startTime = Date()
        super.init()
        setupPipeline()
        setupBuffers()
    }
    
    func updateIntensity(_ intensity: Double) {
        self.intensity = intensity
    }
    
    private func setupPipeline() {
        guard let device = device,
              let library = device.makeDefaultLibrary() else { return }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "ambient_vertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "ambient_fragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func setupBuffers() {
        guard let device = device else { return }
        
        // Full screen quad vertices in NDC (-1 to 1)
        let vertices: [simd_float2] = [
            simd_float2(-1, -1),
            simd_float2( 1, -1),
            simd_float2(-1,  1),
            simd_float2( 1,  1)
        ]
        
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<simd_float2>.stride, options: [])
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer,
              let commandQueue = commandQueue else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: descriptor)
        
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        var uniforms = AmbientUniforms(
            color: simd_float4(0, 0, 0, 0),
            resolution: simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: Float(Date().timeIntervalSince(startTime)),
            intensity: Float(intensity),
            tilt: MotionManager.shared.latestTilt
        )
        
        renderEncoder?.setFragmentBytes(&uniforms, length: MemoryLayout<AmbientUniforms>.stride, index: 1)
        
        renderEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
