// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Drives a GSEngine offline in audio-callback-sized blocks, so tests can
// change parameters between blocks exactly as the UI would during playback.

import GawdDSP

final class EngineRig {
    let engine: OpaquePointer
    private let source: [UnsafeMutableBufferPointer<Float>]
    private var sourcePointers: [UnsafePointer<Float>?]
    private(set) var output: [[Float]] = [[], []]
    let block: Int

    init(source planar: [[Float]], block: Int = testBlock) {
        self.block = block
        engine = gs_engine_create(testSampleRate, 2, Int32(block))!
        source = planar.map { samples in
            let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: samples.count)
            _ = buffer.initialize(from: samples)
            return buffer
        }
        sourcePointers = source.map { UnsafePointer($0.baseAddress) }
        sourcePointers.withUnsafeBufferPointer {
            gs_engine_set_source(engine, $0.baseAddress!, Int32(source.count), Int64(planar[0].count))
        }
    }

    deinit {
        gs_engine_destroy(engine)
        source.forEach { $0.deallocate() }
    }

    /// Frames rendered so far.
    var frames: Int { output[0].count }

    /// Renders `seconds` more audio, a block at a time.
    func render(seconds: Double) {
        let total = Int(seconds * testSampleRate)
        var left = [Float](repeating: 0, count: block), right = left
        var done = 0
        while done < total {
            let n = min(block, total - done)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    var pointers: [UnsafeMutablePointer<Float>?] = [l.baseAddress, r.baseAddress]
                    pointers.withUnsafeMutableBufferPointer { gs_engine_render(engine, $0.baseAddress!, Int32(n)) }
                }
            }
            output[0].append(contentsOf: left[0..<n])
            output[1].append(contentsOf: right[0..<n])
            done += n
        }
    }

    var position: Double { gs_engine_position(engine) }
}
