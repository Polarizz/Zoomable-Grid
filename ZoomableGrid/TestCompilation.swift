// Test file to verify all new components compile correctly
import SwiftUI
import Photos

// This file tests that all the new optimized components compile correctly
struct TestCompilationView: View {
    @State private var photos: [GridItemData] = []
    @State private var selectedIndex = 0
    @State private var isPresented = false
    
    var body: some View {
        VStack {
            // Test OptimizedFullscreenPagingView
            OptimizedFullscreenPagingView(
                photos: photos,
                selectedIndex: $selectedIndex,
                isPresented: $isPresented,
                initialFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                frameForIndex: { index in
                    return CGRect(x: 0, y: 0, width: 100, height: 100)
                }
            )
            
            // Test OptimizedBlurView
            OptimizedBlurView(blurRadius: 10, opacity: 0.5, isEnabled: true) {
                Text("Test")
            }
            
            // Test OptimizedGridItemView
            if let firstPhoto = photos.first {
                OptimizedGridItemView(item: firstPhoto, size: 100)
            }
            
            // Test PerformanceMonitor
            Text("Test")
                .monitorPerformance("test")
        }
    }
}