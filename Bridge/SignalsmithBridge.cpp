// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// Algorithm A: Signalsmith Stretch (MIT), vendored in ThirdParty/.

#include "Stretcher.hpp"

#include "signalsmith-stretch/signalsmith-stretch.h"

namespace gs {
namespace {

// Fixed seed so the same input always renders the same output.
constexpr long kSeed = 0x6A5D;

class SignalsmithStretcher final : public Stretcher {
public:
    SignalsmithStretcher(double sampleRate, int channels, int maxBlockFrames, bool cheaper, Source source)
        : engine_(kSeed), channels_(channels), maxBlock_(std::max(maxBlockFrames, 1)), source_(source) {
        if (cheaper) engine_.presetCheaper(channels, float(sampleRate));
        else engine_.presetDefault(channels, float(sampleRate));

        const int seekInput = engine_.seekLength();
        const int discardInput = int(std::ceil(engine_.outputLatency() * kMaxSpeed)) + 2;
        const int chunkInput = int(std::ceil(maxBlock_ * kMaxSpeed)) + 2;
        input_.allocate(channels, std::max({seekInput, discardInput, chunkInput}));
        discard_.allocate(channels, std::max(engine_.outputLatency(), 1));
        outputPointers_.resize(size_t(channels));

        // The first seek sizes the engine's scratch buffers; later seeks reuse them.
        seek(0);
    }

    GSAlgorithm algorithm() const override { return GSAlgorithmA; }

    void setSpeed(double speed) override { speed_ = clampSpeed(speed); }

    void setTranspose(double semitones) override {
        engine_.setTransposeSemitones(float(clampTranspose(semitones)));
    }

    void seek(int64_t position) override {
        engine_.reset();
        inputFraction_ = 0;

        // Hand the engine the audio leading up to `position` so its processing
        // time lands exactly on `position` (README: "Seeking and starting").
        const int latency = engine_.inputLatency();
        const int length = engine_.seekLength();
        const int64_t end = position + latency;
        source_(end - length, input_.data(), length);
        engine_.seek(input_.data(), length, speed_);
        cursor_ = end;

        // The next outputLatency() frames are pre-roll from before `position`.
        // Render and drop them, so the next frame out is the one at `position`.
        const int discardFrames = engine_.outputLatency();
        const int discardInput = takeInputFrames(discardFrames);
        source_(cursor_, input_.data(), discardInput);
        engine_.process(input_.data(), discardInput, discard_.data(), discardFrames);
        cursor_ += discardInput;

        position_ = double(position);
    }

    void render(float *const *output, int frames) override {
        int done = 0;
        while (done < frames) {
            const int n = std::min(frames - done, maxBlock_);
            const int inputFrames = takeInputFrames(n);
            source_(cursor_, input_.data(), inputFrames);
            for (int c = 0; c < channels_; ++c) outputPointers_[size_t(c)] = output[c] + done;
            engine_.process(input_.data(), inputFrames, outputPointers_.data(), n);
            cursor_ += inputFrames;
            position_ += n * speed_;
            done += n;
        }
    }

    double position() const override { return position_; }
    int64_t inputCursor() const override { return cursor_; }

private:
    // How many input frames to consume for `outputFrames` of output at the
    // current speed, carrying the fractional remainder to the next call.
    int takeInputFrames(int outputFrames) {
        const double wanted = inputFraction_ + outputFrames * speed_;
        const int frames = int(std::floor(wanted));
        inputFraction_ = wanted - frames;
        return frames;
    }

    signalsmith::stretch::SignalsmithStretch<float> engine_;
    const int channels_;
    const int maxBlock_;
    const Source source_;

    PlanarBuffer input_;
    PlanarBuffer discard_;
    std::vector<float *> outputPointers_;

    double speed_ = 1.0;
    double inputFraction_ = 0;
    int64_t cursor_ = 0;
    double position_ = 0;
};

} // namespace

std::unique_ptr<Stretcher> makeSignalsmithStretcher(double sampleRate, int channels, int maxBlockFrames,
                                                    bool cheaper, Source source) {
    return std::make_unique<SignalsmithStretcher>(sampleRate, channels, maxBlockFrames, cheaper, source);
}

} // namespace gs
