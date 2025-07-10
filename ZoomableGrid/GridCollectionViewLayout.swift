//
//  GridCollectionViewLayout.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/10/25.
//

import UIKit

class GridCollectionViewLayout: UICollectionViewFlowLayout {
    var numberOfColumns: Int = 5 {
        didSet {
            if numberOfColumns != oldValue {
                invalidateLayout()
            }
        }
    }
    
    var spacing: CGFloat = 2.0 {
        didSet {
            if spacing != oldValue {
                invalidateLayout()
            }
        }
    }
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = collectionView else { return }
        
        let availableWidth = collectionView.bounds.width - collectionView.contentInset.left - collectionView.contentInset.right
        let itemWidth = (availableWidth - CGFloat(numberOfColumns - 1) * spacing) / CGFloat(numberOfColumns)
        
        itemSize = CGSize(width: itemWidth, height: itemWidth)
        minimumInteritemSpacing = spacing
        minimumLineSpacing = spacing
        
        scrollDirection = .vertical
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else { return false }
        return collectionView.bounds.width != newBounds.width
    }
    
    // Support for animated layout transitions
    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)
        attributes?.alpha = 0
        attributes?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        return attributes
    }
    
    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)
        attributes?.alpha = 0
        attributes?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        return attributes
    }
}