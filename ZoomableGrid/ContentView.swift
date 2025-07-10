//
//  ContentView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/5/25.
//

import SwiftUI
import PhotosUI
import Photos

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var seed: UInt64

    init(seed: Int) {
        // Better seed initialization to avoid clustering with small indices
        self.seed = UInt64(bitPattern: Int64(seed &* 2654435761))
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator with better parameters
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed
    }
}

struct GridItemData: Identifiable {
    let id: String
    let asset: PHAsset?
    let image: UIImage?
    let aspectRatio: CGFloat

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = nil
        self.aspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    init(image: UIImage, id: String) {
        self.id = id
        self.asset = nil
        self.image = image
        self.aspectRatio = image.size.width / image.size.height
    }
}

struct PhotoGridImage: View {
    let itemData: GridItemData
    let targetSize: CGSize
    let contentMode: ContentMode
    @State private var loadedImage: UIImage?

    private let imageManager = PHImageManager.default()

    var body: some View {
        Group {
            if let image = loadedImage ?? itemData.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            }
        }
        .onAppear {
            loadImageIfNeeded()
        }
    }

    private func loadImageIfNeeded() {
        guard loadedImage == nil, let asset = itemData.asset else { return }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            if let image = image {
                DispatchQueue.main.async {
                    self.loadedImage = image
                }
            }
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    // Photo library data
    @State private var photos: [GridItemData] = []
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isLoadingPhotos: Bool = false

    // Image manager for loading photos
    private let imageManager = PHImageManager.default()
    private let thumbnailSize = CGSize(width: 300, height: 300)
    private let fullImageSize = CGSize(width: 1024, height: 1024)

    // Grid spacing configuration - single source of truth
    private let gridSpacing: CGFloat = 2.0 // Spacing between grid items
    private let itemPadding: CGFloat = 0.0 // Padding inside each grid item

    // Constants for zoom behavior
    private let fiveGridScale: CGFloat = 1.0
    private let threeGridScale: CGFloat = 5.0 / 3.0 // ~1.667
    private let resistanceMinScale: CGFloat = 0.7 // Soft minimum scale when zooming out with resistance
    private let resistanceMaxScale: CGFloat = 2.1 // Soft maximum scale when zooming in with resistance
    private let gridTransitionThreshold: CGFloat = 1.3 // Scale at which grids transition
    private let gridTransitionFadeRange: CGFloat = 0.6 // Range over which fade happens
    private let velocityThreshold: CGFloat = 0.05 // Minimum velocity for snap decisions
    private let snapThreshold: CGFloat = 1.05 // Scale threshold for snapping to 3-grid
    private let maxBlurRadius: CGFloat = 10.0 // Maximum blur radius during transitions

    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    @State private var anchor: UnitPoint = .center
    @State private var isZooming: Bool = false
    @State private var lastMagnification: CGFloat = 1.0
    @State private var blueScrollOffset: CGFloat = 0
    @State private var redScrollOffset: CGFloat = 0
    @State private var showRedGrid: Bool = false
    @State private var centerVisibleItem: Int = 0
    @State private var visibleItems: Set<Int> = []
    @State private var targetRedGridItem: Int = 0
    @State private var redGridCenterItem: Int = 0
    @State private var redGridVisibleItems: Set<Int> = []
    @State private var itemToMaintainOnZoomOut: Int? = nil
    @State private var blueGridScrollToItem: Int? = nil
    @State private var redGridScrollToItem: Int? = nil
    @State private var redGridTargetScale: CGFloat = 1.0
    @State private var blueGridOpacity: Double = 1.0
    @State private var redGridOpacity: Double = 0.0
    @State private var blueGridBlur: Double = 0.0
    @State private var redGridBlur: Double = 0.0
    @State private var gestureStarted: Bool = false
    @State private var initialTargetRedGridItem: Int? = nil

    // Expansion states
    @State private var selectedItem: Int? = nil
    @State private var showFullscreen: Bool = false
    @State private var expandedFromFiveGrid: Bool = true
    @State private var selectedItemFrame: CGRect = .zero
    @State private var itemFrames: [Int: CGRect] = [:]
    @State private var overlayOpacity: Double = 0.0
    @State private var overlayBlur: Double = 0.0
    @State private var currentPageItem: Int = 0

    // Image display mode
    @State private var useImageFill: Bool = true

    // Collapse/expand state
    @State private var isGridCollapsed: Bool = false
    @State private var gridCollapseScale: CGFloat = 1.0
    @State private var gridCollapseOpacity: Double = 1.0
    @State private var collapseButtonRotation: Double = 0
    @State private var gridCollapseBlur: Double = 0.0
    @State private var gridCollapseScaleX: CGFloat = 1.0
    @State private var gridCollapseScaleY: CGFloat = 1.0
    
    // Remove staggered animation states - no longer needed


    // Namespaces for animations
    @Namespace private var fiveGridNamespace
    @Namespace private var threeGridNamespace
    @Namespace private var collapseNamespace
    @Namespace private var gridCollapseNamespace

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 5)
    }

    var threeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
    }


    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Show loading or permission states
                if isLoadingPhotos {
                    VStack {
                        ProgressView("Loading photos...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                        Text("Please wait while we load your photo library")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Photo Library Access Required")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Please enable photo library access in Settings to view your photos.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                } else if photos.isEmpty && !isLoadingPhotos {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Photos Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Your photo library appears to be empty.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                } else {
                    ZStack {
                        // Original 5-column blue grid using UICollectionView
                        CollectionViewRepresentable(
                            photos: photos,
                            numberOfColumns: 5,
                            spacing: gridSpacing,
                            useImageFill: useImageFill,
                            isScrollEnabled: !isZooming,
                            currentScale: currentScale,
                            anchor: anchor,
                            opacity: blueGridOpacity,
                            blur: blueGridBlur,
                            onItemTapped: { item, globalFrame in
                                selectedItemFrame = globalFrame
                                selectedItem = item
                                currentPageItem = item
                                expandedFromFiveGrid = true
                                withAnimation(.smooth(duration: 0.39, extraBounce: 0.3)) {
                                    showFullscreen = true
                                }
                            },
                            onVisibleItemsChanged: { items, centerItem in
                                visibleItems = items
                                centerVisibleItem = centerItem
                            },
                            scrollToItem: $blueGridScrollToItem
                        )
                        .ignoresSafeArea(edges: .all)
                        .onChange(of: itemToMaintainOnZoomOut) { _, newValue in
                            if let item = newValue, !showRedGrid {
                                blueGridScrollToItem = item
                            }
                        }

                        // 3-column red grid overlay using UICollectionView
                        CollectionViewRepresentable(
                            photos: photos,
                            numberOfColumns: 3,
                            spacing: gridSpacing,
                            useImageFill: useImageFill,
                            isScrollEnabled: !isZooming && redGridOpacity > 0.5,
                            currentScale: redGridTargetScale,
                            anchor: anchor,
                            opacity: redGridOpacity,
                            blur: redGridBlur,
                            onItemTapped: { item, globalFrame in
                                selectedItemFrame = globalFrame
                                selectedItem = item
                                currentPageItem = item
                                expandedFromFiveGrid = false
                                withAnimation(.smooth(duration: 0.39, extraBounce: 0.3)) {
                                    showFullscreen = true
                                }
                            },
                            onVisibleItemsChanged: { items, centerItem in
                                if redGridOpacity > 0.5 {
                                    redGridVisibleItems = items
                                    redGridCenterItem = centerItem
                                }
                            },
                            scrollToItem: $redGridScrollToItem
                        )
                        .ignoresSafeArea(edges: .all)
                        .allowsHitTesting(redGridOpacity > 0.5 && !isZooming)
                        .onAppear {
                            redGridScrollToItem = targetRedGridItem
                        }
                        .onChange(of: targetRedGridItem) { _, newValue in
                            if showRedGrid {
                                redGridScrollToItem = newValue
                            }
                        }
                    }
                    .blur(radius: gridCollapseBlur)
                    .scaleEffect(x: gridCollapseScaleX, y: gridCollapseScaleY, anchor: .trailing)
                    .scaleEffect(gridCollapseScale, anchor: .bottomLeading)
                    .opacity(gridCollapseOpacity)
                    .allowsHitTesting(!isGridCollapsed)
                } // End of else block for photo states

            } // End of main ZStack
            .highPriorityGesture(
                MagnificationGesture(minimumScaleDelta: 0)
                    .onChanged { magnification in
                        // Start gesture on any change
                        if !gestureStarted {
                            gestureStarted = true
                            isZooming = true
                            lastMagnification = currentScale

                            // Pre-calculate target item for red grid if zooming in
                            if finalScale <= fiveGridScale && magnification > 1.0 {
                                initialTargetRedGridItem = centerVisibleItem
                            }
                        }

                        // Calculate raw scale first
                        _ = finalScale * magnification

                        // Apply resistance based on scale values, independent of grid state
                        let targetScale = finalScale * magnification

                        // Resistance for zooming out when 5-grid scale < 1.0
                        if targetScale < fiveGridScale {
                            // How far below 1.0 we're trying to go (0 to 1)
                            let overshoot = (fiveGridScale - targetScale) / fiveGridScale

                            // Smooth exponential resistance that increases gradually
                            let resistance = 1.0 - exp(-overshoot * 3.0)

                            // Apply resistance smoothly
                            currentScale = fiveGridScale - (fiveGridScale - targetScale) * (1.0 - resistance * 0.7)
                        }
                        // Resistance for zooming in when 3-grid scale > 1.0
                        else if targetScale > threeGridScale {
                            // How far beyond 3-grid scale we're trying to go
                            let overshoot = (targetScale - threeGridScale) / threeGridScale

                            // Smooth exponential resistance that increases gradually
                            let resistance = 1.0 - exp(-overshoot * 3.0)

                            // Apply resistance smoothly
                            currentScale = threeGridScale + (targetScale - threeGridScale) * (1.0 - resistance * 0.7)
                        } else {
                            // Normal scaling in the allowed range
                            currentScale = targetScale
                        }

                        // Update grid visibility during zoom
                        // Calculate opacity and blur based on scale
                        if currentScale < gridTransitionThreshold - gridTransitionFadeRange/2 {
                            blueGridOpacity = 1.0
                            redGridOpacity = 0.0
                            blueGridBlur = 0.0
                            redGridBlur = maxBlurRadius
                        } else if currentScale > gridTransitionThreshold + gridTransitionFadeRange/2 {
                            blueGridOpacity = 0.0
                            redGridOpacity = 1.0
                            blueGridBlur = maxBlurRadius
                            redGridBlur = 0.0
                        } else {
                            // In transition zone
                            let progress = (currentScale - (gridTransitionThreshold - gridTransitionFadeRange/2)) / gridTransitionFadeRange
                            blueGridOpacity = 1.0 - progress
                            redGridOpacity = progress
                            blueGridBlur = progress * maxBlurRadius
                            redGridBlur = (1.0 - progress) * maxBlurRadius
                        }

                        // Use pre-calculated target item or update based on transition
                        if redGridOpacity > 0.3 && !showRedGrid {
                            targetRedGridItem = initialTargetRedGridItem ?? centerVisibleItem
                            showRedGrid = true
                        } else if redGridOpacity < 0.3 && showRedGrid {
                            itemToMaintainOnZoomOut = redGridCenterItem
                            showRedGrid = false
                        }

                        // Update red grid scale during gesture
                        redGridTargetScale = currentScale * 3 / 5
                    }
                    .onEnded { _ in
                        isZooming = false
                        finalScale = currentScale
                        gestureStarted = false
                        initialTargetRedGridItem = nil

                        // Calculate velocity (change in scale)
                        let velocity = currentScale - lastMagnification

                        // Determine target scale based on velocity and current scale
                        var targetScale: CGFloat = fiveGridScale

                        if abs(velocity) > velocityThreshold { // If there's significant velocity
                            if velocity > 0 && currentScale > 1.02 { // Zooming in - very low threshold
                                targetScale = threeGridScale
                            } else { // Zooming out or small scale
                                targetScale = fiveGridScale
                            }
                        } else { // No significant velocity, snap to nearest
                            // Very low snap threshold
                            if currentScale >= 1.02 {
                                targetScale = threeGridScale
                            } else {
                                targetScale = fiveGridScale
                            }
                        }

                        // Set anchor to center for simplicity
                        let targetAnchor: UnitPoint = targetScale == threeGridScale ? anchor : .center

                        withAnimation(.smooth(duration: 0.39)) {
                            currentScale = targetScale
                            finalScale = targetScale
                            anchor = targetAnchor

                            // Set final opacity and blur values
                            if targetScale == fiveGridScale {
                                blueGridOpacity = 1.0
                                redGridOpacity = 0.0
                                blueGridBlur = 0.0
                                redGridBlur = maxBlurRadius
                                showRedGrid = false
                            } else {
                                blueGridOpacity = 0.0
                                redGridOpacity = 1.0
                                blueGridBlur = maxBlurRadius
                                redGridBlur = 0.0
                                redGridTargetScale = 1.0
                                showRedGrid = true
                            }
                        }
                    }
            )
            .animation(isZooming ? nil : .smooth(duration: 0.24), value: currentScale)
            .animation(isZooming ? nil : .smooth(duration: 0.39), value: redGridTargetScale)
            .animation(isZooming ? nil : .smooth(duration: 0.5), value: blueGridOpacity)
            .animation(isZooming ? nil : .smooth(duration: 0.5), value: redGridOpacity)
            .animation(isZooming ? nil : .smooth(duration: 0.5), value: blueGridBlur)
            .animation(isZooming ? nil : .smooth(duration: 0.5), value: redGridBlur)

            // Fullscreen overlay
            if let item = selectedItem {
                ZStack {
                    // Background
                    Color.black
                        .opacity(showFullscreen ? 0.9 : 0)
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.3), value: showFullscreen)
                        .onTapGesture {
                            // Keep the existing frame for animation back

                            withAnimation(.smooth(duration: 0.39, extraBounce: 0.3)) {
                                showFullscreen = false
                            }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                selectedItem = nil
                            }
                        }

                    // Animated square that transitions from grid to fullscreen
                    GeometryReader { geo in
                        let maxWidth = geo.size.width - 40
                        let maxHeight = geo.size.height - 100

                        // Calculate expanded size based on current page item
                        let expandedItemData = getItemData(for: currentPageItem)
                        let expandedWidth = min(maxWidth, maxHeight / expandedItemData.aspectRatio)
                        let expandedHeight = expandedWidth * expandedItemData.aspectRatio

                        if showFullscreen {
                            // Horizontal ScrollView with paging
                            ScrollViewReader { scrollProxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 0) {
                                        // Only render items within a range to improve performance
                                        let startIndex = max(0, item - 50)
                                        let endIndex = min(photos.count, item + 50)
                                        ForEach(startIndex..<endIndex, id: \.self) { index in
                                            let itemData = getItemData(for: index)
                                            ZStack {
                                                let itemWidth = min(maxWidth, maxHeight / itemData.aspectRatio)
                                                let itemHeight = itemWidth * itemData.aspectRatio

                                                PhotoGridImage(itemData: itemData, targetSize: fullImageSize, contentMode: .fit)
                                                    .cornerRadius(expandedFromFiveGrid ? 7 : 10)
                                                    .frame(width: itemWidth, height: itemHeight)
                                                    .onTapGesture {
                                                        // Keep the existing frame for animation back

                                                        withAnimation(.smooth(duration: 0.39, extraBounce: 0.3)) {
                                                            showFullscreen = false
                                                        }
                                                        Task { @MainActor in
                                                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                                            selectedItem = nil
                                                        }
                                                    }
                                            }
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .id(index)
                                            .onAppear {
                                                if abs(Double(index) - Double(currentPageItem)) < 2 {
                                                    currentPageItem = index
                                                }
                                            }
                                        }
                                    }
                                }
                                .scrollTargetBehavior(.paging)
                                .scrollTargetLayout()
                                .onAppear {
                                    scrollProxy.scrollTo(item, anchor: .center)
                                }
                            }
                        }

                        // Animated transition square
                        let itemData = getItemData(for: currentPageItem)
                        RoundedRectangle(cornerRadius: expandedFromFiveGrid ? 7 : 10)
                            .fill(Color.clear)
                            .frame(
                                width: showFullscreen ? expandedWidth : selectedItemFrame.width,
                                height: showFullscreen ? expandedHeight : selectedItemFrame.height
                            )
                            .overlay(
                                PhotoGridImage(itemData: itemData, targetSize: fullImageSize, contentMode: useImageFill ? .fill : .fit)
                                    .cornerRadius(useImageFill ? 0 : (expandedFromFiveGrid ? 7 : 10))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: expandedFromFiveGrid ? 7 : 10))
                            .position(
                                x: showFullscreen ? geo.size.width / 2 : selectedItemFrame.midX,
                                y: showFullscreen ? geo.size.height / 2 : selectedItemFrame.midY
                            )
                            .opacity(showFullscreen ? 0 : 1)
                            .animation(.smooth(duration: 0.39, extraBounce: 0.3), value: showFullscreen)
                    }
                }
                .zIndex(1000)
                .allowsHitTesting(selectedItem != nil)
            }

            // Toggle overlay at the bottom
            VStack {
                Spacer()
                HStack {
                    // Collapse button in bottom left
                    ZStack {
                        if isGridCollapsed {
                            Circle()
                                .fill(.regularMaterial)
                                .frame(width: 50, height: 50)
                                .matchedGeometryEffect(id: "gridContent", in: gridCollapseNamespace)
                        }

                        Button(action: {
                            let targetCollapsed = !isGridCollapsed
                            let duration = targetCollapsed ? 0.55 : 0.45
                            
                            // Animate grid-level effects
                            withAnimation(.smooth(duration: duration, extraBounce: 0.2)) {
                                isGridCollapsed = targetCollapsed
                                collapseButtonRotation = targetCollapsed ? 180 : 0
                                gridCollapseScale = targetCollapsed ? 0.1 : 1.0
                                gridCollapseOpacity = targetCollapsed ? 0 : 1.0
                                gridCollapseBlur = targetCollapsed ? 30 : 0
                                gridCollapseScaleX = targetCollapsed ? 0.3 : 1.0
                                gridCollapseScaleY = targetCollapsed ? 0.5 : 1.0
                            }
                            
                            // No staggered animations - just grid-level effects
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.regularMaterial)
                                    .frame(width: 50, height: 50)

                                Image(systemName: isGridCollapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.primary)
                                    .rotationEffect(.degrees(collapseButtonRotation))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 30)

                    Spacer()

                    VStack(spacing: 16) {
                        // Show limited access notice if applicable
                        if authorizationStatus == .limited && !photos.isEmpty {
                            HStack {
                                Image(systemName: "info.circle")
                                Text("\(photos.count) photos available with limited access")
                                    .font(.system(size: 14))
                                Button("Select More") {
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let rootViewController = windowScene.windows.first?.rootViewController {
                                        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
                                    }
                                }
                                .font(.system(size: 14, weight: .medium))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                        }

                        Button(action: {
                            withAnimation(.smooth(duration: 0.3)) {
                                useImageFill.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: useImageFill ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                                Text(useImageFill ? "Fill" : "Fit")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.bottom, 30)

                    Spacer()
                }
            }
            .ignoresSafeArea()
            .onAppear {
                checkPhotoLibraryAuthorization()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Reload photos when app becomes active in case user changed selection
                if authorizationStatus == .limited {
                    loadPhotosFromLibrary()
                }
            }
        } // End of GeometryReader
        .ignoresSafeArea()
    }

    func getItemData(for index: Int) -> GridItemData {
        guard index >= 0 && index < photos.count else {
            // Return a placeholder if index is out of bounds
            return GridItemData(image: UIImage(systemName: "photo")!, id: "placeholder-\(index)")
        }
        return photos[index]
    }

    func getRedGridPosition(geometry: GeometryProxy) -> CGPoint {
        let baseX = geometry.size.width / 2
        let baseY = geometry.size.height / 2

        // Adjust position based on anchor
        var offsetX: CGFloat = 0
        if anchor.x <= 0.0 {
            // Left anchor - align red grid to left
            offsetX = -(geometry.size.width * 1 / 5)
        } else if anchor.x >= 1.0 {
            // Right anchor - align red grid to right
            offsetX = geometry.size.width * 1 / 5
        }
        // Center anchor (0.5) needs no offset

        return CGPoint(x: baseX + offsetX, y: baseY)
    }

    // These functions are now handled by the UICollectionView internally
    
    // Removed animation functions - no longer needed

    // MARK: - Photo Library Methods

    func checkPhotoLibraryAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = status

        switch status {
        case .authorized, .limited:
            loadPhotosFromLibrary()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.authorizationStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        self.loadPhotosFromLibrary()
                    }
                }
            }
        case .denied, .restricted:
            // Handle denied access - user will see empty grid
            break
        @unknown default:
            break
        }
    }

    func loadPhotosFromLibrary() {
        isLoadingPhotos = true

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var loadedPhotos: [GridItemData] = []

        fetchResult.enumerateObjects { asset, _, _ in
            loadedPhotos.append(GridItemData(asset: asset))
        }

        DispatchQueue.main.async {
            self.photos = loadedPhotos
            self.isLoadingPhotos = false
        }
    }
}
