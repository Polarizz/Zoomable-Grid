import SwiftUI
import os.log

class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    private let logger = Logger(subsystem: "com.zoomablegrid", category: "Performance")
    
    @Published var dismissAnimationTime: TimeInterval = 0
    @Published var expandAnimationTime: TimeInterval = 0
    @Published var frameCalculationTime: TimeInterval = 0
    
    private var startTimes: [String: Date] = [:]
    
    func startMeasuring(_ operation: String) {
        startTimes[operation] = Date()
    }
    
    func endMeasuring(_ operation: String) {
        guard let startTime = startTimes[operation] else { return }
        let duration = Date().timeIntervalSince(startTime)
        
        DispatchQueue.main.async {
            switch operation {
            case "dismiss":
                self.dismissAnimationTime = duration
                self.logger.info("Dismiss animation took: \(duration * 1000, format: .fixed(precision: 2))ms")
            case "expand":
                self.expandAnimationTime = duration
                self.logger.info("Expand animation took: \(duration * 1000, format: .fixed(precision: 2))ms")
            case "frameCalculation":
                self.frameCalculationTime = duration
                self.logger.info("Frame calculation took: \(duration * 1000, format: .fixed(precision: 2))ms")
            default:
                self.logger.info("\(operation) took: \(duration * 1000, format: .fixed(precision: 2))ms")
            }
        }
        
        startTimes.removeValue(forKey: operation)
    }
    
    func logMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsageMB = Double(info.resident_size) / 1024.0 / 1024.0
            logger.info("Memory usage: \(memoryUsageMB, format: .fixed(precision: 2)) MB")
        }
    }
}

// Performance monitoring view modifier
struct PerformanceMonitoringModifier: ViewModifier {
    let operation: String
    @StateObject private var monitor = PerformanceMonitor.shared
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor.startMeasuring(operation)
            }
            .onDisappear {
                monitor.endMeasuring(operation)
            }
    }
}

extension View {
    func monitorPerformance(_ operation: String) -> some View {
        modifier(PerformanceMonitoringModifier(operation: operation))
    }
}