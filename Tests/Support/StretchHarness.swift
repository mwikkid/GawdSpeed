// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Offline driver for the stretchers: feeds an in-memory source through the C
// API exactly the way the audio callback will (fixed-size render blocks).

import Foundation
import GawdDSP

let testSampleRate = 48_000.0
let testBlock = 512

/// In-memory planar source that the C read callback pulls from.
final class SourceBox {
    let channels: [UnsafeMutableBufferPointer<Float>]
    let frames: Int

    init(_ planar: [[Float]]) {
        frames = planar[0].count
        channels = planar.map { samples in
            let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: samples.count)
            _ = buffer.initialize(from: samples)
            return buffer
        }
    }

    deinit { channels.forEach { $0.deallocate() } }

    func read(start: Int64, into dest: UnsafePointer<UnsafeMutablePointer<Float>?>, frames count: Int) {
        for (c, channel) in channels.enumerated() {
            guard let out = dest[c] else { continue }
            for i in 0..<count {
                let index = Int(start) + i
                out[i] = (index >= 0 && index < frames) ? channel[index] : 0
            }
        }
    }
}

private let readCallback: GSSourceRead = { context, start, dest, frames in
    guard let context, let dest else { return }
    Unmanaged<SourceBox>.fromOpaque(context).takeUnretainedValue()
        .read(start: start, into: dest, frames: Int(frames))
}

/// Algorithm A and B, by display name.
let allAlgorithms: [(name: String, algorithm: GSAlgorithm)] = [("A", GSAlgorithmA), ("B", GSAlgorithmB)]

/// Renders `outputFrames` frames of `source` through one stretcher.
func renderStretched(algorithm: GSAlgorithm,
                     source: [[Float]],
                     speed: Double,
                     transpose: Double = 0,
                     seekTo position: Int64 = 0,
                     outputFrames: Int,
                     block: Int = testBlock,
                     flags: UInt32 = 0) -> [[Float]] {
    let box = SourceBox(source)
    let channelCount = source.count
    guard let stretcher = gs_stretcher_create(algorithm, testSampleRate, Int32(channelCount), Int32(block),
                                              flags, readCallback,
                                              Unmanaged.passUnretained(box).toOpaque()) else {
        fatalError("gs_stretcher_create failed")
    }
    defer { gs_stretcher_destroy(stretcher) }

    gs_stretcher_set_speed(stretcher, speed)
    gs_stretcher_set_transpose(stretcher, transpose)
    gs_stretcher_seek(stretcher, position)

    let output = (0..<channelCount).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: outputFrames) }
    defer { output.forEach { $0.deallocate() } }
    var pointers: [UnsafeMutablePointer<Float>?] = output.map { $0 }

    var done = 0
    while done < outputFrames {
        let n = min(block, outputFrames - done)
        for c in 0..<channelCount { pointers[c] = output[c] + done }
        pointers.withUnsafeBufferPointer { gs_stretcher_render(stretcher, $0.baseAddress!, Int32(n)) }
        done += n
    }
    return output.map { Array(UnsafeBufferPointer(start: $0, count: outputFrames)) }
}

// MARK: - Test signals

func sine(frequency: Double, seconds: Double, amplitude: Float = 0.5, phase: Double = 0) -> [Float] {
    let frames = Int(seconds * testSampleRate)
    let w = 2 * Double.pi * frequency / testSampleRate
    return (0..<frames).map { amplitude * Float(sin(w * Double($0) + phase)) }
}

/// A sine that is on only between `on` and `off` seconds, with 1 ms ramps.
func gatedSine(frequency: Double, seconds: Double, on: Double, off: Double, amplitude: Float = 0.5) -> [Float] {
    let ramp = 0.001
    var samples = sine(frequency: frequency, seconds: seconds, amplitude: amplitude)
    for i in samples.indices {
        let t = Double(i) / testSampleRate
        let gain = max(0, min(1, (t - on) / ramp + 0.5, (off - t) / ramp + 0.5))
        samples[i] *= Float(gain)
    }
    return samples
}

func stereo(_ mono: [Float]) -> [[Float]] { [mono, mono] }
