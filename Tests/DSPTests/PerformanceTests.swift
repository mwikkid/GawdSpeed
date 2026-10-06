// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// CPU cost of each path (spec §11 Phase 1: "CPU numbers for A and B at 50%
// speed recorded in README"). Prints, never asserts: one machine's timing is
// orientation, not a gate. Repeated and interleaved so drift shows as spread.

import GawdDSP
import XCTest

final class PerformanceTests: XCTestCase {
    func testPrintCPUCostAtHalfSpeed() {
        let seconds = 30.0
        let source = stereo(sine(frequency: 440, seconds: 40).enumerated().map {
            $0.element + 0.2 * Float(sin(Double($0.offset) * 0.031)) // two partials, so it isn't trivial
        })
        let paths: [(String, (EngineRig) -> Void)] = [
            ("bypass (100%)", { _ in }),
            ("A at 50%", { gs_engine_set_algorithm($0.engine, GSAlgorithmA); gs_engine_set_speed($0.engine, 0.5) }),
            ("B at 50%", { gs_engine_set_algorithm($0.engine, GSAlgorithmB); gs_engine_set_speed($0.engine, 0.5) }),
        ]
        var results: [String: [Double]] = [:]
        for _ in 0..<3 {
            for (name, setup) in paths {
                let rig = EngineRig(source: source)
                setup(rig)
                gs_engine_set_playing(rig.engine, true)
                let start = DispatchTime.now()
                rig.render(seconds: seconds)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
                results[name, default: []].append(elapsed / seconds * 100)
            }
        }
        for (name, _) in paths {
            let runs = results[name]!.map { String(format: "%.2f", $0) }.joined(separator: ", ")
            print("CPU \(name): \(runs) % of one core (stereo, 48 kHz, 3 interleaved runs)")
        }
    }
}
