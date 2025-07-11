//
//  Extensions.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import Foundation

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}