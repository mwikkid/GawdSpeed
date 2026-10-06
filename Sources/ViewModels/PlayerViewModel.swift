// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III

import AppKit
import GawdDSP
import Observation
import UniformTypeIdentifiers

enum Algorithm: String, CaseIterable, Identifiable {
    case a = "A", b = "B"
    var id: String { rawValue }
    var dsp: GSAlgorithm { self == .a ? GSAlgorithmA : GSAlgorithmB }
}

/// Knob ranges (spec §5.4). Knob position 0...1 is the cutoff on a log taper.
/// High-pass: 20 Hz (all the way down, off) to 2 kHz. Low-pass: 200 Hz to
/// 20 kHz (all the way up, off).
enum FilterRange {
    static let highpassDefault = 0.0
    static let lowpassDefault = 1.0
    static func highpassHz(_ knob: Double) -> Double { 20 * pow(2_000.0 / 20, knob) }
    static func lowpassHz(_ knob: Double) -> Double { 200 * pow(20_000.0 / 200, knob) }
}

@MainActor
@Observable
final class PlayerViewModel {
    enum LoadState: Equatable {
        case empty
        case loading(String)
        case loaded
        case failed(message: String, details: String)
    }

    // MARK: State the UI shows

    private(set) var loadState: LoadState = .empty
    private(set) var title = ""
    private(set) var artist: String?
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var peaks = WaveformPeaks.empty
    private(set) var statusMessage: String?

    var allowFaster: Bool = UserDefaults.standard.bool(forKey: "allowFaster") {
        didSet {
            UserDefaults.standard.set(allowFaster, forKey: "allowFaster")
            if speed > maxSpeed { speed = maxSpeed }
        }
    }
    var maxSpeed: Double { allowFaster ? 1.5 : 1.0 }
    static let minSpeed = 0.25

    // Clamped settings. Stored separately and exposed through plain get/set,
    // so a setter never re-assigns its own property.
    private var speedValue = 1.0
    private var semitoneValue = 0
    private var centValue = 0.0

    /// Playback speed, 0.25...1.0 (1.5 with "allow faster"), in 1% steps.
    var speed: Double {
        get { speedValue }
        set {
            speedValue = min(max((newValue * 100).rounded() / 100, Self.minSpeed), maxSpeed)
            if let dsp { gs_engine_set_speed(dsp, speedValue) }
        }
    }
    var semitones: Int {
        get { semitoneValue }
        set { semitoneValue = min(max(newValue, -12), 12); applyTranspose() }
    }
    var cents: Double {
        get { centValue }
        set { centValue = min(max(newValue.rounded(), -50), 50); applyTranspose() }
    }
    var algorithm: Algorithm = .b { // DECISIONS 2026-10-06: B is the default
        didSet { if let dsp { gs_engine_set_algorithm(dsp, algorithm.dsp) } }
    }
    /// Knob positions, 0...1 (see FilterRange for which end is off).
    var highpassKnob: Double = FilterRange.highpassDefault {
        didSet { if let dsp { gs_engine_set_highpass(dsp, FilterRange.highpassHz(highpassKnob)) } }
    }
    var lowpassKnob: Double = FilterRange.lowpassDefault {
        didSet { if let dsp { gs_engine_set_lowpass(dsp, FilterRange.lowpassHz(lowpassKnob)) } }
    }

    var isTransposed: Bool { semitones != 0 || cents != 0 }
    var hasFile: Bool { loadState == .loaded }

    // MARK: Engine

    private let playback = PlaybackEngine()
    private var dsp: OpaquePointer? { playback.dsp }
    private var loadTask: Task<Void, Never>?
    private var stateTimer: Timer?
    private var statusClear: Task<Void, Never>?

    init() {
        playback.onOutputChange = { [weak self] in
            MainActor.assumeIsolated { self?.outputDeviceChanged() }
        }
    }

    /// Spec §3 rule 5: sources are decoded at the device rate, so a new rate
    /// means decoding again; keep the place in the song and the play state.
    private func outputDeviceChanged() {
        guard hasFile, let url = playback.source?.url else { return }
        if playback.restartIfRateUnchanged() { return }
        let resumeAt = livePosition()
        let wasPlaying = isPlaying
        open(url, resumeAt: resumeAt, play: wasPlaying)
        showStatus("Audio output changed")
    }

    /// The source position being heard, in seconds. Read by the playhead at
    /// display rate; not observed, so polling it doesn't redraw the window.
    func livePosition() -> Double {
        guard let dsp, let source = playback.source else { return 0 }
        return gs_engine_position(dsp) / source.sampleRate
    }

    // MARK: Opening files

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AudioLoader.openableExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = "Choose a song or video to practice with"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL, resumeAt: Double = 0, play resume: Bool = false) {
        loadTask?.cancel()
        pause()
        loadState = .loading(url.deletingPathExtension().lastPathComponent)
        let rate = playback.outputSampleRate
        loadTask = Task {
            let started = Date()
            do {
                let audio = try await Task.detached(priority: .userInitiated) {
                    try await AudioLoader.load(url, sampleRate: rate)
                }.value
                let peaks = await Task.detached(priority: .userInitiated) {
                    WaveformAnalyzer.overview(of: audio)
                }.value
                guard !Task.isCancelled else { return }
                try playback.load(audio)
                title = audio.title
                artist = audio.artist
                duration = audio.duration
                self.peaks = peaks
                if resumeAt == 0 {
                    semitones = 0 // transpose resets on every new file (spec §5.3)
                    cents = 0
                }
                applyAllToEngine()
                if resumeAt > 0 { seek(to: resumeAt) }
                if resume { play() }
                loadState = .loaded
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                let seconds = Date().timeIntervalSince(started)
                FileHandle.standardError.write(Data(String(format: "LOAD %@: %.3f s\n", url.lastPathComponent, seconds).utf8))
                showStatus(String(format: "Opened %@ (%.1f s to load)", audio.title, seconds))
                startStateTimer()
            } catch is CancellationError {
            } catch let error as LoadError {
                loadState = .failed(message: error.errorDescription ?? "", details: error.details)
            } catch {
                loadState = .failed(message: LoadError(kind: .unreadable, details: "").errorDescription ?? "",
                                    details: error.localizedDescription)
            }
        }
    }

    private func applyAllToEngine() {
        guard let dsp else { return }
        gs_engine_set_speed(dsp, speed)
        gs_engine_set_algorithm(dsp, algorithm.dsp)
        gs_engine_set_highpass(dsp, FilterRange.highpassHz(highpassKnob))
        gs_engine_set_lowpass(dsp, FilterRange.lowpassHz(lowpassKnob))
        applyTranspose()
    }

    private func applyTranspose() {
        if let dsp { gs_engine_set_transpose(dsp, Double(semitones) + cents / 100) }
    }

    private func startStateTimer() {
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollEngineState() }
        }
    }

    private func pollEngineState() {
        guard let dsp else { return }
        let playing = gs_engine_is_playing(dsp)
        if playing != isPlaying { isPlaying = playing }
    }

    // MARK: Transport

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard let dsp, hasFile else { return }
        if gs_engine_reached_end(dsp) { gs_engine_seek(dsp, 0) }
        gs_engine_set_playing(dsp, true)
        isPlaying = true
    }

    func pause() {
        guard let dsp else { return }
        gs_engine_set_playing(dsp, false)
        isPlaying = false
    }

    func seek(to seconds: Double) {
        guard let dsp, let source = playback.source else { return }
        let clamped = min(max(seconds, 0), source.duration)
        gs_engine_seek(dsp, Int64(clamped * source.sampleRate))
    }

    func skip(by seconds: Double) { seek(to: livePosition() + seconds) }

    func backToStart() { seek(to: 0) }

    // MARK: Speed and transpose

    func nudgeSpeed(by delta: Double) {
        speed += delta
        showStatus("Speed \(Int((speed * 100).rounded()))%")
    }

    func setSpeedPreset(_ value: Double) {
        speed = value
        showStatus("Speed \(Int((speed * 100).rounded()))%")
    }

    func nudgeSemitones(by delta: Int) {
        semitones += delta
        showStatus(transposeDescription)
    }

    func nudgeCents(by delta: Double) {
        cents += delta
        showStatus(transposeDescription)
    }

    func resetTranspose() {
        semitones = 0
        cents = 0
        showStatus("Transpose off: original key")
    }

    var transposeDescription: String {
        guard isTransposed else { return "Transpose off: original key" }
        var text = "Transpose \(semitones >= 0 ? "+" : "")\(semitones) st"
        if cents != 0 { text += " \(cents >= 0 ? "+" : "")\(Int(cents)) ¢" }
        return text
    }

    // MARK: Status line

    func showStatus(_ message: String) {
        statusMessage = message
        statusClear?.cancel()
        statusClear = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { statusMessage = nil }
        }
    }
}
