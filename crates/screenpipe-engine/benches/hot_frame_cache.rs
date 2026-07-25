//! Benchmarks for HotFrameCache hot paths.
//!
//! Measures the cost of the three allocation-heavy operations that run on
//! every captured frame:
//!   1. HotFrame clone (happens on push_frame + broadcast send)
//!   2. BTreeMap insert via push_frame
//!   3. BTreeMap range query via get_frames_in_range
//!   4. find_audio_for_frame string clone overhead
//!   5. hot_frame_to_timeseries conversion (multiple string clones per call)
//!
//! Run with:
//!   cargo bench -p screenpipe-engine --bench hot_frame_cache

use chrono::{Duration, Utc};
use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use screenpipe_engine::hot_frame_cache::{HotAudio, HotFrame, HotFrameCache};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_frame(id: i64) -> HotFrame {
    HotFrame {
        frame_id: id,
        timestamp: Utc::now() + Duration::milliseconds(id * 500),
        device_name: "monitor_0".into(),
        app_name: "Google Chrome".into(),
        window_name: "screenpipe — Memory Optimization - Google Chrome".into(),
        ocr_text_preview: "The quick brown fox jumps over the lazy dog. "
            .repeat(4)
            .into(),
        snapshot_path: format!(
            "/Users/user/Library/Application Support/screenpipe/data/monitor_0_{}.jpg",
            id
        )
        .into(),
        browser_url: Some("https://github.com/mediar-ai/screenpipe".into()),
        capture_trigger: "app_switch".into(),
        offset_index: id * 30,
        fps: 0.033,
        machine_id: Some("abc123def456".into()),
    }
}

fn make_audio(id: i64, frame_ts: chrono::DateTime<Utc>) -> HotAudio {
    HotAudio {
        audio_chunk_id: id,
        timestamp: frame_ts + Duration::seconds(2),
        transcription: "Hello, this is a sample transcription for benchmarking purposes. It represents real-world audio captured by screenpipe.".into(),
        device_name: "MacBook Pro Microphone".into(),
        is_input: true,
        audio_file_path: format!("/Users/user/Library/Application Support/screenpipe/data/input_{}.mp4", id).into(),
        duration_secs: 30.0,
        start_time: Some(0.0),
        end_time: Some(30.0),
        speaker_id: Some(1),
        speaker_name: Some("Speaker 1".into()),
    }
}

// Pre-built runtime for async benchmarks.
fn rt() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

// ---------------------------------------------------------------------------
// 1. HotFrame clone cost
//    This happens TWICE per push_frame: once for the BTreeMap insert and
//    once for the broadcast send. Repeated across every subscriber.
// ---------------------------------------------------------------------------

fn bench_hotframe_clone(c: &mut Criterion) {
    let frame = make_frame(1);
    c.bench_function("HotFrame::clone", |b| b.iter(|| black_box(frame.clone())));
}

// ---------------------------------------------------------------------------
// 2. push_frame — full insert path (acquire write lock + BTreeMap insert +
//    broadcast clone). This is the per-capture-event hot path.
// ---------------------------------------------------------------------------

fn bench_push_frame(c: &mut Criterion) {
    let rt = rt();
    let cache = HotFrameCache::new();

    c.bench_function("HotFrameCache::push_frame", |b| {
        let mut id = 0i64;
        b.iter(|| {
            id += 1;
            let frame = make_frame(id);
            rt.block_on(cache.push_frame(frame));
        });
    });
}

// ---------------------------------------------------------------------------
// 3. get_frames_in_range — BTreeMap range query at various cache sizes.
//    Simulates the WS handler reading today's timeline.
// ---------------------------------------------------------------------------

fn bench_get_frames_in_range(c: &mut Criterion) {
    let rt = rt();
    let mut group = c.benchmark_group("HotFrameCache::get_frames_in_range");

    for &n in &[100usize, 500, 1_000, 5_000] {
        let cache = HotFrameCache::new();
        let base = Utc::now();

        rt.block_on(async {
            for i in 0..n as i64 {
                cache.push_frame(make_frame(i)).await;
            }
        });

        let start = base - Duration::seconds(1);
        let end = base + Duration::hours(8);

        group.bench_with_input(BenchmarkId::from_parameter(n), &n, |b, _| {
            b.iter(|| rt.block_on(cache.get_frames_in_range(black_box(start), black_box(end))));
        });
    }
    group.finish();
}

// ---------------------------------------------------------------------------
// 4. push_audio — measures string clone cost on every transcription insert.
// ---------------------------------------------------------------------------

fn bench_push_audio(c: &mut Criterion) {
    let rt = rt();
    let cache = HotFrameCache::new();
    let base_ts = Utc::now();

    c.bench_function("HotFrameCache::push_audio", |b| {
        let mut id = 0i64;
        b.iter(|| {
            id += 1;
            let audio = make_audio(id, base_ts + Duration::seconds(id));
            rt.block_on(cache.push_audio(audio));
        });
    });
}

// ---------------------------------------------------------------------------
// 5. find_audio_near — string clone cost of the ±60s audio lookup that
//    runs for every frame returned by get_frames_in_range.
// ---------------------------------------------------------------------------

fn bench_find_audio_near(c: &mut Criterion) {
    let rt = rt();
    let cache = HotFrameCache::new();
    let base_ts = Utc::now();

    // Seed with 200 audio entries around the query timestamp
    rt.block_on(async {
        for i in -100i64..100 {
            let audio = make_audio(i + 1000, base_ts + Duration::seconds(i));
            cache.push_audio(audio).await;
        }
    });

    c.bench_function("HotFrameCache::find_audio_near", |b| {
        b.iter(|| rt.block_on(cache.find_audio_near(black_box(base_ts))));
    });
}

// ---------------------------------------------------------------------------
// 6. evict_range — retention / delete path.
// ---------------------------------------------------------------------------

fn bench_evict_range(c: &mut Criterion) {
    let rt = rt();

    c.bench_function("HotFrameCache::evict_range/1000_frames", |b| {
        b.iter_with_setup(
            || {
                let cache = HotFrameCache::new();
                let base = Utc::now();
                rt.block_on(async {
                    for i in 0..1_000i64 {
                        cache.push_frame(make_frame(i)).await;
                    }
                });
                (cache, base)
            },
            |(cache, base)| {
                let start = base - Duration::seconds(1);
                let end = base + Duration::hours(8);
                rt.block_on(cache.evict_range(black_box(start), black_box(end)));
            },
        );
    });
}

// ---------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------

criterion_group!(
    benches,
    bench_hotframe_clone,
    bench_push_frame,
    bench_get_frames_in_range,
    bench_push_audio,
    bench_find_audio_near,
    bench_evict_range,
);
criterion_main!(benches);
