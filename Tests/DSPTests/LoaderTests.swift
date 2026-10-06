// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Decoding (spec §5.10): rate conversion, channel handling, tags, errors.
// Files are generated here, so no audio is checked in.

import AVFoundation
import XCTest

final class LoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes a sine to a file with the given format settings.
    private func writeTone(_ name: String, frequency: Double, seconds: Double, rate: Double, channels: Int,
                           settings extra: [String: Any] = [:]) throws -> URL {
        let url = directory.appendingPathComponent(name)
        var settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 24,
                                       AVLinearPCMIsFloatKey: false]
        settings.merge(extra) { $1 }
        // More than two channels needs an explicit layout (5.1 here).
        let layout = channels > 2 ? AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A)! : nil
        if let layout {
            settings[AVChannelLayoutKey] = Data(bytes: layout.layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = layout.map { AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: $0) }
            ?? AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels))!
        let frames = AVAudioFrameCount(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<channels {
            for i in 0..<Int(frames) {
                buffer.floatChannelData![c][i] = 0.5 * Float(sin(2 * .pi * frequency * Double(i) / rate))
            }
        }
        try file.write(from: buffer)
        return url
    }

    func testResamplesToDeviceRateAndKeepsPitch() async throws {
        let url = try writeTone("tone.wav", frequency: 440, seconds: 3, rate: 44_100, channels: 2)
        let audio = try await AudioLoader.load(url, sampleRate: 48_000)
        XCTAssertEqual(audio.channels.count, 2)
        XCTAssertEqual(Double(audio.frameCount), 3 * 48_000, accuracy: 48) // within 1 ms
        let samples = Array(audio.channels[0])
        XCTAssertEqual(cents(dominantFrequency(samples, start: 24_000), relativeTo: 440), 0, accuracy: 0.05)
    }

    func testMonoStaysMono() async throws {
        let url = try writeTone("mono.aiff", frequency: 330, seconds: 1, rate: 48_000, channels: 1,
                                settings: [AVLinearPCMIsBigEndianKey: true])
        let audio = try await AudioLoader.load(url, sampleRate: 48_000)
        XCTAssertEqual(audio.channels.count, 1)
    }

    func testSurroundIsDownmixedToStereo() async throws {
        let url = try writeTone("surround.caf", frequency: 440, seconds: 1, rate: 48_000, channels: 6)
        let audio = try await AudioLoader.load(url, sampleRate: 48_000)
        XCTAssertEqual(audio.channels.count, 2)
        XCTAssertGreaterThan(Array(audio.channels[0]).map { abs($0) }.max() ?? 0, 0.1, "downmix is silent")
    }

    func testReadsCompressedAudio() async throws {
        let url = try writeTone("tone.m4a", frequency: 440, seconds: 2, rate: 44_100, channels: 2,
                                settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 192_000])
        let audio = try await AudioLoader.load(url, sampleRate: 48_000)
        XCTAssertEqual(audio.channels.count, 2)
        XCTAssertEqual(cents(dominantFrequency(Array(audio.channels[0]), start: 12_000), relativeTo: 440), 0,
                       accuracy: 0.1)
    }

    func testFileNameIsTheFallbackTitle() async throws {
        let url = try writeTone("My Practice Song.wav", frequency: 440, seconds: 0.5, rate: 48_000, channels: 1)
        let audio = try await AudioLoader.load(url, sampleRate: 48_000)
        XCTAssertEqual(audio.title, "My Practice Song")
    }

    func testGarbageFileGivesPlainError() async throws {
        let url = directory.appendingPathComponent("broken.mp3")
        try Data(repeating: 0x42, count: 10_000).write(to: url)
        do {
            _ = try await AudioLoader.load(url, sampleRate: 48_000)
            XCTFail("loaded a garbage file")
        } catch let error as LoadError {
            XCTAssertTrue(error.errorDescription?.hasPrefix("Couldn't open this file") ?? false)
        }
    }
}
