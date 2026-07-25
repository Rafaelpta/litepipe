//! Counting-allocator benchmark.
//!
//! Wraps the system allocator to count heap allocations per operation.
//! Reports allocations-per-call for:
//!   - HotFrame::clone
//!   - HotFrame construction from raw strings (as happens in warm_from_db)
//!   - HotAudio construction + clone
//!
//! Run with:
//!   cargo bench -p screenpipe-engine --bench alloc_counter

use chrono::Utc;
use criterion::{black_box, criterion_group, criterion_main, Criterion};
use screenpipe_engine::hot_frame_cache::{HotAudio, HotFrame};
use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};

// ---------------------------------------------------------------------------
// Counting allocator
// ---------------------------------------------------------------------------

pub static ALLOC_COUNT: AtomicUsize = AtomicUsize::new(0);
pub static ALLOC_BYTES: AtomicUsize = AtomicUsize::new(0);

struct CountingAllocator;

unsafe impl GlobalAlloc for CountingAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        ALLOC_COUNT.fetch_add(1, Ordering::Relaxed);
        ALLOC_BYTES.fetch_add(layout.size(), Ordering::Relaxed);
        unsafe { System.alloc(layout) }
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) }
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        ALLOC_COUNT.fetch_add(1, Ordering::Relaxed);
        ALLOC_BYTES.fetch_add(layout.size(), Ordering::Relaxed);
        unsafe { System.alloc_zeroed(layout) }
    }
    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // realloc is effectively a dealloc + alloc — count it
        ALLOC_COUNT.fetch_add(1, Ordering::Relaxed);
        ALLOC_BYTES.fetch_add(new_size, Ordering::Relaxed);
        unsafe { System.realloc(ptr, layout, new_size) }
    }
}

#[global_allocator]
static GLOBAL: CountingAllocator = CountingAllocator;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn reset_counters() -> (usize, usize) {
    let prev_count = ALLOC_COUNT.swap(0, Ordering::SeqCst);
    let prev_bytes = ALLOC_BYTES.swap(0, Ordering::SeqCst);
    (prev_count, prev_bytes)
}

fn read_counters() -> (usize, usize) {
    (
        ALLOC_COUNT.load(Ordering::SeqCst),
        ALLOC_BYTES.load(Ordering::SeqCst),
    )
}

fn make_frame(id: i64) -> HotFrame {
    HotFrame {
        frame_id: id,
        timestamp: Utc::now(),
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

// ---------------------------------------------------------------------------
// Benchmarks that print alloc counts as custom values
// ---------------------------------------------------------------------------

fn bench_hotframe_clone_allocs(c: &mut Criterion) {
    let frame = make_frame(1);

    c.bench_function("alloc_count/HotFrame::clone", |b| {
        b.iter_custom(|iters| {
            reset_counters();
            let start = std::time::Instant::now();
            for _ in 0..iters {
                let _ = black_box(frame.clone());
            }
            let elapsed = start.elapsed();
            let (count, bytes) = read_counters();
            // Print so results are visible in bench output
            eprintln!(
                "\n  HotFrame::clone × {} → {} allocs, {} bytes ({} allocs/call, {} bytes/call)",
                iters,
                count,
                bytes,
                count / iters as usize,
                bytes / iters as usize
            );
            elapsed
        });
    });
}

fn bench_hotframe_construct_allocs(c: &mut Criterion) {
    c.bench_function("alloc_count/HotFrame::construct", |b| {
        b.iter_custom(|iters| {
            reset_counters();
            let start = std::time::Instant::now();
            for i in 0..iters {
                let _ = black_box(make_frame(i as i64));
            }
            let elapsed = start.elapsed();
            let (count, bytes) = read_counters();
            eprintln!(
                "\n  HotFrame::construct × {} → {} allocs, {} bytes ({} allocs/call, {} bytes/call)",
                iters,
                count,
                bytes,
                count / iters as usize,
                bytes / iters as usize
            );
            elapsed
        });
    });
}

fn bench_hotaudio_clone_allocs(c: &mut Criterion) {
    let audio = HotAudio {
        audio_chunk_id: 1,
        timestamp: Utc::now(),
        transcription: "Hello, this is a sample transcription for benchmarking purposes. It represents real-world audio captured by screenpipe.".into(),
        device_name: "MacBook Pro Microphone".into(),
        is_input: true,
        audio_file_path: "/Users/user/Library/Application Support/screenpipe/data/input_1.mp4".into(),
        duration_secs: 30.0,
        start_time: Some(0.0),
        end_time: Some(30.0),
        speaker_id: Some(1),
        speaker_name: Some("Speaker 1".into()),
    };

    c.bench_function("alloc_count/HotAudio::clone", |b| {
        b.iter_custom(|iters| {
            reset_counters();
            let start = std::time::Instant::now();
            for _ in 0..iters {
                let _ = black_box(audio.clone());
            }
            let elapsed = start.elapsed();
            let (count, bytes) = read_counters();
            eprintln!(
                "\n  HotAudio::clone × {} → {} allocs, {} bytes ({} allocs/call, {} bytes/call)",
                iters,
                count,
                bytes,
                count / iters as usize,
                bytes / iters as usize
            );
            elapsed
        });
    });
}

criterion_group!(
    benches,
    bench_hotframe_clone_allocs,
    bench_hotframe_construct_allocs,
    bench_hotaudio_clone_allocs,
);
criterion_main!(benches);
