//
//  ContentView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/5/25.
//

import SwiftUI

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

struct GridItemData {
    let imageName: String
    let aspectRatio: CGFloat // width/height ratio
    
    static func generateRandomItem(for index: Int) -> GridItemData {
        let imageNames = ["LR-1787", "LR-1788", "LR-1789"]
        
        // Simple hash function for better distribution
        let hash = (index &* 2654435761) % imageNames.count
        let imageIndex = abs(hash)
        
        // All images appear to be photos, so using standard photo aspect ratio
        let aspectRatio: CGFloat = 1.0
        
        return GridItemData(
            imageName: imageNames[imageIndex],
            aspectRatio: aspectRatio
        )
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    // Grid item data
    @State private var gridItemsData: [Int: GridItemData] = [:]
    
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
 
    
    // Namespaces for animations
    @Namespace private var fiveGridNamespace
    @Namespace private var threeGridNamespace

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 5)
    }
    
    var threeColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
    }


    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Original 5-column blue grid
                ScrollView {
                    ScrollViewReader { blueScrollProxy in
                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            ForEach(0..<9999) { item in
                                GeometryReader { itemGeo in
                                    ZStack {
                                        let itemData = getItemData(for: item)
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Color.clear)
                                            .frame(width: itemGeo.size.width - itemPadding * 2, height: itemGeo.size.height - itemPadding * 2)
                                            .overlay(
                                                Image(itemData.imageName)
                                                    .resizable()
                                                    .aspectRatio(contentMode: useImageFill ? .fill : .fit)
                                                    .cornerRadius(useImageFill ? 0 : 7)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 7))
                                            .position(x: itemGeo.size.width / 2, y: itemGeo.size.height / 2)
                                    }
                                    .onTapGesture {
                                        let globalFrame = itemGeo.frame(in: .global)
                                        selectedItemFrame = globalFrame
                                        selectedItem = item
                                        currentPageItem = item
                                        expandedFromFiveGrid = true
                                        withAnimation(.smooth(duration: 0.39, extraBounce: 0.3)) {
                                            showFullscreen = true
                                        }
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .id(item)
                                .onAppear {
                                    visibleItems.insert(item)
                                    updateCenterFromVisibleItems()
                                }
                                .onDisappear {
                                    visibleItems.remove(item)
                                    updateCenterFromVisibleItems()
                                }
                            }
                        }
                        .onChange(of: itemToMaintainOnZoomOut) { newValue in
                            if let item = newValue, !showRedGrid {
                                blueScrollProxy.scrollTo(item, anchor: .center)
                            }
                        }
                    }
                }
                .scrollClipDisabled(true)
                .scrollDisabled(isZooming)
                .scaleEffect(currentScale, anchor: anchor)
                .opacity(blueGridOpacity)
                .blur(radius: blueGridBlur)

                // 3-column red grid overlay
                ScrollView {
                    ScrollViewReader { scrollProxy in
                        LazyVGrid(columns: threeColumns, spacing: gridSpacing) {
                            ForEach(0..<9999) { item in
                                GeometryReader { itemGeo in
                                    ZStack {
                                        let itemData = getItemData(for: item)
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.clear)
                                            .frame(width: itemGeo.size.width - itemPadding * 2, height: itemGeo.size.height - itemPadding * 2)
                                            .overlay(
                                                Image(itemData.imageName)
                                                    .resizable()
                                                    .aspectRatio(contentMode: useImageFill ? .fill : .fit)
                                                    .cornerRadius(useImageFill ? 0 : 10)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .position(x: itemGeo.size.width / 2, y: itemGeo.size.height / 2)
                                    }
                                    .onTapGesture {
                                        let globalFrame = itemGeo.frame(in: .global)
                                        selectedItemFrame = globalFrame
                                        selectedItem = item
                                        currentPageItem = item
                                        expandedFromFiveGrid = false
                                        withAnimation(.smooth(duration: 0.39, extraBounce: 0.3)) {
                                            showFullscreen = true
                                        }
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .id(item)
                                .onAppear {
                                    if redGridOpacity > 0.5 {
                                        redGridVisibleItems.insert(item)
                                        updateRedGridCenterItem()
                                    }
                                }
                                .onDisappear {
                                    redGridVisibleItems.remove(item)
                                    if redGridOpacity > 0.5 {
                                        updateRedGridCenterItem()
                                    }
                                }
                            }
                        }
                        .onAppear {
                            // Scroll to target item without delay
                            scrollProxy.scrollTo(targetRedGridItem, anchor: .center)
                        }
                        .onChange(of: targetRedGridItem) { newValue in
                            if showRedGrid {
                                scrollProxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
                .scrollClipDisabled(true)
                .scrollDisabled(isZooming || redGridOpacity < 0.5)
                .allowsHitTesting(redGridOpacity > 0.5 && !isZooming)
                .scaleEffect(redGridTargetScale, anchor: anchor)
                .opacity(redGridOpacity)
                .blur(radius: redGridBlur)
            }
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
                        let rawScale = finalScale * magnification

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
                                        let endIndex = min(9999, item + 50)
                                        ForEach(startIndex..<endIndex) { index in
                                            let itemData = getItemData(for: index)
                                                ZStack {
                                                    let itemWidth = min(maxWidth, maxHeight / itemData.aspectRatio)
                                                    let itemHeight = itemWidth * itemData.aspectRatio
                                                    
                                                    Image(itemData.imageName)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
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
                                Image(itemData.imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: useImageFill ? .fill : .fit)
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
                    Spacer()
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
                    Spacer()
                }
                .padding(.bottom, 30)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Don't pre-generate all items - they'll be generated on demand
        }
    }

    func getItemData(for index: Int) -> GridItemData {
        if let existingData = gridItemsData[index] {
            return existingData
        }
        // Generate and cache the data
        let newData = GridItemData.generateRandomItem(for: index)
        gridItemsData[index] = newData
        return newData
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

    func updateCenterFromVisibleItems() {
        guard !visibleItems.isEmpty else { return }

        // Get all visible items sorted
        let sortedItems = visibleItems.sorted()

        // Group items by row
        var rowGroups: [Int: [Int]] = [:]
        for item in sortedItems {
            let row = item / 5
            if rowGroups[row] == nil {
                rowGroups[row] = []
            }
            rowGroups[row]?.append(item)
        }

        // Find the middle row
        let sortedRows = rowGroups.keys.sorted()
        guard !sortedRows.isEmpty else { return }

        let middleRowIndex = sortedRows.count / 2
        let middleRow = sortedRows[middleRowIndex]

        // Get the middle item from the middle row (prefer column 2)
        if let rowItems = rowGroups[middleRow] {
            // Try to find column 2 (middle column) in this row
            let targetItem = middleRow * 5 + 2
            let newCenterItem = rowItems.contains(targetItem) ? targetItem : rowItems[rowItems.count / 2]

            if newCenterItem != centerVisibleItem {
                centerVisibleItem = newCenterItem
            }
        }
    }

    func updateRedGridCenterItem() {
        guard !redGridVisibleItems.isEmpty else { return }

        // Get all visible items sorted
        let sortedItems = redGridVisibleItems.sorted()

        // Group items by row
        var rowGroups: [Int: [Int]] = [:]
        for item in sortedItems {
            let row = item / 3  // 3 columns for red grid
            if rowGroups[row] == nil {
                rowGroups[row] = []
            }
            rowGroups[row]?.append(item)
        }

        // Find the middle row
        let sortedRows = rowGroups.keys.sorted()
        guard !sortedRows.isEmpty else { return }

        let middleRowIndex = sortedRows.count / 2
        let middleRow = sortedRows[middleRowIndex]

        // Get the middle item from the middle row (prefer column 1 - middle column)
        if let rowItems = rowGroups[middleRow] {
            // Try to find column 1 (middle column) in this row
            let targetItem = middleRow * 3 + 1
            let newCenterItem = rowItems.contains(targetItem) ? targetItem : rowItems[rowItems.count / 2]

            if newCenterItem != redGridCenterItem {
                redGridCenterItem = newCenterItem
            }
        }
    }

}
