//
//  GridCollectionViewController.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/10/25.
//

import UIKit
import SwiftUI
import Combine
import Photos

class GridCollectionViewController: UIViewController {
    
    // Collection view and layout
    private var collectionView: UICollectionView!
    private var layout: GridCollectionViewLayout!
    
    // Data
    var photos: [GridItemData] = [] {
        didSet {
            collectionView?.reloadData()
        }
    }
    
    // Configuration
    var numberOfColumns: Int = 5 {
        didSet {
            layout?.numberOfColumns = numberOfColumns
            updateCellCornerRadius()
        }
    }
    
    var spacing: CGFloat = 2.0 {
        didSet {
            layout?.spacing = spacing
        }
    }
    
    var useImageFill: Bool = true {
        didSet {
            guard oldValue != useImageFill else { return }
            animateContentModeChange()
        }
    }
    
    private func animateContentModeChange() {
        // Force all visible cells to update with animation
        collectionView?.visibleCells.forEach { cell in
            if let gridCell = cell as? GridCollectionViewCell {
                gridCell.useImageFill = useImageFill
            }
        }
    }
    
    var isScrollEnabled: Bool = true {
        didSet {
            collectionView?.isScrollEnabled = isScrollEnabled
        }
    }
    
    var topSafeAreaInset: CGFloat = 0 {
        didSet {
            updateContentInsets()
        }
    }
    
    var bottomSafeAreaInset: CGFloat = 0 {
        didSet {
            updateContentInsets()
        }
    }
    
    // Callbacks
    var onVisibleItemsChanged: ((Set<Int>, Int) -> Void)?
    var onImageTapped: ((GridItemData, CGRect) -> Void)?
    var frameForIndex: ((Int) -> CGRect?)?
    
    // Tracking visible items
    private var visibleItems: Set<Int> = []
    private var centerVisibleItem: Int = 0
    
    // Image loading - Use screen scale for better quality
    private var thumbnailSize: CGSize {
        let scale = UIScreen.main.scale
        let baseSize: CGFloat = 200 // Base size for thumbnails
        return CGSize(width: baseSize * scale, height: baseSize * scale)
    }
    
    // Prefetch cache
    private var prefetchCache: [IndexPath: PHImageRequestID] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
    }
    
    private func setupCollectionView() {
        layout = GridCollectionViewLayout()
        layout.numberOfColumns = numberOfColumns
        layout.spacing = spacing
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.register(GridCollectionViewCell.self, forCellWithReuseIdentifier: GridCollectionViewCell.identifier)
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delaysContentTouches = false
        
        view.addSubview(collectionView)
        
        // Apply initial content insets
        updateContentInsets()
    }
    
    private func updateCellCornerRadius() {
        let cornerRadius: CGFloat = numberOfColumns == 5 ? 7 : 10
        collectionView?.visibleCells.forEach { cell in
            (cell as? GridCollectionViewCell)?.cornerRadius = cornerRadius
        }
    }
    
    private func updateContentInsets() {
        guard let collectionView = collectionView else { return }
        collectionView.contentInset = UIEdgeInsets(top: topSafeAreaInset, left: 0, bottom: bottomSafeAreaInset, right: 0)
        collectionView.scrollIndicatorInsets = collectionView.contentInset
    }
    
    func scrollToItem(_ item: Int, animated: Bool = true) {
        guard item >= 0 && item < photos.count else { return }
        let indexPath = IndexPath(item: item, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
    }
    
    func getFrameForIndex(_ index: Int) -> CGRect? {
        guard index >= 0 && index < photos.count else { return nil }
        let indexPath = IndexPath(item: index, section: 0)
        
        // Make sure the cell is visible or get its frame from layout
        if let cell = collectionView.cellForItem(at: indexPath) {
            return getImageFrameInCell(cell, at: indexPath)
        }
        return nil
    }
    
    private func getImageFrameInCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) -> CGRect? {
        guard indexPath.item < photos.count else { return nil }
        
        let itemData = photos[indexPath.item]
        let cellFrame = cell.frame
        var imageFrame = cellFrame
        
        // If in fit mode, calculate the actual image position within the cell
        if !useImageFill {
            let cellAspect = cellFrame.width / cellFrame.height
            let imageAspect = itemData.aspectRatio
            
            if imageAspect > cellAspect {
                // Image is wider - has vertical padding
                let imageHeight = cellFrame.width / imageAspect
                let yOffset = (cellFrame.height - imageHeight) / 2
                imageFrame = CGRect(
                    x: cellFrame.origin.x,
                    y: cellFrame.origin.y + yOffset,
                    width: cellFrame.width,
                    height: imageHeight
                )
            } else {
                // Image is taller - has horizontal padding
                let imageWidth = cellFrame.height * imageAspect
                let xOffset = (cellFrame.width - imageWidth) / 2
                imageFrame = CGRect(
                    x: cellFrame.origin.x + xOffset,
                    y: cellFrame.origin.y,
                    width: imageWidth,
                    height: cellFrame.height
                )
            }
        }
        
        // Convert to window coordinates
        if let window = collectionView.window {
            return collectionView.convert(imageFrame, to: nil)
        }
        return imageFrame
    }
    
    func updateVisibleItems() {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        visibleItems = Set(visibleIndexPaths.map { $0.item })
        updateCenterFromVisibleItems()
        onVisibleItemsChanged?(visibleItems, centerVisibleItem)
    }
    
    private func updateCenterFromVisibleItems() {
        guard !visibleItems.isEmpty else { return }
        
        let sortedItems = visibleItems.sorted()
        
        var rowGroups: [Int: [Int]] = [:]
        for item in sortedItems {
            let row = item / numberOfColumns
            if rowGroups[row] == nil {
                rowGroups[row] = []
            }
            rowGroups[row]?.append(item)
        }
        
        let sortedRows = rowGroups.keys.sorted()
        guard !sortedRows.isEmpty else { return }
        
        let middleRowIndex = sortedRows.count / 2
        let middleRow = sortedRows[middleRowIndex]
        
        if let rowItems = rowGroups[middleRow] {
            let targetColumn = numberOfColumns / 2
            let targetItem = middleRow * numberOfColumns + targetColumn
            centerVisibleItem = rowItems.contains(targetItem) ? targetItem : rowItems[rowItems.count / 2]
        }
    }
    
    // Apply transform for zoom and animations
    func applyTransform(scale: CGFloat, anchor: UnitPoint, opacity: CGFloat, blur: CGFloat) {
        // Calculate anchor point
        let anchorPoint = CGPoint(x: anchor.x, y: anchor.y)
        
        // Apply transform with proper anchor
        let view = collectionView!
        view.layer.anchorPoint = anchorPoint
        
        // Adjust position to maintain visual anchor during scale
        let xDiff = (anchorPoint.x - 0.5) * view.bounds.width
        let yDiff = (anchorPoint.y - 0.5) * view.bounds.height
        let newTransform = CGAffineTransform(translationX: xDiff, y: yDiff)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -xDiff, y: -yDiff)
        
        // Check if we should animate (when there's a significant change and we're not actively zooming)
        let shouldAnimate = abs(view.transform.a - newTransform.a) > 0.01 && opacity > 0.1
        
        if shouldAnimate {
            UIView.animate(withDuration: 0.39, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: [.curveEaseInOut, .allowUserInteraction]) {
                view.transform = newTransform
                view.alpha = opacity
            }
        } else {
            view.transform = newTransform
            view.alpha = opacity
        }
    }
    
}

// MARK: - UICollectionViewDataSource
extension GridCollectionViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GridCollectionViewCell.identifier, for: indexPath) as! GridCollectionViewCell
        
        let itemData = photos[indexPath.item]
        cell.configure(with: itemData, targetSize: thumbnailSize)
        cell.useImageFill = useImageFill
        cell.cornerRadius = numberOfColumns == 5 ? 7 : 10
        cell.delegate = self
        
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension GridCollectionViewController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisibleItems()
    }
}

// MARK: - GridCollectionViewCellDelegate
extension GridCollectionViewController: GridCollectionViewCellDelegate {
    func cellTapped(_ cell: GridCollectionViewCell) {
        guard var itemData = cell.currentItemData else { return }
        
        // If we have a loaded thumbnail, create a new GridItemData with it
        if let loadedImage = cell.loadedImage, itemData.image == nil {
            itemData = GridItemData(
                asset: itemData.asset,
                image: loadedImage,
                id: itemData.id,
                aspectRatio: itemData.aspectRatio
            )
        }
        
        // Get the actual image frame within the cell
        let cellFrame = cell.frame
        var imageFrame = cellFrame
        
        // If in fit mode, calculate the actual image position within the cell
        if !useImageFill {
            let cellAspect = cellFrame.width / cellFrame.height
            let imageAspect = itemData.aspectRatio
            
            if imageAspect > cellAspect {
                // Image is wider - has vertical padding
                let imageHeight = cellFrame.width / imageAspect
                let yOffset = (cellFrame.height - imageHeight) / 2
                imageFrame = CGRect(
                    x: cellFrame.origin.x,
                    y: cellFrame.origin.y + yOffset,
                    width: cellFrame.width,
                    height: imageHeight
                )
            } else {
                // Image is taller - has horizontal padding
                let imageWidth = cellFrame.height * imageAspect
                let xOffset = (cellFrame.width - imageWidth) / 2
                imageFrame = CGRect(
                    x: cellFrame.origin.x + xOffset,
                    y: cellFrame.origin.y,
                    width: imageWidth,
                    height: cellFrame.height
                )
            }
        }
        
        // Convert to screen coordinates
        if let window = collectionView.window {
            let frameInWindow = collectionView.convert(imageFrame, to: nil)
            onImageTapped?(itemData, frameInWindow)
        } else {
            onImageTapped?(itemData, imageFrame)
        }
    }
}

// MARK: - UICollectionViewDataSourcePrefetching
extension GridCollectionViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .fast
        
        for indexPath in indexPaths {
            guard indexPath.item < photos.count else { continue }
            let itemData = photos[indexPath.item]
            
            guard let asset = itemData.asset else { continue }
            
            // Start loading the image
            let requestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { _, _ in
                // Just prefetching, we don't need to do anything with the image
            }
            
            prefetchCache[indexPath] = requestID
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            if let requestID = prefetchCache[indexPath] {
                PHImageManager.default().cancelImageRequest(requestID)
                prefetchCache.removeValue(forKey: indexPath)
            }
        }
    }
}