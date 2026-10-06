// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The playback/render engine: source -> stretcher (or bypass) -> HPF -> LPF.
// The same engine renders live playback and offline export.
//
// Threading: gs_engine_render runs on the audio thread. Every gs_engine_set_*
// and gs_engine_seek call is safe from any one other thread (the UI); they
// only store atomics that render reads at the top of each block. Create,
// destroy and set_source must not overlap a render call.

#ifndef GS_ENGINE_H
#define GS_ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#include "GSStretcher.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GSEngine GSEngine;

/// `outputChannels` is what render writes (1 or 2). A mono source is copied to
/// both outputs; a stereo source to a mono output is summed.
GSEngine *gs_engine_create(double sampleRate, int32_t outputChannels, int32_t maxBlockFrames);
void gs_engine_destroy(GSEngine *engine);

/// Stretcher options (GSStretcherFlags) for the voices built by the next
/// gs_engine_set_source, e.g. Algorithm A's cheaper preset.
void gs_engine_set_options(GSEngine *engine, uint32_t flags);

/// Borrows planar source audio (already at the engine's sample rate). The
/// caller keeps it alive until another source is set or the engine is
/// destroyed. Builds the stretchers for this channel count, so call it off
/// the audio thread and never during a render. Resets position to 0, paused.
void gs_engine_set_source(GSEngine *engine, const float *const *channels, int32_t channelCount, int64_t frames);

void gs_engine_set_playing(GSEngine *engine, bool playing);
void gs_engine_set_speed(GSEngine *engine, double speed);
void gs_engine_set_transpose(GSEngine *engine, double semitones);
void gs_engine_set_algorithm(GSEngine *engine, GSAlgorithm algorithm);
/// High-pass cutoff in Hz; 20 or below means off.
void gs_engine_set_highpass(GSEngine *engine, double hz);
/// Low-pass cutoff in Hz; 20000 or above means off.
void gs_engine_set_lowpass(GSEngine *engine, double hz);
/// Loop between two source frames. Ignored unless enabled and end > start.
/// The wrap happens on the exact frame where playback reaches `end`.
void gs_engine_set_loop(GSEngine *engine, int64_t start, int64_t end, bool enabled);
/// Each loop pass restarts this many source frames before the loop start (0–2 s, spec §5.6).
void gs_engine_set_loop_preroll(GSEngine *engine, int64_t frames);
/// Offline rendering (export): jump straight to `frame`, playing at full
/// volume with no fade-in. Not for live use; call before the first render.
void gs_engine_start_offline(GSEngine *engine, int64_t frame);
void gs_engine_seek(GSEngine *engine, int64_t frame);

/// Renders `frames` frames into `output` (one pointer per output channel).
void gs_engine_render(GSEngine *engine, float *const *output, int32_t frames);

/// Source frame being rendered right now (what the playhead shows).
double gs_engine_position(const GSEngine *engine);
bool gs_engine_is_playing(const GSEngine *engine);
/// True once playback has run off the end of the source (and paused itself).
bool gs_engine_reached_end(const GSEngine *engine);
/// Which processing path is producing sound: 0 = bypass (100%, no transpose),
/// 1 = Algorithm A, 2 = Algorithm B. Diagnostics and tests.
int32_t gs_engine_active_path(const GSEngine *engine);

#ifdef __cplusplus
}
#endif

#endif
