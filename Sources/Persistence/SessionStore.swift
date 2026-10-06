// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Per-song memory (spec §5.9): speed, transpose, algorithm, filters, loop,
// playhead and zoom, saved as JSON in Application Support and keyed by the
// file's content fingerprint, so it survives renaming or moving the file.

import Foundation

struct SongSession: Codable, Equatable {
    var speed: Double
    var semitones: Int
    var cents: Double
    var algorithm: String
    var highpassKnob: Double
    var lowpassKnob: Double
    var selection: Selection?
    var loopEnabled: Bool
    var position: Double
    var visibleStart: Double
    var visibleDuration: Double
}

struct SessionStore {
    let directory: URL

    static let standard = SessionStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GawdSpeed/Sessions", isDirectory: true))

    private func url(_ fingerprint: String) -> URL { directory.appendingPathComponent("\(fingerprint).json") }

    func load(_ fingerprint: String) -> SongSession? {
        guard let data = try? Data(contentsOf: url(fingerprint)) else { return nil }
        return try? JSONDecoder().decode(SongSession.self, from: data)
    }

    func save(_ session: SongSession, for fingerprint: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(session).write(to: url(fingerprint), options: .atomic)
        } catch {
            // Losing a session is an annoyance, not a failure the player should show.
            FileHandle.standardError.write(Data("session save failed: \(error)\n".utf8))
        }
    }
}
