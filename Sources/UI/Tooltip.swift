// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Hover tooltips drawn inside the interface (spec §5.11). SwiftUI's `.help()`
// places its tooltip from the unscaled layout, so once the window is scaled
// the tooltips land in the wrong place or not at all. These live in the scaled
// layout, so they follow the controls and scale with them.

import SwiftUI

@MainActor
@Observable
final class TooltipCenter {
    static let space = "tooltipSpace"
    static let delay: Duration = .milliseconds(600)

    private(set) var text: String?
    private(set) var anchor: CGRect = .zero
    @ObservationIgnored private var pending: Task<Void, Never>?

    func hover(_ text: String, over rect: CGRect, inside: Bool) {
        pending?.cancel()
        guard inside else {
            self.text = nil
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let self else { return }
            self.anchor = rect
            self.text = text
        }
    }

    func dismiss() {
        pending?.cancel()
        text = nil
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String
    @Environment(TooltipCenter.self) private var center
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { frame = geometry.frame(in: .named(TooltipCenter.space)) }
                        .onChange(of: geometry.frame(in: .named(TooltipCenter.space))) { _, new in frame = new }
                }
            )
            .onHover { center.hover(text, over: frame, inside: $0) }
            .simultaneousGesture(TapGesture().onEnded { center.dismiss() })
    }
}

extension View {
    /// A hover tooltip: what the control does in plain words, then its shortcut.
    func tip(_ text: String) -> some View { modifier(TooltipModifier(text: text)) }
}

/// Draws the current tooltip. Put it in an overlay over the whole layout,
/// in the `TooltipCenter.space` coordinate space.
struct TooltipLayer: View {
    let bounds: CGSize
    @Environment(TooltipCenter.self) private var center
    @State private var size: CGSize = .zero

    var body: some View {
        if let text = center.text {
            let gap: CGFloat = 6
            let below = center.anchor.maxY + gap + size.height <= bounds.height - 4
            let x = min(max(center.anchor.midX - size.width / 2, 6), bounds.width - size.width - 6)
            let y = below ? center.anchor.maxY + gap : center.anchor.minY - gap - size.height
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.2, green: 0.215, blue: 0.245)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { size = g.size }
                        .onChange(of: g.size) { _, new in size = new }
                })
                .offset(x: x, y: y)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
