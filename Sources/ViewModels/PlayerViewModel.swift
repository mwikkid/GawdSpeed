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
    private(set) var pyramid: PeakPyramid?
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
        saveSession() // the song we're leaving, while it's still the loaded one
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
                let fingerprint = await Task.detached(priority: .userInitiated) { FileFingerprint.of(url) }.value
                let pyramid = await Task.detached(priority: .userInitiated) { () -> PeakPyramid in
                    if let fingerprint, let cached = PeakPyramid.cached(
                        fingerprint: fingerprint, sampleRate: audio.sampleRate, frameCount: audio.frameCount) {
                        return cached
                    }
                    let built = PeakPyramid(channels: audio.channels, frameCount: audio.frameCount)
                    if let fingerprint { built.store(fingerprint: fingerprint, sampleRate: audio.sampleRate) }
                    return built
                }.value
                guard !Task.isCancelled else { return }
                try playback.load(audio)
                title = audio.title
                artist = audio.artist
                duration = audio.duration
                self.pyramid = pyramid
                self.fingerprint = fingerprint
                selection = nil
                loopEnabled = false
                visibleStart = 0
                visibleDuration = audio.duration
                if resumeAt == 0 {
                    semitones = 0 // transpose resets on every new file (spec §5.3)
                    cents = 0
                }
                applyAllToEngine()
                var pickedUp = false
                if resumeAt == 0, let fingerprint, let session = sessions.load(fingerprint) {
                    restore(session)
                    pickedUp = true
                }
                if resumeAt > 0 { seek(to: resumeAt) }
                if resume { play() }
                loadState = .loaded
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                recentFiles = NSDocumentController.shared.recentDocumentURLs
                let seconds = Date().timeIntervalSince(started)
                FileHandle.standardError.write(Data(String(format: "LOAD %@: %.3f s\n", url.lastPathComponent, seconds).utf8))
                showStatus(pickedUp ? "Picked up \(audio.title) where you left off" : "Opened \(audio.title)")
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
        if playing, followMode == .page, isFollowing { pageFlipIfNeeded() }
        pollCount += 1
        if pollCount % 50 == 0 { saveSession() }
    }
    @ObservationIgnored private var pollCount = 0

    // MARK: Transport

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard let dsp, hasFile else {
            showStatus("Open a song first: drop it on the window, or press ⌘O")
            return
        }
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

    func skip(by seconds: Double) {
        guard hasFile else { return play() } // play() explains how to open a song
        seek(to: livePosition() + seconds)
    }

    /// Return: the loop's start if there is a selection, else the song's (spec §5.7).
    func backToStart() {
        guard hasFile else { return play() }
        seek(to: selection?.start ?? 0)
    }

    // MARK: Selection and loop (spec §5.6)

    private(set) var selection: Selection?
    var loopEnabled = false {
        didSet {
            syncLoop()
            if loopEnabled, let selection, !(selection.start...selection.end).contains(livePosition()) {
                seek(to: selection.start)
            }
        }
    }
    var snapToZeroCrossing: Bool = UserDefaults.standard.object(forKey: "snapToZeroCrossing") as? Bool ?? true {
        didSet { UserDefaults.standard.set(snapToZeroCrossing, forKey: "snapToZeroCrossing") }
    }
    /// Seconds each loop pass starts before loop-in, 0...2.
    var prerollSeconds: Double = UserDefaults.standard.double(forKey: "loopPreroll") {
        didSet {
            UserDefaults.standard.set(prerollSeconds, forKey: "loopPreroll")
            syncLoop()
        }
    }
    /// True while a text field is being typed in, so single-key shortcuts
    /// (Space, I, O, L, arrows...) type instead of firing.
    var isEditingText = false

    /// Sets the highlighted section. Edges snap to zero crossings unless
    /// `snap` is false (dragging snaps only when the drag ends).
    func setSelection(_ newValue: Selection?, snap: Bool = true) {
        guard var s = newValue?.clamped(to: duration), s.length >= Selection.minimumLength else {
            selection = nil
            if loopEnabled { loopEnabled = false } else { syncLoop() }
            return
        }
        if snap, snapToZeroCrossing, let source = playback.source {
            s = Selection(
                ZeroCrossing.snap(s.start, channels: source.channels, frameCount: source.frameCount,
                                  sampleRate: source.sampleRate),
                ZeroCrossing.snap(s.end, channels: source.channels, frameCount: source.frameCount,
                                  sampleRate: source.sampleRate))
        }
        selection = s
        syncLoop()
    }

    func finishSelectionEdit() {
        setSelection(selection)
        if let selection { showStatus("Loop set: \(formatTime(selection.start)) – \(formatTime(selection.end))") }
    }

    func setLoopIn() {
        guard hasFile else { return play() }
        let t = livePosition()
        setSelection(Selection(t, max(selection?.end ?? duration, t + Selection.minimumLength)))
        if let selection { showStatus("Loop starts at \(formatTime(selection.start))") }
    }

    func setLoopOut() {
        guard hasFile else { return play() }
        let t = livePosition()
        setSelection(Selection(min(selection?.start ?? 0, t - Selection.minimumLength), t))
        if let selection { showStatus("Loop ends at \(formatTime(selection.end))") }
    }

    func toggleLoop() {
        guard selection != nil else {
            showStatus("Highlight a section first: drag across the waveform, or press I and O")
            return
        }
        loopEnabled.toggle()
        showStatus(loopEnabled ? "Loop on" : "Loop off")
    }

    func clearSelection() {
        setSelection(nil)
        showStatus("Selection cleared")
    }

    private func syncLoop() {
        guard let dsp, let source = playback.source else { return }
        let rate = source.sampleRate
        if let selection {
            gs_engine_set_loop(dsp, Int64(selection.start * rate), Int64(selection.end * rate), loopEnabled)
        } else {
            gs_engine_set_loop(dsp, 0, 0, false)
        }
        gs_engine_set_loop_preroll(dsp, Int64(min(max(prerollSeconds, 0), 2) * rate))
    }

    // MARK: Waveform view (spec §5.5)

    enum FollowMode: String, CaseIterable { case page, smooth }

    /// The part of the song the detail waveform shows, in seconds.
    var visibleStart: Double = 0
    var visibleDuration: Double = 1
    var followMode: FollowMode = FollowMode(rawValue: UserDefaults.standard.string(forKey: "followMode") ?? "") ?? .page {
        didSet { UserDefaults.standard.set(followMode.rawValue, forKey: "followMode") }
    }
    /// Following pauses for a few seconds after the user scrolls by hand.
    private var manualScrollAt: Date?
    var isFollowing: Bool { manualScrollAt.map { Date().timeIntervalSince($0) > 4 } ?? true }

    static let minimumVisible = 0.05 // seconds; about 2,400 samples at 48 kHz

    func zoom(by factor: Double, around time: Double) {
        guard duration > 0 else { return }
        let newDuration = min(max(visibleDuration / factor, Self.minimumVisible), duration)
        let anchor = (time - visibleStart) / visibleDuration
        visibleDuration = newDuration
        setVisibleStart(time - anchor * newDuration)
    }

    func zoomIn() { zoom(by: 2, around: livePositionClampedToView()) }
    func zoomOut() { zoom(by: 0.5, around: livePositionClampedToView()) }
    func zoomToFit() { visibleDuration = duration; setVisibleStart(0) }

    private func livePositionClampedToView() -> Double {
        min(max(livePosition(), visibleStart), visibleStart + visibleDuration)
    }

    /// Scrolls by hand: pauses following for a few seconds.
    func scrollView(by seconds: Double) {
        manualScrollAt = Date()
        setVisibleStart(visibleStart + seconds)
    }

    func setVisibleStart(_ start: Double) {
        visibleStart = min(max(start, 0), max(0, duration - visibleDuration))
    }

    /// Page-flip following: when the playhead leaves the view, turn the page.
    private func pageFlipIfNeeded() {
        let p = livePosition()
        if p < visibleStart || p > visibleStart + visibleDuration * 0.97 {
            setVisibleStart(p - visibleDuration * 0.03)
        }
    }

    /// For smooth following: where the view would start to keep the playhead
    /// a third of the way in. Read while drawing; changes nothing.
    func smoothFollowStart(at position: Double) -> Double {
        min(max(position - visibleDuration / 3, 0), max(0, duration - visibleDuration))
    }

    var sourceAudio: SourceAudio? { playback.source }

    // MARK: Per-song memory (spec §5.9) and Open Recent

    private let sessions = SessionStore.standard
    private var fingerprint: String?
    private(set) var recentFiles: [URL] = NSDocumentController.shared.recentDocumentURLs

    func clearRecentFiles() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        recentFiles = []
    }

    var currentSession: SongSession {
        SongSession(speed: speed, semitones: semitones, cents: cents, algorithm: algorithm.rawValue,
                    highpassKnob: highpassKnob, lowpassKnob: lowpassKnob, selection: selection,
                    loopEnabled: loopEnabled, position: livePosition(),
                    visibleStart: visibleStart, visibleDuration: visibleDuration)
    }

    /// Saves the open song's settings. Called when switching songs, every few
    /// seconds while open (if anything changed), and when the app quits.
    func saveSession() {
        guard hasFile, let fingerprint else { return }
        let session = currentSession
        guard session != lastSaved else { return }
        sessions.save(session, for: fingerprint)
        lastSaved = session
    }
    @ObservationIgnored private var lastSaved: SongSession?

    private func restore(_ session: SongSession) {
        speed = session.speed
        semitones = session.semitones
        cents = session.cents
        algorithm = Algorithm(rawValue: session.algorithm) ?? .b
        highpassKnob = session.highpassKnob
        lowpassKnob = session.lowpassKnob
        visibleDuration = min(max(session.visibleDuration, Self.minimumVisible), duration)
        setVisibleStart(session.visibleStart)
        setSelection(session.selection, snap: false)
        loopEnabled = session.loopEnabled && selection != nil
        seek(to: session.position)
        lastSaved = session
    }

    // MARK: Export (spec §5.8)

    struct ExportRequest: Identifiable {
        let id = UUID()
        let selectionOnly: Bool
    }
    var exportRequest: ExportRequest?

    func requestExport(selectionOnly: Bool) {
        guard hasFile else { return play() }
        exportRequest = ExportRequest(selectionOnly: selectionOnly && selection != nil)
    }

    /// The current settings as export options (the sheet lets you change them).
    func exportOptions(selectionOnly: Bool) -> ExportOptions {
        ExportOptions(range: selectionOnly ? selection.map { $0.start...$0.end } : nil,
                      speed: speed, transpose: Double(semitones) + cents / 100, algorithm: algorithm.dsp,
                      applyFilters: true, highpassHz: FilterRange.highpassHz(highpassKnob),
                      lowpassHz: FilterRange.lowpassHz(lowpassKnob))
    }

    var sourceURL: URL? { playback.source?.url }

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
