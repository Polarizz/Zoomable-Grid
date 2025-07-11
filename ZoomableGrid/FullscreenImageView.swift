//
//  FullscreenImageView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI
import Photos

struct FullscreenImageView: View {
    let itemData: GridItemData
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    @Binding var isCurrentPage: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var dragScale: CGFloat = 1.0
    @State private var fullImage: UIImage? = nil
    @State private var isLoadingFullImage: Bool = false
    @State private var showContent: Bool = false
    @State private var dismissalProgress: CGFloat = 0
    @State private var isDraggingVertically: Bool = false
    
    // Zoom related states
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isZooming = false
    
    private let imageManager = PHImageManager.default()
    private let minimumScale: CGFloat = 1.0
    private let maximumScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(showContent ? (1.0 - abs(dragOffset.height) / 300.0).clamped(to: 0...1) : 0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: showContent)
                
                if let image = fullImage ?? itemData.image {
                    ZoomableImageView(
                        image: image,
                        geometry: geometry,
                        sourceFrame: sourceFrame,
                        showContent: $showContent,
                        dismissalProgress: $dismissalProgress,
                        isPresented: $isPresented,
                        currentScale: $currentScale,
                        offset: $offset,
                        isCurrentPage: isCurrentPage,
                        dragOffset: dragOffset
                    )
                } else if let asset = itemData.asset {
                    ZStack {
                        // Placeholder while loading
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        // Low-res thumbnail while loading full image
                        if let thumbnailImage = itemData.image {
                            ZoomableImageView(
                                image: thumbnailImage,
                                geometry: geometry,
                                sourceFrame: sourceFrame,
                                showContent: $showContent,
                                dismissalProgress: $dismissalProgress,
                                isPresented: $isPresented,
                                currentScale: $currentScale,
                                offset: $offset,
                                isCurrentPage: isCurrentPage,
                                dragOffset: dragOffset
                            )
                            .blur(radius: isLoadingFullImage ? 2 : 0)
                        }
                    }
                    .onAppear {
                        loadFullImage(from: asset)
                    }
                }
            }
        }
        .offset(dragOffset)
        .scaleEffect(1.0 - min(abs(dragOffset.height) / 1000.0, 0.3))
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if currentScale <= 1 && isCurrentPage {
                        let translation = value.translation
                        // Only vertical drags
                        if abs(translation.height) > abs(translation.width) {
                            dragOffset = translation
                        }
                    }
                }
                .onEnded { value in
                    if abs(value.translation.height) > 100 {
                        // Dismiss
                        withAnimation(.smooth(duration: 0.4)) {
                            showContent = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onAppear {
            if sourceFrame != .zero {
                // Small delay to ensure view is laid out
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    withAnimation(.smooth(duration: 0.4)) {
                        showContent = true
                    }
                }
            } else {
                // Already in position (adjacent pages)
                showContent = true
            }
        }
    }
    
    private func loadFullImage(from asset: PHAsset) {
        guard fullImage == nil else { return }
        
        isLoadingFullImage = true
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .fast
        
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: UIScreen.main.bounds.height * scale
        )
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [self] image, info in
            
            if let error = info?[PHImageErrorKey] as? Error {
                print("Error loading full image: \(error.localizedDescription)")
                return
            }
            
            if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                return
            }
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            
            guard let image = image else { return }
            
            Task { @MainActor in
                if self.fullImage == nil {
                    self.fullImage = image
                    if !isDegraded {
                        self.isLoadingFullImage = false
                    }
                } else if !isDegraded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.fullImage = image
                        self.isLoadingFullImage = false
                    }
                }
            }
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    let geometry: GeometryProxy
    let sourceFrame: CGRect
    @Binding var showContent: Bool
    @Binding var dismissalProgress: CGFloat
    @Binding var isPresented: Bool
    @Binding var currentScale: CGFloat
    @Binding var offset: CGSize
    let isCurrentPage: Bool
    let dragOffset: CGSize
    
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var isDragging = false
    @GestureState private var magnifyBy = CGFloat(1.0)
    
    private let minimumScale: CGFloat = 1.0
    private let maximumScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5
    
    var combinedScale: CGFloat {
        let scale = currentScale * magnifyBy
        
        // Apply rubber band effect when beyond limits
        if magnifyBy != 1.0 {
            if scale < minimumScale {
                let diff = minimumScale - scale
                return minimumScale - (diff * 0.5)
            } else if scale > maximumScale {
                let diff = scale - maximumScale
                return maximumScale + (diff * 0.1)
            }
        }
        
        return scale
    }
    
    var body: some View {
        let imageAspectRatio = image.size.width / image.size.height
        let screenAspectRatio = geometry.size.width / geometry.size.height
        
        let finalWidth: CGFloat = imageAspectRatio > screenAspectRatio ? geometry.size.width : geometry.size.height * imageAspectRatio
        let finalHeight: CGFloat = imageAspectRatio > screenAspectRatio ? geometry.size.width / imageAspectRatio : geometry.size.height
        
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(
                width: showContent ? finalWidth : sourceFrame.width,
                height: showContent ? finalHeight : sourceFrame.height
            )
            .clipped()
            .scaleEffect(showContent ? combinedScale : 1.0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.9), value: combinedScale)
            .offset(showContent ? offset : .zero)
            .blur(radius: dismissalProgress * 30)
            .opacity(1.0 - dismissalProgress)
            .position(
                x: showContent ? geometry.size.width / 2 + dragOffset.width : sourceFrame.midX,
                y: showContent ? geometry.size.height / 2 + dragOffset.height : sourceFrame.midY
            )
            .animation(.smooth(duration: 0.4), value: showContent)
            .animation(.easeOut(duration: 0.1), value: dismissalProgress)
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
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($magnifyBy) { currentState, gestureState, _ in
                        gestureState = currentState
                    }
                    .onEnded { value in
                        let newScale = currentScale * value
                        
                        // Simply clamp the scale - animation modifier handles the spring back
                        currentScale = min(max(newScale, minimumScale), maximumScale)
                        
                        // Reset offset if we're back at 1x
                        if currentScale <= 1.0 {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9)) {
                                offset = .zero
                            }
                        }
                        
                        constrainOffset(imageSize: CGSize(width: finalWidth, height: finalHeight))
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            if currentScale > 1 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { value in
                            lastOffset = offset
                            constrainOffset(imageSize: CGSize(width: finalWidth, height: finalHeight))
                        }
                    )
            )
    }
    
    private func constrainOffset(imageSize: CGSize) {
        let scaledWidth = imageSize.width * currentScale
        let scaledHeight = imageSize.height * currentScale
        
        let maxOffsetX = max((scaledWidth - geometry.size.width) / 2, 0)
        let maxOffsetY = max((scaledHeight - geometry.size.height) / 2, 0)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset.width = min(max(offset.width, -maxOffsetX), maxOffsetX)
            offset.height = min(max(offset.height, -maxOffsetY), maxOffsetY)
        }
        
        lastOffset = offset
    }
}
