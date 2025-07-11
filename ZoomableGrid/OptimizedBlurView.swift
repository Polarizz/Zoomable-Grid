import SwiftUI
import Photos

struct OptimizedBlurView<Content: View>: View {
    let content: Content
    let blurRadius: CGFloat
    let opacity: Double
    let isEnabled: Bool
    
    init(blurRadius: CGFloat, opacity: Double, isEnabled: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.blurRadius = blurRadius
        self.opacity = opacity
        self.isEnabled = isEnabled
    }
    
    var body: some View {
        if isEnabled && (blurRadius > 0.1 || opacity < 0.9) {
            content
                .blur(radius: blurRadius)
                .opacity(opacity)
                .animation(.easeInOut(duration: 0.3), value: blurRadius)
                .animation(.easeInOut(duration: 0.3), value: opacity)
        } else if opacity > 0.1 {
            content
        }
    }
}

// Simplified grid item view for better performance
struct OptimizedGridItemView: View {
    let item: GridItemData
    let size: CGFloat
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let image = item.image ?? image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: size, height: size)
                
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard image == nil,
              let asset = item.asset else { return }
        
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        
        let targetSize = CGSize(width: size * UIScreen.main.scale,
                               height: size * UIScreen.main.scale)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            if let img = img {
                DispatchQueue.main.async {
                    self.image = img
                }
            }
        }
    }
}