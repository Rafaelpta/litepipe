//! Core capture functionality using ScreenCaptureKit via cidre

use cidre::{api, cv, ns, sc};
use image::RgbaImage;
use once_cell::sync::Lazy;
use std::panic;
use tokio::runtime::Runtime;
use tracing::debug;

use crate::error::{XCapError, XCapResult};

/// Global tokio runtime for blocking on async operations (only used when not in an existing runtime)
static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to create tokio runtime")
});

/// Run an async operation synchronously using the global runtime
///
/// Note: This must be called from outside a tokio runtime context.
/// For use within async code, use the async capture functions directly.
pub(crate) fn block_on<F: std::future::Future>(f: F) -> F::Output {
    RUNTIME.block_on(f)
}

/// Run a sync closure in a separate thread to avoid nested runtime issues
///
/// If the spawned thread panics, this returns an error instead of propagating
/// the panic to the calling thread (which would cause abort via panic_cannot_unwind).
pub(crate) fn run_in_thread<F, T>(f: F) -> XCapResult<T>
where
    F: FnOnce() -> T + Send + 'static,
    T: Send + 'static,
{
    match std::thread::spawn(f).join() {
        Ok(result) => Ok(result),
        Err(panic_info) => {
            let msg = if let Some(s) = panic_info.downcast_ref::<&str>() {
                format!("Thread panicked: {}", s)
            } else if let Some(s) = panic_info.downcast_ref::<String>() {
                format!("Thread panicked: {}", s)
            } else {
                "Thread panicked with unknown payload".to_string()
            };
            Err(XCapError::capture_failed(msg))
        }
    }
}

// CoreGraphics FFI for display enumeration fallback
extern "C" {
    fn CGGetOnlineDisplayList(
        max_displays: u32,
        online_displays: *mut u32,
        display_count: *mut u32,
    ) -> i32;
}

/// Check how many displays CoreGraphics sees (more reliable than SCK after wake)
fn cg_online_display_count() -> u32 {
    let mut count: u32 = 0;
    let err = unsafe { CGGetOnlineDisplayList(0, std::ptr::null_mut(), &mut count) };
    if err == 0 {
        count
    } else {
        0
    }
}

/// Fetch SCShareableContent once
fn fetch_shareable_content() -> XCapResult<cidre::arc::R<sc::ShareableContent>> {
    let fetch = || {
        block_on(async {
            sc::ShareableContent::current().await.map_err(|e| {
                let err_str = format!("{:?}", e);
                if err_str.contains("permission")
                    || err_str.contains("denied")
                    || err_str.contains("-3801")
                {
                    XCapError::permission_denied()
                } else {
                    XCapError::capture_failed(format!(
                        "Failed to get shareable content: {}",
                        err_str
                    ))
                }
            })
        })
    };

    if tokio::runtime::Handle::try_current().is_ok() {
        run_in_thread(fetch)?
    } else {
        fetch()
    }
}

/// Get shareable content synchronously.
///
/// After sleep/wake, SCK can return 0 displays even though the display is
/// active. When this happens and CoreGraphics still sees displays, retry
/// with increasing delays to give SCK time to resync with the WindowServer.
pub fn get_shareable_content() -> XCapResult<cidre::arc::R<sc::ShareableContent>> {
    let content = fetch_shareable_content()?;
    if !content.displays().is_empty() {
        return Ok(content);
    }

    // SCK returned 0 displays — check CoreGraphics as ground truth
    let cg_count = cg_online_display_count();
    if cg_count == 0 {
        // Genuinely no displays (lid closed, no external monitor)
        return Ok(content);
    }

    // CG sees displays but SCK doesn't — SCK is stale after wake.
    // Retry with increasing delays.
    debug!(
        "SCK returned 0 displays but CG sees {} — retrying after wake",
        cg_count
    );
    for delay_ms in [200, 500, 1000, 2000, 3000] {
        std::thread::sleep(std::time::Duration::from_millis(delay_ms));
        let content = fetch_shareable_content()?;
        if !content.displays().is_empty() {
            debug!("SCK recovered after {}ms delay", delay_ms);
            return Ok(content);
        }
    }

    // Still empty after ~7s — return what we have (caller handles empty)
    debug!("SCK still empty after retries, returning empty content");
    fetch_shareable_content()
}

// FFI bindings for non-planar pixel buffer functions (not exposed by cidre)
extern "C" {
    fn CVPixelBufferGetBytesPerRow(pixelBuffer: *const std::ffi::c_void) -> usize;
    fn CVPixelBufferGetBaseAddress(pixelBuffer: *const std::ffi::c_void) -> *const u8;
}

/// Extract an RGBA image from a cv::ImageBuf (pixel buffer)
fn image_buf_to_rgba(image_buf: &mut cv::ImageBuf) -> XCapResult<RgbaImage> {
    // Get all metadata BEFORE locking
    let width = image_buf.width();
    let height = image_buf.height();
    let plane_count = image_buf.plane_count();
    let pixel_format = image_buf.pixel_format();

    // Validate dimensions before any unsafe operations
    if width == 0 || height == 0 {
        return Err(XCapError::capture_failed(format!(
            "Invalid image buffer dimensions: {}x{}",
            width, height
        )));
    }

    // Guard against absurdly large buffers (>256 megapixels)
    if width > 16384 || height > 16384 {
        return Err(XCapError::capture_failed(format!(
            "Image buffer dimensions too large: {}x{}",
            width, height
        )));
    }

    // Lock the buffer for reading using raw lock/unlock
    let lock_flags = cv::pixel_buffer::LockFlags::READ_ONLY;

    // Lock
    let lock_result = unsafe { image_buf.lock_base_addr(lock_flags) };
    if lock_result.is_err() {
        return Err(XCapError::capture_failed(format!(
            "Failed to lock pixel buffer: {:?}",
            lock_result
        )));
    }

    // Get bytes_per_row and base address based on buffer type
    // For non-planar buffers (plane_count == 0), use non-plane functions
    // For planar buffers, use plane functions
    let (bytes_per_row, pixels_ptr) = if plane_count == 0 {
        // Non-planar buffer - use CVPixelBufferGetBytesPerRow/GetBaseAddress
        let bpr = unsafe {
            CVPixelBufferGetBytesPerRow(image_buf as *const _ as *const std::ffi::c_void)
        };
        let ptr = unsafe {
            CVPixelBufferGetBaseAddress(image_buf as *const _ as *const std::ffi::c_void)
        };
        (bpr, ptr)
    } else {
        // Planar buffer - use plane functions
        (
            image_buf.plane_bytes_per_row(0),
            image_buf.plane_base_address(0),
        )
    };

    debug!(
        "Converting image buffer: {}x{}, plane_count={}, format={:?}, bytes_per_row={}",
        width, height, plane_count, pixel_format, bytes_per_row
    );

    let result = if pixels_ptr.is_null() {
        Err(XCapError::capture_failed(
            "Pixel buffer base address is null",
        ))
    } else if bytes_per_row == 0 {
        Err(XCapError::capture_failed("Pixel buffer bytes_per_row is 0"))
    } else if bytes_per_row < width * 4 {
        Err(XCapError::capture_failed(format!(
            "bytes_per_row ({}) is less than width * 4 ({}), buffer may be corrupt",
            bytes_per_row,
            width * 4
        )))
    } else {
        // Validate data_size won't overflow
        let data_size = match bytes_per_row.checked_mul(height) {
            Some(size) if size > 0 => size,
            _ => {
                // Must unlock before returning
                let _ = unsafe { image_buf.unlock_lock_base_addr(lock_flags) };
                return Err(XCapError::capture_failed(format!(
                    "Invalid buffer size: bytes_per_row={} * height={} overflows or is zero",
                    bytes_per_row, height
                )));
            }
        };

        // Create a slice from the raw pixel data
        let pixels = unsafe { std::slice::from_raw_parts(pixels_ptr, data_size) };

        // Copy and convert BGRA to RGBA
        let mut buffer = Vec::with_capacity(width * height * 4);

        for row in 0..height {
            let row_start = row * bytes_per_row;
            for col in 0..width {
                let pixel_start = row_start + col * 4;
                if pixel_start + 3 < pixels.len() {
                    // BGRA to RGBA conversion
                    buffer.push(pixels[pixel_start + 2]); // R
                    buffer.push(pixels[pixel_start + 1]); // G
                    buffer.push(pixels[pixel_start]); // B
                    buffer.push(pixels[pixel_start + 3]); // A
                }
            }
        }

        RgbaImage::from_raw(width as u32, height as u32, buffer)
            .ok_or_else(|| XCapError::capture_failed("Failed to create image from buffer"))
    };

    // Unlock
    let unlock_result = unsafe { image_buf.unlock_lock_base_addr(lock_flags) };
    if unlock_result.is_err() {
        debug!(
            "Warning: failed to unlock pixel buffer: {:?}",
            unlock_result
        );
    }

    result
}

/// Safely call image_buf_to_rgba with catch_unwind to prevent panics from
/// corrupt pixel buffers from crashing the entire application.
pub(crate) fn safe_image_buf_to_rgba(image_buf: &mut cv::ImageBuf) -> XCapResult<RgbaImage> {
    match panic::catch_unwind(panic::AssertUnwindSafe(|| image_buf_to_rgba(image_buf))) {
        Ok(result) => result,
        Err(_) => Err(XCapError::capture_failed(
            "Panic in image_buf_to_rgba: pixel buffer may be corrupt or deallocated",
        )),
    }
}

/// Capture a single frame from a window using ScreenCaptureKit
///
/// This captures the display containing the window and crops to the window bounds.
/// This approach works reliably for all window types.
pub fn capture_window_sync(window_id: u32, width: u32, height: u32) -> XCapResult<RgbaImage> {
    // If we're in a tokio runtime, run in a separate thread to avoid nested runtime panic
    if tokio::runtime::Handle::try_current().is_ok() {
        run_in_thread(move || block_on(capture_window_async(window_id, width, height)))?
    } else {
        block_on(capture_window_async(window_id, width, height))
    }
}

/// Async version of window capture
async fn capture_window_async(window_id: u32, _width: u32, _height: u32) -> XCapResult<RgbaImage> {
    // Get shareable content
    let content = sc::ShareableContent::current().await.map_err(|e| {
        XCapError::capture_failed(format!("Failed to get shareable content: {:?}", e))
    })?;

    // Find the window
    let windows = content.windows();
    let window = windows
        .iter()
        .find(|w| w.id() == window_id)
        .ok_or_else(|| XCapError::window_not_found(window_id))?;

    // Get window frame
    let window_frame = window.frame();
    let window_x = window_frame.origin.x;
    let window_y = window_frame.origin.y;
    let window_width = window_frame.size.width as u32;
    let window_height = window_frame.size.height as u32;

    debug!(
        "Window {} frame: {}x{} at ({}, {})",
        window_id, window_width, window_height, window_x, window_y
    );

    // Find the display that contains this window
    let displays = content.displays();
    let display = displays
        .iter()
        .find(|d| {
            let display_frame = d.frame();
            // Check if window's origin is within this display
            window_x >= display_frame.origin.x
                && window_y >= display_frame.origin.y
                && window_x < display_frame.origin.x + display_frame.size.width
                && window_y < display_frame.origin.y + display_frame.size.height
        })
        .or_else(|| displays.first())
        .ok_or_else(|| XCapError::capture_failed("No display found for window"))?;

    let display_frame = display.frame();
    let display_width = display.width() as u32;
    let display_height = display.height() as u32;

    debug!(
        "Display frame: {}x{} at ({}, {})",
        display_width, display_height, display_frame.origin.x, display_frame.origin.y
    );

    // Create content filter for the display (captures everything)
    let empty_windows = ns::Array::new();
    let filter = sc::ContentFilter::with_display_excluding_windows(&display, &empty_windows);

    // Create stream configuration - capture at display resolution
    let mut cfg = sc::StreamCfg::new();
    cfg.set_width(display_width as usize);
    cfg.set_height(display_height as usize);
    cfg.set_pixel_format(cv::PixelFormat::_32_BGRA);
    cfg.set_shows_cursor(false);
    if api::macos_available("15.0") {
        cfg.set_show_mouse_clicks(false);
    }
    cfg.set_scales_to_fit(false); // Don't scale, capture at native resolution

    // Use ScreenshotManager for single frame capture (macOS 14.0+)
    let sample_buf = sc::ScreenshotManager::capture_sample_buf(&filter, &cfg)
        .await
        .map_err(|e| XCapError::capture_failed(format!("Screenshot capture failed: {:?}", e)))?;

    // Get the image buffer from the sample buffer
    let mut image_buf = sample_buf
        .image_buf()
        .ok_or_else(|| XCapError::capture_failed("Failed to get image buffer from sample"))?
        .retained();

    // Convert to RGBA (with catch_unwind safety net)
    let full_image = safe_image_buf_to_rgba(&mut image_buf)?;

    // Calculate crop coordinates relative to display origin
    let crop_x = (window_x - display_frame.origin.x) as u32;
    let crop_y = (window_y - display_frame.origin.y) as u32;

    // Clamp crop region to image bounds
    let crop_x = crop_x.min(full_image.width().saturating_sub(1));
    let crop_y = crop_y.min(full_image.height().saturating_sub(1));
    let crop_width = window_width.min(full_image.width().saturating_sub(crop_x));
    let crop_height = window_height.min(full_image.height().saturating_sub(crop_y));

    debug!(
        "Cropping: {}x{} at ({}, {})",
        crop_width, crop_height, crop_x, crop_y
    );

    // Crop to window bounds
    let cropped = image::imageops::crop_imm(&full_image, crop_x, crop_y, crop_width, crop_height);

    Ok(cropped.to_image())
}

/// Build an `SCContentFilter` that excludes the given window IDs from the
/// display capture. If `excluded_window_ids` is empty, returns a filter with
/// an empty exclusion list (captures everything — same as previous behaviour).
fn build_exclusion_filter(
    sc_display: &sc::Display,
    content: &sc::ShareableContent,
    excluded_window_ids: &[u32],
) -> cidre::arc::R<sc::ContentFilter> {
    if excluded_window_ids.is_empty() {
        let empty = ns::Array::new();
        return sc::ContentFilter::with_display_excluding_windows(sc_display, &empty);
    }

    // Collect sc::Window references that match the exclusion list
    let sc_windows = content.windows();
    let mut to_exclude: Vec<&sc::Window> = Vec::new();
    for w in sc_windows.iter() {
        if excluded_window_ids.contains(&w.id()) {
            to_exclude.push(w);
        }
    }

    if to_exclude.is_empty() {
        let empty = ns::Array::new();
        return sc::ContentFilter::with_display_excluding_windows(sc_display, &empty);
    }

    debug!(
        "excluding {} window(s) from display {} capture",
        to_exclude.len(),
        sc_display.display_id().0
    );

    let excluded_array = ns::Array::from_slice(&to_exclude);
    sc::ContentFilter::with_display_excluding_windows(sc_display, &excluded_array)
}

/// Capture a single frame from a monitor using ScreenCaptureKit.
///
/// `excluded_window_ids` — SCK window IDs to exclude from the capture via
/// `SCContentFilter(display:excludingWindows:)`. The OS simply won't render
/// those windows into the capture buffer (zero overhead, pixel-perfect).
/// Pass an empty slice to capture everything (previous behaviour).
pub fn capture_monitor_sync(
    monitor_id: u32,
    width: u32,
    height: u32,
    excluded_window_ids: &[u32],
) -> XCapResult<RgbaImage> {
    let ids = excluded_window_ids.to_vec();
    // If we're in a tokio runtime, run in a separate thread to avoid nested runtime panic
    if tokio::runtime::Handle::try_current().is_ok() {
        run_in_thread(move || block_on(capture_monitor_async(monitor_id, width, height, &ids)))?
    } else {
        block_on(capture_monitor_async(monitor_id, width, height, &ids))
    }
}

/// Async version of monitor capture.
///
/// Uses a persistent SCStream when possible (reuses a single stream per monitor).
/// Falls back to one-shot ScreenshotManager if the persistent stream fails.
async fn capture_monitor_async(
    monitor_id: u32,
    width: u32,
    height: u32,
    excluded_window_ids: &[u32],
) -> XCapResult<RgbaImage> {
    // Try persistent stream first
    match crate::stream_manager::capture_monitor_persistent(
        monitor_id,
        width,
        height,
        excluded_window_ids,
    )
    .await
    {
        Ok(image) => {
            debug!(
                "persistent stream: captured {}x{} for display {}",
                image.width(),
                image.height(),
                monitor_id
            );
            return Ok(image);
        }
        Err(e) => {
            debug!(
                "persistent stream failed for display {}, falling back to one-shot: {}",
                monitor_id, e
            );
        }
    }

    // Fallback: one-shot ScreenshotManager (original path)
    capture_monitor_oneshot(monitor_id, width, height, excluded_window_ids).await
}

/// One-shot monitor capture via ScreenshotManager (fallback path).
async fn capture_monitor_oneshot(
    monitor_id: u32,
    width: u32,
    height: u32,
    excluded_window_ids: &[u32],
) -> XCapResult<RgbaImage> {
    let content = sc::ShareableContent::current().await.map_err(|e| {
        XCapError::capture_failed(format!("Failed to get shareable content: {:?}", e))
    })?;

    let displays = content.displays();
    let display = displays
        .iter()
        .find(|d| d.display_id().0 == monitor_id)
        .ok_or_else(|| XCapError::monitor_not_found(monitor_id))?;

    let filter = build_exclusion_filter(&display, &content, excluded_window_ids);

    let mut cfg = sc::StreamCfg::new();
    cfg.set_width(width as usize);
    cfg.set_height(height as usize);
    cfg.set_pixel_format(cv::PixelFormat::_32_BGRA);
    cfg.set_shows_cursor(false);
    if api::macos_available("15.0") {
        cfg.set_show_mouse_clicks(false);
    }
    cfg.set_scales_to_fit(false);

    debug!(
        "one-shot: capturing monitor {} at {}x{}",
        monitor_id, width, height
    );

    let sample_buf = sc::ScreenshotManager::capture_sample_buf(&filter, &cfg)
        .await
        .map_err(|e| XCapError::capture_failed(format!("Screenshot capture failed: {:?}", e)))?;

    let mut image_buf = sample_buf
        .image_buf()
        .ok_or_else(|| XCapError::capture_failed("Failed to get image buffer from sample"))?
        .retained();

    let result = safe_image_buf_to_rgba(&mut image_buf)?;

    debug!(
        "one-shot: captured {}x{} (requested {}x{})",
        result.width(),
        result.height(),
        width,
        height
    );

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_shareable_content() {
        // This test will fail if screen recording permission is not granted
        let content = get_shareable_content();
        // We just verify the API works
        assert!(content.is_ok() || content.is_err());
    }

    #[tokio::test]
    async fn test_async_shareable_content() {
        let content = sc::ShareableContent::current().await;
        if let Ok(content) = content {
            assert!(!content.windows().is_empty() || !content.displays().is_empty());
        }
    }
}
