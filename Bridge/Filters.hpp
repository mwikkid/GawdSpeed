// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// 24 dB/octave Butterworth high-pass and low-pass: two cascaded 2-pole
// state-variable filters (trapezoidal integration), Q = 0.5412 and 1.3066.
// The response is the same as a pair of bilinear-transform biquads, but the
// state-variable form can have its cutoff moved every sample without the
// zipper noise a biquad makes when its coefficients jump. (A biquad version
// clicked audibly when the low-pass knob moved; see FINDINGS F2.)
//
// At its "off" position the filter is fully bypassed. Switching in or out
// crossfades dry/filtered over 10 ms, because even a 20 kHz low-pass shifts
// the phase of what it passes and an abrupt switch is a click.

#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace gs {

class ButterworthFilter {
public:
    enum class Type { LowPass, HighPass };

    static constexpr double kGlideSeconds = 0.02;   // cutoff smoothing time constant
    static constexpr double kSwitchSeconds = 0.010; // dry/filtered crossfade

    explicit ButterworthFilter(Type type) : type_(type) {}

    void prepare(double sampleRate, int channels) {
        sampleRate_ = sampleRate;
        state_.assign(size_t(channels), {});
        glide_ = 1.0 - std::exp(-1.0 / (kGlideSeconds * sampleRate));
        wetStep_ = float(1.0 / (kSwitchSeconds * sampleRate));
        offHz_ = type_ == Type::HighPass ? 20.0 : std::min(20000.0, 0.45 * sampleRate);
        active_ = false;
        currentHz_ = offHz_;
        wet_ = 0;
    }

    /// `off` means the knob is at its default; the filter glides there and
    /// then switches itself out.
    void setTarget(double hz, bool off) {
        targetOff_ = off;
        targetHz_ = std::clamp(hz, 20.0, 0.45 * sampleRate_);
    }

    bool active() const { return active_; }

    void process(float *const *buffer, int channels, int frames) {
        if (!active_) {
            if (targetOff_) return;
            // Switching in: start from the "off" end so the change glides,
            // and fade the filtered signal in.
            active_ = true;
            wet_ = 0;
            currentHz_ = offHz_;
            for (auto &s : state_) s = {};
        }
        const double logGoal = std::log(targetOff_ ? offHz_ : targetHz_);
        double logHz = std::log(currentHz_);
        const int channelCount = std::min(channels, int(state_.size()));

        for (int i = 0; i < frames; ++i) {
            logHz += (logGoal - logHz) * glide_;
            const double g = std::tan(M_PI * std::exp(logHz) / sampleRate_);
            // At the off position, fade the filtered signal out, then bypass.
            const bool releasing = targetOff_ && std::abs(logHz - logGoal) < 0.01;
            wet_ = releasing ? std::max(0.0f, wet_ - wetStep_) : std::min(1.0f, wet_ + wetStep_);

            for (int c = 0; c < channelCount; ++c) {
                const double dry = buffer[c][i];
                double v = dry;
                for (int k = 0; k < 2; ++k) v = state_[size_t(c)][size_t(k)].tick(v, g, kInverseQ[k], type_);
                buffer[c][i] = float(dry + (v - dry) * wet_);
            }
            if (releasing && wet_ == 0.0f) {
                active_ = false;
                break;
            }
        }
        currentHz_ = std::exp(logHz);
    }

private:
    // 1/Q of each section of a 4th-order Butterworth: 2 cos(pi/8), 2 cos(3pi/8).
    static constexpr double kInverseQ[2] = {1.8477590650225735, 0.7653668647301796};

    // Two-pole state-variable filter, trapezoidal integrators.
    struct Section {
        double ic1 = 0, ic2 = 0;
        double tick(double x, double g, double k, Type type) {
            const double a1 = 1.0 / (1.0 + g * (g + k));
            const double a2 = g * a1;
            const double a3 = g * a2;
            const double v3 = x - ic2;
            const double v1 = a1 * ic1 + a2 * v3;
            const double v2 = ic2 + a2 * ic1 + a3 * v3;
            ic1 = 2 * v1 - ic1;
            ic2 = 2 * v2 - ic2;
            return type == Type::LowPass ? v2 : x - k * v1 - v2;
        }
    };

    const Type type_;
    double sampleRate_ = 48000;
    double glide_ = 0.001;
    double offHz_ = 20;
    double currentHz_ = 20;
    double targetHz_ = 20;
    bool targetOff_ = true;
    bool active_ = false;
    float wet_ = 0;
    float wetStep_ = 0.002f;
    std::vector<std::array<Section, 2>> state_;
};

} // namespace gs
