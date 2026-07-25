//! # Audio Pipeline Benchmark Suite
//!
//! End-to-end benchmarks for the screenpipe audio pipeline, measuring:
//! - VAD threshold sensitivity vs. speech recall
//! - Meeting detection accuracy and latency
//! - Smart mode data loss under app restart
//! - Cross-device (input/output) coverage
//! - Full pipeline: audio → VAD → DB
//!
//! ## Running
//!
//! ```bash
//! # Synthetic VAD sweep (no dataset needed, runs in CI)
//! cargo test -p screenpipe-audio --test audio_pipeline_benchmark vad_threshold_sweep_synthetic -- --nocapture
//!
//! # Full benchmark suite (requires dataset)
//! AUDIO_BENCHMARK_DATASET=./scripts/generate-audio-dataset/output \
//!   cargo test --release -p screenpipe-audio --test audio_pipeline_benchmark -- --nocapture --ignored
//! ```

#[allow(dead_code)]
mod audio_fixtures;
mod cross_device_benchmark;
#[allow(dead_code)]
mod ground_truth;
mod meeting_benchmark;
#[allow(dead_code)]
mod metrics;
mod pipeline_benchmark;
mod quality_regression;
mod smart_mode_benchmark;
mod vad_benchmark;

/// Construct a SileroVad after ensuring the model is fully downloaded.
/// Fixes a race in parallel test runs: `SileroVad::new()` on its own is
/// non-blocking — the first caller spawns the download and returns an
/// error, siblings see DOWNLOADING=true and error too. Here we poll until
/// the file is on disk, then construct. Safe to call from many tests
/// concurrently; only the first pays the download cost.
#[allow(dead_code)]
pub async fn new_test_vad() -> screenpipe_audio::vad::silero::SileroVad {
    screenpipe_audio::vad::silero::SileroVad::ensure_model_available()
        .await
        .expect("silero model prefetch failed");
    screenpipe_audio::vad::silero::SileroVad::new()
        .await
        .expect("failed to init SileroVad")
}
