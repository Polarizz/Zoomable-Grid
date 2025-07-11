//
//  CollectionViewRepresentable.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/10/25.
//

import SwiftUI
import UIKit

struct CollectionViewRepresentable: UIViewControllerRepresentable {
    let photos: [GridItemData]
    let numberOfColumns: Int
    let spacing: CGFloat
    let useImageFill: Bool
    let isScrollEnabled: Bool
    let currentScale: CGFloat
    let anchor: UnitPoint
    let opacity: Double
    let blur: Double
    let topSafeAreaInset: CGFloat
    let bottomSafeAreaInset: CGFloat
    
    let onVisibleItemsChanged: (Set<Int>, Int) -> Void
    let onImageTapped: ((GridItemData, CGRect) -> Void)?
    @Binding var scrollToItem: Int?
    
    func makeUIViewController(context: Context) -> GridCollectionViewController {
        let controller = GridCollectionViewController()
        controller.photos = photos
        controller.numberOfColumns = numberOfColumns
        controller.spacing = spacing
        controller.useImageFill = useImageFill
        controller.isScrollEnabled = isScrollEnabled
        controller.topSafeAreaInset = topSafeAreaInset
        controller.bottomSafeAreaInset = bottomSafeAreaInset
        controller.onVisibleItemsChanged = onVisibleItemsChanged
        controller.onImageTapped = onImageTapped
        controller.frameForIndex = { index in
            return controller.getFrameForIndex(index)
        }
        
        context.coordinator.viewController = controller
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: GridCollectionViewController, context: Context) {
        // Update data if changed
        if uiViewController.photos.count != photos.count {
            uiViewController.photos = photos
        }
        
        // Update configuration
        uiViewController.numberOfColumns = numberOfColumns
        uiViewController.spacing = spacing
        uiViewController.useImageFill = useImageFill
        uiViewController.isScrollEnabled = isScrollEnabled
        uiViewController.topSafeAreaInset = topSafeAreaInset
        uiViewController.bottomSafeAreaInset = bottomSafeAreaInset
        
        // Apply transform for zoom
        uiViewController.applyTransform(scale: currentScale, anchor: anchor, opacity: opacity, blur: blur)
        
        // Handle scroll to item
        if let item = scrollToItem {
            uiViewController.scrollToItem(item, animated: true)
            // Clear the binding after a delay to avoid state modification during view update
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                scrollToItem = nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        weak var viewController: GridCollectionViewController?
    }
}