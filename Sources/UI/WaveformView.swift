// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The overview waveform with the moving playhead; click or drag to seek.
// The playhead redraws at display rate from the engine's published position
// without invalidating anything else (spec §3: the UI polls).

import SwiftUI

struct WaveformView: View {
    let peaks: WaveformPeaks
    let duration: Double
    let position: () -> Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            TimelineView(.animation) { _ in
                let fraction = duration > 0 ? min(max(position() / duration, 0), 1) : 0
                Canvas { context, size in
                    draw(&context, size: size, playedFraction: fraction)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onSeek(seconds(atX: $0.location.x, width: size.width)) }
            )
        }
        .tip(HelpText.waveform)
        .accessibilityElement()
        .accessibilityLabel("Waveform")
        .accessibilityHint(HelpText.waveform)
    }

    private func seconds(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * duration
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, playedFraction: Double) {
        guard peaks.count > 0 else { return }
        let mid = size.height / 2
        let halfHeight = size.height / 2 * 0.92
        let columns = max(1, Int(size.width))
        let playedX = size.width * playedFraction

        var unplayed = Path(), played = Path()
        for column in 0..<columns {
            // Each pixel column covers a range of bins; take its extremes.
            let first = column * peaks.count / columns
            let last = max(first + 1, (column + 1) * peaks.count / columns)
            var lo: Float = 0, hi: Float = 0
            for bin in first..<min(last, peaks.count) {
                lo = min(lo, peaks.minimums[bin])
                hi = max(hi, peaks.maximums[bin])
            }
            let x = CGFloat(column) + 0.5
            let top = mid - CGFloat(hi) * halfHeight
            let bottom = mid - CGFloat(lo) * halfHeight
            let rect = CGRect(x: x - 0.5, y: top, width: 1, height: max(1, bottom - top))
            if x <= playedX { played.addRect(rect) } else { unplayed.addRect(rect) }
        }
        context.fill(unplayed, with: .color(Theme.waveform))
        context.fill(played, with: .color(Theme.waveformPlayed))

        var playhead = Path()
        playhead.addRect(CGRect(x: playedX - 1, y: 0, width: 2, height: size.height))
        context.fill(playhead, with: .color(Theme.playhead))
    }
}
