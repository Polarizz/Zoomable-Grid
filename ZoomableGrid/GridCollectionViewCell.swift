//
//  GridCollectionViewCell.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/10/25.
//

import UIKit
import Photos

class GridCollectionViewCell: UICollectionViewCell {
    static let identifier = "GridCollectionViewCell"
    
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = UIColor.systemGray6
        return view
    }()
    
    private let placeholderImageView: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(systemName: "photo")
        view.tintColor = .gray
        view.contentMode = .scaleAspectFit
        return view
    }()
    
    private var currentRequestID: PHImageRequestID?
    private let imageManager = PHImageManager.default()
    
    var useImageFill: Bool = true {
        didSet {
            imageView.contentMode = useImageFill ? .scaleAspectFill : .scaleAspectFit
            setNeedsLayout()
        }
    }
    
    var cornerRadius: CGFloat = 7 {
        didSet {
            layer.cornerRadius = cornerRadius
            imageView.layer.cornerRadius = useImageFill ? 0 : cornerRadius
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.addSubview(imageView)
        contentView.addSubview(placeholderImageView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            placeholderImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.3),
            placeholderImageView.heightAnchor.constraint(equalTo: placeholderImageView.widthAnchor)
        ])
        
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        backgroundColor = UIColor.systemGray6
    }
    
    func configure(with itemData: GridItemData, targetSize: CGSize) {
        // Cancel any previous request
        if let requestID = currentRequestID {
            imageManager.cancelImageRequest(requestID)
        }
        
        // Reset to placeholder
        imageView.image = nil
        placeholderImageView.isHidden = false
        
        if let image = itemData.image {
            // Use provided UIImage
            imageView.image = image
            placeholderImageView.isHidden = true
        } else if let asset = itemData.asset {
            // Load from PHAsset
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            currentRequestID = imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, _ in
                guard let self = self, let image = image else { return }
                DispatchQueue.main.async {
                    self.imageView.image = image
                    self.placeholderImageView.isHidden = true
                }
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        if let requestID = currentRequestID {
            imageManager.cancelImageRequest(requestID)
        }
        currentRequestID = nil
        imageView.image = nil
        placeholderImageView.isHidden = false
    }
}