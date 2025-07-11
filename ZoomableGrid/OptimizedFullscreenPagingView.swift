import SwiftUI
import Photos

struct OptimizedFullscreenPagingView: View {
    let photos: [GridItemData]
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool
    let initialFrame: CGRect
    let frameForIndex: ((Int) -> CGRect?)?
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var preloadedImages: [Int: UIImage] = [:]
    @State private var dismissProgress: CGFloat = 0
    @State private var cachedFrames: [Int: CGRect] = [:]
    
    // Performance optimizations
    private let preloadRange = 2
    private let dismissThreshold: CGFloat = 100
    private let maxDismissScale: CGFloat = 0.7
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(1.0 - dismissProgress)
                    .ignoresSafeArea()
                
                TabView(selection: $selectedIndex) {
                    ForEach(photos.indices, id: \.self) { index in
                        OptimizedSingleFullscreenView(
                            index: index,
                            itemData: photos[index],
                            image: preloadedImages[index],
                            geometry: geometry,
                            sourceFrame: getCachedFrame(for: index) ?? initialFrame,
                            isCurrentPage: index == selectedIndex,
                            isInitialPage: index == photos.firstIndex(where: { $0.id == photos[selectedIndex].id }),
                            isDismissing: isDragging,
                            dismissProgress: dismissProgress,
                            onDragChanged: { translation in
                                handleDragChanged(translation)
                            },
                            onDragEnded: { shouldDismiss in
                                handleDragEnded(shouldDismiss)
                            },
                            getCurrentFrame: {
                                getCachedFrame(for: index) ?? .zero
                            },
                            onDismissComplete: {
                                isPresented = false
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .disabled(isDragging)
            }
        }
        .onAppear {
            preloadImages(around: selectedIndex)
            cacheFrames(around: selectedIndex)
        }
        .onChange(of: selectedIndex) { _, newIndex in
            preloadImages(around: newIndex)
            cacheFrames(around: newIndex)
        }
    }
    
    private func handleDragChanged(_ translation: CGSize) {
        if abs(translation.height) > abs(translation.width) {
            dragOffset = translation
            dismissProgress = min(abs(translation.height) / 300.0, 1.0)
        }
    }
    
    private func handleDragEnded(_ shouldDismiss: Bool) {
        if shouldDismiss {
            withAnimation(.easeOut(duration: 0.25)) {
                isDragging = true
                dismissProgress = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isPresented = false
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = .zero
                dismissProgress = 0
            }
        }
    }
    
    private func getCachedFrame(for index: Int) -> CGRect? {
        if let cached = cachedFrames[index] {
            return cached
        }
        
        if let frameFunction = frameForIndex, let frame = frameFunction(index) {
            cachedFrames[index] = frame
            return frame
        }
        
        return nil
    }
    
    private func cacheFrames(around index: Int) {
        let startIndex = max(0, index - preloadRange)
        let endIndex = min(photos.count - 1, index + preloadRange)
        
        for i in startIndex...endIndex {
            if cachedFrames[i] == nil {
                if let frameFunction = frameForIndex {
                    cachedFrames[i] = frameFunction(i)
                }
            }
        }
        
        // Clean up distant frames
        cachedFrames = cachedFrames.filter { key, _ in
            abs(key - index) <= preloadRange * 2
        }
    }
    
    private func preloadImages(around index: Int) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )
        
        let startIndex = max(0, index - preloadRange)
        let endIndex = min(photos.count - 1, index + preloadRange)
        
        for i in startIndex...endIndex {
            if preloadedImages[i] == nil, let asset = photos[i].asset {
                imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, _ in
                    if let image = image {
                        DispatchQueue.main.async {
                            self.preloadedImages[i] = image
                        }
                    }
                }
            }
        }
        
        // Clean up distant images
        preloadedImages = preloadedImages.filter { key, _ in
            abs(key - index) <= preloadRange * 2
        }
    }
}

struct OptimizedSingleFullscreenView: View {
    let index: Int
    let itemData: GridItemData
    var image: UIImage?
    let geometry: GeometryProxy
    let sourceFrame: CGRect
    let isCurrentPage: Bool
    let isInitialPage: Bool
    let isDismissing: Bool
    let dismissProgress: CGFloat
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (Bool) -> Void
    let getCurrentFrame: () -> CGRect
    let onDismissComplete: () -> Void
    
    @State private var fullImage: UIImage?
    @State private var showContent = false
    @State private var currentScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    
    var displayImage: UIImage? {
        fullImage ?? image ?? itemData.image
    }
    
    var imageSize: CGSize {
        guard let img = displayImage else { return .zero }
        let imageAspectRatio = img.size.width / img.size.height
        let screenAspectRatio = geometry.size.width / geometry.size.height
        
        if imageAspectRatio > screenAspectRatio {
            let width = geometry.size.width
            let height = width / imageAspectRatio
            return CGSize(width: width, height: height)
        } else {
            let height = geometry.size.height
            let width = height * imageAspectRatio
            return CGSize(width: width, height: width)
        }
    }
    
    var body: some View {
        ZStack {
            if let displayImage = displayImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: showContent && !isDismissing ? imageSize.width : sourceFrame.width,
                        height: showContent && !isDismissing ? imageSize.height : sourceFrame.height
                    )
                    .cornerRadius(isDismissing ? 8 : 0)
                    .scaleEffect(1.0 - dismissProgress * 0.3)
                    .offset(y: dragOffset.height)
                    .position(
                        x: showContent && !isDismissing ? geometry.size.width / 2 : sourceFrame.midX,
                        y: showContent && !isDismissing ? geometry.size.height / 2 : sourceFrame.midY + dragOffset.height
                    )
                    .opacity(1.0 - dismissProgress * 0.3)
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: showContent)
                    .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: isDismissing)
                    .onAppear {
                        if isInitialPage {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                showContent = true
                            }
                        } else {
                            showContent = true
                        }
                    }
                    .onChange(of: isDismissing) { _, dismissing in
                        if dismissing && isCurrentPage {
                            onDismissComplete()
                        }
                    }
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { value in
                                if isCurrentPage && currentScale <= 1.0 {
                                    dragOffset = value.translation
                                    onDragChanged(value.translation)
                                }
                            }
                            .onEnded { value in
                                if isCurrentPage && currentScale <= 1.0 {
                                    let shouldDismiss = abs(value.translation.height) > 100
                                    onDragEnded(shouldDismiss)
                                    if !shouldDismiss {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            dragOffset = .zero
                                        }
                                    }
                                }
                            }
                    )
            }
            
            if fullImage == nil && itemData.asset != nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .opacity(1.0 - dismissProgress)
            }
        }
        .onAppear {
            loadFullImage()
        }
    }
    
    private func loadFullImage() {
        guard fullImage == nil,
              let asset = itemData.asset else { return }
        
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(
            width: asset.pixelWidth,
            height: asset.pixelHeight
        )
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.fullImage = image
                }
            }
        }
    }
}