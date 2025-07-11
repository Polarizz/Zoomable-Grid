//
//  VerticalDragGesture.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI

struct VerticalDragGesture: UIViewRepresentable {
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void
    let isEnabled: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let panGesture = uiView.gestureRecognizers?.first as? UIPanGestureRecognizer {
            panGesture.isEnabled = isEnabled
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: VerticalDragGesture
        
        init(_ parent: VerticalDragGesture) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let dragSize = CGSize(width: translation.x, height: translation.y)
            
            switch gesture.state {
            case .changed:
                parent.onChanged(dragSize)
            case .ended:
                parent.onEnded(dragSize)
            default:
                break
            }
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            
            let velocity = panGesture.velocity(in: panGesture.view)
            // Only begin if vertical velocity is greater than horizontal
            return abs(velocity.y) > abs(velocity.x)
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Don't interfere with page view controller's pan gesture
            return false
        }
    }
}