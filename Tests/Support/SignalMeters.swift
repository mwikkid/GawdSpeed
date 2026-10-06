// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Measuring instruments for the DSP tests. Each one is checked against
// signals with a known answer in InstrumentTests before it is trusted to
// judge a stretcher.

import Accelerate
import Foundation

func cents(_ frequency: Double, relativeTo reference: Double) -> Double {
    1200 * log2(frequency / reference)
}

/// Frequency of the strongest partial in `samples[start ..< start + 65536]`:
/// Hann window, zero-padded 4x, Gaussian (log-parabolic) interpolation of
/// the peak. Padded bin width at 48 kHz is 0.18 Hz; 1 cent at 440 Hz is 0.25 Hz.
func dominantFrequency(_ samples: [Float], start: Int, sampleRate: Double = testSampleRate) -> Double {
    let windowLength = 1 << 16
    let log2n = vDSP_Length(18)
    let n = 1 << 18
    precondition(start >= 0 && start + windowLength <= samples.count, "window outside signal")

    var frame = [Float](repeating: 0, count: n)
    var window = [Float](repeating: 0, count: windowLength)
    vDSP_hann_window(&window, vDSP_Length(windowLength), Int32(vDSP_HANN_DENORM))
    samples.withUnsafeBufferPointer { src in
        vDSP_vmul(src.baseAddress! + start, 1, window, 1, &frame, 1, vDSP_Length(windowLength))
    }

    var real = [Float](repeating: 0, count: n / 2)
    var imag = [Float](repeating: 0, count: n / 2)
    var power = [Float](repeating: 0, count: n / 2)
    real.withUnsafeMutableBufferPointer { re in
        imag.withUnsafeMutableBufferPointer { im in
            var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
            frame.withUnsafeBytes { raw in
                vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
            }
            let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
            vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            vDSP_destroy_fftsetup(setup)
            vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
        }
    }
    power[0] = 0 // zrip packs Nyquist into bin 0's imaginary part

    var peak: Float = 0
    var peakIndex: vDSP_Length = 0
    vDSP_maxvi(power, 1, &peak, &peakIndex, vDSP_Length(n / 2))
    let k = Int(peakIndex)
    precondition(k > 0 && k < n / 2 - 1, "peak at the edge of the spectrum")

    let a = log(Double(power[k - 1])), b = log(Double(power[k])), c = log(Double(power[k + 1]))
    let offset = 0.5 * (a - c) / (a - 2 * b + c)
    return (Double(k) + offset) * sampleRate / Double(n)
}

/// Where a tone switches on and off, in seconds: the first and last 1 ms
/// window whose RMS is at least half the median RMS of the loud windows.
func toneSpan(_ samples: [Float], sampleRate: Double = testSampleRate) -> (on: Double, off: Double)? {
    let hop = Int(sampleRate * 0.001)
    let windowCount = samples.count / hop
    guard windowCount > 2 else { return nil }
    var rms = [Float](repeating: 0, count: windowCount)
    samples.withUnsafeBufferPointer { src in
        for w in 0..<windowCount {
            vDSP_rmsqv(src.baseAddress! + w * hop, 1, &rms[w], vDSP_Length(hop))
        }
    }
    guard let loudest = rms.max(), loudest > 1e-4 else { return nil }
    let loud = rms.filter { $0 > loudest * 0.25 }.sorted()
    let threshold = loud[loud.count / 2] * 0.5
    guard let first = rms.firstIndex(where: { $0 >= threshold }),
          let last = rms.lastIndex(where: { $0 >= threshold }) else { return nil }
    let windowSeconds = Double(hop) / sampleRate
    return (Double(first) * windowSeconds + windowSeconds / 2, Double(last) * windowSeconds + windowSeconds / 2)
}

/// Naive varispeed (changes pitch with speed). A deliberately wrong
/// "stretcher" the tests use to prove their checks can fail.
func varispeed(_ samples: [Float], speed: Double, outputFrames: Int) -> [Float] {
    (0..<outputFrames).map { i in
        let x = Double(i) * speed
        let j = Int(x)
        guard j + 1 < samples.count else { return 0 }
        let f = Float(x - Double(j))
        return samples[j] * (1 - f) + samples[j + 1] * f
    }
}
