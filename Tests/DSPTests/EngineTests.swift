// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The render engine: bypass transparency, clicks on every kind of live
// change, filters, end of song.

import GawdDSP
import XCTest

final class EngineTests: XCTestCase {
    private let tone = stereo(sine(frequency: 440, seconds: 30))

    /// Plays 1 s, makes `change`, plays 1 s more, and returns the click ratio
    /// around the change against the steady second before it.
    private func clickAround(_ change: (EngineRig) -> Void, setup: (EngineRig) -> Void = { _ in }) -> Double {
        let rig = EngineRig(source: tone)
        setup(rig)
        gs_engine_set_playing(rig.engine, true)
        rig.render(seconds: 1)
        let at = rig.frames
        change(rig)
        rig.render(seconds: 1)
        let ratios = rig.output.map {
            clickRatio($0, window: at..<(at + Int(0.5 * testSampleRate)),
                       reference: (at - Int(0.6 * testSampleRate))..<(at - Int(0.05 * testSampleRate)))
        }
        return ratios.max()!
    }

    private let paths: [(String, (EngineRig) -> Void)] = [
        ("bypass", { _ in }),
        ("A at 75%", { gs_engine_set_algorithm($0.engine, GSAlgorithmA); gs_engine_set_speed($0.engine, 0.75) }),
        ("B at 75%", { gs_engine_set_algorithm($0.engine, GSAlgorithmB); gs_engine_set_speed($0.engine, 0.75) }),
    ]

    /// At 100% with no transpose and the filters off, playback is the source,
    /// sample for sample (after the 10 ms fade-in).
    func testBypassIsBitTransparent() {
        let source = stereo(sine(frequency: 440, seconds: 3, amplitude: 0.3) .enumerated()
            .map { $0.element + 0.1 * Float(sin(Double($0.offset) * 0.37)) })
        let rig = EngineRig(source: source)
        gs_engine_set_playing(rig.engine, true)
        rig.render(seconds: 2)
        XCTAssertEqual(gs_engine_active_path(rig.engine), 0)
        let start = 1_000 // past the fade-in
        for c in 0..<2 {
            XCTAssertEqual(Array(rig.output[c][start..<rig.frames]), Array(source[c][start..<rig.frames]),
                           "channel \(c) differs from the source")
        }
    }

    /// Negative control for every click test here: a hard cut (no crossfade)
    /// between two renders of the same path, from different points in the
    /// song, must read as a click. If this ever passes as clean, the click
    /// tests cannot fail.
    func testMeterCatchesHardCutInEngineOutput() {
        for (name, setup) in paths {
            let renders = [Int64(0), Int64(10.0 * testSampleRate) + 13].map { start -> [Float] in
                let rig = EngineRig(source: tone)
                setup(rig)
                gs_engine_seek(rig.engine, start)
                gs_engine_set_playing(rig.engine, true)
                rig.render(seconds: 2)
                return rig.output[0]
            }
            let at = Int(testSampleRate)
            let spliced = Array(renders[0][..<at] + renders[1][at...])
            let ratio = clickRatio(spliced, window: at..<(at + Int(0.5 * testSampleRate)),
                                   reference: (at - Int(0.6 * testSampleRate))..<(at - Int(0.05 * testSampleRate)))
            print("CLICK control hard cut, \(name): \(ratio)")
            XCTAssertGreaterThan(ratio, clickThreshold, "hard cut, \(name): read only \(ratio)")
        }
    }

    func testSeekDoesNotClick() {
        for (name, setup) in paths {
            let ratio = clickAround({ gs_engine_seek($0.engine, Int64(10.0 * testSampleRate) + 13) }, setup: setup)
            print("CLICK seek, \(name): \(ratio)")
            XCTAssertLessThan(ratio, clickThreshold, "seek, \(name): click ratio \(ratio)")
        }
    }

    func testAlgorithmSwitchDoesNotClick() {
        let cases: [(String, (EngineRig) -> Void, (EngineRig) -> Void)] = [
            ("A to B", { gs_engine_set_algorithm($0.engine, GSAlgorithmA); gs_engine_set_speed($0.engine, 0.6) },
             { gs_engine_set_algorithm($0.engine, GSAlgorithmB) }),
            ("B to A", { gs_engine_set_algorithm($0.engine, GSAlgorithmB); gs_engine_set_speed($0.engine, 0.6) },
             { gs_engine_set_algorithm($0.engine, GSAlgorithmA) }),
            ("bypass to B", { _ in }, { gs_engine_set_speed($0.engine, 0.8) }),
            ("B to bypass", { gs_engine_set_speed($0.engine, 0.8) }, { gs_engine_set_speed($0.engine, 1.0) }),
            ("bypass to A (transpose)", { gs_engine_set_algorithm($0.engine, GSAlgorithmA) },
             { gs_engine_set_transpose($0.engine, 2) }),
        ]
        for (name, setup, change) in cases {
            let ratio = clickAround(change, setup: setup)
            print("CLICK \(name): \(ratio)")
            XCTAssertLessThan(ratio, clickThreshold, "\(name): click ratio \(ratio)")
        }
    }

    func testSpeedChangeDoesNotClick() {
        for (name, setup) in paths.dropFirst() {
            let ratio = clickAround({ gs_engine_set_speed($0.engine, 0.5) }, setup: setup)
            print("CLICK speed change, \(name): \(ratio)")
            XCTAssertLessThan(ratio, clickThreshold, "speed change, \(name): click ratio \(ratio)")
        }
    }

    func testPauseAndPlayDoNotClick() {
        for (name, setup) in paths {
            let pause = clickAround({ gs_engine_set_playing($0.engine, false) }, setup: setup)
            print("CLICK pause, \(name): \(pause)")
            XCTAssertLessThan(pause, clickThreshold, "pause, \(name): click ratio \(pause)")
        }
    }

    /// Switching each filter in and out, and moving it, while a tone plays.
    func testFilterMovesDoNotClick() {
        let cases: [(String, (EngineRig) -> Void, (EngineRig) -> Void)] = [
            ("high-pass on", { _ in }, { gs_engine_set_highpass($0.engine, 300) }),
            ("high-pass off", { gs_engine_set_highpass($0.engine, 300) }, { gs_engine_set_highpass($0.engine, 20) }),
            ("high-pass moved", { gs_engine_set_highpass($0.engine, 100) }, { gs_engine_set_highpass($0.engine, 1_500) }),
            ("low-pass on", { _ in }, { gs_engine_set_lowpass($0.engine, 2_000) }),
            ("low-pass off", { gs_engine_set_lowpass($0.engine, 2_000) }, { gs_engine_set_lowpass($0.engine, 20_000) }),
            ("low-pass moved", { gs_engine_set_lowpass($0.engine, 8_000) }, { gs_engine_set_lowpass($0.engine, 600) }),
        ]
        for (name, setup, change) in cases {
            let ratio = clickAround(change, setup: setup)
            print("CLICK \(name): \(ratio)")
            XCTAssertLessThan(ratio, clickThreshold, "\(name): click ratio \(ratio)")
        }
    }

    /// 24 dB/octave: a decade below a high-pass cutoff (or above a low-pass
    /// one) is about 80 dB down; two octaves into the passband is near 0 dB.
    func testFilterResponse() {
        func level(_ frequency: Double, highpass: Double = 20, lowpass: Double = 20_000) -> Double {
            let rig = EngineRig(source: stereo(sine(frequency: frequency, seconds: 3)))
            gs_engine_set_highpass(rig.engine, highpass)
            gs_engine_set_lowpass(rig.engine, lowpass)
            gs_engine_set_playing(rig.engine, true)
            rig.render(seconds: 2)
            let tail = Array(rig.output[0][Int(testSampleRate)...])
            let peak = tail.map { abs(Double($0)) }.max()!
            return 20 * log10(peak / 0.5)
        }
        XCTAssertLessThan(level(100, highpass: 1_000), -60)
        XCTAssertEqual(level(4_000, highpass: 1_000), 0, accuracy: 0.5)
        XCTAssertLessThan(level(10_000, lowpass: 1_000), -60)
        XCTAssertEqual(level(250, lowpass: 1_000), 0, accuracy: 0.5)
        // At the cutoff a Butterworth is 3 dB down.
        XCTAssertEqual(level(1_000, highpass: 1_000), -3.01, accuracy: 0.3)
    }

    func testPlaybackStopsAtEnd() {
        let rig = EngineRig(source: stereo(sine(frequency: 440, seconds: 1)))
        gs_engine_set_playing(rig.engine, true)
        rig.render(seconds: 1.2)
        XCTAssertTrue(gs_engine_reached_end(rig.engine))
        XCTAssertFalse(gs_engine_is_playing(rig.engine))
    }

    /// The published position tracks speed: 2 s of output at 50% advances 1 s.
    func testPositionTracksSpeed() {
        for algorithm in [GSAlgorithmA, GSAlgorithmB] {
            let rig = EngineRig(source: tone)
            gs_engine_set_algorithm(rig.engine, algorithm)
            gs_engine_set_speed(rig.engine, 0.5)
            gs_engine_seek(rig.engine, Int64(5 * testSampleRate))
            gs_engine_set_playing(rig.engine, true)
            rig.render(seconds: 2)
            rig.render(seconds: Double(testBlock) / testSampleRate) // publish happens at block start
            XCTAssertEqual(rig.position / testSampleRate, 6.0, accuracy: 0.02)
        }
    }
}
