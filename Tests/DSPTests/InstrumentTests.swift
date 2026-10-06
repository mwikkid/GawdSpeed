// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Checks the measuring instruments on signals whose answer is known, before
// they are allowed to judge a stretcher.

import XCTest

final class InstrumentTests: XCTestCase {
    /// The pitch meter must read known sines to well under the 1-cent
    /// tolerance the stretcher tests use, at several phases and window
    /// positions, and must tell 440 Hz from 440 Hz ± 1 cent.
    func testPitchMeterReadsKnownSines() {
        let cases: [(frequency: Double, label: String)] = [
            (440, "440 Hz"),
            (440 * pow(2, 1.0 / 1200), "440 Hz +1 cent"),
            (440 * pow(2, -1.0 / 1200), "440 Hz -1 cent"),
            (523.2511306, "C5 (440 Hz +3 semitones)"),
            (110, "110 Hz"),
            (1760, "1760 Hz"),
        ]
        for (frequency, label) in cases {
            for phase in [0.0, 1.1, 2.9] {
                let signal = sine(frequency: frequency, seconds: 3, phase: phase)
                for start in [0, 12_345, 50_000] {
                    let measured = dominantFrequency(signal, start: start)
                    XCTAssertEqual(cents(measured, relativeTo: frequency), 0, accuracy: 0.05,
                                   "\(label), phase \(phase), start \(start): read \(measured) Hz")
                }
            }
        }
    }

    func testPitchMeterSeparatesOneCent() {
        let up = dominantFrequency(sine(frequency: 440 * pow(2, 1.0 / 1200), seconds: 2), start: 0)
        let down = dominantFrequency(sine(frequency: 440 * pow(2, -1.0 / 1200), seconds: 2), start: 0)
        XCTAssertEqual(cents(up, relativeTo: down), 2, accuracy: 0.05)
    }

    /// The tone-span meter must find the gate edges of a gated sine to within
    /// a millisecond.
    func testToneSpanFindsGateEdges() throws {
        let signal = gatedSine(frequency: 440, seconds: 5, on: 1.0, off: 3.25)
        let span = try XCTUnwrap(toneSpan(signal))
        XCTAssertEqual(span.on, 1.0, accuracy: 0.001)
        XCTAssertEqual(span.off, 3.25, accuracy: 0.001)
    }

    /// Negative controls: a varispeed "stretcher" changes pitch, so the pitch
    /// check must reject it; a pass-through ignores speed, so the duration
    /// check must reject it. If either of these ever passes, the stretcher
    /// tests can no longer tell a broken stretcher from a working one.
    func testChecksRejectKnownBrokenStretchers() throws {
        let source = sine(frequency: 440, seconds: 10)
        let slowed = varispeed(source, speed: 0.75, outputFrames: 120_000)
        let measured = dominantFrequency(slowed, start: 24_000)
        XCTAssertGreaterThan(abs(cents(measured, relativeTo: 440)), 1,
                             "varispeed at 75% read \(measured) Hz; the pitch check could not fail")

        let gated = gatedSine(frequency: 440, seconds: 6, on: 1.0, off: 3.0)
        let span = try XCTUnwrap(toneSpan(gated))
        let expected = 2.0 / 0.5
        XCTAssertGreaterThan(abs((span.off - span.on) - expected), Double(testBlock) / testSampleRate,
                             "an unstretched tone passed the 50% duration check")
    }
}
