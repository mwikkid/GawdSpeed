// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Earl Scioneaux, III
//
// The render engine behind GSEngine.h. Sound comes from one "voice" at a
// time: a direct (bypass) reader or a stretcher. Every seek, algorithm switch,
// bypass change and loop wrap starts a fresh voice at the right source frame
// and crossfades to it, so nothing ever cuts abruptly.

#include "Filters.hpp"
#include "Stretcher.hpp"
#include "include/GSEngine.h"

#include <atomic>

namespace gs {
namespace {

constexpr double kCrossfadeSeconds = 0.010; // spec §3: ~10 ms
constexpr double kPlayRampSeconds = 0.010;  // fade on play/pause

enum class Path : int { Bypass = 0, A = 1, B = 2 };

/// One way of producing sound from the source, starting at a source frame.
class Voice {
public:
    Voice(Path path, std::unique_ptr<Stretcher> stretcher, const float *const *source, int channels,
          int64_t frames)
        : path_(path), stretcher_(std::move(stretcher)), source_(source), channels_(channels), frames_(frames) {}

    Path path() const { return path_; }

    void start(int64_t position, double speed, double transpose) {
        if (stretcher_) {
            setParameters(speed, transpose);
            stretcher_->seek(position);
        } else {
            directPosition_ = position;
        }
    }

    void setParameters(double speed, double transpose) {
        if (!stretcher_) return;
        if (speed != speed_) stretcher_->setSpeed(speed_ = speed);
        if (transpose != transpose_) stretcher_->setTranspose(transpose_ = transpose);
    }

    void render(float *const *out, int frames) {
        if (stretcher_) {
            stretcher_->render(out, frames);
            return;
        }
        for (int c = 0; c < channels_; ++c) {
            for (int i = 0; i < frames; ++i) {
                const int64_t k = directPosition_ + i;
                out[c][i] = (k >= 0 && k < frames_) ? source_[c][k] : 0.0f;
            }
        }
        directPosition_ += frames;
    }

    double position() const { return stretcher_ ? stretcher_->position() : double(directPosition_); }

private:
    const Path path_;
    std::unique_ptr<Stretcher> stretcher_;
    const float *const *source_;
    const int channels_;
    const int64_t frames_;
    int64_t directPosition_ = 0;
    double speed_ = -1;
    double transpose_ = -1000;
};

} // namespace
} // namespace gs

using namespace gs;

struct GSEngine {
    GSEngine(double sampleRate, int outputChannels, int maxBlock)
        : sampleRate(sampleRate), outputChannels(outputChannels), maxBlock(maxBlock),
          crossfadeFrames(std::max(1, int(kCrossfadeSeconds * sampleRate))),
          playRampStep(float(1.0 / (kPlayRampSeconds * sampleRate))) {}

    // --- fixed configuration -------------------------------------------------
    const double sampleRate;
    const int outputChannels;
    const int maxBlock;
    const int crossfadeFrames;
    const float playRampStep;

    // --- source (set off the audio thread) ------------------------------------
    std::vector<const float *> sourceChannels;
    int channels = 0;
    int64_t frames = 0;
    std::vector<std::unique_ptr<Voice>> voices; // bypass x2, A x2, B x2
    PlanarBuffer mix, incoming;
    ButterworthFilter highpass{ButterworthFilter::Type::HighPass};
    ButterworthFilter lowpass{ButterworthFilter::Type::LowPass};

    // --- parameters, written by the UI thread ---------------------------------
    std::atomic<bool> playing{false};
    std::atomic<double> speed{1.0};
    std::atomic<double> transpose{0.0};
    std::atomic<int> algorithm{GSAlgorithmB};
    std::atomic<double> highpassHz{20.0};
    std::atomic<double> lowpassHz{20000.0};
    std::atomic<int64_t> loopStart{0}, loopEnd{0};
    std::atomic<bool> loopEnabled{false};
    std::atomic<int64_t> loopPreroll{0};
    std::atomic<int64_t> seekTarget{0};
    std::atomic<uint32_t> seekRequests{0};

    // --- published by the audio thread ----------------------------------------
    std::atomic<double> publishedPosition{0};
    std::atomic<bool> reachedEnd{false};
    std::atomic<int> publishedPath{0};

    // --- audio-thread state ---------------------------------------------------
    Voice *active = nullptr;
    Voice *fadingOut = nullptr;
    int fadeDone = 0;
    bool fadeEqualPower = true;
    uint32_t seeksHandled = 0;
    float gain = 0;

    static void readSource(void *context, int64_t start, float *const *dest, int32_t count) {
        auto *engine = static_cast<GSEngine *>(context);
        for (int c = 0; c < engine->channels; ++c) {
            const float *src = engine->sourceChannels[size_t(c)];
            for (int i = 0; i < count; ++i) {
                const int64_t k = start + i;
                dest[c][i] = (k >= 0 && k < engine->frames) ? src[k] : 0.0f;
            }
        }
    }

    void setSource(const float *const *data, int channelCount, int64_t frameCount) {
        voices.clear();
        active = fadingOut = nullptr;
        sourceChannels.assign(data, data + channelCount);
        channels = channelCount;
        frames = frameCount;
        if (channels < 1) return;

        const Source source{&GSEngine::readSource, this};
        for (int copy = 0; copy < 2; ++copy) {
            voices.push_back(std::make_unique<Voice>(Path::Bypass, nullptr, sourceChannels.data(), channels, frames));
            voices.push_back(std::make_unique<Voice>(
                Path::A, makeSignalsmithStretcher(sampleRate, channels, maxBlock, false, source),
                sourceChannels.data(), channels, frames));
            voices.push_back(std::make_unique<Voice>(
                Path::B, makeRubberBandStretcher(sampleRate, channels, maxBlock, source),
                sourceChannels.data(), channels, frames));
        }
        mix.allocate(channels, maxBlock);
        incoming.allocate(channels, maxBlock);
        highpass.prepare(sampleRate, channels);
        lowpass.prepare(sampleRate, channels);

        playing.store(false);
        gain = 0;
        reachedEnd.store(false);
        seeksHandled = seekRequests.load();
        active = startVoice(desiredPath(), 0);
        publish();
    }

    Path desiredPath() const {
        const double s = speed.load(std::memory_order_relaxed);
        const double t = transpose.load(std::memory_order_relaxed);
        if (std::abs(s - 1.0) < 1e-9 && std::abs(t) < 1e-9) return Path::Bypass;
        return algorithm.load(std::memory_order_relaxed) == GSAlgorithmA ? Path::A : Path::B;
    }

    Voice *startVoice(Path path, int64_t position) {
        for (auto &v : voices) {
            Voice *voice = v.get();
            if (voice->path() == path && voice != active && voice != fadingOut) {
                voice->start(position, speed.load(std::memory_order_relaxed),
                             transpose.load(std::memory_order_relaxed));
                return voice;
            }
        }
        return active; // unreachable: each path has two voices
    }

    /// Moves playback to a new voice. While paused this is instant; while
    /// sounding it crossfades.
    void switchTo(Path path, int64_t position, bool equalPower) {
        Voice *next = startVoice(path, position);
        if (gain == 0 || active == nullptr) {
            active = next;
            fadingOut = nullptr;
            return;
        }
        fadingOut = active;
        active = next;
        fadeDone = 0;
        fadeEqualPower = equalPower;
    }

    void publish() {
        if (active) publishedPosition.store(active->position(), std::memory_order_relaxed);
        if (active) publishedPath.store(int(active->path()), std::memory_order_relaxed);
    }

    void render(float *const *output, int count) {
        for (int done = 0; done < count;) {
            int n = std::min(maxBlock, count - done);
            // Stop the block exactly where the loop ends, so the wrap lands on
            // the loop-out frame rather than up to a block late.
            const int toLoopEnd = framesUntilLoopEnd();
            if (toLoopEnd > 0) n = std::min(n, toLoopEnd);
            float *out[2] = {output[0] + done, outputChannels > 1 ? output[1] + done : nullptr};
            renderBlock(out, n);
            done += n;
        }
    }

    /// Output frames until the playing voice reaches the loop's end, or 0 if
    /// no loop is due (looping off, a crossfade running, or already past it).
    int framesUntilLoopEnd() const {
        if (!active || fadingOut || !loopEnabled.load(std::memory_order_relaxed)) return 0;
        const double end = double(loopEnd.load(std::memory_order_relaxed));
        const double position = active->position();
        if (end <= double(loopStart.load(std::memory_order_relaxed)) || position >= end) return 0;
        const double s = speed.load(std::memory_order_relaxed);
        const double frames = std::ceil((end - position) / (active->path() == Path::Bypass ? 1.0 : s));
        return int(std::min(frames, double(maxBlock)));
    }

    void renderBlock(float *const *out, int n) {
        if (active == nullptr) {
            for (int c = 0; c < outputChannels; ++c) std::fill(out[c], out[c] + n, 0.0f);
            return;
        }

        // 1. Commands. A switch waits for any crossfade in progress to finish.
        const double s = speed.load(std::memory_order_relaxed);
        const double t = transpose.load(std::memory_order_relaxed);
        if (fadingOut == nullptr) {
            const uint32_t requests = seekRequests.load(std::memory_order_acquire);
            if (requests != seeksHandled) {
                seeksHandled = requests;
                reachedEnd.store(false, std::memory_order_relaxed);
                switchTo(desiredPath(), seekTarget.load(std::memory_order_relaxed), true);
            } else if (desiredPath() != active->path()) {
                // Same moment in the song, different processing: the two
                // signals are time-aligned, so use an equal-gain fade into
                // or out of bypass (no +3 dB bump), equal-power between A and B.
                const bool involvesBypass = desiredPath() == Path::Bypass || active->path() == Path::Bypass;
                switchTo(desiredPath(), int64_t(std::llround(active->position())), !involvesBypass);
            } else if (loopEnabled.load(std::memory_order_relaxed)) {
                const int64_t ls = loopStart.load(std::memory_order_relaxed);
                const int64_t le = loopEnd.load(std::memory_order_relaxed);
                if (le > ls && active->position() >= double(le)) {
                    const int64_t restart = std::max<int64_t>(0, ls - loopPreroll.load(std::memory_order_relaxed));
                    switchTo(active->path(), restart, true);
                }
            }
        }
        active->setParameters(s, t);
        if (fadingOut) fadingOut->setParameters(s, t);

        // 2. Play/pause ramp. Fully paused: output silence, voices stand still.
        const float target = playing.load(std::memory_order_relaxed) ? 1.0f : 0.0f;
        if (gain == 0 && target == 0) {
            for (int c = 0; c < outputChannels; ++c) std::fill(out[c], out[c] + n, 0.0f);
            publish();
            return;
        }
        publish(); // position of the first frame of this block

        // 3. Voices, with the crossfade if one is running.
        active->render(mix.data(), n);
        if (fadingOut) {
            fadingOut->render(incoming.data(), n);
            for (int i = 0; i < n; ++i) {
                const float x = std::min(1.0f, float(fadeDone + i) / float(crossfadeFrames));
                const float in = fadeEqualPower ? std::sin(x * float(M_PI_2)) : x;
                const float old = fadeEqualPower ? std::cos(x * float(M_PI_2)) : 1 - x;
                for (int c = 0; c < channels; ++c)
                    mix.channel(c)[i] = mix.channel(c)[i] * in + incoming.channel(c)[i] * old;
            }
            fadeDone += n;
            if (fadeDone >= crossfadeFrames) fadingOut = nullptr;
        }

        // 4. Filters, then the play/pause ramp.
        highpass.setTarget(highpassHz.load(std::memory_order_relaxed), highpassHz.load() <= 20.0);
        lowpass.setTarget(lowpassHz.load(std::memory_order_relaxed), lowpassHz.load() >= 20000.0);
        highpass.process(mix.data(), channels, n);
        lowpass.process(mix.data(), channels, n);

        for (int i = 0; i < n; ++i) {
            if (gain != target) gain = target > gain ? std::min(target, gain + playRampStep)
                                                     : std::max(target, gain - playRampStep);
            for (int c = 0; c < channels; ++c) mix.channel(c)[i] *= gain;
        }

        // 5. Channel mapping to the output.
        if (outputChannels == channels) {
            for (int c = 0; c < channels; ++c) std::copy(mix.channel(c), mix.channel(c) + n, out[c]);
        } else if (channels == 1) {
            for (int c = 0; c < outputChannels; ++c) std::copy(mix.channel(0), mix.channel(0) + n, out[c]);
        } else {
            for (int i = 0; i < n; ++i) out[0][i] = 0.5f * (mix.channel(0)[i] + mix.channel(1)[i]);
        }

        // 6. End of the song: pause (with the ramp) and report it.
        if (!loopEnabled.load(std::memory_order_relaxed) && active->position() >= double(frames)) {
            playing.store(false, std::memory_order_relaxed);
            reachedEnd.store(true, std::memory_order_relaxed);
        }
    }
};

extern "C" {

GSEngine *gs_engine_create(double sampleRate, int32_t outputChannels, int32_t maxBlockFrames) {
    if (sampleRate <= 0 || outputChannels < 1 || outputChannels > 2 || maxBlockFrames < 1) return nullptr;
    return new GSEngine(sampleRate, outputChannels, maxBlockFrames);
}

void gs_engine_destroy(GSEngine *engine) { delete engine; }

void gs_engine_set_source(GSEngine *engine, const float *const *channels, int32_t channelCount, int64_t frames) {
    engine->setSource(channels, std::clamp(channelCount, 0, 2), frames);
}

void gs_engine_set_playing(GSEngine *engine, bool playing) {
    if (playing) engine->reachedEnd.store(false, std::memory_order_relaxed);
    engine->playing.store(playing, std::memory_order_relaxed);
}

void gs_engine_set_speed(GSEngine *engine, double speed) {
    engine->speed.store(Stretcher::clampSpeed(speed), std::memory_order_relaxed);
}

void gs_engine_set_transpose(GSEngine *engine, double semitones) {
    engine->transpose.store(Stretcher::clampTranspose(semitones), std::memory_order_relaxed);
}

void gs_engine_set_algorithm(GSEngine *engine, GSAlgorithm algorithm) {
    engine->algorithm.store(int(algorithm), std::memory_order_relaxed);
}

void gs_engine_set_highpass(GSEngine *engine, double hz) { engine->highpassHz.store(hz, std::memory_order_relaxed); }
void gs_engine_set_lowpass(GSEngine *engine, double hz) { engine->lowpassHz.store(hz, std::memory_order_relaxed); }

void gs_engine_set_loop(GSEngine *engine, int64_t start, int64_t end, bool enabled) {
    engine->loopStart.store(start, std::memory_order_relaxed);
    engine->loopEnd.store(end, std::memory_order_relaxed);
    engine->loopEnabled.store(enabled, std::memory_order_relaxed);
}

void gs_engine_set_loop_preroll(GSEngine *engine, int64_t frames) {
    engine->loopPreroll.store(std::max<int64_t>(0, frames), std::memory_order_relaxed);
}

void gs_engine_start_offline(GSEngine *engine, int64_t frame) {
    engine->seekRequests.fetch_add(1);
    engine->seeksHandled = engine->seekRequests.load();
    engine->fadingOut = nullptr;
    if (!engine->voices.empty()) engine->active = engine->startVoice(engine->desiredPath(), std::max<int64_t>(0, frame));
    engine->playing.store(true);
    engine->gain = 1.0f;
    engine->reachedEnd.store(false);
    engine->publish();
}

void gs_engine_seek(GSEngine *engine, int64_t frame) {
    engine->seekTarget.store(std::max<int64_t>(0, frame), std::memory_order_relaxed);
    engine->seekRequests.fetch_add(1, std::memory_order_release);
}

void gs_engine_render(GSEngine *engine, float *const *output, int32_t frames) { engine->render(output, frames); }

double gs_engine_position(const GSEngine *engine) {
    return engine->publishedPosition.load(std::memory_order_relaxed);
}

bool gs_engine_is_playing(const GSEngine *engine) { return engine->playing.load(std::memory_order_relaxed); }
bool gs_engine_reached_end(const GSEngine *engine) { return engine->reachedEnd.load(std::memory_order_relaxed); }
int32_t gs_engine_active_path(const GSEngine *engine) { return engine->publishedPath.load(std::memory_order_relaxed); }

} // extern "C"
