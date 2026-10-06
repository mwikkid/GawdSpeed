// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Waveform peaks at several resolutions (spec §5.5): min/max pairs at 256,
// 1024, 4096 and 16384 frames per bin, so any zoom draws from a table close
// to one bin per pixel. Cached in ~/Library/Caches/GawdSpeed by content.

import Accelerate
import CryptoKit
import Foundation

struct PeakPyramid {
    static let binSizes = [256, 1_024, 4_096, 16_384]

    struct Level {
        let framesPerBin: Int
        var minimums: [Float]
        var maximums: [Float]
    }

    let frameCount: Int
    let levels: [Level]

    /// Builds every level from planar audio (all channels folded together).
    init(channels: [UnsafeMutableBufferPointer<Float>], frameCount: Int) {
        self.frameCount = frameCount
        // Finest level straight from the samples; each coarser level from the one before.
        let first = Self.binSizes[0]
        let bins = (frameCount + first - 1) / first
        var minimums = [Float](repeating: 0, count: bins)
        var maximums = [Float](repeating: 0, count: bins)
        for b in 0..<bins {
            let start = b * first
            let length = min(first, frameCount - start)
            var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
            for channel in channels {
                var cmin: Float = 0, cmax: Float = 0
                vDSP_minv(channel.baseAddress! + start, 1, &cmin, vDSP_Length(length))
                vDSP_maxv(channel.baseAddress! + start, 1, &cmax, vDSP_Length(length))
                lo = min(lo, cmin)
                hi = max(hi, cmax)
            }
            minimums[b] = lo
            maximums[b] = hi
        }
        var levels = [Level(framesPerBin: first, minimums: minimums, maximums: maximums)]
        for size in Self.binSizes.dropFirst() {
            let previous = levels.last!
            let factor = size / previous.framesPerBin
            let count = (previous.minimums.count + factor - 1) / factor
            var lo = [Float](repeating: 0, count: count), hi = lo
            for b in 0..<count {
                let range = (b * factor)..<min((b + 1) * factor, previous.minimums.count)
                lo[b] = previous.minimums[range].min() ?? 0
                hi[b] = previous.maximums[range].max() ?? 0
            }
            levels.append(Level(framesPerBin: size, minimums: lo, maximums: hi))
        }
        self.levels = levels
    }

    private init(frameCount: Int, levels: [Level]) {
        self.frameCount = frameCount
        self.levels = levels
    }

    /// The coarsest level that still has at least one bin per pixel, or nil
    /// when even the finest is too coarse (then draw from the samples).
    func level(forFramesPerPixel framesPerPixel: Double) -> Level? {
        levels.last { Double($0.framesPerBin) <= framesPerPixel }
    }

    // MARK: Cache

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GawdSpeed", isDirectory: true)
    }

    private static func cacheURL(fingerprint: String, sampleRate: Double) -> URL {
        cacheDirectory.appendingPathComponent("\(fingerprint)-\(Int(sampleRate)).peaks")
    }

    static func cached(fingerprint: String, sampleRate: Double, frameCount: Int) -> PeakPyramid? {
        guard let data = try? Data(contentsOf: cacheURL(fingerprint: fingerprint, sampleRate: sampleRate)) else {
            return nil
        }
        var levels: [Level] = []
        var offset = 0
        for size in binSizes {
            let count = (frameCount + size - 1) / size
            let bytes = count * MemoryLayout<Float>.size
            guard offset + 2 * bytes <= data.count else { return nil }
            let lo = data[offset..<(offset + bytes)].withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            let hi = data[(offset + bytes)..<(offset + 2 * bytes)].withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            levels.append(Level(framesPerBin: size, minimums: lo, maximums: hi))
            offset += 2 * bytes
        }
        guard offset == data.count else { return nil }
        return PeakPyramid(frameCount: frameCount, levels: levels)
    }

    func store(fingerprint: String, sampleRate: Double) {
        var data = Data()
        for level in levels {
            level.minimums.withUnsafeBytes { data.append(contentsOf: $0) }
            level.maximums.withUnsafeBytes { data.append(contentsOf: $0) }
        }
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL(fingerprint: fingerprint, sampleRate: sampleRate), options: .atomic)
    }
}

enum FileFingerprint {
    /// Identifies a file by content, cheaply: SHA-256 of its size plus its
    /// first and last megabyte. Survives renames and moves; changes when the
    /// audio is edited. Keys the peak cache and per-song memory (spec §5.5, §5.9).
    static func of(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        let chunk: UInt64 = 1 << 20
        try? handle.seek(toOffset: 0)
        if let head = try? handle.read(upToCount: Int(min(chunk, size))) { hasher.update(data: head) }
        if size > chunk {
            try? handle.seek(toOffset: size - min(chunk, size - chunk))
            if let tail = try? handle.readToEnd() { hasher.update(data: tail) }
        }
        return hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
