// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Export (spec §5.8, §5.10): the song, or a selection of it, rendered offline
// through the same engine as playback, so what you hear is what you get.

import AVFoundation
import Foundation
import GawdDSP

enum ExportFormat: String, CaseIterable, Identifiable {
    case wav, aiff, alac, aac
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .alac: "Apple Lossless (ALAC)"
        case .aac: "AAC (M4A)"
        }
    }

    var fileExtension: String {
        switch self {
        case .wav: "wav"
        case .aiff: "aiff"
        case .alac, .aac: "m4a"
        }
    }

    /// Bit depths offered (32 means 32-bit float). Empty for AAC.
    var bitDepths: [Int] {
        switch self {
        case .wav: [16, 24, 32]
        case .aiff, .alac: [16, 24]
        case .aac: []
        }
    }

    static let aacBitRates = [128, 192, 256]
}

enum ExportSampleRate: Hashable {
    case matchSource
    case fixed(Double)
}

struct ExportOptions {
    /// Seconds of source time; nil exports the whole song.
    var range: ClosedRange<Double>?
    var speed: Double
    var transpose: Double // semitones, cents as a fraction
    var algorithm: GSAlgorithm
    var applyFilters: Bool
    var highpassHz: Double
    var lowpassHz: Double
    var format: ExportFormat = .wav
    var bitDepth: Int = 24
    var aacBitRate: Int = 256
    var sampleRate: ExportSampleRate = .matchSource
    var monoSum = false

    /// Fade length at the edges of a selection export (spec §5.8).
    static let selectionFadeSeconds = 0.020
}

enum ExportRenderer {
    static let block = 4096

    /// "<Title> (75%).wav", "<Title> (75% +2st).wav",
    /// "<Title> 0m41s–0m48s (75%).wav" (spec §5.8).
    static func suggestedFileName(title: String, options: ExportOptions) -> String {
        var label = "\(Int((options.speed * 100).rounded()))%"
        let semitones = Int(options.transpose.rounded(.towardZero))
        let cents = Int(((options.transpose - Double(semitones)) * 100).rounded())
        if semitones != 0 || cents != 0 {
            label += " \(semitones >= 0 ? "+" : "")\(semitones)st"
            if cents != 0 { label += "\(cents >= 0 ? "+" : "")\(cents)c" }
        }
        var name = title
        if let range = options.range {
            func stamp(_ s: Double) -> String { "\(Int(s) / 60)m\(String(format: "%02d", Int(s) % 60))s" }
            name += " \(stamp(range.lowerBound))–\(stamp(range.upperBound))"
        }
        let safe = "\(name) (\(label))".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safe).\(options.format.fileExtension)"
    }

    /// Renders and writes the export. `progress` gets 0...1. Throws
    /// CancellationError (and removes the partial file) if cancelled.
    static func export(from url: URL, options: ExportOptions, to destination: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let rate: Double
        switch options.sampleRate {
        case .matchSource: rate = await AudioLoader.nativeSampleRate(of: url) ?? 48_000
        case .fixed(let value): rate = value
        }
        let audio = try await AudioLoader.load(url, sampleRate: rate)
        let outChannels = options.monoSum ? 1 : audio.channels.count

        guard let engine = gs_engine_create(rate, Int32(outChannels), Int32(block)) else {
            throw LoadError(kind: .unreadable, details: "gs_engine_create failed")
        }
        defer { gs_engine_destroy(engine) }
        var sourcePointers: [UnsafePointer<Float>?] = audio.channels.map { UnsafePointer($0.baseAddress) }
        sourcePointers.withUnsafeMutableBufferPointer {
            gs_engine_set_source(engine, $0.baseAddress!, Int32(audio.channels.count), Int64(audio.frameCount))
        }
        gs_engine_set_speed(engine, options.speed)
        gs_engine_set_transpose(engine, options.transpose)
        gs_engine_set_algorithm(engine, options.algorithm)
        gs_engine_set_highpass(engine, options.applyFilters ? options.highpassHz : 20)
        gs_engine_set_lowpass(engine, options.applyFilters ? options.lowpassHz : 20_000)

        let startFrame = Int64(((options.range?.lowerBound ?? 0) * rate).rounded())
        let endFrame = min(Int64(audio.frameCount),
                           options.range.map { Int64(($0.upperBound * rate).rounded()) } ?? Int64(audio.frameCount))
        let outputFrames = Int((Double(endFrame - startFrame) / options.speed).rounded(.up))
        guard outputFrames > 0 else { throw LoadError(kind: .noAudio, details: "empty export range") }
        gs_engine_start_offline(engine, startFrame)

        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(outChannels))!
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: destination, settings: fileSettings(options, rate: rate, channels: outChannels),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw LoadError(kind: .unreadable, details: "couldn't create \(destination.path): \(error.localizedDescription)")
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(block))!
        let fadeFrames = options.range == nil ? 0 : Int(ExportOptions.selectionFadeSeconds * rate)
        let dither = options.bitDepth == 16 && options.format != .aac
        var generator = SystemRandomNumberGenerator()
        let lsb: Float = 1.0 / 32_768

        var written = 0
        do {
            while written < outputFrames {
                try Task.checkCancellation()
                let n = min(block, outputFrames - written)
                buffer.frameLength = AVAudioFrameCount(n)
                let channels = buffer.floatChannelData!
                var pointers = (0..<outChannels).map { Optional(channels[$0]) }
                pointers.withUnsafeMutableBufferPointer { gs_engine_render(engine, $0.baseAddress!, Int32(n)) }

                for c in 0..<outChannels {
                    let samples = channels[c]
                    for i in 0..<n {
                        let frame = written + i
                        var gain: Float = 1
                        if fadeFrames > 0 {
                            gain = min(1, Float(frame) / Float(fadeFrames),
                                       Float(outputFrames - 1 - frame) / Float(fadeFrames))
                        }
                        var value = samples[i] * gain
                        if dither { // TPDF, ±1 LSB at 16 bits
                            value += (Float.random(in: 0..<1, using: &generator)
                                      - Float.random(in: 0..<1, using: &generator)) * lsb
                        }
                        samples[i] = value
                    }
                }
                try file.write(from: buffer)
                written += n
                progress(Double(written) / Double(outputFrames))
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func fileSettings(_ options: ExportOptions, rate: Double, channels: Int) -> [String: Any] {
        var settings: [String: Any] = [AVSampleRateKey: rate, AVNumberOfChannelsKey: channels]
        switch options.format {
        case .wav, .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = options.bitDepth
            settings[AVLinearPCMIsFloatKey] = options.bitDepth == 32
            settings[AVLinearPCMIsBigEndianKey] = options.format == .aiff
            settings[AVLinearPCMIsNonInterleaved] = false
        case .alac:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = options.bitDepth
        case .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = options.aacBitRate * 1000
        }
        return settings
    }
}
