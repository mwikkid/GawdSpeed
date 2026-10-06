// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// A rotary knob (spec §5.4): drag up/down (⇧ for fine), scroll wheel,
// double-click or right-click to reset, arrow keys when focused.

import AppKit
import SwiftUI

struct Knob: View {
    let label: String
    @Binding var value: Double // 0...1, the knob's position
    let defaultValue: Double
    let valueText: String
    let help: String

    /// Dragging this far (points, at design size) sweeps the whole range.
    private let dragRange: CGFloat = 160
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Theme.panel)
                    .overlay(Circle().stroke(Theme.panelEdge, lineWidth: 1))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Theme.secondaryText.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(4)
                Circle()
                    .trim(from: 0, to: 0.75 * value)
                    .stroke(Theme.secondaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(4)
                Capsule()
                    .fill(Theme.primaryText)
                    .frame(width: 2.5, height: 9)
                    .offset(y: -9)
                    .rotationEffect(.degrees(-135 + 270 * value))
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        let fine = NSEvent.modifierFlags.contains(.shift) ? 0.1 : 1.0
                        value = clamp(start - Double(drag.translation.height / dragRange) * fine)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
            .onScrollWheel { delta in value = clamp(value + delta / 200) }
            .contextMenu { Button("Reset to Default") { value = defaultValue } }

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(valueText)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(value == defaultValue ? Theme.secondaryText : Theme.primaryText)
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityHint(help)
        .accessibilityAdjustableAction { direction in
            value = clamp(value + (direction == .increment ? 0.05 : -0.05))
        }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

// MARK: - Scroll wheel

private struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void

    final class View: NSView {
        var onScroll: ((Double) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 4 : event.scrollingDeltaY * 2
            onScroll?(Double(delta))
        }
        // Let clicks and drags fall through to the SwiftUI gestures.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }
    }

    func makeNSView(context: Context) -> View {
        let view = View()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: View, context: Context) { view.onScroll = onScroll }
}

extension View {
    func onScrollWheel(_ action: @escaping (Double) -> Void) -> some View {
        overlay(ScrollWheelCatcher(onScroll: action))
    }
}
