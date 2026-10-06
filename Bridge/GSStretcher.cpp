// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III

#include "Stretcher.hpp"

struct GSStretcher {
    std::unique_ptr<gs::Stretcher> impl;
};

extern "C" {

GSStretcher *gs_stretcher_create(GSAlgorithm algorithm, double sampleRate, int32_t channels,
                                 int32_t maxBlockFrames, uint32_t flags,
                                 GSSourceRead read, void *context) {
    if (read == nullptr || channels < 1 || sampleRate <= 0 || maxBlockFrames < 1) return nullptr;
    gs::Source source{read, context};
    auto *stretcher = new GSStretcher;
    switch (algorithm) {
    case GSAlgorithmA:
        stretcher->impl = gs::makeSignalsmithStretcher(sampleRate, channels, maxBlockFrames,
                                                       (flags & GSStretcherFlagCheaper) != 0, source);
        break;
    case GSAlgorithmB:
        stretcher->impl = gs::makeRubberBandStretcher(sampleRate, channels, maxBlockFrames, source);
        break;
    }
    if (!stretcher->impl) {
        delete stretcher;
        return nullptr;
    }
    return stretcher;
}

void gs_stretcher_destroy(GSStretcher *stretcher) { delete stretcher; }

void gs_stretcher_set_speed(GSStretcher *stretcher, double speed) { stretcher->impl->setSpeed(speed); }

void gs_stretcher_set_transpose(GSStretcher *stretcher, double semitones) {
    stretcher->impl->setTranspose(semitones);
}

void gs_stretcher_seek(GSStretcher *stretcher, int64_t position) { stretcher->impl->seek(position); }

void gs_stretcher_render(GSStretcher *stretcher, float *const *output, int32_t frames) {
    stretcher->impl->render(output, frames);
}

double gs_stretcher_position(const GSStretcher *stretcher) { return stretcher->impl->position(); }

int64_t gs_stretcher_input_cursor(const GSStretcher *stretcher) { return stretcher->impl->inputCursor(); }

GSAlgorithm gs_stretcher_algorithm(const GSStretcher *stretcher) { return stretcher->impl->algorithm(); }

} // extern "C"
