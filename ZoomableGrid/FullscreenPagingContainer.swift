//
//  FullscreenPagingContainer.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI

struct FullscreenPagingContainer: View {
    let photos: [GridItemData]
    let initialIndex: Int
    let initialSourceFrame: CGRect
    @Binding var isPresented: Bool
    
    @State private var currentIndex: Int
    
    init(photos: [GridItemData], initialIndex: Int, initialSourceFrame: CGRect, isPresented: Binding<Bool>) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.initialSourceFrame = initialSourceFrame
        self._isPresented = isPresented
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            FullscreenPageViewController(
                photos: photos,
                currentIndex: $currentIndex,
                isPresented: $isPresented,
                initialSourceFrame: initialSourceFrame
            )
            .ignoresSafeArea()
        }
        .onTapGesture {
            // Add tap to dismiss if needed
        }
    }
}