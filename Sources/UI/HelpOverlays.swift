// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// First-run tips and the keyboard-shortcut cheat sheet (spec §5.11).

import SwiftUI

// MARK: - Keyboard shortcuts

struct ShortcutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let groups: [(String, [(String, String)])] = [
        ("Playback", [("Space", "Play or pause"), ("Return", "Back to the loop start, or the song's start"),
                      ("← / →", "Back or ahead 1 second"), ("⇧← / ⇧→", "Back or ahead 5 seconds"),
                      ("⌥← / ⌥→", "Back or ahead 0.1 second")]),
        ("Speed", [("− / =", "Slower or faster by 5%"), ("⌥− / ⌥=", "Slower or faster by 1%")]),
        ("Key", [("[ / ]", "Transpose down or up a semitone"), ("⌥[ / ⌥]", "Tune down or up 5 cents"),
                 ("⌘0", "Back to the original key")]),
        ("Loop", [("I / O", "Loop start or end at the playhead"), ("L", "Loop on or off"),
                  ("Esc", "Clear the highlighted section")]),
        ("Waveform", [("⌘+ / ⌘−", "Zoom in or out"), ("Pinch, ⌘-scroll", "Zoom"),
                      ("Scroll", "Move through the song")]),
        ("Files", [("⌘O", "Open a song"), ("⌘E", "Export"), ("⌘Z / ⇧⌘Z", "Undo or redo")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Shortcuts").font(.system(size: 18, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                GridItem(.flexible(), alignment: .topLeading)], spacing: 16) {
                ForEach(groups, id: \.0) { title, rows in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                        ForEach(rows, id: \.0) { key, action in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(key)
                                    .font(.system(size: 12, weight: .medium).monospaced())
                                    .frame(width: 110, alignment: .leading)
                                Text(action).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640)
    }
}

// MARK: - First-run tips

/// Three short tips shown on first launch: open a song, drag the speed slider,
/// highlight and loop. Dismissible; "Don't show again" sticks; Help ▸ Show
/// Tips brings them back.
struct FirstRunTips: View {
    @Binding var step: Int? // nil = hidden
    @AppStorage("tipsDone") private var tipsDone = false

    private struct Tip {
        let title: String
        let body: String
        /// Where the card sits in the design-size layout, beside what it describes.
        let position: CGPoint
    }

    private let tips = [
        Tip(title: "1. Open a song",
            body: "Drag a song from Finder onto the window, or press ⌘O. MP3, WAV, AIFF, M4A, FLAC and video files all work.",
            position: CGPoint(x: 450, y: 165)),
        Tip(title: "2. Slow it down",
            body: "Drag the orange SPEED slider, or click 50 or 75. The key stays the same.",
            position: CGPoint(x: 360, y: 285)),
        Tip(title: "3. Loop the hard part",
            body: "Drag across the waveform to highlight a section, then press L to loop it. Press L again to stop.",
            position: CGPoint(x: 450, y: 165)),
    ]

    var body: some View {
        if let step, step < tips.count {
            let tip = tips[step]
            VStack(alignment: .leading, spacing: 10) {
                Text(tip.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primaryText)
                Text(tip.body)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Don't show again") {
                        tipsDone = true
                        self.step = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    Spacer()
                    Text("\(step + 1) of \(tips.count)").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    // Click-only: Return stays "Back to Start". (A Return shortcut here
                    // worked once, then the menu's Return took it back.)
                    Button(step + 1 < tips.count ? "Next" : "Got it") {
                        if step + 1 < tips.count { self.step = step + 1 } else {
                            tipsDone = true
                            self.step = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 360)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.17, green: 0.19, blue: 0.23)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.7), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
            .position(tip.position)
            .transition(.opacity)
        }
    }
}
