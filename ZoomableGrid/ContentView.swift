//
//  ContentView.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/5/25.
//

import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
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
                                Rectangle()
                                    .fill(Color.blue)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(
                                        Text("\(item)")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                    )
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
                        .padding(3)
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
                .scrollDisabled(isZooming)
                .scaleEffect(currentScale, anchor: anchor)
                .opacity(showRedGrid ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: showRedGrid)
                
                // 3-column red grid overlay
                ScrollView {
                    ScrollViewReader { scrollProxy in
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 3),
                                GridItem(.flexible(), spacing: 3),
                                GridItem(.flexible(), spacing: 3)
                            ], spacing: 3) {
                                ForEach(0..<200) { item in
                                    Rectangle()
                                        .fill(item == targetRedGridItem ? Color.green : Color.red)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay(
                                            Text("\(item)")
                                                .foregroundColor(.white)
                                                .font(.caption)
                                        )
                                        .id(item)
                                        .onAppear {
                                            if showRedGrid {
                                                redGridVisibleItems.insert(item)
                                                updateRedGridCenterItem()
                                            }
                                        }
                                        .onDisappear {
                                            redGridVisibleItems.remove(item)
                                            if showRedGrid {
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
                .scrollDisabled(isZooming || !showRedGrid)
                .allowsHitTesting(showRedGrid)
                .scaleEffect(currentScale * 3 / 5, anchor: anchor)
                .opacity(showRedGrid ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showRedGrid)
            }
            .gesture(
                MagnificationGesture()
                    .simultaneously(with: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        if let magnification = value.first {
                            lastMagnification = currentScale
                            currentScale = finalScale * magnification
                            isZooming = magnification != 1.0
                            
                            // Update grid visibility during zoom
                            let zoomThreshold: CGFloat = 1.3
                            
                            if currentScale >= zoomThreshold && !showRedGrid {
                                // Capture the current center item BEFORE showing the red grid
                                targetRedGridItem = centerVisibleItem
                                print("Capturing target item for red grid: \(targetRedGridItem)")
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showRedGrid = true
                                }
                            } else if currentScale < zoomThreshold && showRedGrid {
                                // When zooming out, use the red grid's center item
                                itemToMaintainOnZoomOut = redGridCenterItem
                                print("Zooming out - maintaining position for item: \(redGridCenterItem)")
                                
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showRedGrid = false
                                }
                            }
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
                            
                            if finalScale == 1.0 {
                                anchor = UnitPoint(x: x, y: y)
                            }
                        }
                    }
                    .onEnded { value in
                        isZooming = false
                        finalScale = currentScale
                        
                        // Calculate velocity (change in scale)
                        let velocity = currentScale - lastMagnification
                        
                        // Scale where 3 items fill the width (5 columns -> 3 columns visible)
                        let snapScale: CGFloat = 5.0 / 3.0
                        
                        // Determine target scale based on velocity and current scale
                        var targetScale: CGFloat = 1.0
                        var targetAnchor = anchor
                        
                        if abs(velocity) > 0.1 { // If there's significant velocity
                            if velocity > 0 && currentScale > 1.1 { // Zooming in
                                targetScale = snapScale
                            } else { // Zooming out or small scale
                                targetScale = 1.0
                            }
                        } else { // No significant velocity, snap to nearest
                            // Snap happens at 1.2
                            if currentScale >= 1.2 {
                                targetScale = snapScale
                            } else {
                                targetScale = 1.0
                            }
                        }
                        
                        // Calculate anchor for 3-column view
                        if targetScale == snapScale {
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
                            
                        }
                    }
            )
            .animation(.smooth(duration: 0.2), value: currentScale)
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
