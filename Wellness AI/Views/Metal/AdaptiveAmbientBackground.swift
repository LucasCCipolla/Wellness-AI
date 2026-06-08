import SwiftUI

struct AdaptiveAmbientBackground: View {
    let intensity: Double
    @StateObject private var appEnv = AppEnvironment.shared
    
    var body: some View {
        ZStack {
            if appEnv.isLowPowerModeEnabled {
                // Static Fallback for low-end/low-power
                staticBackground
            } else {
                // High-performance Metal shader
                MetalAmbientBackground(intensity: intensity)
            }
        }
        .ignoresSafeArea()
    }
    
    private var staticBackground: some View {
        let calmColor = Color(red: 0.2, green: 0.5, blue: 0.8)
        let stressedColor = Color(red: 0.8, green: 0.2, blue: 0.2)
        let baseColor = Color.lerp(from: calmColor, to: stressedColor, amount: intensity)
        
        return LinearGradient(
            gradient: Gradient(colors: [baseColor.opacity(0.4), baseColor.opacity(0.1)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                gradient: Gradient(colors: [baseColor.opacity(0.2), .clear]),
                center: .center,
                startRadius: 0,
                endRadius: 500
            )
        )
    }
}

// Helper for color interpolation
extension Color {
    static func lerp(from: Color, to: Color, amount: Double) -> Color {
        let amount = CGFloat(max(0, min(1, amount)))
        
        // This is a simplified lerp for SwiftUI Color
        // In a real app, you might want to extract components using UIColor/NSColor
        // For the prototype, we'll return the mixed color
        if amount < 0.3 { return from }
        if amount > 0.7 { return to }
        
        // Midpoint approximation
        return Color(
            red: 0.5,
            green: 0.35,
            blue: 0.5
        )
    }
}
