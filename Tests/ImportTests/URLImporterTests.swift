// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// URL import plumbing, tested against a stand-in yt-dlp (a shell script that
// prints what yt-dlp prints), so no network and no real media are involved.

import XCTest

final class URLImporterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testLinkRecognition() {
        XCTAssertNotNil(URLImporter.link(from: " https://www.youtube.com/watch?v=abc123 \n"))
        XCTAssertNotNil(URLImporter.link(from: "https://soundcloud.com/artist/track"))
        XCTAssertNil(URLImporter.link(from: "not a link"))
        XCTAssertNil(URLImporter.link(from: "file:///Users/me/song.mp3"))
        XCTAssertNil(URLImporter.link(from: "https://localhost"))
        XCTAssertTrue(URLImporter.isLikelyMediaLink(URL(string: "https://music.youtube.com/watch?v=x")!))
        XCTAssertTrue(URLImporter.isLikelyMediaLink(URL(string: "https://youtu.be/x")!))
        XCTAssertFalse(URLImporter.isLikelyMediaLink(URL(string: "https://example.com/x")!))
    }

    func testParsesProgressAndFile() {
        XCTAssertEqual(URLImporter.parse("GSPROGRESS  42.3%"), .progress(0.423))
        XCTAssertEqual(URLImporter.parse("GSPROGRESS 100.0%"), .progress(1))
        XCTAssertEqual(URLImporter.parse("GSFILE /Users/me/Music/GawdSpeed/Downloads/Song.webm"),
                       .file("/Users/me/Music/GawdSpeed/Downloads/Song.webm"))
        XCTAssertEqual(URLImporter.parse("[youtube] abc: Downloading webpage"), .other)
    }

    func testArgumentsMatchTheSpec() {
        let args = URLImporter.arguments(for: URL(string: "https://youtu.be/x")!, into: directory,
                                         ffmpeg: URL(fileURLWithPath: "/tmp/ffmpeg"))
        XCTAssertEqual(Array(args.prefix(3)), ["-f", "bestaudio/best", "--no-playlist"])
        XCTAssertTrue(args.contains("--ffmpeg-location"))
        XCTAssertFalse(args.contains("-x"), "no re-encode: the stream is kept as-is")
        XCTAssertEqual(args.last, "https://youtu.be/x")
    }

    private func fakeTool(_ body: String) throws -> URL {
        let url = directory.appendingPathComponent("fake-yt-dlp")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// The whole run: progress arrives, the file the tool reports comes back.
    func testDownloadReportsProgressAndFile() async throws {
        let target = directory.appendingPathComponent("Some Song.webm").path
        let tool = try fakeTool("""
        echo "[youtube] x: Downloading webpage"
        for p in 10.0 55.5 100.0; do echo "GSPROGRESS  $p%"; done
        printf 'audio' > "\(target)"
        echo "GSFILE \(target)"
        """)
        let seen = ProgressLog()
        let file = try await URLImporter.download(URL(string: "https://youtu.be/x")!, into: directory,
                                                  tool: tool, ffmpeg: nil) { seen.add($0) }
        XCTAssertEqual(file.path, target)
        XCTAssertEqual(seen.values, [0.1, 0.555, 1.0])
    }

    func testFailureCarriesTheToolsReason() async throws {
        let tool = try fakeTool("echo 'ERROR: [youtube] x: Video unavailable' >&2; exit 1")
        do {
            _ = try await URLImporter.download(URL(string: "https://youtu.be/x")!, into: directory,
                                               tool: tool, ffmpeg: nil) { _ in }
            XCTFail("a failing tool returned a file")
        } catch let error as URLImporter.ImportError {
            XCTAssertTrue(error.details.contains("Video unavailable"))
        }
    }

    func testCancelStopsTheTool() async throws {
        // A child process, like the ffmpeg yt-dlp runs. 307 s is just a marker.
        let tool = try fakeTool("echo 'GSPROGRESS 1%'; sleep 307; echo finished")
        let task = Task {
            try await URLImporter.download(URL(string: "https://youtu.be/x")!, into: directory,
                                           tool: tool, ffmpeg: nil) { _ in }
        }
        try await Task.sleep(for: .milliseconds(300))
        let started = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled download returned")
        } catch is CancellationError {
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the tool kept running after cancel")
        try await Task.sleep(for: .milliseconds(200))
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        check.arguments = ["-f", "sleep 307"]
        check.standardOutput = FileHandle.nullDevice
        try check.run()
        check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus, 1, "the tool's child process was left running")
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func add(_ v: Double) { lock.lock(); stored.append(v); lock.unlock() }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
}
