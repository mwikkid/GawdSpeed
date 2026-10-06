// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Menu bar: every action with its shortcut shown (spec §5.11
// "Discoverability"). The shortcuts are the spec's (§5.2, §5.3, §5.7).

import SwiftUI

struct PlayerCommands: Commands {
    let player: PlayerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About GawdSpeed") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("Open…") { player.showOpenPanel() }
                .keyboardShortcut("o")
        }

        CommandMenu("Playback") {
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Back to Start") { player.backToStart() }
                .keyboardShortcut(.return, modifiers: [])
            Divider()
            Button("Back 1 Second") { player.skip(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Ahead 1 Second") { player.skip(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Back 5 Seconds") { player.skip(by: -5) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("Ahead 5 Seconds") { player.skip(by: 5) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("Back 0.1 Second") { player.skip(by: -0.1) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button("Ahead 0.1 Second") { player.skip(by: 0.1) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
        }

        CommandMenu("Speed") {
            Button("Slower (5%)") { player.nudgeSpeed(by: -0.05) }
                .keyboardShortcut("-", modifiers: [])
            Button("Faster (5%)") { player.nudgeSpeed(by: 0.05) }
                .keyboardShortcut("=", modifiers: [])
            Button("A Little Slower (1%)") { player.nudgeSpeed(by: -0.01) }
                .keyboardShortcut("-", modifiers: .option)
            Button("A Little Faster (1%)") { player.nudgeSpeed(by: 0.01) }
                .keyboardShortcut("=", modifiers: .option)
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
            Button("Up a Semitone") { player.nudgeSemitones(by: 1) }
                .keyboardShortcut("]", modifiers: [])
            Button("Down 5 Cents") { player.nudgeCents(by: -5) }
                .keyboardShortcut("[", modifiers: .option)
            Button("Up 5 Cents") { player.nudgeCents(by: 5) }
                .keyboardShortcut("]", modifiers: .option)
            Divider()
            Button("Original Key") { player.resetTranspose() }
                .keyboardShortcut("0")
        }
    }
}
