import SwiftUI
import MetalKit

struct MetalStressChart: UIViewRepresentable {
    let points: [StressDataPoint]
    let color: Color
    
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isOpaque = false
        mtkView.enableSetNeedsDisplay = true
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updatePoints(points, color: color)
        uiView.setNeedsDisplay()
    }
    
    func makeCoordinator() -> Renderer {
        Renderer(points: points, color: color)
    }
}

class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice?
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?
    
    private var points: [StressDataPoint]
    private var vertexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var color: Color
    
    struct Uniforms {
        var color: simd_float4
        var resolution: simd_float2
        var time: Float
    }
    
    init(points: [StressDataPoint], color: Color) {
        self.points = points
        self.color = color
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        super.init()
        setupPipeline()
        updateBuffers()
    }
    
    func updatePoints(_ points: [StressDataPoint], color: Color) {
        self.points = points
        self.color = color
        updateBuffers()
    }
    
    private func setupPipeline() {
        guard let device = device,
              let library = device.makeDefaultLibrary() else { return }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "chart_vertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "chart_fragment")
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
    
    private func updateBuffers() {
        guard let device = device, !points.isEmpty else { return }
        
        var vertices: [simd_float2] = []
        var lineVertices: [simd_float2] = []
        
        let minTime = points.map { $0.timestamp.timeIntervalSince1970 }.min() ?? 0
        let maxTime = points.map { $0.timestamp.timeIntervalSince1970 }.max() ?? 1
        let timeRange = maxTime - minTime
        
        // Sorting points by time to ensure correct rendering
        let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
        
        for i in 0..<sortedPoints.count {
            let p = sortedPoints[i]
            let x = Float((p.timestamp.timeIntervalSince1970 - minTime) / (timeRange > 0 ? timeRange : 1.0))
            let y = Float(p.stressScore / 100.0)
            
            // Area fill vertices
            vertices.append(simd_float2(x, 0))
            vertices.append(simd_float2(x, y))
            
            // Top line vertices
            lineVertices.append(simd_float2(x, y))
        }
        
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<simd_float2>.stride, options: [])
        
        // We'll reuse uniforms but add a line vertex buffer if we wanted separate drawing
        // For now, let's keep it simple and just use the triangle strip.
        
        let uiColor = UIColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        var uniforms = Uniforms(
            color: simd_float4(Float(red), Float(green), Float(blue), Float(alpha)),
            resolution: simd_float2(0, 0),
            time: Float(Date().timeIntervalSince1970)
        )
        
        uniformBuffer = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<Uniforms>.stride, options: [])
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
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
        renderEncoder?.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        renderEncoder?.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        
        // Draw as triangle strip for a filled area
        let vertexCount = points.count * 2
        renderEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCount)
        
        renderEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
