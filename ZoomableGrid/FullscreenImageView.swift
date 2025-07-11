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
    @State private var dragOffset: CGSize = .zero
    @State private var dragScale: CGFloat = 1.0
    @State private var fullImage: UIImage? = nil
    @State private var isLoadingFullImage: Bool = false
    @State private var showContent: Bool = false
    
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(showContent ? (1.0 - min(abs(dragOffset.height) / 300.0, 1.0)) : 0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: showContent)
                
                if let image = fullImage ?? itemData.image {
                    imageView(image: image, in: geometry)
                } else if let asset = itemData.asset {
                    ZStack {
                        // Placeholder while loading
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        // Low-res thumbnail while loading full image
                        if let thumbnailImage = itemData.image {
                            imageView(image: thumbnailImage, in: geometry)
                                .blur(radius: isLoadingFullImage ? 2 : 0)
                        }
                    }
                    .onAppear {
                        loadFullImage(from: asset)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.4)) {
                showContent = true
            }
        }
        .onTapGesture {
            withAnimation(.smooth(duration: 0.3)) {
                showContent = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPresented = false
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                    let progress = min(abs(value.translation.height) / 200.0, 1.0)
                    dragScale = 1.0 - (progress * 0.3)
                }
                .onEnded { value in
                    if abs(value.translation.height) > 100 {
                        withAnimation(.smooth(duration: 0.3)) {
                            showContent = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isPresented = false
                        }
                    } else {
                        withAnimation(.smooth(duration: 0.2)) {
                            dragOffset = .zero
                            dragScale = 1.0
                        }
                    }
                }
        )
    }
    
    @ViewBuilder
    private func imageView(image: UIImage, in geometry: GeometryProxy) -> some View {
        let imageAspectRatio = image.size.width / image.size.height
        let screenAspectRatio = geometry.size.width / geometry.size.height
        
        // Calculate final frame (aspect fit in screen)
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
            .scaleEffect(showContent ? dragScale : 1.0)
            .position(
                x: showContent ? geometry.size.width / 2 + dragOffset.width : sourceFrame.midX,
                y: showContent ? geometry.size.height / 2 + dragOffset.height : sourceFrame.midY
            )
            .animation(.smooth(duration: 0.4), value: showContent)
    }
    
    private func loadFullImage(from asset: PHAsset) {
        guard fullImage == nil else { return }
        
        isLoadingFullImage = true
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic // This delivers low quality first, then high quality
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .fast
        
        // Request image at a reasonable size for display (not full resolution which can be huge)
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
            
            // Check for errors
            if let error = info?[PHImageErrorKey] as? Error {
                print("Error loading full image: \(error.localizedDescription)")
                return
            }
            
            // Check if request was cancelled
            if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                return
            }
            
            // Check if this is a degraded image (low quality)
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            
            // Only proceed if we have an image
            guard let image = image else { return }
            
            Task { @MainActor in
                // If we don't have any image yet, use this one immediately
                if self.fullImage == nil {
                    self.fullImage = image
                    if !isDegraded {
                        self.isLoadingFullImage = false
                    }
                } else if !isDegraded {
                    // Replace with high quality image
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.fullImage = image
                        self.isLoadingFullImage = false
                    }
                }
            }
        }
    }
}