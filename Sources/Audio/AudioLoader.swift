// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Decodes an audio or video file into memory as planar Float32 at the output
// device's sample rate (spec §3 rules 4–5, §5.10). Mono stays mono; more than
// two channels are downmixed to stereo by Core Audio.

import Accelerate
import AVFoundation
import Foundation

/// Decoded audio, owned here and lent to the engine by pointer.
final class SourceAudio {
    let channels: [UnsafeMutableBufferPointer<Float>]
    let frameCount: Int
    let sampleRate: Double
    let title: String
    let artist: String?
    let url: URL

    init(channels: [UnsafeMutableBufferPointer<Float>], frameCount: Int, sampleRate: Double,
         title: String, artist: String?, url: URL) {
        self.channels = channels
        self.frameCount = frameCount
        self.sampleRate = sampleRate
        self.title = title
        self.artist = artist
        self.url = url
    }

    deinit { channels.forEach { $0.deallocate() } }

    var duration: Double { Double(frameCount) / sampleRate }
}

/// Load failures, worded for musicians (spec §5.11). `details` holds the
/// technical reason for the "Details" disclosure.
struct LoadError: LocalizedError {
    enum Kind { case protected, noAudio, unreadable }
    let kind: Kind
    let details: String

    var errorDescription: String? {
        switch kind {
        case .protected:
            "Couldn't open this file. It's copy-protected (DRM), so it can only play in the app it came from."
        case .noAudio:
            "This file doesn't contain any audio."
        case .unreadable:
            "Couldn't open this file. It may be damaged, or in a format GawdSpeed can't read yet. Try a different copy."
        }
    }
}

enum AudioLoader {
    /// File types the Open panel offers.
    /// Formats AVFoundation reads itself (spec §5.10).
    static let nativeExtensions = ["wav", "wave", "aif", "aiff", "aifc", "caf", "mp3", "m4a", "aac",
                                   "alac", "flac", "mp4", "mov", "m4v"]
    /// Formats that go straight to the bundled ffmpeg.
    static let ffmpegExtensions = ["ogg", "oga", "opus", "webm", "mkv", "mka", "avi", "wma", "asf", "ape",
                                   "wv", "tta", "ac3", "eac3", "dsf", "dff", "amr", "w64"]
    static var openableExtensions: [String] { nativeExtensions + ffmpegExtensions }

    /// Decodes `url` to planar float at `sampleRate` (nil keeps the file's own
    /// rate). Tries AVFoundation first; anything it can't open, or any
    /// ffmpeg-only format, goes through the bundled ffmpeg (spec §5.1, §5.10).
    static func load(_ url: URL, sampleRate: Double?) async throws -> SourceAudio {
        if !ffmpegExtensions.contains(url.pathExtension.lowercased()) {
            do {
                return try await loadNative(url, sampleRate: sampleRate)
            } catch let error as LoadError where error.kind == .protected {
                throw error
            } catch {
                guard FFmpegRunner.executable != nil else { throw error }
            }
        }
        return try await loadViaFFmpeg(url, sampleRate: sampleRate)
    }

    /// ffmpeg decodes to a temporary float CAF (more than two channels folded
    /// to stereo), which AVFoundation then reads; the temp file is removed.
    private static func loadViaFFmpeg(_ url: URL, sampleRate: Double?) async throws -> SourceAudio {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GawdSpeed/Decoded", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: temp) }

        var arguments = ["-loglevel", "info", "-i", url.path, "-vn", "-map", "0:a:0",
                         "-af", "aformat=channel_layouts=mono|stereo"]
        if let sampleRate { arguments += ["-ar", String(Int(sampleRate.rounded()))] }
        arguments += ["-c:a", "pcm_f32le", "-f", "caf", temp.path]
        let stderr: String
        do {
            stderr = try await FFmpegRunner.run(arguments)
        } catch let failure as FFmpegRunner.Failure {
            let tail = failure.stderr.split(separator: "\n").suffix(4).joined(separator: "\n")
            throw LoadError(kind: .unreadable, details: tail.isEmpty ? failure.localizedDescription : tail)
        }
        let tags = FFmpegRunner.tags(fromStderr: stderr)
        return try await loadNative(temp, sampleRate: sampleRate, original: url,
                                    title: tags["title"], artist: tags["artist"])
    }

    private static func loadNative(_ url: URL, sampleRate requestedRate: Double?, original: URL? = nil,
                                   title titleOverride: String? = nil, artist artistOverride: String? = nil)
        async throws -> SourceAudio {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw LoadError(kind: .unreadable, details: error.localizedDescription)
        }
        guard let track = tracks.first else {
            if (try? await asset.load(.hasProtectedContent)) == true {
                throw LoadError(kind: .protected, details: "hasProtectedContent")
            }
            throw LoadError(kind: .noAudio, details: "no audio track in \(url.lastPathComponent)")
        }
        if (try? await asset.load(.hasProtectedContent)) == true {
            throw LoadError(kind: .protected, details: "hasProtectedContent")
        }

        let sourceChannels = await channelCount(of: track)
        let channels = min(max(sourceChannels, 1), 2)
        let fileURL = original ?? url
        var (title, artist) = await tags(of: asset, fallback: fileURL.deletingPathExtension().lastPathComponent)
        if let titleOverride { title = titleOverride }
        if let artistOverride { artist = artistOverride }
        let fileRate = await nativeRate(of: track)
        let sampleRate = requestedRate ?? fileRate ?? 48_000

        // Interleaved Float32 at the device rate; Core Audio resamples and,
        // for more than two channels, downmixes.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            // Best resampler. (AVSampleRateConverterAudioQualityKey would be the
            // obvious key, but a track output throws on it and kills the app.)
            AVSampleRateConverterAlgorithmKey: AVSampleRateConverterAlgorithm_Mastering,
        ]

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw LoadError(kind: .unreadable, details: error.localizedDescription)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw LoadError(kind: .unreadable, details: "reader cannot add track output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw LoadError(kind: .unreadable, details: reader.error?.localizedDescription ?? "startReading failed")
        }

        // Decode into growable planar arrays, then copy into owned buffers.
        var planar = [[Float]](repeating: [], count: channels)
        if let estimate = try? await asset.load(.duration).seconds, estimate.isFinite {
            for c in 0..<channels { planar[c].reserveCapacity(Int(estimate * sampleRate) + 4096) }
        }
        var scratch = [Float]()
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            // Copy out rather than borrow: a block buffer need not be contiguous.
            let length = CMBlockBufferGetDataLength(block)
            let frames = length / (MemoryLayout<Float>.size * channels)
            guard frames > 0 else { continue }
            if scratch.count < frames * channels { scratch = [Float](repeating: 0, count: frames * channels) }
            let status = scratch.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * channels * 4,
                                           destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            scratch.withUnsafeBufferPointer { samples in
                for c in 0..<channels {
                    let start = planar[c].count
                    planar[c].append(contentsOf: repeatElement(0, count: frames))
                    planar[c].withUnsafeMutableBufferPointer { dest in
                        var zero: Float = 0 // strided copy: dest = samples[c, c+channels, ...] + 0
                        vDSP_vsadd(samples.baseAddress! + c, vDSP_Stride(channels), &zero,
                                   dest.baseAddress! + start, 1, vDSP_Length(frames))
                    }
                }
            }
        }
        if reader.status == .failed {
            throw LoadError(kind: .unreadable, details: reader.error?.localizedDescription ?? "decode failed")
        }
        let frameCount = planar[0].count
        guard frameCount > 0 else { throw LoadError(kind: .noAudio, details: "decoded 0 frames") }

        let owned = planar.map { samples in
            let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: samples.count)
            _ = buffer.initialize(from: samples)
            return buffer
        }
        return SourceAudio(channels: owned, frameCount: frameCount, sampleRate: sampleRate,
                           title: title, artist: artist, url: fileURL)
    }

    private static func nativeRate(of track: AVAssetTrack) async -> Double? {
        guard let descriptions = try? await track.load(.formatDescriptions),
              let first = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first) else { return nil }
        let rate = basic.pointee.mSampleRate
        return rate > 0 ? rate : nil
    }

    private static func channelCount(of track: AVAssetTrack) async -> Int {
        guard let descriptions = try? await track.load(.formatDescriptions),
              let first = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(first) else { return 2 }
        return Int(basic.pointee.mChannelsPerFrame)
    }

    private static func tags(of asset: AVAsset, fallback: String) async -> (String, String?) {
        let common = (try? await asset.load(.commonMetadata)) ?? []
        // FLAC (and Ogg) tags are Vorbis comments, which AVFoundation lists as
        // "vorb/TITLE" etc. and leaves out of commonMetadata.
        let all = (try? await asset.load(.metadata)) ?? []
        func value(_ key: AVMetadataKey, vorbis: String) async -> String? {
            if let item = AVMetadataItem.metadataItems(from: common, withKey: key, keySpace: .common).first,
               let text = try? await item.load(.stringValue), !text.isEmpty { return text }
            for item in all where item.identifier?.rawValue.uppercased() == "VORB/\(vorbis)" {
                if let text = try? await item.load(.stringValue), !text.isEmpty { return text }
            }
            return nil
        }
        let title = await value(.commonKeyTitle, vorbis: "TITLE")
        let artist = await value(.commonKeyArtist, vorbis: "ARTIST")
        return (title ?? fallback, artist)
    }
}
