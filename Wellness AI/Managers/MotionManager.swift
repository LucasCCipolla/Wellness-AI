import Foundation
import CoreMotion
import simd

class MotionManager {
    static let shared = MotionManager()
    
    private let motionManager = CMMotionManager()
    
    /// Synchronously returns the latest tilt data.
    /// Polling is more efficient for high-frequency render loops (Metal).
    var latestTilt: simd_float2 {
        guard let attitude = motionManager.deviceMotion?.attitude else {
            return simd_float2(0, 0)
        }
        return simd_float2(Float(attitude.roll), Float(attitude.pitch))
    }
    
    private init() {
        setupMotion()
    }
    
    private func setupMotion() {
        if motionManager.isDeviceMotionAvailable {
            // Start updates without a handler for efficient polling
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates()
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    deinit {
        stopUpdates()
    }
}
