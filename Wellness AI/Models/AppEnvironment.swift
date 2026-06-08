import SwiftUI
import Combine

class AppEnvironment: ObservableObject {
    @Published var isLowPowerModeEnabled: Bool
    
    private var cancellables = Set<AnyCancellable>()
    
    static let shared = AppEnvironment()
    
    private init() {
        self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .store(in: &cancellables)
    }
}
