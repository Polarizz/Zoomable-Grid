//
//  FullscreenImageViewSimple.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI
import Photos

struct FullscreenImageViewSimple: View {
    let image: UIImage
    let geometry: GeometryProxy
    @Binding var currentScale: CGFloat
    @Binding var imageOpacity: Double
    let isCurrentPage: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (Bool) -> Void
    
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
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
            .frame(width: imageSize.width, height: imageSize.height)
            .scaleEffect(combinedScale * (1.0 - min(abs(dragOffset.height) / 1000.0, 0.3)))
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.9), value: combinedScale)
            .offset(
                x: offset.width + dragOffset.width,
                y: offset.height + dragOffset.height
            )
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.9), value: offset)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .opacity(imageOpacity)
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