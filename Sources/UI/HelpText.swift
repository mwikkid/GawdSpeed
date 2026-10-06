// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Every tooltip and accessibility label in one place (spec §5.11), so the
// wording is easy to edit. Plain musician language; shortcut in parentheses.

enum HelpText {
    static let open = "Open an audio or video file: WAV, MP3, FLAC, AIFF, M4A, MP4, MOV and more (⌘O). You can also drag a file onto the window."
    static let playPause = "Play or pause (Space)"
    static let backToStart = "Jump back to the start of the song (Return)"
    static let rewind = "Skip back 5 seconds (⇧←)"
    static let forward = "Skip ahead 5 seconds (⇧→)"
    static let speedSlider = "Slow the song down without changing its key. 100% is normal speed (− / =)"
    static let speed50 = "Jump to half speed"
    static let speed75 = "Jump to three-quarter speed"
    static let speed100 = "Jump to normal speed"
    static let transpose = "Change the key in semitones (half steps) without changing the speed. Leave at 0 unless you want to play it in another key ([ / ])"
    static let tune = "Fine-tune in cents (hundredths of a semitone), for recordings that are slightly sharp or flat compared to your instrument (⌥[ / ⌥])"
    static let resetKey = "The key is shifted. Click to go back to the original key (⌘0)"
    static let highpass = "Remove the bass. Drag up to cut more low end. Double-click to reset"
    static let lowpass = "Remove the treble. Drag down to cut more high end. Double-click to reset"
    static let algorithm = "Two different ways of slowing down audio. Try both: one may sound better on this song"
    static let waveform = "The whole song. Click anywhere to jump there"
    static let time = "Where you are in the song"
}
