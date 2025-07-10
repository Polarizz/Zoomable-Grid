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
    
    let onItemTapped: (Int, CGRect) -> Void
    let onVisibleItemsChanged: (Set<Int>, Int) -> Void
    @Binding var scrollToItem: Int?
    
    func makeUIViewController(context: Context) -> GridCollectionViewController {
        let controller = GridCollectionViewController()
        controller.photos = photos
        controller.numberOfColumns = numberOfColumns
        controller.spacing = spacing
        controller.useImageFill = useImageFill
        controller.isScrollEnabled = isScrollEnabled
        controller.onItemTapped = onItemTapped
        controller.onVisibleItemsChanged = onVisibleItemsChanged
        
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
        
        // Apply transform for zoom
        uiViewController.applyTransform(scale: currentScale, anchor: anchor, opacity: opacity, blur: blur)
        
        // Handle scroll to item
        if let item = scrollToItem {
            uiViewController.scrollToItem(item, animated: true)
            DispatchQueue.main.async {
                self.scrollToItem = nil
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