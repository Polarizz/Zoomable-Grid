//
//  FullscreenPagingView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI
import Photos

struct FullscreenPagingView: View {
    let photos: [GridItemData]
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    @Namespace private var animationNamespace
    
    @State private var currentPage: Int = 0
    @State private var isDismissing: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 0.0
    @State private var sidePhotosOpacity: Double = 1.0
    @State private var preloadedIndices: Set<Int> = []
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: backgroundOpacity)
                .onTapGesture {
                    isDismissing = true
                    withAnimation(.smooth(duration: 0.35)) {
                        backgroundOpacity = 0
                    }
                }
            
            // TabView for paging
            TabView(selection: $currentPage) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    SingleFullscreenView(
                        itemData: photo,
                        isPresented: $isPresented,
                        sourceFrame: index == selectedIndex ? sourceFrame : .zero,
                        isCurrentPage: index == currentPage,
                        shouldPreload: shouldPreloadImage(at: index),
                        onDragChanged: { offset in
                            dragOffset = offset
                            // Calculate opacity based on drag distance
                            let dragDistance = abs(offset.height)
                            backgroundOpacity = max(0, 1.0 - (dragDistance / 300.0))
                            
                            // Immediately hide side photos when dragging starts
                            if abs(offset.height) > 0 {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    sidePhotosOpacity = 0.0
                                }
                            }
                        },
                        onDragEnded: { shouldDismiss in
                            if shouldDismiss {
                                isDismissing = true
                                withAnimation(.smooth(duration: 0.35)) {
                                    backgroundOpacity = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = .zero
                                    backgroundOpacity = 1.0
                                    sidePhotosOpacity = 1.0
                                }
                            }
                        },
                        isDismissing: isDismissing,
                        onDismissComplete: {
                            isPresented = false
                        }
                    )
                    .tag(index)
                    .opacity(index == currentPage ? 1.0 : sidePhotosOpacity)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .onAppear {
            currentPage = selectedIndex
            withAnimation(.easeInOut(duration: 0.3)) {
                backgroundOpacity = 1.0
            }
            preloadAdjacentImages()
        }
        .onChange(of: currentPage) { _, newValue in
            selectedIndex = newValue
            preloadAdjacentImages()
        }
    }
    
    private func shouldPreloadImage(at index: Int) -> Bool {
        // Preload current image and 2 images on each side
        let distance = abs(index - currentPage)
        return distance <= 2
    }
    
    private func preloadAdjacentImages() {
        // Determine which indices need to be preloaded
        let indicesToPreload = (max(0, currentPage - 2)...min(photos.count - 1, currentPage + 2))
        
        for index in indicesToPreload {
            if !preloadedIndices.contains(index) {
                preloadedIndices.insert(index)
                // Trigger preload by accessing the view
                if let asset = photos[index].asset {
                    preloadImage(from: asset, at: index)
                }
            }
        }
    }
    
    private func preloadImage(from asset: PHAsset, at index: Int) {
        let assetId = asset.localIdentifier
        
        // Skip if already cached
        if ImageCacheManager.shared.image(for: assetId) != nil {
            return
        }
        
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        // Use a more reasonable size - 2x screen size for zoom headroom
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: screenSize.width * 2,
            height: screenSize.height * 2
        )
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if let image = image {
                // Cache the image
                ImageCacheManager.shared.cache(image, for: assetId)
            }
        }
    }
}

struct SingleFullscreenView: View {
    let itemData: GridItemData
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    let isCurrentPage: Bool
    let shouldPreload: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (Bool) -> Void
    let isDismissing: Bool
    let onDismissComplete: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var showContent: Bool = false
    @State private var fullImage: UIImage? = nil
    @State private var imageOpacity: Double = 1.0
    
    private let imageManager = PHImageManager.default()
    
    // Use shared cache manager instead of static cache
    private let cacheManager = ImageCacheManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = fullImage ?? itemData.image {
                    let adjustedFrame = CGRect(
                        x: sourceFrame.origin.x,
                        y: sourceFrame.origin.y - geometry.safeAreaInsets.top,
                        width: sourceFrame.width,
                        height: sourceFrame.height
                    )
                    InteractiveImageView(
                        image: image,
                        geometry: geometry,
                        sourceFrame: adjustedFrame,
                        showContent: $showContent,
                        currentScale: $currentScale,
                        dragOffset: $dragOffset,
                        imageOpacity: $imageOpacity,
                        isCurrentPage: isCurrentPage,
                        isInitialAppearance: sourceFrame != .zero,
                        onDragChanged: onDragChanged,
                        onDragEnded: onDragEnded
                    )
                    .onAppear {
                        if sourceFrame != .zero {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.smooth(duration: 0.35)) {
                                    showContent = true
                                }
                            }
                        } else {
                            showContent = true
                        }
                    }
                    .onChange(of: isDismissing) { _, isDismissing in
                        if isDismissing && isCurrentPage {
                            withAnimation(.smooth(duration: 0.35)) {
                                showContent = false
                                currentScale = 1.0
                                dragOffset = .zero
                            }
                            // Fade out the image after it reaches the root position
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    imageOpacity = 0
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onDismissComplete()
                            }
                        }
                    }
                }
                
                if fullImage == nil && itemData.asset != nil {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .onAppear {
            if shouldPreload, let asset = itemData.asset {
                loadFullImage(from: asset)
            }
        }
    }
    
    private func loadFullImage(from asset: PHAsset) {
        guard fullImage == nil else { return }
        
        let assetId = asset.localIdentifier
        
        // Check cache first
        if let cachedImage = ImageCacheManager.shared.image(for: assetId) {
            DispatchQueue.main.async {
                self.fullImage = cachedImage
            }
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        // Use a more reasonable size - 2x screen size for zoom headroom
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: screenSize.width * 2,
            height: screenSize.height * 2
        )
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if let image = image {
                // Cache the image
                ImageCacheManager.shared.cache(image, for: assetId)
                
                DispatchQueue.main.async {
                    self.fullImage = image
                }
            }
        }
    }
}

struct InteractiveImageView: View {
    let image: UIImage
    let geometry: GeometryProxy
    var sourceFrame: CGRect
    @Binding var showContent: Bool
    @Binding var currentScale: CGFloat
    @Binding var dragOffset: CGSize
    @Binding var imageOpacity: Double
    let isCurrentPage: Bool
    let isInitialAppearance: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (Bool) -> Void
    
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @GestureState private var magnifyBy = CGFloat(1.0)
    
    private let minimumScale: CGFloat = 1.0
    private let maximumScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5
    
    var combinedScale: CGFloat {
        currentScale * magnifyBy
    }
    
    var imageSize: CGSize {
        let imageAspectRatio = image.size.width / image.size.height
        let screenAspectRatio = geometry.size.width / geometry.size.height
        
        if imageAspectRatio > screenAspectRatio {
            let width = geometry.size.width
            let height = width / imageAspectRatio
            return CGSize(width: width, height: height)
        } else {
            let height = geometry.size.height
            let width = height * imageAspectRatio
            return CGSize(width: width, height: height)
        }
    }
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(
                width: showContent ? imageSize.width : sourceFrame.width,
                height: showContent ? imageSize.height : sourceFrame.height
            )
            .cornerRadius(showContent ? 0 : 8)
            .scaleEffect(showContent ? combinedScale * (1.0 - min(abs(dragOffset.height) / 1000.0, 0.3)) : 1.0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.9), value: combinedScale)
            .offset(
                x: showContent ? offset.width + dragOffset.width : 0,
                y: showContent ? offset.height + dragOffset.height : 0
            )
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.9), value: offset)
            .position(
                x: showContent ? geometry.size.width / 2 : sourceFrame.midX,
                y: showContent ? geometry.size.height / 2 : sourceFrame.midY
            )
            .opacity(imageOpacity)
            .animation(isInitialAppearance ? .smooth(duration: 0.35) : nil, value: showContent)
            .animation(.easeOut(duration: 0.15), value: imageOpacity)
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if currentScale > 1 {
                        currentScale = 1.0
                        offset = .zero
                    } else {
                        currentScale = doubleTapScale
                    }
                }
            }
            .gesture(
                MagnificationGesture()
                    .updating($magnifyBy) { currentState, gestureState, _ in
                        gestureState = currentState
                    }
                    .onEnded { value in
                        currentScale = min(max(currentScale * value, minimumScale), maximumScale)
                        if currentScale <= 1.0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                offset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if currentScale <= 1.0 && isCurrentPage {
                            // Only allow vertical drag for dismissal
                            if abs(value.translation.height) > abs(value.translation.width) {
                                dragOffset = value.translation
                                onDragChanged(value.translation)
                            }
                        } else if currentScale > 1.0 {
                            // Allow panning when zoomed
                            offset = CGSize(
                                width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { value in
                        if currentScale <= 1.0 && isCurrentPage {
                            let shouldDismiss = abs(value.translation.height) > 100
                            onDragEnded(shouldDismiss)
                            if !shouldDismiss {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = .zero
                                }
                            }
                        } else if currentScale > 1.0 {
                            // Constrain pan offset
                            constrainOffset()
                        }
                    }
            )
    }
    
    private func constrainOffset() {
        let scaledWidth = imageSize.width * currentScale
        let scaledHeight = imageSize.height * currentScale
        
        let maxOffsetX = max((scaledWidth - geometry.size.width) / 2, 0)
        let maxOffsetY = max((scaledHeight - geometry.size.height) / 2, 0)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset.width = min(max(offset.width, -maxOffsetX), maxOffsetX)
            offset.height = min(max(offset.height, -maxOffsetY), maxOffsetY)
        }
    }
}