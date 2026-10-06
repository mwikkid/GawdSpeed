// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Menu bar: every action with its shortcut shown (spec §5.11
// "Discoverability"). The shortcuts are the spec's (§5.2, §5.3, §5.7).

import SwiftUI

struct PlayerCommands: Commands {
    let player: PlayerViewModel
    @Environment(\.openWindow) private var openWindow

    /// Single-key shortcuts step aside while a text field has the keyboard.
    private var typing: Bool { player.isEditingText }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About GawdSpeed") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("Open…") { player.showOpenPanel() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(player.recentFiles, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) { player.open(url) }
                }
                if !player.recentFiles.isEmpty { Divider() }
                Button("Clear Menu") { player.clearRecentFiles() }
                    .disabled(player.recentFiles.isEmpty)
            }
            Divider()
            Button("Export…") { player.requestExport(selectionOnly: false) }
                .keyboardShortcut("e")
        }

        CommandMenu("Loop") {
            Button("Set Loop Start at Playhead") { player.setLoopIn() }
                .keyboardShortcut("i", modifiers: [])
                .disabled(typing)
            Button("Set Loop End at Playhead") { player.setLoopOut() }
                .keyboardShortcut("o", modifiers: [])
                .disabled(typing)
            Button(player.loopEnabled ? "Stop Looping" : "Loop Highlighted Section") { player.toggleLoop() }
                .keyboardShortcut("l", modifiers: [])
                .disabled(typing)
            Button("Clear Selection") { player.clearSelection() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(typing || player.selection == nil)
            Divider()
            Button("Zoom In") { player.zoomIn() }
                .keyboardShortcut("+")
            Button("Zoom Out") { player.zoomOut() }
                .keyboardShortcut("-")
            Button("Zoom to Fit") { player.zoomToFit() }
        }

        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(typing)
            Button("Back to Start") { player.backToStart() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(typing)
            Divider()
            Button("Back 1 Second") { player.skip(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(typing)
            Button("Ahead 1 Second") { player.skip(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(typing)
            Button("Back 5 Seconds") { player.skip(by: -5) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
                .disabled(typing)
            Button("Ahead 5 Seconds") { player.skip(by: 5) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
                .disabled(typing)
            Button("Back 0.1 Second") { player.skip(by: -0.1) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(typing)
            Button("Ahead 0.1 Second") { player.skip(by: 0.1) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(typing)
        }

        CommandMenu("Speed") {
            Button("Slower (5%)") { player.nudgeSpeed(by: -0.05) }
                .keyboardShortcut("-", modifiers: [])
                .disabled(typing)
            Button("Faster (5%)") { player.nudgeSpeed(by: 0.05) }
                .keyboardShortcut("=", modifiers: [])
                .disabled(typing)
            Button("A Little Slower (1%)") { player.nudgeSpeed(by: -0.01) }
                .keyboardShortcut("-", modifiers: .option)
                .disabled(typing)
            Button("A Little Faster (1%)") { player.nudgeSpeed(by: 0.01) }
                .keyboardShortcut("=", modifiers: .option)
                .disabled(typing)
            Divider()
            Button("Half Speed (50%)") { player.setSpeedPreset(0.5) }
            Button("Three-Quarter Speed (75%)") { player.setSpeedPreset(0.75) }
            Button("Normal Speed (100%)") { player.setSpeedPreset(1.0) }
            Divider()
            Picker("Algorithm", selection: Binding(get: { player.algorithm }, set: { player.algorithm = $0 })) {
                Text("Algorithm A").tag(Algorithm.a)
                Text("Algorithm B").tag(Algorithm.b)
            }
            .pickerStyle(.inline)
        }

        CommandMenu("Transpose") {
            Button("Down a Semitone") { player.nudgeSemitones(by: -1) }
                .keyboardShortcut("[", modifiers: [])
                .disabled(typing)
            Button("Up a Semitone") { player.nudgeSemitones(by: 1) }
                .keyboardShortcut("]", modifiers: [])
                .disabled(typing)
            Button("Down 5 Cents") { player.nudgeCents(by: -5) }
                .keyboardShortcut("[", modifiers: .option)
                .disabled(typing)
            Button("Up 5 Cents") { player.nudgeCents(by: 5) }
                .keyboardShortcut("]", modifiers: .option)
                .disabled(typing)
            Divider()
            Button("Original Key") { player.resetTranspose() }
                .keyboardShortcut("0")
        }
    }
}
