// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Algorithm B: Rubber Band Library v4 (GPL-2.0-or-later), R3 "finer" engine,
// real-time mode. Vendored in ThirdParty/rubberband; the library itself is
// compiled from ThirdParty/rubberband/single/RubberBandSingle.cpp.

#include "Stretcher.hpp"

#include "rubberband/rubberband/RubberBandStretcher.h"

namespace gs {
namespace {

using RubberBand::RubberBandStretcher;

constexpr RubberBandStretcher::Options kOptions =
    RubberBandStretcher::OptionProcessRealTime |
    RubberBandStretcher::OptionEngineFiner |
    RubberBandStretcher::OptionPitchHighConsistency;

// Largest block handed to process(); also what setMaxProcessSize promises.
constexpr int kProcessChunk = 4096;

// Upper bound on process/retrieve rounds in one render call, so a stretcher
// that stops producing can never hang the audio thread.
constexpr int kMaxRoundsPerRender = 4096;

class RubberBandStretcherImpl final : public Stretcher {
public:
    RubberBandStretcherImpl(double sampleRate, int channels, int maxBlockFrames, Source source)
        : engine_(size_t(sampleRate), size_t(channels), kOptions, 1.0, 1.0),
          channels_(channels), source_(source) {
        (void)maxBlockFrames; // render() works in whatever sizes Rubber Band asks for
        engine_.setMaxProcessSize(kProcessChunk);
        input_.allocate(channels, kProcessChunk);
        discard_.allocate(channels, kProcessChunk);
        outputPointers_.resize(size_t(channels));
        seek(0);
    }

    GSAlgorithm algorithm() const override { return GSAlgorithmB; }

    void setSpeed(double speed) override {
        speed_ = clampSpeed(speed);
        engine_.setTimeRatio(1.0 / speed_);
    }

    void setTranspose(double semitones) override {
        engine_.setPitchScale(std::pow(2.0, clampTranspose(semitones) / 12.0));
    }

    void seek(int64_t position) override {
        engine_.reset(); // keeps the current time ratio and pitch scale

        // Rubber Band asks for getPreferredStartPad() frames of padding before
        // the first frame we want to hear, and its output starts
        // getStartDelay() frames late. Feed real audio as the padding (so the
        // start isn't a fade-in from silence) and drop the delay.
        cursor_ = position - int64_t(engine_.getPreferredStartPad());
        discardRemaining_ = int(engine_.getStartDelay());
        position_ = double(position);
    }

    void render(float *const *output, int frames) override {
        int done = 0;
        for (int round = 0; done < frames && round < kMaxRoundsPerRender; ++round) {
            const int available = engine_.available();
            if (available > 0 && discardRemaining_ > 0) {
                const int n = std::min({available, discardRemaining_, discard_.frames()});
                engine_.retrieve(discard_.data(), size_t(n));
                discardRemaining_ -= n;
            } else if (available > 0) {
                const int n = std::min(available, frames - done);
                for (int c = 0; c < channels_; ++c) outputPointers_[size_t(c)] = output[c] + done;
                engine_.retrieve(outputPointers_.data(), size_t(n));
                done += n;
            } else {
                int n = int(engine_.getSamplesRequired());
                if (n <= 0) n = 256;
                n = std::min(n, kProcessChunk);
                source_(cursor_, input_.data(), n);
                engine_.process(input_.data(), size_t(n), false);
                cursor_ += n;
            }
        }
        // Only reachable if the engine stalls: output silence rather than garbage.
        for (int c = 0; c < channels_ && done < frames; ++c)
            std::fill(output[c] + done, output[c] + frames, 0.0f);

        position_ += frames * speed_;
    }

    double position() const override { return position_; }
    int64_t inputCursor() const override { return cursor_; }

private:
    RubberBandStretcher engine_;
    const int channels_;
    const Source source_;

    PlanarBuffer input_;
    PlanarBuffer discard_;
    std::vector<float *> outputPointers_;

    double speed_ = 1.0;
    int discardRemaining_ = 0;
    int64_t cursor_ = 0;
    double position_ = 0;
};

} // namespace

std::unique_ptr<Stretcher> makeRubberBandStretcher(double sampleRate, int channels, int maxBlockFrames,
                                                   Source source) {
    return std::make_unique<RubberBandStretcherImpl>(sampleRate, channels, maxBlockFrames, source);
}

} // namespace gs
