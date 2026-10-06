// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The waveform (spec §5.5–5.6): an overview strip of the whole song with a
// box showing what the detail view shows, and the zoomable detail view with
// a time ruler, the highlighted section and its handles, and the playhead.
// Playheads redraw at display rate from the engine's published position.

import AppKit
import SwiftUI

// MARK: - Drawing

private enum WaveDraw {
    /// Fills one min/max bar per pixel column for `start ..< start+duration` seconds.
    static func bars(_ context: inout GraphicsContext, size: CGSize, pyramid: PeakPyramid?, audio: SourceAudio?,
                     start: Double, duration: Double, playedUntil: Double,
                     color: Color, playedColor: Color) {
        guard let audio, duration > 0, size.width > 0 else { return }
        let rate = audio.sampleRate
        let columns = Int(size.width.rounded(.up))
        let framesPerPixel = duration * rate / Double(size.width)
        let level = pyramid?.level(forFramesPerPixel: framesPerPixel)
        let mid = size.height / 2, half = size.height / 2 * 0.92

        var unplayed = Path(), played = Path()
        for column in 0..<columns {
            let t0 = start + Double(column) / Double(size.width) * duration
            let t1 = start + Double(column + 1) / Double(size.width) * duration
            let f0 = max(0, Int(t0 * rate)), f1 = min(audio.frameCount, max(Int(t1 * rate), f0 + 1))
            guard f0 < audio.frameCount else { break }
            var lo: Float = 0, hi: Float = 0
            if let level {
                let b0 = f0 / level.framesPerBin
                let b1 = min(level.minimums.count, max(b0 + 1, (f1 + level.framesPerBin - 1) / level.framesPerBin))
                for b in b0..<b1 {
                    lo = min(lo, level.minimums[b])
                    hi = max(hi, level.maximums[b])
                }
            } else {
                for channel in audio.channels {
                    for f in f0..<f1 {
                        lo = min(lo, channel[f])
                        hi = max(hi, channel[f])
                    }
                }
            }
            let top = mid - CGFloat(hi) * half
            let bottom = mid - CGFloat(lo) * half
            let rect = CGRect(x: CGFloat(column), y: top, width: 1, height: max(1, bottom - top))
            if t0 < playedUntil { played.addRect(rect) } else { unplayed.addRect(rect) }
        }
        context.fill(unplayed, with: .color(color))
        context.fill(played, with: .color(playedColor))
    }

    static func line(_ context: inout GraphicsContext, x: CGFloat, height: CGFloat, color: Color, width: CGFloat = 2) {
        context.fill(Path(CGRect(x: x - width / 2, y: 0, width: width, height: height)), with: .color(color))
    }
}

// MARK: - Overview strip

/// The whole song, with the detail view's window drawn as a box you can drag.
struct OverviewStrip: View {
    @Bindable var player: PlayerViewModel
    @State private var dragOffset: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            TimelineView(.animation) { _ in
                let position = player.livePosition()
                Canvas { context, size in
                    let duration = max(player.duration, 0.001)
                    if let selection = player.selection {
                        let x0 = CGFloat(selection.start / duration) * size.width
                        let x1 = CGFloat(selection.end / duration) * size.width
                        context.fill(Path(CGRect(x: x0, y: 0, width: max(1, x1 - x0), height: size.height)),
                                     with: .color(Theme.selection.opacity(player.loopEnabled ? 0.35 : 0.2)))
                    }
                    WaveDraw.bars(&context, size: size, pyramid: player.pyramid, audio: player.sourceAudio,
                                  start: 0, duration: duration, playedUntil: position,
                                  color: Theme.waveform, playedColor: Theme.waveformPlayed)
                    for region in player.regions { // saved regions: a bar along the top
                        let x0 = CGFloat(region.selection.start / duration) * size.width
                        let x1 = CGFloat(region.selection.end / duration) * size.width
                        context.fill(Path(roundedRect: CGRect(x: x0, y: 1, width: max(3, x1 - x0), height: 3), cornerRadius: 1.5),
                                     with: .color(Theme.accent.opacity(0.85)))
                    }
                    let box = CGRect(x: CGFloat(player.visibleStart / duration) * size.width, y: 0.5,
                                     width: max(4, CGFloat(player.visibleDuration / duration) * size.width),
                                     height: size.height - 1)
                    context.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(.white.opacity(0.55)), lineWidth: 1)
                    WaveDraw.line(&context, x: CGFloat(position / duration) * size.width, height: size.height,
                                  color: Theme.playhead, width: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let duration = max(player.duration, 0.001)
                        let t = Double(drag.location.x / width) * duration
                        if dragOffset == nil {
                            // Grab the box where it was clicked; a click outside centres it there.
                            let inside = t >= player.visibleStart && t <= player.visibleStart + player.visibleDuration
                            dragOffset = inside ? t - player.visibleStart : player.visibleDuration / 2
                        }
                        player.scrollView(by: (t - dragOffset!) - player.visibleStart)
                    }
                    .onEnded { _ in dragOffset = nil }
            )
        }
        .tip(HelpText.overview)
        .accessibilityElement()
        .accessibilityLabel("Song overview")
        .accessibilityHint(HelpText.overview)
    }
}

// MARK: - Detail view

struct DetailWaveform: View {
    @Bindable var player: PlayerViewModel

    private enum DragMode { case undecided, create(anchor: Double), resizeStart, resizeEnd, move(from: Double, original: Selection) }
    @State private var dragMode: DragMode?
    @State private var pinchBase: Double?
    @State private var hoverEdge = false
    static let rulerHeight: CGFloat = 16
    /// How close to a selection edge (points) a drag grabs the edge.
    private let edgeGrab: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            TimelineView(.animation) { _ in
                let position = player.livePosition()
                let start = viewStart(position)
                Canvas { context, size in
                    draw(&context, size: size, start: start, position: position)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: size.width))
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? player.visibleDuration
                        if pinchBase == nil { pinchBase = base }
                        let center = player.visibleStart + player.visibleDuration / 2
                        player.zoom(by: player.visibleDuration / (base / value.magnification), around: center)
                    }
                    .onEnded { _ in pinchBase = nil }
            )
            .onScrollWheel { event, location in
                let t = time(atX: location.x, width: size.width)
                if event.modifierFlags.contains(.command) {
                    player.zoom(by: pow(1.01, Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 8)),
                                around: t)
                } else {
                    // Horizontal (trackpad) or vertical (mouse wheel) both scroll through time.
                    let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                        ? event.scrollingDeltaX : event.scrollingDeltaY
                    let points = Double(delta) * (event.hasPreciseScrollingDeltas ? 1 : 10)
                    player.scrollView(by: -points / Double(size.width) * player.visibleDuration)
                }
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    let onEdge = edgeHit(x: location.x, width: size.width) != nil
                    if onEdge != hoverEdge {
                        hoverEdge = onEdge
                        if onEdge { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                } else if hoverEdge {
                    hoverEdge = false
                    NSCursor.pop()
                }
            }
            .contextMenu { contextMenu(width: size.width) }
        }
        .tip(HelpText.detail)
        .accessibilityElement()
        .accessibilityLabel("Waveform")
        .accessibilityHint(HelpText.detail)
    }

    /// Where the view starts this frame: follows smoothly while playing in
    /// smooth mode; otherwise the stored window (page mode flips it).
    private func viewStart(_ position: Double) -> Double {
        if player.followMode == .smooth, player.isPlaying, player.isFollowing {
            return player.smoothFollowStart(at: position)
        }
        return player.visibleStart
    }

    private func time(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return player.visibleStart + Double(x / width) * player.visibleDuration
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        CGFloat((time - player.visibleStart) / player.visibleDuration) * width
    }

    private enum Edge { case start, end }
    private func edgeHit(x: CGFloat, width: CGFloat) -> Edge? {
        guard let s = player.selection else { return nil }
        if abs(x - self.x(for: s.start, width: width)) <= edgeGrab { return .start }
        if abs(x - self.x(for: s.end, width: width)) <= edgeGrab { return .end }
        return nil
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let t = time(atX: drag.location.x, width: width)
                if dragMode == nil {
                    let t0 = time(atX: drag.startLocation.x, width: width)
                    switch edgeHit(x: drag.startLocation.x, width: width) {
                    case .start: dragMode = .resizeStart
                    case .end: dragMode = .resizeEnd
                    case nil:
                        if let s = player.selection, (s.start...s.end).contains(t0) {
                            dragMode = .move(from: t0, original: s)
                        } else {
                            dragMode = .undecided
                        }
                    }
                }
                switch dragMode {
                case .undecided:
                    // A drag shorter than 3 points is a click (seek), not a selection.
                    if abs(drag.translation.width) >= 3 {
                        let anchor = time(atX: drag.startLocation.x, width: width)
                        dragMode = .create(anchor: anchor)
                        player.setSelection(Selection(anchor, t), snap: false)
                    }
                case .create(let anchor):
                    player.setSelection(Selection(anchor, t), snap: false)
                case .resizeStart:
                    if let s = player.selection { player.setSelection(Selection(t, s.end), snap: false) }
                case .resizeEnd:
                    if let s = player.selection { player.setSelection(Selection(s.start, t), snap: false) }
                case .move(let from, let original):
                    if abs(drag.translation.width) >= 3 {
                        player.setSelection(original.moved(by: t - from, within: player.duration), snap: false)
                    }
                case nil:
                    break
                }
            }
            .onEnded { drag in
                switch dragMode {
                case .undecided:
                    // A click outside the highlighted section clears it (Earl:
                    // highlights were too hard to get rid of), then jumps there.
                    if player.selection != nil { player.clearSelection() }
                    player.seek(to: time(atX: drag.location.x, width: width))
                case .move(_, _) where abs(drag.translation.width) < 3:
                    player.seek(to: time(atX: drag.location.x, width: width))
                case .create, .resizeStart, .resizeEnd, .move:
                    player.finishSelectionEdit()
                case nil:
                    break
                }
                dragMode = nil
            }
    }

    @ViewBuilder private func contextMenu(width: CGFloat) -> some View {
        Button("Set Loop Start Here (I)") { player.setLoopIn() }
        Button("Set Loop End Here (O)") { player.setLoopOut() }
        Button(player.loopEnabled ? "Stop Looping (L)" : "Loop This Section (L)") { player.toggleLoop() }
            .disabled(player.selection == nil)
        Button("Export This Section…") { player.requestExport(selectionOnly: true) }
            .disabled(player.selection == nil)
        Divider()
        Button("Clear Selection (Esc)") { player.clearSelection() }
            .disabled(player.selection == nil)
        Button("Zoom to Fit") { player.zoomToFit() }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, start: Double, position: Double) {
        let duration = player.visibleDuration
        let ruler = Self.rulerHeight
        func xs(_ t: Double) -> CGFloat { CGFloat((t - start) / duration) * size.width }

        drawRuler(&context, width: size.width, start: start, duration: duration)

        // Highlighted section, behind the waveform.
        if let s = player.selection {
            let x0 = xs(s.start), x1 = xs(s.end)
            let rect = CGRect(x: x0, y: ruler, width: max(1, x1 - x0), height: size.height - ruler)
            context.fill(Path(rect), with: .color(Theme.selection.opacity(player.loopEnabled ? 0.28 : 0.16)))
            for edge in [x0, x1] {
                WaveDraw.line(&context, x: edge, height: size.height, color: Theme.selection, width: 2)
                let grip = CGRect(x: edge - 4, y: ruler, width: 8, height: 10)
                context.fill(Path(roundedRect: grip, cornerRadius: 2), with: .color(Theme.selection))
            }
        }

        var wave = context
        wave.translateBy(x: 0, y: ruler)
        WaveDraw.bars(&wave, size: CGSize(width: size.width, height: size.height - ruler), pyramid: player.pyramid,
                      audio: player.sourceAudio, start: start, duration: duration, playedUntil: position,
                      color: Theme.waveform, playedColor: Theme.waveformPlayed)

        WaveDraw.line(&context, x: xs(position), height: size.height, color: Theme.playhead)
    }

    private func drawRuler(_ context: inout GraphicsContext, width: CGFloat, start: Double, duration: Double) {
        // Pick a tick spacing that gives roughly one label per 90 points.
        let steps: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        let wanted = duration * 90 / Double(max(width, 1))
        let step = steps.first { $0 >= wanted } ?? 600
        var t = (start / step).rounded(.down) * step
        while t <= start + duration {
            let x = CGFloat((t - start) / duration) * width
            context.fill(Path(CGRect(x: x, y: Self.rulerHeight - 5, width: 1, height: 5)),
                         with: .color(Theme.secondaryText.opacity(0.6)))
            let label = Text(rulerLabel(t, step: step))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            context.draw(label, at: CGPoint(x: x + 3, y: 1), anchor: .topLeading)
            t += step
        }
    }

    /// mm:ss with as many decimals as the tick spacing needs (spec: mm:ss.ms).
    private func rulerLabel(_ t: Double, step: Double) -> String {
        let decimals = step >= 1 ? 0 : step >= 0.1 ? 1 : 2
        let minutes = Int(t) / 60
        let seconds = t - Double(minutes * 60)
        let width = decimals == 0 ? 2 : 3 + decimals
        return String(format: "%d:%0\(width).\(decimals)f", minutes, seconds)
    }
}

// MARK: - Scroll wheel

/// Scroll-wheel events over a view, with the pointer's location in the view.
/// Uses an app-level event monitor plus SwiftUI hover tracking rather than an
/// AppKit view, so it keeps working when the interface is scaled.
private struct ScrollWheelModifier: ViewModifier {
    let action: (NSEvent, CGPoint) -> Void
    @State private var location: CGPoint?
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                if case .active(let point) = phase { location = point } else { location = nil }
            }
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    guard let location else { return event }
                    action(event, location)
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (NSEvent, CGPoint) -> Void) -> some View {
        modifier(ScrollWheelModifier(action: action))
    }
}
