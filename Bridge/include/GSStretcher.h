// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// C interface to the two time-stretch engines. Swift only ever sees this
// header; the C++ engines stay behind it.

#ifndef GS_STRETCHER_H
#define GS_STRETCHER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum GSAlgorithm {
    GSAlgorithmA = 0, ///< Signalsmith Stretch
    GSAlgorithmB = 1  ///< Rubber Band Library, R3 ("finer") engine
} GSAlgorithm;

typedef enum GSStretcherFlags {
    GSStretcherFlagNone = 0,
    GSStretcherFlagCheaper = 1 ///< Algorithm A only: Signalsmith's "cheaper" preset
} GSStretcherFlags;

/// Supplies source audio to a stretcher, on the thread that calls render.
/// Fill `frames` frames of every channel of `dest`, starting at source frame
/// `start`. Frames before 0 or past the end of the source must be zeros.
/// Must not allocate or lock.
typedef void (*GSSourceRead)(void *context, int64_t start, float *const *dest, int32_t frames);

typedef struct GSStretcher GSStretcher;

/// Creates a stretcher. Allocates everything it will ever need, so every call
/// below except create/destroy is safe on the audio thread.
GSStretcher *gs_stretcher_create(GSAlgorithm algorithm, double sampleRate, int32_t channels,
                                 int32_t maxBlockFrames, uint32_t flags,
                                 GSSourceRead read, void *context);
void gs_stretcher_destroy(GSStretcher *stretcher);

/// Playback speed: 1 = normal, 0.5 = half speed. Clamped to 0.25...1.5.
void gs_stretcher_set_speed(GSStretcher *stretcher, double speed);
/// Pitch shift in semitones (fractional values are cents). Clamped to -12...12.
void gs_stretcher_set_transpose(GSStretcher *stretcher, double semitones);

/// Restarts at source frame `position`: the next rendered frame is the one
/// heard at `position`. Uses the source audio before `position` as context.
void gs_stretcher_seek(GSStretcher *stretcher, int64_t position);

/// Renders `frames` frames into `output` (one pointer per channel).
void gs_stretcher_render(GSStretcher *stretcher, float *const *output, int32_t frames);

/// Source position (in source frames) of the next frame render will produce.
double gs_stretcher_position(const GSStretcher *stretcher);

/// Next source frame the stretcher will read. Diagnostics and tests only.
int64_t gs_stretcher_input_cursor(const GSStretcher *stretcher);

GSAlgorithm gs_stretcher_algorithm(const GSStretcher *stretcher);

#ifdef __cplusplus
}
#endif

#endif
