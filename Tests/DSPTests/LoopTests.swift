// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Seamless looping (spec §5.6, Phase 2 acceptance): the wrap lands on the
// loop-out frame, pre-roll restarts early, and five minutes of looping
// never clicks.

import GawdDSP
import XCTest

final class LoopTests: XCTestCase {
    private let rate = testSampleRate

    /// A silent source with single-sample clicks at the given frames, which
    /// show exactly where playback is in the output.
    private func markers(_ frames: [Int], length: Int) -> [[Float]] {
        var samples = [Float](repeating: 0, count: length)
        for f in frames { samples[f] = 1 }
        return stereo(samples)
    }

    private func outputIndices(of rig: EngineRig, above threshold: Float = 0.5) -> [Int] {
        rig.output[0].indices.filter { rig.output[0][$0] > threshold }
    }

    /// Bypass path (sample-exact): start at 1.0 s, loop [1.5 s, 2.0 s). A marker
    /// 30 ms into the loop (after the 10 ms crossfade) must appear first at
    /// 0.53 s of output, then again exactly one loop length later, every pass.
    func testWrapLandsOnLoopOutFrame() {
        let loopIn = Int(1.5 * rate), loopOut = Int(2.0 * rate)
        let marker = loopIn + Int(0.03 * rate)
        let rig = EngineRig(source: markers([marker], length: Int(4 * rate)))
        gs_engine_set_loop(rig.engine, Int64(loopIn), Int64(loopOut), true)
        gs_engine_seek(rig.engine, Int64(rate)) // paused: applies at once
        gs_engine_set_playing(rig.engine, true)
        rig.render(seconds: 2.2)
        let start = Int(rate)
        let expected = (0..<4).map { marker - start + $0 * (loopOut - loopIn) }
        XCTAssertEqual(Array(outputIndices(of: rig).prefix(4)), expected)
    }

    /// With 0.25 s of pre-roll, each pass restarts 0.25 s before loop-in.
    func testPrerollRestartsEarly() {
        let loopIn = Int(1.5 * rate), loopOut = Int(2.0 * rate), preroll = Int(0.25 * rate)
        let marker = loopIn - preroll + Int(0.03 * rate) // only heard via the pre-roll
        let rig = EngineRig(source: markers([marker], length: Int(4 * rate)))
        gs_engine_set_loop(rig.engine, Int64(loopIn), Int64(loopOut), true)
        gs_engine_set_loop_preroll(rig.engine, Int64(preroll))
        gs_engine_seek(rig.engine, Int64(1.6 * rate)) // already inside the loop, past the marker
        gs_engine_set_playing(rig.engine, true)
        rig.render(seconds: 1.5)
        let firstWrap = loopOut - Int(1.6 * rate)
        let pass = loopOut - (loopIn - preroll)
        XCTAssertEqual(Array(outputIndices(of: rig).prefix(2)),
                       [firstWrap + (marker - (loopIn - preroll)), firstWrap + (marker - (loopIn - preroll)) + pass])
    }

    /// Stretched paths: at 50% a tone that starts 0.2 s into the loop is heard
    /// 0.4 s after each wrap. Stretchers smear onsets, so this checks to 6 ms.
    func testWrapTimingWhenStretched() throws {
        let loopIn = 1.0, loopOut = 2.0
        let source = stereo(gatedSine(frequency: 440, seconds: 4, on: 1.2, off: 1.8))
        for algorithm in [GSAlgorithmA, GSAlgorithmB] {
            let rig = EngineRig(source: source)
            gs_engine_set_algorithm(rig.engine, algorithm)
            gs_engine_set_speed(rig.engine, 0.5)
            gs_engine_set_loop(rig.engine, Int64(loopIn * rate), Int64(loopOut * rate), true)
            gs_engine_seek(rig.engine, Int64(loopIn * rate))
            gs_engine_set_playing(rig.engine, true)
            rig.render(seconds: 2.0 + 1.0) // first pass is 2 s of output; look into the second
            let second = Array(rig.output[0][Int(2.0 * rate)...])
            let span = try XCTUnwrap(toneSpan(second))
            XCTAssertEqual(span.on, 0.4, accuracy: 0.006, "algorithm \(algorithm.rawValue): tone at \(span.on) s")
        }
    }

    /// Spec Phase 2 acceptance: loop a 2-bar region (4 s at 120 bpm) for five
    /// minutes with no click. Loop points sit mid-cycle on purpose (worst case
    /// for a splice). Measured over the whole render against the first pass.
    /// Reads exactly 1.0 (2026-10-06): every pass replays the first one sample
    /// for sample, so the loudest curvature in five minutes is the first pass's,
    /// repeated one loop length later; no wrap comes near it.
    func testFiveMinutesOfLoopingNeverClicks() {
        let source = stereo(sine(frequency: 440, seconds: 20).enumerated().map {
            $0.element + 0.15 * Float(sin(Double($0.offset) * 2 * .pi * 660 / testSampleRate))
        })
        let loopIn = Int64(3.0 * rate) + 17, loopOut = Int64(7.0 * rate) + 41
        let cases: [(String, (OpaquePointer) -> Void)] = [
            ("bypass", { _ in }),
            ("A at 75%", { gs_engine_set_algorithm($0, GSAlgorithmA); gs_engine_set_speed($0, 0.75) }),
            ("B at 75%", { gs_engine_set_algorithm($0, GSAlgorithmB); gs_engine_set_speed($0, 0.75) }),
        ]
        for (name, setup) in cases {
            let rig = EngineRig(source: source)
            setup(rig.engine)
            gs_engine_set_loop(rig.engine, loopIn, loopOut, true)
            gs_engine_seek(rig.engine, loopIn)
            gs_engine_set_playing(rig.engine, true)
            rig.render(seconds: 300)
            // The loop must actually have been looping: after 5 minutes the
            // playhead is inside it, and the output never went silent.
            XCTAssertGreaterThanOrEqual(rig.position, Double(loopIn), "\(name) left the loop")
            XCTAssertLessThanOrEqual(rig.position, Double(loopOut), "\(name) left the loop")
            let firstPass = Int(4.0 / (name == "bypass" ? 1 : 0.75) * rate)
            let ratio = rig.output.map {
                clickRatio($0, window: firstPass..<$0.count, reference: Int(0.1 * rate)..<(firstPass - Int(0.05 * rate)))
            }.max()!
            print("CLICK 5-minute loop, \(name): \(ratio)")
            XCTAssertLessThan(ratio, clickThreshold, "5-minute loop, \(name): click ratio \(ratio)")
        }
    }

    /// Export starts at full volume: the first output frame is the source frame.
    func testOfflineStartHasNoFadeIn() {
        let source = stereo(sine(frequency: 440, seconds: 2, amplitude: 0.5, phase: 1.0))
        let rig = EngineRig(source: source)
        gs_engine_start_offline(rig.engine, 4_800)
        rig.render(seconds: 0.1)
        XCTAssertEqual(Array(rig.output[0][0..<64]), Array(source[0][4_800..<4_864]))
    }
}
