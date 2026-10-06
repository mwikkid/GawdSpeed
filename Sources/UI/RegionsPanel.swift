// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Named regions (spec §5.9): a list of saved sections for this song. Opens
// from the top bar as a panel rather than a permanent sidebar, so the scaled
// window keeps its shape (DECISIONS).

import SwiftUI

struct RegionsPanel: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Regions").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { player.addRegion() } label: {
                    Label("Save Highlighted Section", systemImage: "plus")
                }
                .disabled(player.selection == nil)
                .help("Save the highlighted section with a name (⌘D)")
            }
            if player.regions.isEmpty {
                Text("Highlight a section of the song, then save it here with a name like \"Bridge lick\". Click a saved region to jump back and loop it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(player.regions) { region in
                            RegionRow(player: player, region: region)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { player.isEditingText = true } // names are typed here
        .onDisappear { player.isEditingText = false }
    }
}

private struct RegionRow: View {
    @Bindable var player: PlayerViewModel
    let region: NamedRegion
    @State private var name = ""

    private var isCurrent: Bool { player.selection == region.selection }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .onSubmit { player.renameRegion(region.id, to: name) }
                .onAppear { name = region.name }
                .onChange(of: name) { _, new in player.renameRegion(region.id, to: new) }
            Spacer()
            Text("\(formatTime(region.selection.start)) – \(formatTime(region.selection.end))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
            Button { player.goTo(region) } label: { Image(systemName: "arrow.right.circle") }
                .buttonStyle(.borderless)
                .help("Jump here and highlight it")
            Button {
                player.goTo(region)
                player.loopEnabled = true
            } label: { Image(systemName: "repeat") }
                .buttonStyle(.borderless)
                .help("Jump here and loop it")
            Button { player.deleteRegion(region.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this region")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Theme.selection.opacity(0.18) : Theme.panel))
    }
}
