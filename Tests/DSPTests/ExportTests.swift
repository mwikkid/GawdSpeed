// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Export (spec §5.8, Phase 2 acceptance): a selection exported at 75% / +2 st
// matches playback and lasts region ÷ 0.75.

import AVFoundation
import GawdDSP
import XCTest

final class ExportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    /// A 44.1 kHz stereo WAV: a 440 Hz tone plus a quieter 660 Hz one.
    private func writeSource(seconds: Double = 6) throws -> (URL, [[Float]]) {
        let rate = 44_100.0
        let url = directory.appendingPathComponent("source.wav")
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true])
        let frames = Int(seconds * rate)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        var planar: [[Float]] = [[], []]
        for c in 0..<2 {
            for i in 0..<frames {
                let t = Double(i) / rate
                let v = Float(0.4 * sin(2 * .pi * 440 * t) + 0.15 * sin(2 * .pi * 660 * t + Double(c)))
                buffer.floatChannelData![c][i] = v
                planar[c].append(v)
            }
        }
        try file.write(from: buffer)
        return (url, planar)
    }

    private func read(_ url: URL) throws -> (samples: [[Float]], rate: Double) {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let channels = Int(buffer.format.channelCount)
        return ((0..<channels).map { Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0],
                                                               count: Int(buffer.frameLength))) },
                file.fileFormat.sampleRate)
    }

    private func options(_ algorithm: GSAlgorithm) -> ExportOptions {
        ExportOptions(range: 1.0...3.0, speed: 0.75, transpose: 2, algorithm: algorithm,
                      applyFilters: true, highpassHz: 20, lowpassHz: 20_000)
    }

    /// Duration = region ÷ 0.75 to the frame, at the source's own rate; and the
    /// audio is the transposed tone (Algorithm B; A's transpose error is F1).
    func testSelectionDurationAndPitch() async throws {
        let (source, _) = try writeSource()
        for (name, algorithm) in allAlgorithms {
            let out = directory.appendingPathComponent("out-\(name).wav")
            try await ExportRenderer.export(from: source, options: options(algorithm), to: out) { _ in }
            let (samples, rate) = try read(out)
            XCTAssertEqual(rate, 44_100, "exports match the source's sample rate by default")
            XCTAssertEqual(samples[0].count, Int((2.0 * 44_100 / 0.75).rounded(.up)), "Algorithm \(name) duration")
            if algorithm == GSAlgorithmB {
                // 440 Hz + 2 semitones, measured at the export's own rate.
                let f = dominantFrequency(samples[0], start: 8_000, sampleRate: rate)
                XCTAssertEqual(cents(f, relativeTo: 440 * pow(2, 2.0 / 12)), 0, accuracy: 1)
            }
        }
    }

    /// The export is what playback plays: the same engine, the same settings,
    /// rendered live in 512-frame blocks, gives the same samples (away from
    /// the 20 ms export fades and the 10 ms play fade-in).
    func testSelectionMatchesPlayback() async throws {
        let (source, planar) = try writeSource()
        for (name, algorithm) in allAlgorithms {
            let out = directory.appendingPathComponent("match-\(name).wav")
            try await ExportRenderer.export(from: source, options: options(algorithm), to: out) { _ in }
            let exported = try read(out).samples[0]

            // Playback path at the same rate, seek to 1.0 s, play.
            let rig = EngineRig(source: planar, rate: 44_100)
            gs_engine_set_algorithm(rig.engine, algorithm)
            gs_engine_set_speed(rig.engine, 0.75)
            gs_engine_set_transpose(rig.engine, 2)
            gs_engine_seek(rig.engine, 44_100)
            gs_engine_set_playing(rig.engine, true)
            rig.render(seconds: Double(exported.count) / 44_100)
            let played = rig.output[0]

            let middle = 4_410..<(exported.count - 4_410) // skip 100 ms at each end
            var errorEnergy = 0.0, signalEnergy = 0.0
            for i in middle {
                errorEnergy += Double(exported[i] - played[i]) * Double(exported[i] - played[i])
                signalEnergy += Double(played[i]) * Double(played[i])
            }
            let differenceDB = 10 * log10(max(errorEnergy, 1e-30) / signalEnergy)
            print("EXPORT vs playback, Algorithm \(name): difference \(String(format: "%.1f", differenceDB)) dB")
            XCTAssertLessThan(differenceDB, -60, "Algorithm \(name): export differs from playback")
        }
    }

    func testSuggestedFileNames() {
        var o = ExportOptions(range: nil, speed: 0.75, transpose: 0, algorithm: GSAlgorithmB,
                              applyFilters: true, highpassHz: 20, lowpassHz: 20_000)
        XCTAssertEqual(ExportRenderer.suggestedFileName(title: "Song", options: o), "Song (75%).wav")
        o.transpose = 2
        XCTAssertEqual(ExportRenderer.suggestedFileName(title: "Song", options: o), "Song (75% +2st).wav")
        o.transpose = 0
        o.range = 41.2...48.75
        XCTAssertEqual(ExportRenderer.suggestedFileName(title: "Song", options: o), "Song 0m41s–0m48s (75%).wav")
    }

    func testCancelRemovesPartialFile() async throws {
        let (source, _) = try writeSource(seconds: 30)
        let out = directory.appendingPathComponent("cancelled.wav")
        let task = Task {
            try await ExportRenderer.export(from: source, options: ExportOptions(
                range: nil, speed: 0.25, transpose: 0, algorithm: GSAlgorithmB,
                applyFilters: false, highpassHz: 20, lowpassHz: 20_000), to: out) { _ in }
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do {
            try await task.value
            XCTFail("export finished despite cancel")
        } catch is CancellationError {
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }
}
