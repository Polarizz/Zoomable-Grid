//
//  ContentView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/5/25.
//

import SwiftUI

struct GridItemData {
    let color: Color
    let aspectRatio: CGFloat // width/height ratio
    
    static func generateRandomItem() -> GridItemData {
        let colors: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .yellow, .indigo, .teal, .cyan, .mint, .brown]
        
        return GridItemData(
            color: colors.randomElement() ?? .blue,
            aspectRatio: CGFloat.random(in: 0.5...2.0) // From tall to wide rectangles
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
    
    // Constants for zoom behavior
    private let fiveGridScale: CGFloat = 1.0
    private let threeGridScale: CGFloat = 5.0 / 3.0 // ~1.667
    private let resistanceMinScale: CGFloat = 0.95 // Minimum scale when zooming out with resistance
    private let gridTransitionThreshold: CGFloat = 1.3 // Scale at which grids transition
    private let gridTransitionFadeRange: CGFloat = 0.2 // Range over which fade happens
    private let velocityThreshold: CGFloat = 0.1 // Minimum velocity for snap decisions
    private let snapThreshold: CGFloat = 1.1 // Scale threshold for snapping to 3-grid
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

    let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]


    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Original 5-column blue grid
                ScrollView {
                    ScrollViewReader { blueScrollProxy in
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(0..<200) { item in
                                ZStack {
                                    if let itemData = gridItemsData[item] {
                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(itemData.color)
                                                .aspectRatio(itemData.aspectRatio, contentMode: .fit)
                                                .frame(maxWidth: geo.size.width - 8, maxHeight: geo.size.height - 8)
                                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                        }
                                    }
                                    
                                    Text("\(item)")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(4)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
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
                        .onChange(of: showRedGrid) { newValue in
                            if !newValue && itemToMaintainOnZoomOut != nil {
                                // Blue grid is becoming visible, scroll to maintained item
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if let item = itemToMaintainOnZoomOut {
                                        print("Blue grid scrolling to maintained item: \(item)")
                                        blueScrollProxy.scrollTo(item, anchor: .center)
                                        itemToMaintainOnZoomOut = nil
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollClipDisabled(true)
                .scrollDisabled(isZooming)
                .scaleEffect(currentScale, anchor: anchor)
                .opacity(blueGridOpacity)
                .blur(radius: blueGridBlur)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: blueGridOpacity)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: blueGridBlur)

                // 3-column red grid overlay
                ScrollView {
                    ScrollViewReader { scrollProxy in
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 3),
                            GridItem(.flexible(), spacing: 3),
                            GridItem(.flexible(), spacing: 3)
                        ], spacing: 3) {
                            ForEach(0..<200) { item in
                                ZStack {
                                    if let itemData = gridItemsData[item] {
                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(itemData.color)
                                                .aspectRatio(itemData.aspectRatio, contentMode: .fit)
                                                .frame(maxWidth: geo.size.width - 8, maxHeight: geo.size.height - 8)
                                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                        }
                                    }
                                    
                                    Text("\(item)")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .padding(4)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
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
                        .padding(3)
                        .onAppear {
                            // Immediately scroll to the target item when red grid appears
                            print("Red grid appeared, scrolling to target item: \(targetRedGridItem)")
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo(targetRedGridItem, anchor: .center)
                            }
                        }
                        .onChange(of: showRedGrid) { newValue in
                            if newValue {
                                // Ensure scroll happens after grid is visible
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    print("Red grid visible, scrolling to target item: \(targetRedGridItem)")
                                    scrollProxy.scrollTo(targetRedGridItem, anchor: .center)
                                }
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
                .animation(.interactiveSpring(response: 0.39, dampingFraction: 0.9), value: redGridOpacity)
                .animation(.interactiveSpring(response: 0.39, dampingFraction: 0.9), value: redGridBlur)
            }
            .gesture(
                MagnificationGesture()
                    .simultaneously(with: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        if let magnification = value.first {
                            lastMagnification = currentScale

                            // Calculate raw scale first
                            let rawScale = finalScale * magnification

                            // Apply resistance when at or below scale 1.0, regardless of starting point
                            if rawScale <= fiveGridScale && magnification < 1.0 {
                                // Check if we started from above 1.0 or at 1.0
                                let baseScale = min(finalScale, fiveGridScale)

                                // Maximum zoom out is to resistanceMinScale
                                let maxZoomOut = baseScale - resistanceMinScale

                                // Calculate zoom out progress from base scale
                                let currentZoomOut = baseScale - rawScale
                                let maxPossibleZoomOut = baseScale * (1.0 - magnification)
                                let zoomProgress = currentZoomOut / maxPossibleZoomOut

                                // Apply sqrt to create resistance
                                let resistedProgress = sqrt(zoomProgress)

                                // Scale to our maximum zoom out range
                                let actualZoomOut = resistedProgress * maxZoomOut

                                currentScale = baseScale - actualZoomOut
                            } else {
                                // Normal scaling when above scale 1.0
                                currentScale = rawScale
                            }
                            isZooming = magnification != 1.0

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

                            // Capture target item when transitioning
                            if redGridOpacity > 0.3 && !showRedGrid {
                                targetRedGridItem = centerVisibleItem
                                showRedGrid = true
                                print("Capturing target item for red grid: \(targetRedGridItem)")
                            } else if redGridOpacity < 0.3 && showRedGrid {
                                itemToMaintainOnZoomOut = redGridCenterItem
                                showRedGrid = false
                                print("Zooming out - maintaining position for item: \(redGridCenterItem)")
                            }

                            // Update red grid scale during gesture
                            redGridTargetScale = currentScale * 3 / 5
                        }
                        if let location = value.second?.startLocation {
                            var x = location.x / geometry.size.width
                            var y = location.y / geometry.size.height


                            // Force anchor to be left, center, or right
                            if x < 0.33 {
                                x = 0.0
                            } else if x > 0.67 {
                                x = 1.0
                            } else {
                                x = 0.5
                            }

                            // For vertical, allow edge snapping
                            if y < 0.25 {
                                y = 0.0
                            } else if y > 0.75 {
                                y = 1.0
                            }

                            if finalScale == fiveGridScale {
                                anchor = UnitPoint(x: x, y: y)
                            }
                        }
                    }
                    .onEnded { value in
                        isZooming = false
                        finalScale = currentScale

                        // Calculate velocity (change in scale)
                        let velocity = currentScale - lastMagnification

                        // Determine target scale based on velocity and current scale
                        var targetScale: CGFloat = fiveGridScale
                        var targetAnchor = anchor

                        if abs(velocity) > velocityThreshold { // If there's significant velocity
                            if velocity > 0 && currentScale > 1.1 { // Zooming in
                                targetScale = threeGridScale
                            } else { // Zooming out or small scale
                                targetScale = fiveGridScale
                            }
                        } else { // No significant velocity, snap to nearest
                            // Snap happens at snapThreshold
                            if currentScale >= snapThreshold {
                                targetScale = threeGridScale
                            } else {
                                targetScale = fiveGridScale
                            }
                        }

                        // Calculate anchor for 3-column view
                        if targetScale == threeGridScale {
                            // Determine which anchor to use based on current position
                            let anchorX: CGFloat

                            if anchor.x < 0.33 {
                                // Left third - anchor to left edge
                                anchorX = 0.0
                            } else if anchor.x > 0.67 {
                                // Right third - anchor to right edge
                                anchorX = 1.0
                            } else {
                                // Middle third - anchor to center
                                anchorX = 0.5
                            }

                            // For vertical, keep current position unless at edges
                            let anchorY: CGFloat
                            if anchor.y <= 0.0 || anchor.y >= 1.0 {
                                anchorY = 0.5
                            } else {
                                anchorY = anchor.y
                            }

                            targetAnchor = UnitPoint(x: anchorX, y: anchorY)
                        } else {
                            // Return to normal view
                            targetAnchor = .center
                        }

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
            .animation(.smooth(duration: 0.24), value: currentScale)
            .animation(.smooth(duration: 0.39), value: redGridTargetScale)
        }
        .ignoresSafeArea()
        .onAppear {
            // Generate one random rectangle per grid item
            for i in 0..<200 {
                gridItemsData[i] = GridItemData.generateRandomItem()
            }
        }
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
                print("Center visible item updated to: \(newCenterItem) (row: \(middleRow))")
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
                print("Red grid center item updated to: \(newCenterItem) (row: \(middleRow))")
            }
        }
    }

    func updateRedGridScroll(scrollProxy: ScrollViewProxy, geometry: GeometryProxy) {
        // Simply scroll to the same item that's at the center of the blue grid
        let targetItem = centerVisibleItem
        print("Scrolling red grid to item: \(targetItem)")

        // Try without animation first to see if it works
        scrollProxy.scrollTo(targetItem, anchor: .center)

        // Then animate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollProxy.scrollTo(targetItem, anchor: .center)
            }
        }
    }
}
