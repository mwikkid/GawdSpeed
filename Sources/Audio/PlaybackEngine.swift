// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Live output: an AVAudioSourceNode whose render block calls straight into
// the C++ engine. The block touches nothing but the engine pointer and a
// pointer array allocated once, so the audio thread never allocates, locks,
// or retains anything (spec §3 rule 3).

import AVFoundation
import GawdDSP

final class PlaybackEngine {
    static let maxBlock: Int32 = 4096

    private let avEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private(set) var dsp: OpaquePointer?
    private(set) var source: SourceAudio?
    private let outputPointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: 2)
    private var configurationObserver: NSObjectProtocol?

    /// Called on the main queue when the output device changes (headphones,
    /// a different interface, a new sample rate). Output has stopped by then.
    var onOutputChange: (() -> Void)?

    init() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: avEngine, queue: .main
        ) { [weak self] _ in self?.onOutputChange?() }
    }

    /// Restarts output on the same source, if the device's rate still matches.
    /// Returns false when the source must be decoded again at the new rate.
    func restartIfRateUnchanged() -> Bool {
        guard let source, source.sampleRate == outputSampleRate else { return false }
        avEngine.prepare()
        return (try? avEngine.start()) != nil
    }

    /// The output device's sample rate; sources are decoded to this rate.
    var outputSampleRate: Double {
        let rate = avEngine.outputNode.outputFormat(forBus: 0).sampleRate
        return rate > 0 ? rate : 48_000
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        avEngine.stop()
        if let dsp { gs_engine_destroy(dsp) }
        outputPointers.deallocate()
    }

    /// Swaps in a decoded file. Stops output while the engine rebuilds its
    /// stretchers, so the swap never overlaps a render call.
    func load(_ audio: SourceAudio) throws {
        avEngine.stop()
        if let node = sourceNode {
            avEngine.detach(node)
            sourceNode = nil
        }
        if let old = dsp { gs_engine_destroy(old) }

        guard let engine = gs_engine_create(audio.sampleRate, 2, Self.maxBlock) else {
            throw LoadError(kind: .unreadable, details: "gs_engine_create failed")
        }
        var pointers: [UnsafePointer<Float>?] = audio.channels.map { UnsafePointer($0.baseAddress) }
        pointers.withUnsafeMutableBufferPointer {
            gs_engine_set_source(engine, $0.baseAddress!, Int32(audio.channels.count), Int64(audio.frameCount))
        }
        dsp = engine
        source = audio

        let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 2)!
        let outputs = outputPointers
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2 else { return noErr }
            outputs[0] = buffers[0].mData?.assumingMemoryBound(to: Float.self)
            outputs[1] = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            gs_engine_render(engine, outputs, Int32(frameCount))
            return noErr
        }
        avEngine.attach(node)
        avEngine.connect(node, to: avEngine.mainMixerNode, format: format)
        sourceNode = node
        avEngine.prepare()
        try avEngine.start()
    }
}
