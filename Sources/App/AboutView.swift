// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// About window (spec §7.2): the GawdSpeed license, a link to the source, and
// acknowledgements with every shipped dependency's full license text, read
// from the copies bundled in the app's Resources.

import SwiftUI

struct AboutView: View {
    private struct Component: Identifiable {
        let name: String
        let detail: String
        let licenseFile: String
        var id: String { name }
    }

    private let components = [
        Component(name: "Rubber Band Library v4.0.0", detail: "GPL-2.0-or-later · Particular Programs Ltd.",
                  licenseFile: "GPL-2.0-or-later"),
        Component(name: "Signalsmith Stretch 1.4.0", detail: "MIT · Geraint Luff / Signalsmith Audio Ltd.",
                  licenseFile: "MIT-signalsmith-stretch"),
        Component(name: "Signalsmith Linear 0.6.4", detail: "MIT · Signalsmith Audio",
                  licenseFile: "MIT-signalsmith-linear"),
        Component(name: "FFmpeg 9.0.2 (bundled)", detail: "GPL-3.0-or-later as built · the FFmpeg developers",
                  licenseFile: "GPL-3.0-or-later"),
        Component(name: "LAME 3.100 (inside FFmpeg)", detail: "LGPL-2.0-or-later · the LAME developers",
                  licenseFile: "LGPL-2.0-or-later-LAME"),
    ]

    @State private var shownLicense: String?

    /// The commit this build was made from, stamped in by scripts/release.sh
    /// (GPL: the link must lead to this build's exact source).
    private var sourceCommit: String? {
        let commit = Bundle.main.object(forInfoDictionaryKey: "GSSourceCommit") as? String
        return (commit?.count ?? 0) >= 7 ? commit : nil
    }

    private var sourceURL: URL {
        URL(string: "https://github.com/mwikkid/GawdSpeed" + (sourceCommit.map { "/tree/\($0)" } ?? ""))!
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("GawdSpeed").font(.system(size: 26, weight: .semibold))
                Text("Version \(version)").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Image("iiiAudioWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 14)
                    .foregroundStyle(.secondary)
            }
            Text("Slow songs down without changing their key, for practicing and transcribing by ear.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Copyright (C) 2026 Earl Scioneaux, III").font(.system(size: 12))
                Text("GawdSpeed is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version. It comes with ABSOLUTELY NO WARRANTY.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Link(sourceCommit == nil ? "Source code" : "Source code for this build", destination: sourceURL)
                    Button("GNU GPL v3") { shownLicense = "GPL-3.0-or-later" }.buttonStyle(.link)
                }
                .font(.system(size: 12))
            }

            Divider()
            Text("Built with").font(.system(size: 13, weight: .semibold))
            ForEach(components) { component in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(component.name).font(.system(size: 12))
                        Text(component.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("License") { shownLicense = component.licenseFile }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            Text("Websites: audio is fetched by yt-dlp (Unlicense), which GawdSpeed downloads only when you ask; it isn't included.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("The iii.audio name and logo, and the app icon, are not covered by the GPL.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 480)
        .sheet(item: Binding(get: { shownLicense.map(LicenseName.init) }, set: { shownLicense = $0?.id })) {
            LicenseSheet(name: $0.id)
        }
    }
}

private struct LicenseName: Identifiable { let id: String }

private struct LicenseSheet: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "LICENSES"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License text not found in the app bundle (LICENSES/\(name).txt)."
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(name).font(.headline)
            ScrollView {
                Text(text)
                    .font(.system(size: 11).monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 560, height: 480)
    }
}
