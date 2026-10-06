// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The C++ interface both engines implement. Nothing outside Bridge/ sees it.

#pragma once

#include "include/GSStretcher.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>

namespace gs {

constexpr double kMinSpeed = 0.25;
constexpr double kMaxSpeed = 1.5;
constexpr double kMaxTranspose = 12.0;

/// Planar float buffer allocated once, up front.
class PlanarBuffer {
public:
    PlanarBuffer() = default;
    PlanarBuffer(int channels, int frames) { allocate(channels, frames); }

    void allocate(int channels, int frames) {
        storage_.assign(size_t(channels) * size_t(frames), 0.0f);
        pointers_.resize(size_t(channels));
        for (int c = 0; c < channels; ++c) pointers_[size_t(c)] = storage_.data() + size_t(c) * size_t(frames);
        frames_ = frames;
    }

    float *const *data() const { return pointers_.data(); }
    float *channel(int c) const { return pointers_[size_t(c)]; }
    int frames() const { return frames_; }

private:
    std::vector<float> storage_;
    std::vector<float *> pointers_;
    int frames_ = 0;
};

struct Source {
    GSSourceRead read = nullptr;
    void *context = nullptr;
    void operator()(int64_t start, float *const *dest, int32_t frames) const {
        if (frames > 0) read(context, start, dest, frames);
    }
};

class Stretcher {
public:
    virtual ~Stretcher() = default;

    virtual GSAlgorithm algorithm() const = 0;
    virtual void setSpeed(double speed) = 0;
    virtual void setTranspose(double semitones) = 0;
    virtual void seek(int64_t position) = 0;
    virtual void render(float *const *output, int frames) = 0;
    virtual double position() const = 0;
    virtual int64_t inputCursor() const = 0;

    static double clampSpeed(double s) { return std::clamp(s, kMinSpeed, kMaxSpeed); }
    static double clampTranspose(double st) { return std::clamp(st, -kMaxTranspose, kMaxTranspose); }
};

std::unique_ptr<Stretcher> makeSignalsmithStretcher(double sampleRate, int channels, int maxBlockFrames,
                                                    bool cheaper, Source source);
std::unique_ptr<Stretcher> makeRubberBandStretcher(double sampleRate, int channels, int maxBlockFrames,
                                                   Source source);

} // namespace gs
