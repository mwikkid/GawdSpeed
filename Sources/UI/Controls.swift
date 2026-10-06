// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The transport row, the speed control (big, primary) and the transpose and
// filter row (small, secondary), spec §5.2–5.4 and §5.7.

import SwiftUI

/// m:ss.t. Rounds to tenths before splitting, so 179.97 s reads 3:00.0, not 2:60.0.
func formatTime(_ seconds: Double) -> String {
    let tenths = Int((max(0, seconds) * 10).rounded())
    return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}

struct TransportBar: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) { transportControls }
                .disabled(!player.hasFile)

            Spacer()

            // Status line (spec §5.11): brief, non-blocking messages.
            Text(player.statusMessage ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.2), value: player.statusMessage)
        }
    }

    @ViewBuilder private var transportControls: some View {
            transportButton("backward.end.fill", HelpText.backToStart, "Back to start") { player.backToStart() }
            transportButton("gobackward.5", HelpText.rewind, "Skip back 5 seconds") { player.skip(by: -5) }
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 34)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.primaryText)
            .tip(HelpText.playPause)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            transportButton("goforward.5", HelpText.forward, "Skip ahead 5 seconds") { player.skip(by: 5) }

            TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                Text("\(formatTime(player.livePosition()))  /  \(formatTime(player.duration))")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
            }
            .tip(HelpText.time)
            .accessibilityLabel("Position")
    }

    private func transportButton(_ symbol: String, _ help: String, _ label: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.secondaryText)
        .tip(help)
        .accessibilityLabel(label)
    }
}

struct SpeedControl: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("SPEED")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)
                .frame(width: 62, alignment: .leading)

            Slider(value: $player.speed, in: PlayerViewModel.minSpeed...player.maxSpeed, step: 0.01) {
                Text("Speed")
            } minimumValueLabel: {
                Text("25%").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            } maximumValueLabel: {
                Text("\(Int(player.maxSpeed * 100))%").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            .labelsHidden()
            .tint(Theme.accent)
            .controlSize(.large)
            .tip(HelpText.speedSlider)
            .accessibilityValue("\(Int((player.speed * 100).rounded())) percent")
            .contextMenu { Button("Reset to Default") { player.speed = 1 } }

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int((player.speed * 100).rounded()))%")
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Text(String(format: "×%.2f", player.speed))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(width: 86, alignment: .trailing)
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                preset(0.5, HelpText.speed50)
                preset(0.75, HelpText.speed75)
                preset(1.0, HelpText.speed100)
            }
        }
    }

    private func preset(_ value: Double, _ help: String) -> some View {
        let selected = abs(player.speed - value) < 0.001
        return Button { player.setSpeedPreset(value) } label: {
            Text("\(Int(value * 100))")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .frame(width: 40, height: 28)
                .background(Capsule().fill(selected ? Theme.accent.opacity(0.25) : Theme.panel))
                .overlay(Capsule().stroke(selected ? Theme.accent : Theme.panelEdge, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.accent : Theme.primaryText)
        .tip(help)
        .accessibilityLabel("\(Int(value * 100)) percent speed")
    }
}

struct SecondaryControls: View {
    @Bindable var player: PlayerViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Transpose: whole semitones.
            HStack(spacing: 6) {
                Text("transpose")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize()
                smallButton("minus", "Transpose down a semitone") { player.nudgeSemitones(by: -1) }
                Text("\(player.semitones > 0 ? "+" : "")\(player.semitones) st")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(player.semitones == 0 ? Theme.secondaryText : Theme.primaryText)
                    .frame(width: 40)
                smallButton("plus", "Transpose up a semitone") { player.nudgeSemitones(by: 1) }
            }
            .tip(HelpText.transpose)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Transpose")
            .accessibilityValue("\(player.semitones) semitones")
            .accessibilityAdjustableAction { player.nudgeSemitones(by: $0 == .increment ? 1 : -1) }

            Spacer().frame(width: 26)

            // Tune: cents, for recordings that aren't at A440.
            HStack(spacing: 6) {
                Text("tune")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize()
                Slider(value: $player.cents, in: -50...50, step: 1)
                    .controlSize(.mini)
                    .frame(width: 90)
                    .tint(Theme.secondaryText)
                    .contextMenu { Button("Reset to Default") { player.cents = 0 } }
                Text("\(player.cents > 0 ? "+" : "")\(Int(player.cents)) ¢")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(player.cents == 0 ? Theme.secondaryText : Theme.primaryText)
                    .frame(width: 40, alignment: .leading)
            }
            .tip(HelpText.tune)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tune")
            .accessibilityValue("\(Int(player.cents)) cents")
            .accessibilityAdjustableAction { player.nudgeCents(by: $0 == .increment ? 5 : -5) }

            // Lights up only when the key is shifted; click to undo.
            Button { player.resetTranspose() } label: {
                HStack(spacing: 5) {
                    Circle().fill(Theme.activeDot).frame(width: 8, height: 8)
                    Text("original key").font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.activeDot.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primaryText)
            .opacity(player.isTransposed ? 1 : 0)
            .disabled(!player.isTransposed)
            .tip(HelpText.resetKey)
            .accessibilityLabel("Reset to the original key")
            .accessibilityHidden(!player.isTransposed)

            Spacer(minLength: 12)

            // Maker's mark (DECISIONS 2026-10-06). Not covered by the GPL;
            // see THIRD_PARTY_NOTICES.md.
            Image("iiiAudioWordmark")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 13)
                .foregroundStyle(Theme.secondaryText.opacity(0.7))
                .accessibilityLabel("iii.audio")

            Spacer(minLength: 12)

            HStack(spacing: 18) {
                Knob(label: "HIGH-PASS", value: $player.highpassKnob, defaultValue: FilterRange.highpassDefault,
                     valueText: player.highpassKnob == FilterRange.highpassDefault
                        ? "off" : hzText(FilterRange.highpassHz(player.highpassKnob)),
                     help: HelpText.highpass)
                Knob(label: "LOW-PASS", value: $player.lowpassKnob, defaultValue: FilterRange.lowpassDefault,
                     valueText: player.lowpassKnob == FilterRange.lowpassDefault
                        ? "off" : hzText(FilterRange.lowpassHz(player.lowpassKnob)),
                     help: HelpText.lowpass)
            }
        }
    }

    private func hzText(_ hz: Double) -> String {
        hz >= 1_000 ? String(format: "%.1f kHz", hz / 1_000) : "\(Int(hz.rounded())) Hz"
    }

    private func smallButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.secondaryText)
        .accessibilityLabel(label)
    }
}
