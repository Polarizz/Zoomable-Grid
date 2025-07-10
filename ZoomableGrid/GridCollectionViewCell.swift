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
    
    private let containerView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.backgroundColor = .clear
        return view
    }()
    
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .clear
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
    private var imageAspectRatio: CGFloat = 1.0
    
    var useImageFill: Bool = true {
        didSet {
            guard oldValue != useImageFill else { return }
            animateContentModeChange()
        }
    }
    
    var cornerRadius: CGFloat = 7 {
        didSet {
            layer.cornerRadius = cornerRadius
            containerView.layer.cornerRadius = useImageFill ? 0 : cornerRadius
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
        contentView.addSubview(containerView)
        containerView.addSubview(imageView)
        contentView.addSubview(placeholderImageView)
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            placeholderImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.3),
            placeholderImageView.heightAnchor.constraint(equalTo: placeholderImageView.widthAnchor)
        ])
        
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        backgroundColor = .clear
        containerView.layer.cornerRadius = cornerRadius
        
        updateImageFrame(animated: false)
    }
    
    private func updateImageFrame(animated: Bool) {
        let containerBounds = containerView.bounds
        guard containerBounds.width > 0, containerBounds.height > 0 else { return }
        
        var targetFrame: CGRect
        
        if useImageFill {
            // Fill mode - image fills entire container
            targetFrame = containerBounds
        } else {
            // Fit mode - maintain aspect ratio
            let containerAspect = containerBounds.width / containerBounds.height
            
            if imageAspectRatio > containerAspect {
                // Image is wider than container
                let width = containerBounds.width
                let height = width / imageAspectRatio
                let y = (containerBounds.height - height) / 2
                targetFrame = CGRect(x: 0, y: y, width: width, height: height)
            } else {
                // Image is taller than container
                let height = containerBounds.height
                let width = height * imageAspectRatio
                let x = (containerBounds.width - width) / 2
                targetFrame = CGRect(x: x, y: 0, width: width, height: height)
            }
        }
        
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.imageView.frame = targetFrame
                self.containerView.layer.cornerRadius = self.useImageFill ? 0 : self.cornerRadius
            }
        } else {
            imageView.frame = targetFrame
            containerView.layer.cornerRadius = useImageFill ? 0 : cornerRadius
        }
    }
    
    private func animateContentModeChange() {
        updateImageFrame(animated: true)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateImageFrame(animated: false)
    }
    
    func configure(with itemData: GridItemData, targetSize: CGSize) {
        // Cancel any previous request
        if let requestID = currentRequestID {
            imageManager.cancelImageRequest(requestID)
        }
        
        // Reset to placeholder
        imageView.image = nil
        placeholderImageView.isHidden = false
        
        // Store aspect ratio
        imageAspectRatio = itemData.aspectRatio
        
        if let image = itemData.image {
            // Use provided UIImage
            imageView.image = image
            placeholderImageView.isHidden = true
            updateImageFrame(animated: false)
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
            ) { [weak self] image, info in
                guard let self = self else { return }
                
                // Check for errors
                if let error = info?[PHImageErrorKey] as? Error {
                    print("Error loading image: \(error.localizedDescription)")
                    return
                }
                
                // Check if request was cancelled
                if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                    return
                }
                
                // Only proceed if we have an image
                guard let image = image else { return }
                
                Task { @MainActor in
                    self.imageView.image = image
                    self.placeholderImageView.isHidden = true
                    self.updateImageFrame(animated: false)
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