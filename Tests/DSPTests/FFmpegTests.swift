// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The bundled-ffmpeg routes (spec §5.10, §8.1): decoding what AVFoundation
// can't, and FLAC / MP3 export. Needs build/ffmpeg/ffmpeg (scripts/build-ffmpeg.sh).

import AVFoundation
import GawdDSP
import XCTest

final class FFmpegTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try XCTSkipIf(FFmpegRunner.executable == nil, "no ffmpeg: run scripts/build-ffmpeg.sh")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func writeTone(_ name: String, seconds: Double = 3, rate: Double = 44_100) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false], commonFormat: .pcmFormatFloat32,
            interleaved: false)
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = 0.4 * Float(sin(2 * .pi * 440 * Double(i) / rate)) }
        }
        try file.write(from: buffer)
        return url
    }

    /// A file with an ffmpeg-only extension goes through ffmpeg (which reads
    /// the content, not the name): resampled, right length, right pitch.
    func testFFmpegRouteDecodes() async throws {
        let wav = try writeTone("tone.wav")
        let disguised = directory.appendingPathComponent("tone.mka")
        try FileManager.default.copyItem(at: wav, to: disguised)
        let audio = try await AudioLoader.load(disguised, sampleRate: 48_000)
        XCTAssertEqual(audio.sampleRate, 48_000)
        XCTAssertEqual(audio.channels.count, 2)
        XCTAssertEqual(Double(audio.frameCount), 3 * 48_000, accuracy: 48)
        XCTAssertEqual(cents(dominantFrequency(Array(audio.channels[0]), start: 24_000), relativeTo: 440), 0, accuracy: 0.05)
        XCTAssertEqual(audio.url, disguised, "the song keeps its own URL, not the temp file's")
        XCTAssertEqual(audio.title, "tone")
    }

    /// A real Opus file, when Homebrew's ffmpeg is here to make one.
    func testOpusDecodes() async throws {
        let maker = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: maker.path), "no Homebrew ffmpeg to encode Opus")
        let opus = directory.appendingPathComponent("tone.opus")
        let p = Process()
        p.executableURL = maker
        p.arguments = ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
                       "-ac", "2", "-c:a", "libopus", "-b:a", "128k", "-metadata", "title=Opus Tone", opus.path]
        try p.run()
        p.waitUntilExit()
        let audio = try await AudioLoader.load(opus, sampleRate: 48_000)
        XCTAssertEqual(audio.title, "Opus Tone", "tags come through ffmpeg")
        XCTAssertEqual(Double(audio.frameCount), 3 * 48_000, accuracy: 960)
        XCTAssertEqual(cents(dominantFrequency(Array(audio.channels[0]), start: 24_000), relativeTo: 440), 0, accuracy: 0.5)
    }

    func testDamagedFileThroughFFmpegGivesPlainError() async throws {
        let junk = directory.appendingPathComponent("broken.ogg")
        try Data(repeating: 7, count: 5_000).write(to: junk)
        do {
            _ = try await AudioLoader.load(junk, sampleRate: 48_000)
            XCTFail("loaded junk")
        } catch let error as LoadError {
            XCTAssertTrue(error.errorDescription?.hasPrefix("Couldn't open this file") ?? false)
            XCTAssertFalse(error.details.isEmpty, "ffmpeg's reason goes in Details")
        }
    }

    /// FLAC and MP3 exports: readable, the right length (MP3 adds encoder
    /// padding), the transposed pitch, and tagged.
    func testFLACAndMP3Export() async throws {
        let source = try writeTone("Practice Tone.wav", seconds: 6)
        for (format, slack) in [(ExportFormat.flac, 0), (ExportFormat.mp3, 2_400)] {
            var options = ExportOptions(range: 1.0...3.0, speed: 0.75, transpose: 2, algorithm: GSAlgorithmB,
                                        applyFilters: true, highpassHz: 20, lowpassHz: 20_000)
            options.format = format
            options.bitDepth = 16
            let out = directory.appendingPathComponent("out.\(format.fileExtension)")
            try await ExportRenderer.export(from: source, options: options, to: out) { _ in }
            let file = try AVAudioFile(forReading: out)
            let expected = Int((2.0 * 44_100 / 0.75).rounded(.up))
            XCTAssertEqual(Int(file.length), expected, accuracy: slack, "\(format) length")
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            XCTAssertEqual(cents(dominantFrequency(samples, start: 10_000, sampleRate: 44_100),
                                 relativeTo: 440 * pow(2, 2.0 / 12)), 0, accuracy: 1, "\(format) pitch")
            // Read back the way the app reads a song's title.
            let reopened = try await AudioLoader.load(out, sampleRate: nil)
            XCTAssertEqual(reopened.title, "Practice Tone", "\(format) title tag")
        }
    }
}
