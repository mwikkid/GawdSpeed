// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Loop/selection maths (spec §5.6), kept apart from the UI so it can be
// tested offline. Times are seconds of source time, never stretched time.

import Foundation

struct Selection: Equatable, Codable {
    var start: Double
    var end: Double

    /// Shortest selection the waveform will make from a drag (shorter is a click).
    static let minimumLength = 0.01

    init(_ a: Double, _ b: Double) {
        start = min(a, b)
        end = max(a, b)
    }

    var length: Double { end - start }

    func clamped(to duration: Double) -> Selection {
        Selection(min(max(start, 0), duration), min(max(end, 0), duration))
    }

    /// Slides the whole selection by `delta`, stopping at the song's ends.
    func moved(by delta: Double, within duration: Double) -> Selection {
        let shift = min(max(delta, -start), duration - end)
        return Selection(start + shift, end + shift)
    }
}

enum ZeroCrossing {
    /// How far snapping may move a point: 5 ms each way.
    static let searchSeconds = 0.005

    /// The zero crossing nearest `time` within ±5 ms, judged on the sum of
    /// the channels, or `time` itself if there is none.
    static func snap(_ time: Double, channels: [UnsafeMutableBufferPointer<Float>], frameCount: Int,
                     sampleRate: Double) -> Double {
        let center = Int((time * sampleRate).rounded())
        let reach = Int(searchSeconds * sampleRate)
        guard frameCount > 1, !channels.isEmpty else { return time }
        func value(_ i: Int) -> Float { channels.reduce(0) { $0 + $1[i] } }
        for distance in 0...reach {
            for i in [center - distance, center + distance] where i >= 0 && i + 1 < frameCount {
                let a = value(i), b = value(i + 1)
                if a == 0 { return Double(i) / sampleRate }
                if (a < 0) != (b < 0) {
                    // Between i and i+1: take the closer sample.
                    return Double(abs(a) <= abs(b) ? i : i + 1) / sampleRate
                }
            }
        }
        return time
    }
}

/// Parses a time typed into the loop in/out fields: "41.2", "0:41.2", "1:02:03".
func parseTime(_ text: String) -> Double? {
    let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
    guard !parts.isEmpty, parts.count <= 3 else { return nil }
    var total = 0.0
    for (index, part) in parts.enumerated() {
        guard let value = Double(part), value >= 0 else { return nil }
        if index < parts.count - 1, value != value.rounded() { return nil }
        if index > 0, value >= 60 { return nil }
        total = total * 60 + value
    }
    return total
}
