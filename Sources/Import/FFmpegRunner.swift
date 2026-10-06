// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Runs the bundled ffmpeg (spec §8.1): arguments as an array (never a shell
// string), cancellable, stderr kept for the error's "Details". Falls back to
// a system ffmpeg if the bundled one is missing.

import Foundation

enum FFmpegRunner {
    struct Failure: LocalizedError {
        let status: Int32
        let stderr: String
        var errorDescription: String? { "ffmpeg failed (exit \(status))" }
    }

    /// The ffmpeg to use: the app's own, then (for tests and development)
    /// GAWDSPEED_FFMPEG or the repo's build output, then Homebrew's.
    static var executable: URL? {
        var candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ffmpeg")]
        let env = ProcessInfo.processInfo.environment
        if let path = env["GAWDSPEED_FFMPEG"] { candidates.append(URL(fileURLWithPath: path)) }
        if let root = env["GAWDSPEED_SOURCE_ROOT"] {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent("build/ffmpeg/ffmpeg"))
        }
        candidates += ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].map(URL.init(fileURLWithPath:))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs ffmpeg and returns its stderr. Throws Failure on a non-zero exit,
    /// CancellationError if the task is cancelled (the process is terminated).
    @discardableResult
    static func run(_ arguments: [String]) async throws -> String {
        guard let executable else {
            throw Failure(status: -1, stderr: "No ffmpeg found (bundled, GAWDSPEED_FFMPEG, or Homebrew).")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-hide_banner", "-nostdin"] + arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        // Read stderr as it arrives so a chatty ffmpeg can't fill the pipe and stall.
        let collected = StderrBuffer()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            collected.append(handle.availableData)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                process.terminationHandler = { finished in
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    collected.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    let text = collected.text
                    if finished.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else if finished.terminationStatus != 0 {
                        continuation.resume(throwing: Failure(status: finished.terminationStatus, stderr: text))
                    } else {
                        continuation.resume(returning: text)
                    }
                }
                do { try process.run() } catch {
                    continuation.resume(throwing: Failure(status: -1, stderr: error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// Reads "title : ..." style tags from the input section of ffmpeg's stderr.
    static func tags(fromStderr text: String) -> [String: String] {
        var tags: [String: String] = [:]
        var inInput = false
        for line in text.split(separator: "\n") {
            if line.hasPrefix("Input #0") { inInput = true; continue }
            if line.hasPrefix("Output #") || line.hasPrefix("Stream mapping") { break }
            guard inInput, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if ["title", "artist"].contains(key), tags[key] == nil, !value.isEmpty { tags[key] = value }
        }
        return tags
    }
}

private final class StderrBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ more: Data) { lock.lock(); data.append(more); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
