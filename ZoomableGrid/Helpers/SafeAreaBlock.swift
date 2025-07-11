//
//  SafeAreaBlock.swift
//  Whitebored
//
//  Created by Paul Wong on 7/11/24.
//

import SwiftUI

struct SafeAreaBlock: View {

    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.colorScheme) var colorScheme

    var height: CGFloat = 140
    var isTop: Bool
    var isDark: Bool = false
    var minimized: Bool = false

    var body: some View {
        VisualEffectView(effect: UIBlurEffect(style: isDark ? .systemMaterialLight : .systemUltraThinMaterial))
            .frame(
                width: 9999,
                height: height
            )
            .padding(.horizontal, -200)
            .blur(radius: 20)
            .contrast(isDark ? 1.3 : (colorScheme == .dark ? 1.03 : 0.93))
            .brightness(isDark ? -0.9 : 0)
            .offset(y: isTop ? -height/(minimized ? (isDark ? (sizeClass == .compact ? 1.5 : 1.1) : 2) : (sizeClass == .compact ? 4 : 3)) : (isDark ? height/4 : height/2.5))
    }
}


struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
}
