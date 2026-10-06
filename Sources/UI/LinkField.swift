// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The link field (spec §5.11): paste a YouTube, SoundCloud or Bandcamp link
// and press Return. Shows progress while downloading, and a "Use copied
// link?" chip when the clipboard holds one.

import SwiftUI

struct LinkField: View {
    @Bindable var player: PlayerViewModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                if let progress = player.importProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                    Button { player.cancelImport() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .tip("Stop the download")
                } else {
                    TextField("Paste a YouTube, SoundCloud or Bandcamp link…", text: $player.linkText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($focused)
                        .onSubmit { player.importLink() }
                    if !player.linkText.isEmpty {
                        Button { player.importLink() } label: { Image(systemName: "arrow.down.circle.fill") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.accent)
                            .tip("Get the audio from this link (Return)")
                    }
                }
            }
            .padding(.horizontal, 9)
            .frame(width: 260, height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? Theme.accent.opacity(0.7) : Theme.panelEdge,
                                                              lineWidth: 1))
            .tip(HelpText.link)

            if let offered = player.offeredLink {
                HStack(spacing: 4) {
                    Button("Use copied link?") { player.useOfferedLink() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Button { player.dismissOfferedLink() } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Theme.accent.opacity(0.15)))
                .fixedSize()
                .tip("Get the audio from the link you copied: \(offered.host ?? offered.absoluteString)")
            }
        }
        .onChange(of: focused) { _, isFocused in player.isEditingText = isFocused }
        .onChange(of: player.focusLinkField) { _, _ in focused = true }
        // macOS hands the window's first text field the keyboard on launch, which
        // switched off Space and the other single-key shortcuts until a click
        // elsewhere. The field takes the keyboard only when clicked or on ⌘U.
        .onAppear { DispatchQueue.main.async { focused = false } }
    }
}

/// Shown the first time a link is used without yt-dlp (spec §5.11: a
/// friendly one-click setup, not an error).
struct YtDlpSetupSheet: View {
    @Bindable var player: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get audio from websites").font(.system(size: 18, weight: .semibold))
            Text("GawdSpeed uses yt-dlp, a free open-source tool, to fetch the audio from YouTube, SoundCloud, Bandcamp, Vimeo and many other sites. It isn't built in because it needs frequent updates as sites change.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Text("Only download audio you have the right to use.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.activeDot)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Use a Copy I Already Have…") { chooseInstalled() }
                    .disabled(working)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                Button {
                    install()
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Download yt-dlp") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
            Text("Downloads the official release from github.com/yt-dlp into GawdSpeed's Application Support folder. Update it any time in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 480)
        .onAppear { player.isEditingText = true }
        .onDisappear { player.isEditingText = false }
    }

    private func install() {
        working = true
        message = nil
        Task {
            do {
                let version = try await URLImporter.installOfficialCopy()
                player.showStatus("yt-dlp \(version) is ready")
                dismiss()
                player.continuePendingImport()
            } catch {
                working = false
                message = "Couldn't download yt-dlp. Check your internet connection and try again. (\(error.localizedDescription))"
            }
        }
    }

    private func chooseInstalled() {
        let panel = NSOpenPanel()
        panel.message = "Choose the yt-dlp program"
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            message = "That file isn't a program GawdSpeed can run."
            return
        }
        player.ytdlpPath = url.path
        dismiss()
        player.continuePendingImport()
    }
}
