//
//  OptimizedFullscreenPagingView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI
import Photos

struct OptimizedFullscreenPagingView: View {
    let photos: [GridItemData]
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    
    @State private var currentPage: Int = 0
    @State private var isDismissing: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 0.0
    @State private var sidePhotosOpacity: Double = 1.0
    @State private var loadedIndices: Set<Int> = []
    
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
            
            // TabView for reliable paging
            TabView(selection: $currentPage) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    OptimizedFullscreenImageView(
                        itemData: photo,
                        index: index,
                        currentPage: currentPage,
                        isPresented: $isPresented,
                        sourceFrame: index == selectedIndex ? sourceFrame : .zero,
                        isCurrentPage: index == currentPage,
                        isDismissing: isDismissing,
                        onDismissComplete: {
                            isPresented = false
                        }
                    )
                    .tag(index)
                    .opacity(index == currentPage ? 1.0 : sidePhotosOpacity)
                    .gesture(createDismissGesture())
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(dragOffset)
            .scaleEffect(1.0 - min(max(abs(dragOffset.height), abs(dragOffset.width)) / 1000.0, 0.3))
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: dragOffset)
        }
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
            preloadAdjacentImages()
        }
    }
    
    private func createDismissGesture() -> some Gesture {
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
    
    private func preloadAdjacentImages() {
        // Preload images one page away
        let indicesToPreload = [currentPage - 1, currentPage, currentPage + 1]
            .filter { $0 >= 0 && $0 < photos.count }
        
        for index in indicesToPreload {
            if !loadedIndices.contains(index), let asset = photos[index].asset {
                loadedIndices.insert(index)
                preloadImage(from: asset)
            }
        }
    }
    
    private func preloadImage(from asset: PHAsset) {
        let assetId = asset.localIdentifier
        
        // Skip if already cached
        if ImageCacheManager.shared.image(for: assetId) != nil {
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: screenSize.width * scale * 1.5,
            height: screenSize.height * scale * 1.5
        )
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if let image = image {
                ImageCacheManager.shared.cache(image, for: assetId)
            }
        }
    }
}

struct OptimizedFullscreenImageView: View {
    let itemData: GridItemData
    let index: Int
    let currentPage: Int
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
    @State private var hasLoadedFullImage: Bool = false
    
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
                        dragOffset: .constant(.zero),
                        imageOpacity: $imageOpacity,
                        isCurrentPage: isCurrentPage,
                        isInitialAppearance: sourceFrame != .zero,
                        onDragChanged: { _ in },
                        onDragEnded: { _ in }
                    )
                    .onAppear {
                        if sourceFrame != .zero && !showContent {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.smooth(duration: 0.35)) {
                                    showContent = true
                                }
                            }
                        } else if sourceFrame == .zero {
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
                            .blur(radius: isLoadingImage ? 2 : 0)
                    }
                    
                    if isLoadingImage {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
            }
        }
        .onAppear {
            // Only load if we're the current page or adjacent
            let distance = abs(index - currentPage)
            if distance <= 1 && !hasLoadedFullImage {
                loadFullImageIfNeeded()
            }
        }
        .onChange(of: isCurrentPage) { _, isCurrent in
            if isCurrent && !hasLoadedFullImage {
                loadFullImageIfNeeded()
            }
        }
    }
    
    
    private func loadFullImageIfNeeded() {
        guard fullImage == nil, let asset = itemData.asset else { return }
        
        let assetId = asset.localIdentifier
        
        // Check cache first
        if let cachedImage = ImageCacheManager.shared.image(for: assetId) {
            self.fullImage = cachedImage
            self.hasLoadedFullImage = true
            return
        }
        
        isLoadingImage = true
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact
        
        // Use a reasonable size for fullscreen images
        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: screenSize.width * scale * 1.5,
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
                self.hasLoadedFullImage = true
            }
        }
    }
}