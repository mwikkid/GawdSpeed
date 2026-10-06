// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III

import AppKit
import SwiftUI

@main
struct GawdSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var player = PlayerViewModel()

    var body: some Scene {
        Window("GawdSpeed", id: "main") {
            ContentView(player: player)
                .preferredColorScheme(.dark)
                .onAppear { appDelegate.player = player }
        }
        // No title-bar strip: the scaled interface is the whole window, so one
        // aspect ratio fits both (a fixed-height title bar can't scale).
        .windowStyle(.hiddenTitleBar)
        .defaultSize(Theme.designSize)
        .commands { PlayerCommands(player: player) }

        Window("About GawdSpeed", id: "about") {
            AboutView()
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(player: player)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var player: PlayerViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dark mode only (spec §10).
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Files dropped on the Dock icon or chosen from Open Recent.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated { player?.open(url) }
    }
}

struct SettingsView: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        Form {
            Toggle("Allow speeds above 100% (up to 150%)", isOn: $player.allowFaster)
        }
        .padding(20)
        .frame(width: 380)
    }
}
