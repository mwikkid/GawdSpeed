// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III

import AppKit
import SwiftUI

/// The main window. Laid out at Theme.designSize and scaled as a whole to the
/// window, which keeps the design's aspect ratio, so dragging the corner makes
/// everything bigger together (DECISIONS 2026-10-06, as in Hysterical).
struct ContentView: View {
    @Bindable var player: PlayerViewModel
    @State private var tooltips = TooltipCenter()
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Theme.designSize.width,
                            geometry.size.height / Theme.designSize.height)
            MainLayout(player: player)
                .frame(width: Theme.designSize.width, height: Theme.designSize.height)
                .overlay { FirstRunTips(step: $player.tipStep) }
                .overlay(alignment: .topLeading) { TooltipLayer(bounds: Theme.designSize) }
                .coordinateSpace(name: TooltipCenter.space)
                .environment(tooltips)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .background(Theme.background)
        .onAppear { player.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in player.undoManager = new }
        .background(WindowConfigurator())
        .sheet(isPresented: $player.showingShortcuts) {
            ShortcutSheet().preferredColorScheme(.dark)
        }
        .sheet(item: $player.exportRequest) { request in
            ExportSheet(player: player, request: request)
                .preferredColorScheme(.dark)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            player.open(url)
            return true
        }
    }
}

/// Locks the window to the design's aspect ratio, with the design size as
/// the minimum (§5.11: nothing under 11 pt). Runs when
/// the view joins its window; before that there is no window to configure.
private struct WindowConfigurator: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.contentAspectRatio = Theme.designSize
            window.contentMinSize = Theme.designSize
            window.backgroundColor = NSColor(Theme.background)
            // Only the top strip drags the window. A draggable background
            // stole drags meant for the knobs and the waveform.
            window.isMovableByWindowBackground = false
            // The aspect lock only governs later resizes; bring the current
            // content area to the design's proportions now.
            let width = max(window.contentLayoutRect.width, Theme.designSize.width)
            window.setContentSize(NSSize(width: width,
                                         height: width * Theme.designSize.height / Theme.designSize.width))
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

private struct MainLayout: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar(player: player)
                .padding(.leading, 84) // clear of the window's close/minimise/zoom buttons
                .padding(.trailing, 18)
                .frame(height: 48)

            WaveformArea(player: player)
                .frame(height: 230)
                .padding(.horizontal, 18)

            VStack(spacing: 10) {
                TransportBar(player: player)
                    .frame(height: 40)
                // Live even before a song is open: settings apply when one loads.
                SpeedControl(player: player)
                    .frame(height: 58)
                Divider().overlay(Theme.panelEdge)
                SecondaryControls(player: player)
                    .frame(height: 64)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
    }
}

private struct TopBar: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button { player.showOpenPanel() } label: {
                Label("Open…", systemImage: "folder").font(.system(size: 13))
            }
            .tip(HelpText.open)

            if !player.title.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if let artist = player.artist {
                        Text(artist).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                }
            }

            Spacer()

            Button { player.showingRegions.toggle() } label: {
                Label(player.regions.isEmpty ? "Regions" : "Regions (\(player.regions.count))",
                      systemImage: "bookmark").font(.system(size: 12))
            }
            .popover(isPresented: $player.showingRegions, arrowEdge: .bottom) {
                RegionsPanel(player: player).preferredColorScheme(.dark)
            }
            .tip(HelpText.regions)
            .disabled(!player.hasFile)

            Text("Algorithm").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            Picker("Algorithm", selection: $player.algorithm) {
                ForEach(Algorithm.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
            .tip(HelpText.algorithm)
            .accessibilityLabel("Algorithm")
        }
    }
}

private struct WaveformArea: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Theme.panel)
            RoundedRectangle(cornerRadius: 10).stroke(Theme.panelEdge, lineWidth: 1)
            switch player.loadState {
            case .empty:
                DropZone { player.showOpenPanel() }
            case .loading(let name):
                VStack(spacing: 10) {
                    ProgressView().controlSize(.regular)
                    Text("Loading \(name)…").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            case .failed(let message, let details):
                LoadErrorView(message: message, details: details) { player.showOpenPanel() }
            case .loaded:
                VStack(spacing: 6) {
                    OverviewStrip(player: player)
                        .frame(height: 40)
                    DetailWaveform(player: player)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
        }
    }
}

private struct DropZone: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
                Text("Drop a song here")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                Text("or click to open a file")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                Text("WAV · MP3 · FLAC · AIFF · M4A · MP4 · MOV")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(HelpText.open)
        .accessibilityLabel("Open a song")
    }
}

private struct LoadErrorView: View {
    let message: String
    let details: String
    let tryAnother: () -> Void
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button("Choose Another File…", action: tryAnother)
            DisclosureGroup("Details", isExpanded: $showDetails) {
                Text(details)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(Theme.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            .font(.system(size: 11))
            .frame(maxWidth: 520)
        }
        .padding()
    }
}
