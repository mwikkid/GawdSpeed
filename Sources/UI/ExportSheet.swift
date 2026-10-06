// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The Export sheet (spec §5.8): range, speed / transpose / algorithm (start
// at the current values, editable here), apply filters, format; then a save
// panel, progress with cancel, and "Show in Finder" at the end.

import AppKit
import GawdDSP
import SwiftUI

struct ExportSheet: View {
    @Bindable var player: PlayerViewModel
    let request: PlayerViewModel.ExportRequest

    @State private var options: ExportOptions
    @State private var wholeSong: Bool
    @State private var progress: Double?
    @State private var finishedURL: URL?
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @AppStorage("exportFormat") private var formatRaw = ExportFormat.wav.rawValue
    @AppStorage("exportBitDepth") private var bitDepth = 24
    @AppStorage("exportAACBitRate") private var aacBitRate = 256
    @AppStorage("exportMP3BitRate") private var mp3BitRate = 320
    @Environment(\.dismiss) private var dismiss

    init(player: PlayerViewModel, request: PlayerViewModel.ExportRequest) {
        self.player = player
        self.request = request
        let hasSelection = player.selection != nil
        _options = State(initialValue: player.exportOptions(selectionOnly: hasSelection))
        _wholeSong = State(initialValue: !hasSelection)
    }

    private var format: ExportFormat { ExportFormat(rawValue: formatRaw) ?? .wav }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export").font(.system(size: 18, weight: .semibold))

            Form {
                Picker("Range", selection: $wholeSong) {
                    Text("Whole song").tag(true)
                    if let s = player.selection {
                        Text("Highlighted section (\(formatTime(s.start)) – \(formatTime(s.end)))").tag(false)
                    }
                }
                HStack {
                    Slider(value: $options.speed, in: 0.25...(player.allowFaster ? 1.5 : 1.0), step: 0.01) {
                        Text("Speed")
                    }
                    Text("\(Int((options.speed * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Stepper(value: $options.transpose, in: -12...12, step: 1) {
                    Text("Transpose: \(options.transpose >= 0 ? "+" : "")\(String(format: "%g", options.transpose)) st")
                }
                Picker("Algorithm", selection: Binding(get: { options.algorithm == GSAlgorithmA ? "A" : "B" },
                                                       set: { options.algorithm = $0 == "A" ? GSAlgorithmA : GSAlgorithmB })) {
                    Text("A").tag("A")
                    Text("B").tag("B")
                }
                .pickerStyle(.segmented)
                Toggle("Apply the high-pass and low-pass filters", isOn: $options.applyFilters)

                Picker("Format", selection: $formatRaw) {
                    ForEach(ExportFormat.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                if format == .aac {
                    Picker("Quality", selection: $aacBitRate) {
                        ForEach(ExportFormat.aacBitRates, id: \.self) { Text("\($0) kbps").tag($0) }
                    }
                } else if format == .mp3 {
                    Picker("Quality", selection: $mp3BitRate) {
                        ForEach(ExportFormat.mp3BitRates, id: \.self) {
                            Text($0 == 0 ? "V0 (variable, best)" : "\($0) kbps").tag($0)
                        }
                    }
                } else {
                    Picker("Bit depth", selection: $bitDepth) {
                        ForEach(format.bitDepths, id: \.self) { Text($0 == 32 ? "32-bit float" : "\($0)-bit").tag($0) }
                    }
                }
            }
            .disabled(progress != nil)

            if let progress {
                ProgressView(value: progress) { Text(finishedURL == nil ? "Exporting…" : "Done") }
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(Theme.activeDot)
            }

            HStack {
                if let finishedURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finishedURL]) }
                }
                Spacer()
                if finishedURL != nil {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else if progress != nil {
                    Button("Cancel") { task?.cancel() }.keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Export…") { chooseDestination() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { player.isEditingText = true } // the sheet takes the keyboard
        .onDisappear { player.isEditingText = false }
        .onChange(of: formatRaw) { _, _ in
            if !format.bitDepths.isEmpty, !format.bitDepths.contains(bitDepth) { bitDepth = 24 }
        }
    }

    private func finalOptions() -> ExportOptions {
        var o = options
        o.range = wholeSong ? nil : player.selection.map { $0.start...$0.end }
        o.format = format
        o.bitDepth = format.bitDepths.contains(bitDepth) ? bitDepth : 24
        o.aacBitRate = aacBitRate
        o.mp3BitRate = mp3BitRate
        return o
    }

    private func chooseDestination() {
        guard let source = player.sourceURL else { return }
        let o = finalOptions()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportRenderer.suggestedFileName(title: player.title, options: o)
        panel.directoryURL = source.deletingLastPathComponent()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        errorMessage = nil
        progress = 0
        task = Task {
            do {
                try await ExportRenderer.export(from: source, options: o, to: destination) { value in
                    Task { @MainActor in progress = value }
                }
                finishedURL = destination
                progress = 1
                player.showStatus("Exported to \(destination.deletingLastPathComponent().lastPathComponent)")
            } catch is CancellationError {
                progress = nil
                player.showStatus("Export cancelled")
            } catch {
                progress = nil
                errorMessage = "Couldn't export: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }
}
