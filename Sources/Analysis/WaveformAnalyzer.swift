// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Min/max peaks for drawing the waveform. Phase 1 builds the overview only;
// the mip-mapped detail cache comes in Phase 2 (spec §5.5).

import Accelerate

struct WaveformPeaks: Equatable {
    /// One (min, max) pair per bin, across all channels.
    var minimums: [Float]
    var maximums: [Float]
    var count: Int { minimums.count }

    static let empty = WaveformPeaks(minimums: [], maximums: [])
}

enum WaveformAnalyzer {
    static func overview(of audio: SourceAudio, bins: Int = 4_000) -> WaveformPeaks {
        let frames = audio.frameCount
        let binCount = max(1, min(bins, frames))
        var minimums = [Float](repeating: 0, count: binCount)
        var maximums = [Float](repeating: 0, count: binCount)
        for b in 0..<binCount {
            let start = frames * b / binCount
            let length = max(1, frames * (b + 1) / binCount - start)
            var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
            for channel in audio.channels {
                var cmin: Float = 0, cmax: Float = 0
                vDSP_minv(channel.baseAddress! + start, 1, &cmin, vDSP_Length(length))
                vDSP_maxv(channel.baseAddress! + start, 1, &cmax, vDSP_Length(length))
                lo = min(lo, cmin)
                hi = max(hi, cmax)
            }
            minimums[b] = lo
            maximums[b] = hi
        }
        return WaveformPeaks(minimums: minimums, maximums: maximums)
    }
}
