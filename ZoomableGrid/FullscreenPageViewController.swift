//
//  FullscreenPageViewController.swift
//  ZoomableGrid
//
//  Created by Paul Wong on 7/11/25.
//

import SwiftUI
import UIKit

struct FullscreenPageViewController: UIViewControllerRepresentable {
    let photos: [GridItemData]
    @Binding var currentIndex: Int
    @Binding var isPresented: Bool
    let initialSourceFrame: CGRect
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.view.backgroundColor = .clear
        pageViewController.view.isUserInteractionEnabled = true
        
        // Set initial view controller
        if let initialVC = context.coordinator.makeViewController(at: currentIndex) {
            pageViewController.setViewControllers(
                [initialVC],
                direction: .forward,
                animated: false
            )
        }
        
        // Enable scroll view interaction and add vertical dismiss gesture
        for subview in pageViewController.view.subviews {
            if let scrollView = subview as? UIScrollView {
                scrollView.isScrollEnabled = true
                scrollView.isPagingEnabled = true
                
                // Add pan gesture for vertical dismissal
                let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDismissPan(_:)))
                panGesture.delegate = context.coordinator
                scrollView.addGestureRecognizer(panGesture)
            }
        }
        
        return pageViewController
    }
    
    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        // Update current page if changed externally
        if let currentVC = pageViewController.viewControllers?.first,
           let currentPageIndex = context.coordinator.getIndex(for: currentVC),
           currentPageIndex != currentIndex {
            
            if let targetVC = context.coordinator.makeViewController(at: currentIndex) {
                let direction: UIPageViewController.NavigationDirection = currentIndex > currentPageIndex ? .forward : .reverse
                pageViewController.setViewControllers(
                    [targetVC],
                    direction: direction,
                    animated: true
                )
            }
        }
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: FullscreenPageViewController
        private var isDismissing = false
        private var initialTouchPoint: CGPoint = .zero
        
        init(_ parent: FullscreenPageViewController) {
            self.parent = parent
        }
        
        func makeViewController(at index: Int) -> UIViewController? {
            guard index >= 0 && index < parent.photos.count else { return nil }
            
            let hostingController = UIHostingController(
                rootView: FullscreenImageView(
                    itemData: parent.photos[index],
                    isPresented: parent.$isPresented,
                    sourceFrame: index == parent.currentIndex ? parent.initialSourceFrame : .zero,
                    isCurrentPage: .constant(index == parent.currentIndex)
                )
            )
            hostingController.view.backgroundColor = .clear
            hostingController.view.tag = index
            hostingController.view.isUserInteractionEnabled = true
            
            return hostingController
        }
        
        func getIndex(for viewController: UIViewController) -> Int? {
            return viewController.view.tag
        }
        
        // MARK: - Dismissal Gesture Handling
        
        @objc func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            switch gesture.state {
            case .began:
                initialTouchPoint = gesture.location(in: gesture.view)
            case .changed:
                if abs(translation.y) > abs(translation.x) * 2 && !isDismissing {
                    isDismissing = true
                }
                
                if isDismissing {
                    // Handle vertical dismissal animation
                    _ = min(abs(translation.y) / 200.0, 1.0)
                    // You can notify the current page view controller here if needed
                }
            case .ended, .cancelled:
                if isDismissing && (abs(translation.y) > 100 || abs(velocity.y) > 500) {
                    // Trigger dismissal
                    parent.isPresented = false
                }
                isDismissing = false
            default:
                break
            }
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow simultaneous recognition with page view controller's pan gesture
            return true
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            
            let velocity = panGesture.velocity(in: panGesture.view)
            // Only begin if vertical velocity is significant
            return abs(velocity.y) > abs(velocity.x)
        }
        
        // MARK: - UIPageViewControllerDataSource
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = getIndex(for: viewController), index > 0 else { return nil }
            return makeViewController(at: index - 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = getIndex(for: viewController), index < parent.photos.count - 1 else { return nil }
            return makeViewController(at: index + 1)
        }
        
        // MARK: - UIPageViewControllerDelegate
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first,
                  let index = getIndex(for: currentVC) else { return }
            
            parent.currentIndex = index
            
            // Update isCurrentPage for all visible view controllers
            for vc in pageViewController.viewControllers ?? [] {
                if let hostingVC = vc as? UIHostingController<FullscreenImageView>,
                   let rootView = hostingVC.rootView as? FullscreenImageView {
                    hostingVC.rootView = FullscreenImageView(
                        itemData: rootView.itemData,
                        isPresented: parent.$isPresented,
                        sourceFrame: index == parent.currentIndex ? parent.initialSourceFrame : .zero,
                        isCurrentPage: .constant(vc == currentVC)
                    )
                }
            }
        }
    }
}