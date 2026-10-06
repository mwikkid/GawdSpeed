// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The dark palette (spec §10) and the design size the interface is laid out
// at. The window scales everything from this size, like Hysterical.

import SwiftUI

enum Theme {
    /// The interface is laid out at this size and scaled to fit the window.
    /// 900 × 490: the spec's 900 × 520 less the bottom strip Earl asked to
    /// crop once the logo moved into the controls row (DECISIONS).
    static let designSize = CGSize(width: 900, height: 490)

    static let background = Color(red: 0.071, green: 0.078, blue: 0.094)
    static let panel = Color(red: 0.106, green: 0.118, blue: 0.141)
    static let panelEdge = Color.white.opacity(0.06)
    static let waveform = Color(red: 0.36, green: 0.40, blue: 0.46)
    static let waveformPlayed = Color(red: 0.62, green: 0.67, blue: 0.74)
    /// The speed control's colour: the one thing that should draw the eye.
    static let accent = Color(red: 0.95, green: 0.65, blue: 0.26)
    static let primaryText = Color(red: 0.92, green: 0.93, blue: 0.95)
    /// Secondary text, about 7:1 on the background (WCAG AA needs 4.5:1).
    static let secondaryText = Color(red: 0.62, green: 0.65, blue: 0.70)
    static let playhead = Color.white
    static let activeDot = Color(red: 0.98, green: 0.42, blue: 0.33)
}
