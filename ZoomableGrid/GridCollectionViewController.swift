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
            collectionView?.visibleCells.forEach { cell in
                (cell as? GridCollectionViewCell)?.useImageFill = useImageFill
            }
        }
    }
    
    var isScrollEnabled: Bool = true {
        didSet {
            collectionView?.isScrollEnabled = isScrollEnabled
        }
    }
    
    // Callbacks
    var onItemTapped: ((Int, CGRect) -> Void)?
    var onVisibleItemsChanged: ((Set<Int>, Int) -> Void)?
    
    // Tracking visible items
    private var visibleItems: Set<Int> = []
    private var centerVisibleItem: Int = 0
    
    // Image loading
    private let thumbnailSize = CGSize(width: 300, height: 300)
    
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
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(GridCollectionViewCell.self, forCellWithReuseIdentifier: GridCollectionViewCell.identifier)
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delaysContentTouches = false
        
        view.addSubview(collectionView)
    }
    
    private func updateCellCornerRadius() {
        let cornerRadius: CGFloat = numberOfColumns == 5 ? 7 : 10
        collectionView?.visibleCells.forEach { cell in
            (cell as? GridCollectionViewCell)?.cornerRadius = cornerRadius
        }
    }
    
    func scrollToItem(_ item: Int, animated: Bool = true) {
        guard item >= 0 && item < photos.count else { return }
        let indexPath = IndexPath(item: item, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
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
        view.transform = CGAffineTransform(translationX: xDiff, y: yDiff)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -xDiff, y: -yDiff)
        
        view.alpha = opacity
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
        
        return cell
    }
}

// MARK: - UICollectionViewDelegate
extension GridCollectionViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        let globalFrame = cell.convert(cell.bounds, to: nil)
        onItemTapped?(indexPath.item, globalFrame)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisibleItems()
    }
}