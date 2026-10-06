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

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { player?.saveSession() }
    }

    /// Files dropped on the Dock icon or chosen from Open Recent.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated { player?.open(url) }
    }
}

struct SettingsView: View {
    @Bindable var player: PlayerViewModel
    @State private var devices: [OutputDevice] = []

    var body: some View {
        Form {
            Toggle("Allow speeds above 100% (up to 150%)", isOn: $player.allowFaster)
            Toggle("Snap loop points to zero crossings", isOn: $player.snapToZeroCrossing)
                .help("Moves loop edges up to 5 ms to where the wave crosses zero, which avoids clicks")
            HStack {
                Slider(value: $player.prerollSeconds, in: 0...2, step: 0.25) { Text("Loop pre-roll") }
                Text(player.prerollSeconds == 0 ? "off" : String(format: "%.2g s", player.prerollSeconds))
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            .help("Start each pass of the loop this long before the loop start, to get a run-up")
            Picker("Follow the playhead", selection: $player.followMode) {
                Text("Page by page").tag(PlayerViewModel.FollowMode.page)
                Text("Smooth scrolling").tag(PlayerViewModel.FollowMode.smooth)
            }
            Picker("Play through", selection: $player.outputDeviceUID) {
                Text("System default").tag(String?.none)
                ForEach(devices) { Text($0.name).tag(Optional($0.uid)) }
            }
            .help("Which speakers, headphones or interface GawdSpeed plays through")
            Section("Advanced") {
                Toggle("Algorithm A: lighter preset (uses less processing)", isOn: $player.signalsmithCheaper)
                    .help("Signalsmith Stretch's \"cheaper\" preset. Try it on an older Mac if playback stutters")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { devices = OutputDevices.all() }
    }
}
