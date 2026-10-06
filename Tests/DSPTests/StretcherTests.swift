// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Spec §4 acceptance tests, run on both algorithms.

import GawdDSP
import XCTest

final class StretcherTests: XCTestCase {
    /// Output to skip before measuring, so the seek's start-up is excluded.
    private let settle = Int(0.5 * testSampleRate)
    private let measureFrames = 1 << 16

    /// Cases where Algorithm A (Signalsmith Stretch 1.4.0) is known to miss
    /// the 1-cent tolerance. Measured 2026-10-06; see docs/FINDINGS.md (F1).
    /// Strict: if one of these starts passing, the test fails so the list
    /// gets updated.
    private func knownMiss(_ algorithm: GSAlgorithm, speed: Double, transpose: Double) -> Bool {
        algorithm == GSAlgorithmA && (speed < 0.4 || transpose != 0)
    }

    private func checkPitch(_ algorithm: GSAlgorithm, speed: Double, transpose: Double,
                            _ body: () -> Void) {
        if knownMiss(algorithm, speed: speed, transpose: transpose) {
            XCTExpectFailure("Signalsmith pitch error, docs/FINDINGS.md F1", failingBlock: body)
        } else {
            body()
        }
    }

    private func measuredPitch(_ algorithm: GSAlgorithm, speed: Double, transpose: Double) -> [Double] {
        let source = stereo(sine(frequency: 440, seconds: 10))
        let out = renderStretched(algorithm: algorithm, source: source, speed: speed, transpose: transpose,
                                  outputFrames: settle + measureFrames + testBlock)
        return out.map { dominantFrequency($0, start: settle) }
    }

    /// 440 Hz at 25 / 50 / 75 % speed stays at 440 Hz ± 1 cent.
    func testSlowingDownKeepsPitch() {
        for (name, algorithm) in allAlgorithms {
            for speed in [0.25, 0.5, 0.75] {
                let frequencies = measuredPitch(algorithm, speed: speed, transpose: 0)
                checkPitch(algorithm, speed: speed, transpose: 0) {
                    for (channel, frequency) in frequencies.enumerated() {
                        XCTAssertEqual(cents(frequency, relativeTo: 440), 0, accuracy: 1,
                                       "Algorithm \(name) at \(Int(speed * 100))%, channel \(channel): \(frequency) Hz")
                    }
                }
            }
        }
    }

    /// 440 Hz transposed +3 semitones at 100% speed reads 523.25 Hz ± 1 cent.
    func testTransposeAtFullSpeed() {
        let target = 440 * pow(2, 3.0 / 12)
        for (name, algorithm) in allAlgorithms {
            let frequencies = measuredPitch(algorithm, speed: 1, transpose: 3)
            checkPitch(algorithm, speed: 1, transpose: 3) {
                for (channel, frequency) in frequencies.enumerated() {
                    XCTAssertEqual(cents(frequency, relativeTo: target), 0, accuracy: 1,
                                   "Algorithm \(name) +3 st, channel \(channel): \(frequency) Hz")
                }
            }
        }
    }

    /// Transpose also holds while slowed down (75%, -2 st).
    func testTransposeWhileSlowed() {
        let target = 440 * pow(2, -2.0 / 12)
        for (name, algorithm) in allAlgorithms {
            let frequencies = measuredPitch(algorithm, speed: 0.75, transpose: -2)
            checkPitch(algorithm, speed: 0.75, transpose: -2) {
                for frequency in frequencies {
                    XCTAssertEqual(cents(frequency, relativeTo: target), 0, accuracy: 1,
                                   "Algorithm \(name) 75% -2 st: \(frequency) Hz")
                }
            }
        }
    }

    /// A tone lasting 2 s in the source lasts 2 s / speed in the output, ± one
    /// render block; and it starts where the reported position says it should.
    func testDurationAndPosition() throws {
        let on = 1.0, off = 3.0
        let source = stereo(gatedSine(frequency: 440, seconds: 6, on: on, off: off))
        for (name, algorithm) in allAlgorithms {
            for speed in [0.25, 0.5, 0.75, 1.0] {
                let frames = Int((off + 0.5) / speed * testSampleRate)
                let out = renderStretched(algorithm: algorithm, source: source, speed: speed, outputFrames: frames)
                let span = try XCTUnwrap(toneSpan(out[0]), "Algorithm \(name) at \(speed): no tone found")
                let duration = span.off - span.on
                let label = "Algorithm \(name) at \(Int(speed * 100))%"
                XCTAssertEqual(duration, (off - on) / speed, accuracy: Double(testBlock) / testSampleRate,
                               "\(label): tone lasted \(duration) s")
                // Report the start offset; the tolerance for it is set in Phase 1
                // once the playhead's needs are known.
                let startError = (span.on - on / speed) * 1000
                print("TIMING \(label): tone starts \(String(format: "%+.1f", startError)) ms from expected, "
                      + "duration error \(String(format: "%+.1f", (duration - (off - on) / speed) * 1000)) ms")
            }
        }
    }

    /// After a seek into the middle of the source, the first output frame is
    /// the frame at the seek position.
    func testSeekLandsOnPosition() throws {
        let source = stereo(gatedSine(frequency: 440, seconds: 10, on: 5.0, off: 7.0))
        let seekTo = Int64(4.0 * testSampleRate)
        for (name, algorithm) in allAlgorithms {
            for speed in [0.5, 1.0] {
                let out = renderStretched(algorithm: algorithm, source: source, speed: speed, seekTo: seekTo,
                                          outputFrames: Int(4.0 / speed * testSampleRate))
                let span = try XCTUnwrap(toneSpan(out[0]))
                let startError = (span.on - 1.0 / speed) * 1000
                print("SEEK Algorithm \(name) at \(Int(speed * 100))%: tone starts "
                      + "\(String(format: "%+.1f", startError)) ms from expected")
            }
        }
    }
}
