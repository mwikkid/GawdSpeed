// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Import from a website (spec §8.2): runs yt-dlp to fetch the best audio
// stream as-is (no re-encode), into ~/Music/GawdSpeed/Downloads by default.
// yt-dlp is not bundled (it needs frequent updates): GawdSpeed uses an
// installed copy, or downloads the official release into Application Support.

import Foundation

enum URLImporter {
    enum ImportError: LocalizedError {
        case noTool
        case failed(details: String)

        var errorDescription: String? {
            switch self {
            case .noTool: "GawdSpeed needs yt-dlp to grab audio from websites."
            case .failed: "Couldn't get audio from that link. The page may be private, region-locked, or not a site yt-dlp supports."
            }
        }
        var details: String {
            switch self {
            case .noTool: "yt-dlp not found"
            case .failed(let details): details
            }
        }
    }

    // MARK: Links

    /// A pasted string that looks like a web link (http/https with a host).
    static func link(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".") else { return nil }
        return url
    }

    /// Sites worth offering the "Use copied link?" chip for (yt-dlp supports
    /// many more; any link can still be pasted).
    static func isLikelyMediaLink(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return ["youtube.com", "youtu.be", "soundcloud.com", "bandcamp.com", "vimeo.com", "mixcloud.com"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: Where yt-dlp is

    /// GawdSpeed's own copy, downloaded on request.
    static var managedCopy: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GawdSpeed/bin/yt-dlp")
    }

    static let installedCandidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]

    /// The yt-dlp to use: a path chosen in Settings, GawdSpeed's own copy, or
    /// an installed one.
    static func executable(preferred: String?) -> URL? {
        var candidates: [String] = []
        if let preferred, !preferred.isEmpty { candidates.append(preferred) }
        candidates.append(managedCopy.path)
        candidates += installedCandidates
        return candidates.map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var defaultDownloadFolder: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GawdSpeed/Downloads", isDirectory: true)
    }

    // MARK: Downloading audio

    /// The yt-dlp arguments (spec §8.2): best audio as-is, no playlists, one
    /// progress line per update, and the final file path printed at the end.
    static func arguments(for link: URL, into folder: URL, ffmpeg: URL?) -> [String] {
        var args = ["-f", "bestaudio/best", "--no-playlist", "--newline", "--no-simulate",
                    "--progress-template", "download:GSPROGRESS %(progress._percent_str)s",
                    "--print", "after_move:GSFILE %(filepath)s",
                    "-o", folder.appendingPathComponent("%(title)s.%(ext)s").path]
        if let ffmpeg { args += ["--ffmpeg-location", ffmpeg.path] }
        args.append(link.absoluteString)
        return args
    }

    /// Reads one line of yt-dlp output: a progress fraction, or the final file.
    enum OutputLine: Equatable {
        case progress(Double)
        case file(String)
        case other
    }

    static func parse(_ line: String) -> OutputLine {
        if line.hasPrefix("GSPROGRESS ") {
            let number = line.dropFirst("GSPROGRESS ".count)
                .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            if let value = Double(number) { return .progress(min(max(value / 100, 0), 1)) }
            return .other
        }
        if line.hasPrefix("GSFILE ") { return .file(String(line.dropFirst("GSFILE ".count))) }
        return .other
    }

    /// Downloads the audio behind `link`. Returns the file. Cancellable.
    static func download(_ link: URL, into folder: URL, tool: URL, ffmpeg: URL?,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments(for: link, into: folder, ffmpeg: ffmpeg)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let state = ImportState()

        out.fileHandleForReading.readabilityHandler = { handle in
            for line in state.lines(from: handle.availableData) {
                switch parse(line) {
                case .progress(let p): progress(p)
                case .file(let path): state.setFile(path)
                case .other: break
                }
            }
        }
        err.fileHandleForReading.readabilityHandler = { handle in state.appendError(handle.availableData) }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                process.terminationHandler = { finished in
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    for line in state.lines(from: out.fileHandleForReading.readDataToEndOfFile(), flush: true) {
                        if case .file(let path) = parse(line) { state.setFile(path) }
                    }
                    state.appendError(err.fileHandleForReading.readDataToEndOfFile())
                    if finished.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else if finished.terminationStatus == 0, let path = state.file,
                              FileManager.default.fileExists(atPath: path) {
                        continuation.resume(returning: URL(fileURLWithPath: path))
                    } else {
                        let tail = state.errorText.split(separator: "\n").suffix(4).joined(separator: "\n")
                        continuation.resume(throwing: ImportError.failed(details: tail.isEmpty
                            ? "yt-dlp exited with status \(finished.terminationStatus)" : tail))
                    }
                }
                do { try process.run() } catch {
                    continuation.resume(throwing: ImportError.failed(details: error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: Getting yt-dlp

    static let officialRelease = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

    /// Downloads the official yt-dlp release into Application Support and
    /// checks that it runs. Only when the person clicks the setup button.
    static func installOfficialCopy() async throws -> String {
        let (temp, response) = try await URLSession.shared.download(from: officialRelease)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ImportError.failed(details: "download failed: \(response)")
        }
        let destination = managedCopy
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return try await version(of: destination)
    }

    /// `yt-dlp -U` (the standalone release updates itself).
    static func update(_ tool: URL) async throws -> String {
        _ = try await run(tool, ["-U"])
        return try await version(of: tool)
    }

    static func version(of tool: URL) async throws -> String {
        try await run(tool, ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(_ tool: URL, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if finished.terminationStatus == 0 { continuation.resume(returning: text) } else {
                    continuation.resume(throwing: ImportError.failed(details: text))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

/// Line buffering and results shared between the pipe handlers.
private final class ImportState: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var errorData = Data()
    private(set) var file: String?

    func lines(from data: Data, flush: Bool = false) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...newline)
        }
        if flush, !pending.isEmpty {
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll()
        }
        return lines.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
    }

    func setFile(_ path: String) { lock.lock(); file = path; lock.unlock() }
    func appendError(_ data: Data) { lock.lock(); errorData.append(data); lock.unlock() }
    var errorText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errorData, as: UTF8.self) }
}
