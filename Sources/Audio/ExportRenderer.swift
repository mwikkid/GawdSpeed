// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Export (spec §5.8, §5.10): the song, or a selection of it, rendered offline
// through the same engine as playback, so what you hear is what you get.

import AVFoundation
import Foundation
import GawdDSP

enum ExportFormat: String, CaseIterable, Identifiable {
    case wav, aiff, flac, alac, aac, mp3
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .flac: "FLAC"
        case .alac: "Apple Lossless (ALAC)"
        case .aac: "AAC (M4A)"
        case .mp3: "MP3"
        }
    }

    /// Written by the bundled ffmpeg rather than AVAudioFile (spec §5.10).
    var needsFFmpeg: Bool { self == .flac || self == .mp3 }

    var fileExtension: String {
        switch self {
        case .wav: "wav"
        case .aiff: "aiff"
        case .alac, .aac: "m4a"
        case .flac: "flac"
        case .mp3: "mp3"
        }
    }

    /// Bit depths offered (32 means 32-bit float). Empty for AAC.
    var bitDepths: [Int] {
        switch self {
        case .wav: [16, 24, 32]
        case .aiff, .alac, .flac: [16, 24]
        case .aac, .mp3: []
        }
    }

    static let aacBitRates = [128, 192, 256]
    /// 0 means LAME's V0 (best variable bit rate).
    static let mp3BitRates = [192, 256, 320, 0]
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
    var mp3BitRate: Int = 320
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
        let requested: Double?
        switch options.sampleRate {
        case .matchSource: requested = nil // the file's own rate
        case .fixed(let value): requested = value
        }
        let audio = try await AudioLoader.load(url, sampleRate: requested)
        let rate = audio.sampleRate
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

        // FLAC and MP3: render to a temporary 32-bit float WAV, then encode with ffmpeg.
        var renderOptions = options
        var renderURL = destination
        if options.format.needsFFmpeg {
            renderOptions.format = .wav
            renderOptions.bitDepth = 32
            renderURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        }
        defer { if renderURL != destination { try? FileManager.default.removeItem(at: renderURL) } }

        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(outChannels))!
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: renderURL, settings: fileSettings(renderOptions, rate: rate, channels: outChannels),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw LoadError(kind: .unreadable, details: "couldn't create \(destination.path): \(error.localizedDescription)")
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(block))!
        let fadeFrames = options.range == nil ? 0 : Int(ExportOptions.selectionFadeSeconds * rate)
        // 16-bit outputs get TPDF dither here, before anything quantizes.
        let dither = options.bitDepth == 16 && !options.format.bitDepths.isEmpty
        let renderShare = options.format.needsFFmpeg ? 0.9 : 1.0
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
                progress(renderShare * Double(written) / Double(outputFrames))
            }
            if options.format.needsFFmpeg {
                try await encode(renderURL, to: destination, options: options, title: audio.title, artist: audio.artist)
                progress(1)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// FLAC / MP3 via the bundled ffmpeg, with title, artist and a comment
    /// noting the speed (spec §5.10).
    private static func encode(_ wav: URL, to destination: URL, options: ExportOptions,
                               title: String, artist: String?) async throws {
        var arguments = ["-loglevel", "error", "-y", "-i", wav.path]
        switch options.format {
        case .flac:
            arguments += ["-c:a", "flac", "-sample_fmt", options.bitDepth == 16 ? "s16" : "s32"]
            if options.bitDepth == 24 { arguments += ["-bits_per_raw_sample", "24"] }
        case .mp3:
            arguments += ["-c:a", "libmp3lame"]
            arguments += options.mp3BitRate == 0 ? ["-q:a", "0"] : ["-b:a", "\(options.mp3BitRate)k"]
        default:
            return
        }
        var comment = "GawdSpeed \(Int((options.speed * 100).rounded()))%"
        if options.transpose != 0 { comment += String(format: " %+gst", options.transpose) }
        arguments += ["-metadata", "title=\(title)", "-metadata", "comment=\(comment)"]
        if let artist { arguments += ["-metadata", "artist=\(artist)"] }
        arguments.append(destination.path)
        do {
            try await FFmpegRunner.run(arguments)
        } catch let failure as FFmpegRunner.Failure {
            throw LoadError(kind: .unreadable, details: "encoding \(options.format.displayName): \(failure.stderr)")
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
        case .flac, .mp3:
            break // encoded by ffmpeg from a float WAV
        }
        return settings
    }
}
