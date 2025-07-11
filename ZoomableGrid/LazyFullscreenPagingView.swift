//
//  LazyFullscreenPagingView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI
import Photos

struct LazyFullscreenPagingView: View {
    let photos: [GridItemData]
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    
    @State private var currentPage: Int = 0
    @State private var isDismissing: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 0.0
    @State private var sidePhotosOpacity: Double = 1.0
    
    // Gesture states for better performance
    @GestureState private var isDragging: Bool = false
    @GestureState private var dragTranslation: CGSize = .zero
    
    // Track loaded views to avoid recreating them
    @State private var loadedViews: [Int: AnyView] = [:]
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: backgroundOpacity)
                .onTapGesture {
                    dismissView()
                }
            
            // Custom pager that only loads visible views
            GeometryReader { geometry in
                LazyHStack(spacing: 0) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        // Only create views for visible and adjacent pages
                        if shouldLoadView(at: index) {
                            LazyFullscreenImageView(
                                itemData: photo,
                                isPresented: $isPresented,
                                sourceFrame: index == selectedIndex ? sourceFrame : .zero,
                                isCurrentPage: index == currentPage,
                                isDismissing: isDismissing,
                                onDismissComplete: {
                                    isPresented = false
                                }
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .opacity(index == currentPage ? 1.0 : sidePhotosOpacity)
                        } else {
                            // Placeholder for non-loaded views
                            Color.clear
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                }
                .offset(x: -CGFloat(currentPage) * geometry.size.width)
                .offset(x: dragTranslation.width)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: currentPage)
                .gesture(
                    DragGesture()
                        .updating($isDragging) { _, state, _ in
                            state = true
                        }
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onChanged { value in
                            // Handle drag for dismissal feedback
                            dragOffset = value.translation
                            let dragDistance = max(abs(value.translation.height), abs(value.translation.width))
                            backgroundOpacity = max(0, 1.0 - (dragDistance / 300.0))
                            
                            if dragDistance > 10 {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    sidePhotosOpacity = 0.0
                                }
                            }
                        }
                        .onEnded { value in
                            let horizontalThreshold = geometry.size.width * 0.25
                            let verticalThreshold: CGFloat = 100
                            
                            // Check for dismissal (both vertical and horizontal)
                            if abs(value.translation.height) > verticalThreshold || abs(value.translation.width) > verticalThreshold {
                                // If at edges of collection and swiping outward, dismiss
                                if (currentPage == 0 && value.translation.width > verticalThreshold) ||
                                   (currentPage == photos.count - 1 && value.translation.width < -verticalThreshold) ||
                                   abs(value.translation.height) > verticalThreshold {
                                    dismissView()
                                    return
                                }
                            }
                            
                            // Check for horizontal paging only if not dismissing
                            if abs(value.translation.width) > horizontalThreshold {
                                if value.translation.width > 0 && currentPage > 0 {
                                    currentPage -= 1
                                } else if value.translation.width < 0 && currentPage < photos.count - 1 {
                                    currentPage += 1
                                }
                            }
                            
                            // Reset if no action taken
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = .zero
                                backgroundOpacity = 1.0
                                sidePhotosOpacity = 1.0
                            }
                        }
                )
            }
        }
        .offset(dragOffset)
        .scaleEffect(1.0 - min(max(abs(dragOffset.height), abs(dragOffset.width)) / 1000.0, 0.3))
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: dragOffset)
        .onAppear {
            currentPage = selectedIndex
            withAnimation(.easeInOut(duration: 0.3)) {
                backgroundOpacity = 1.0
            }
            // Clean up cache on appear
            ImageCacheManager.shared.trimCache()
        }
        .onChange(of: currentPage) { _, newValue in
            selectedIndex = newValue
            // Unload distant views to save memory
            unloadDistantViews()
        }
    }
    
    private func shouldLoadView(at index: Int) -> Bool {
        // Load current view and one on each side
        let distance = abs(index - currentPage)
        return distance <= 1
    }
    
    private func unloadDistantViews() {
        // Remove views that are more than 2 pages away
        loadedViews = loadedViews.filter { key, _ in
            abs(key - currentPage) <= 2
        }
    }
    
    private func createDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Allow both vertical and horizontal drags for dismissal
                dragOffset = value.translation
                let dragDistance = max(abs(value.translation.height), abs(value.translation.width))
                backgroundOpacity = max(0, 1.0 - (dragDistance / 300.0))
                
                if dragDistance > 10 {
                    withAnimation(.easeOut(duration: 0.1)) {
                        sidePhotosOpacity = 0.0
                    }
                }
            }
            .onEnded { value in
                if abs(value.translation.height) > 100 || abs(value.translation.width) > 100 {
                    dismissView()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                        backgroundOpacity = 1.0
                        sidePhotosOpacity = 1.0
                    }
                }
            }
    }
    
    private func dismissView() {
        isDismissing = true
        withAnimation(.smooth(duration: 0.35)) {
            backgroundOpacity = 0
        }
    }
}

// Separate view for lazy-loaded images
struct LazyFullscreenImageView: View {
    let itemData: GridItemData
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    let isCurrentPage: Bool
    let isDismissing: Bool
    let onDismissComplete: () -> Void
    
    @State private var fullImage: UIImage? = nil
    @State private var isLoadingImage: Bool = false
    @State private var showContent: Bool = false
    @State private var imageOpacity: Double = 1.0
    @State private var currentScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    
    @GestureState private var magnifyBy = CGFloat(1.0)
    
    private let minimumScale: CGFloat = 1.0
    private let maximumScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5
    
    var combinedScale: CGFloat {
        currentScale * magnifyBy
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = fullImage ?? itemData.image {
                    InteractiveImageView(
                        image: image,
                        geometry: geometry,
                        sourceFrame: sourceFrame,
                        showContent: $showContent,
                        currentScale: $currentScale,
                        dragOffset: $dragOffset,
                        imageOpacity: $imageOpacity,
                        isCurrentPage: isCurrentPage,
                        isInitialAppearance: sourceFrame != .zero,
                        onDragChanged: { _ in },
                        onDragEnded: { _ in }
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
                    .onChange(of: isDismissing) { _, dismissing in
                        if dismissing && isCurrentPage {
                            withAnimation(.smooth(duration: 0.35)) {
                                showContent = false
                                currentScale = 1.0
                            }
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
                } else {
                    // Show thumbnail while loading
                    if let thumbnailImage = itemData.image {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .blur(radius: 2)
                    }
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .onAppear {
            if isCurrentPage {
                loadFullImageIfNeeded()
            }
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            if isCurrent {
                loadFullImageIfNeeded()
            }
        }
        .onDisappear {
            // Clean up full image when view disappears to save memory
            if !isCurrentPage {
                fullImage = nil
            }
        }
    }
    
    private func loadFullImageIfNeeded() {
        guard fullImage == nil, let asset = itemData.asset else { return }
        
        let assetId = asset.localIdentifier
        
        // Check cache first
        if let cachedImage = ImageCacheManager.shared.image(for: assetId) {
            self.fullImage = cachedImage
            return
        }
        
        isLoadingImage = true
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact
        
        // Use a more reasonable size for fullscreen images
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(
            width: screenSize.width * scale * 1.5, // 1.5x for some zoom headroom
            height: screenSize.height * scale * 1.5
        )
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image = image else { return }
            
            // Cache the image
            ImageCacheManager.shared.cache(image, for: assetId)
            
            DispatchQueue.main.async {
                self.fullImage = image
                self.isLoadingImage = false
            }
        }
    }
}

// Simple cache manager with memory management
class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private var cache: [String: UIImage] = [:]
    private let maxCacheSize = 5 // Maximum number of full-res images to keep
    private let queue = DispatchQueue(label: "image.cache.queue", attributes: .concurrent)
    
    private init() {}
    
    func image(for key: String) -> UIImage? {
        queue.sync {
            cache[key]
        }
    }
    
    func cache(_ image: UIImage, for key: String) {
        queue.async(flags: .barrier) {
            self.cache[key] = image
            self.trimCacheIfNeeded()
        }
    }
    
    func trimCache() {
        queue.async(flags: .barrier) {
            self.trimCacheIfNeeded()
        }
    }
    
    private func trimCacheIfNeeded() {
        if cache.count > maxCacheSize {
            // Remove oldest entries (simple FIFO for now)
            let keysToRemove = Array(cache.keys.prefix(cache.count - maxCacheSize))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
    }
    
    func clearCache() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}