// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III

import XCTest

final class SelectionTests: XCTestCase {
    func testSelectionOrdersAndClamps() {
        let s = Selection(5, 2)
        XCTAssertEqual(s.start, 2)
        XCTAssertEqual(s.end, 5)
        XCTAssertEqual(Selection(-1, 12).clamped(to: 10), Selection(0, 10))
    }

    func testMoveStopsAtTheEnds() {
        let s = Selection(2, 5)
        XCTAssertEqual(s.moved(by: 3, within: 10), Selection(5, 8))
        XCTAssertEqual(s.moved(by: 9, within: 10), Selection(7, 10))
        XCTAssertEqual(s.moved(by: -9, within: 10), Selection(0, 3))
    }

    func testParseTime() {
        XCTAssertEqual(parseTime("41.2"), 41.2)
        XCTAssertEqual(parseTime("0:41.2")!, 41.2, accuracy: 1e-9)
        XCTAssertEqual(parseTime("1:02:03"), 3723)
        XCTAssertNil(parseTime("1:75"))
        XCTAssertNil(parseTime("abc"))
        XCTAssertNil(parseTime(""))
    }

    /// Snapping finds the nearest sign change of a 100 Hz sine (crossings
    /// every 5 ms) and never moves a point more than 5 ms.
    func testSnapFindsNearestZeroCrossing() {
        let rate = 48_000.0
        let samples = (0..<48_000).map { Float(sin(2 * .pi * 100 * Double($0) / rate + 0.3)) }
        let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: samples.count)
        _ = buffer.initialize(from: samples)
        defer { buffer.deallocate() }
        for time in [0.1013, 0.25, 0.5021, 0.77777] {
            let snapped = ZeroCrossing.snap(time, channels: [buffer], frameCount: samples.count, sampleRate: rate)
            let i = Int((snapped * rate).rounded())
            XCTAssertLessThanOrEqual(abs(snapped - time), ZeroCrossing.searchSeconds + 1 / rate)
            XCTAssertLessThan(abs(samples[i]), 0.01, "snapped \(time) to \(snapped), value \(samples[i])")
        }
    }

    /// Silence has no crossing worth snapping to: the time is returned as is
    /// (a == 0 counts, so exact zeros return the nearest zero sample).
    func testSnapLeavesTimeAloneWithoutCrossings() {
        let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: 1_000)
        buffer.initialize(repeating: 0.5)
        defer { buffer.deallocate() }
        XCTAssertEqual(ZeroCrossing.snap(0.01, channels: [buffer], frameCount: 1_000, sampleRate: 48_000), 0.01)
    }
}

final class PeakPyramidTests: XCTestCase {
    private func buffer(_ samples: [Float]) -> UnsafeMutableBufferPointer<Float> {
        let b = UnsafeMutableBufferPointer<Float>.allocate(capacity: samples.count)
        _ = b.initialize(from: samples)
        return b
    }

    /// Every level's bins hold the true min/max of their frames, checked
    /// against a direct scan, and the cache returns the same tables.
    func testLevelsMatchDirectScanAndCacheRoundTrips() {
        var generator = SystemRandomNumberGenerator()
        let frames = 100_003 // not a multiple of any bin size
        let left = buffer((0..<frames).map { _ in Float.random(in: -1...1, using: &generator) })
        let right = buffer((0..<frames).map { _ in Float.random(in: -0.5...0.5, using: &generator) })
        defer { left.deallocate(); right.deallocate() }
        let pyramid = PeakPyramid(channels: [left, right], frameCount: frames)
        for level in pyramid.levels {
            for bin in [0, level.minimums.count / 2, level.minimums.count - 1] {
                let range = (bin * level.framesPerBin)..<min((bin + 1) * level.framesPerBin, frames)
                let lo = range.map { min(left[$0], right[$0]) }.min()!
                let hi = range.map { max(left[$0], right[$0]) }.max()!
                XCTAssertEqual(level.minimums[bin], lo, "level \(level.framesPerBin) bin \(bin)")
                XCTAssertEqual(level.maximums[bin], hi, "level \(level.framesPerBin) bin \(bin)")
            }
        }
        let key = "test-\(UUID().uuidString)"
        pyramid.store(fingerprint: key, sampleRate: 48_000)
        let loaded = PeakPyramid.cached(fingerprint: key, sampleRate: 48_000, frameCount: frames)
        XCTAssertEqual(loaded?.levels.map(\.maximums), pyramid.levels.map(\.maximums))
        XCTAssertNil(PeakPyramid.cached(fingerprint: key, sampleRate: 48_000, frameCount: frames + 999),
                     "a cache for a different length must not load")
    }

    func testLevelChoice() {
        let b = buffer([Float](repeating: 0, count: 50_000))
        defer { b.deallocate() }
        let pyramid = PeakPyramid(channels: [b], frameCount: 50_000)
        XCTAssertNil(pyramid.level(forFramesPerPixel: 100))
        XCTAssertEqual(pyramid.level(forFramesPerPixel: 300)?.framesPerBin, 256)
        XCTAssertEqual(pyramid.level(forFramesPerPixel: 5_000)?.framesPerBin, 4_096)
        XCTAssertEqual(pyramid.level(forFramesPerPixel: 1e9)?.framesPerBin, 16_384)
    }
}

final class SessionStoreTests: XCTestCase {
    func testRoundTripAndMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        let session = SongSession(speed: 0.75, semitones: -2, cents: 15, algorithm: "A", highpassKnob: 0.3,
                                  lowpassKnob: 0.8, selection: Selection(41.2, 48.75), loopEnabled: true,
                                  position: 44.0, visibleStart: 30, visibleDuration: 20)
        store.save(session, for: "abc123")
        XCTAssertEqual(store.load("abc123"), session)
        XCTAssertNil(store.load("nothing-here"))
    }

    /// The fingerprint follows content, not the name: a renamed copy matches,
    /// a one-byte edit does not.
    func testFingerprintFollowsContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var bytes = (0..<3_000_000).map { UInt8($0 % 251) }
        let a = directory.appendingPathComponent("a.wav"), b = directory.appendingPathComponent("renamed.wav")
        try Data(bytes).write(to: a)
        try Data(bytes).write(to: b)
        XCTAssertEqual(FileFingerprint.of(a), FileFingerprint.of(b))
        bytes[10] ^= 0xFF
        try Data(bytes).write(to: b)
        XCTAssertNotEqual(FileFingerprint.of(a), FileFingerprint.of(b))
    }
}

final class RegionPersistenceTests: XCTestCase {
    /// Sessions saved before regions existed must still load (regions = nil).
    func testOldSessionWithoutRegionsLoads() throws {
        let old = #"{"algorithm":"B","cents":0,"highpassKnob":0,"loopEnabled":false,"lowpassKnob":1,"position":3,"semitones":0,"speed":0.75,"visibleDuration":10,"visibleStart":0}"#
        let session = try JSONDecoder().decode(SongSession.self, from: Data(old.utf8))
        XCTAssertNil(session.regions)
        XCTAssertEqual(session.speed, 0.75)
    }

    func testRegionsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(directory: directory)
        var session = SongSession(speed: 1, semitones: 0, cents: 0, algorithm: "B", highpassKnob: 0, lowpassKnob: 1,
                                  selection: nil, loopEnabled: false, position: 0, visibleStart: 0, visibleDuration: 10)
        session.regions = [NamedRegion(name: "Bridge lick", selection: Selection(61.5, 66.25))]
        store.save(session, for: "regions")
        XCTAssertEqual(store.load("regions")?.regions?.first?.name, "Bridge lick")
    }
}
