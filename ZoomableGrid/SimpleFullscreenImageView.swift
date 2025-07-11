//
//  SimpleFullscreenImageView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI
import Photos

struct SimpleFullscreenImageView: View {
    let itemData: GridItemData
    @Binding var isPresented: Bool
    let sourceFrame: CGRect
    
    @State private var showContent: Bool = false
    @State private var fullImage: UIImage? = nil
    @State private var isLoadingImage: Bool = false
    @State private var currentScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var imageOpacity: Double = 1.0
    
    @GestureState private var magnifyBy = CGFloat(1.0)
    
    private let minimumScale: CGFloat = 1.0
    private let maximumScale: CGFloat = 5.0
    private let doubleTapScale: CGFloat = 2.5
    
    var combinedScale: CGFloat {
        currentScale * magnifyBy
    }
    
    var body: some View {
        ZStack {
            // Background - only fades, doesn't move or scale
            Color.black
                .opacity(showContent ? (1.0 - abs(dragOffset.height) / 300.0).clamped(to: 0...1) : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: showContent)
                .onTapGesture {
                    dismissView()
                }
            
            // Image container - this moves and scales
            GeometryReader { geometry in
                if let image = fullImage ?? itemData.image {
                    InteractiveImageView(
                        image: image,
                        geometry: geometry,
                        sourceFrame: sourceFrame,
                        showContent: $showContent,
                        currentScale: $currentScale,
                        dragOffset: $dragOffset,
                        imageOpacity: $imageOpacity,
                        isCurrentPage: true,
                        isInitialAppearance: true,
                        onDragChanged: { _ in },
                        onDragEnded: { _ in }
                    )
                } else {
                    // Show loading
                    if let thumbnailImage = itemData.image {
                        Image(uiImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .blur(radius: 2)
                    }
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .offset(dragOffset)
            .scaleEffect(1.0 - min(abs(dragOffset.height) / 1000.0, 0.3))
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8), value: dragOffset)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if currentScale <= 1 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if abs(value.translation.height) > 100 {
                        dismissView()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onAppear {
            // Animate in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                withAnimation(.smooth(duration: 0.4)) {
                    showContent = true
                }
            }
            loadFullImage()
        }
    }
    
    private func dismissView() {
        withAnimation(.smooth(duration: 0.4)) {
            showContent = false
            imageOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isPresented = false
        }
    }
    
    private func loadFullImage() {
        guard fullImage == nil, let asset = itemData.asset else { return }
        
        isLoadingImage = true
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        
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
            
            DispatchQueue.main.async {
                self.fullImage = image
                self.isLoadingImage = false
            }
        }
    }
}