//! Monitor/Display capture using ScreenCaptureKit via cidre

use cidre::cg;
use image::RgbaImage;
use tracing::debug;

use crate::capture;
use crate::error::{XCapError, XCapResult};

/// Represents a capturable monitor/display
///
/// This type provides an API compatible with xcap::Monitor
#[derive(Debug, Clone)]
pub struct Monitor {
    /// The display ID
    display_id: u32,
    /// Display name (if available)
    name: String,
    /// Display X position
    x: i32,
    /// Display Y position
    y: i32,
    /// Display width in pixels used for capture (SCK dimensions)
    width: u32,
    /// Display height in pixels used for capture (SCK dimensions)
    height: u32,
    /// Logical width (what macOS reports for UI layout)
    logical_width: u32,
    /// Logical height (what macOS reports for UI layout)
    logical_height: u32,
    /// Scale factor (for Retina displays) - ratio of physical to logical pixels
    scale_factor: f64,
    /// Whether this is the primary display
    is_primary: bool,
}

impl Monitor {
    /// Get all available monitors
    ///
    /// Returns a list of all displays that can be captured.
    /// Requires screen recording permission.
    pub fn all() -> XCapResult<Vec<Monitor>> {
        let content = capture::get_shareable_content()?;

        let displays = content.displays();

        if displays.is_empty() {
            return Err(XCapError::no_monitors());
        }

        // Find the primary display (usually the first one, or has origin at 0,0)
        let primary_id = displays
            .iter()
            .find(|d| {
                let frame = d.frame();
                frame.origin.x == 0.0 && frame.origin.y == 0.0
            })
            .map(|d| d.display_id().0)
            .unwrap_or_else(|| displays.first().map(|d| d.display_id().0).unwrap_or(0));

        let monitors: Vec<Monitor> = displays
            .iter()
            .map(|d| {
                let frame = d.frame();
                let display_id = d.display_id().0;

                // SCK dimensions (what SCK expects for capture)
                let sck_width = d.width() as u32;
                let sck_height = d.height() as u32;

                // Use cidre's CGDirectDisplayId for native pixel info
                let cg_id = cg::DirectDisplayId(display_id);
                let cg_pixels_width = cg_id.pixels_wide() as u32;
                let cg_pixels_height = cg_id.pixels_high() as u32;
                let cg_bounds = cg_id.bounds();
                let cg_bounds_width = cg_bounds.size.width as u32;
                let cg_bounds_height = cg_bounds.size.height as u32;

                // Use SCK dimensions for capture
                let (capture_width, capture_height) = (sck_width, sck_height);

                // Calculate scale factor
                let scale_factor = if sck_width > 0 && sck_height > 0 {
                    let width_scale = cg_pixels_width as f64 / sck_width as f64;
                    let height_scale = cg_pixels_height as f64 / sck_height as f64;
                    ((width_scale + height_scale) / 2.0).max(1.0)
                } else {
                    1.0
                };

                debug!(
                    "Display {} dimensions - SCK: {}x{}, CGPixels: {}x{}, CGBounds: {}x{}, using: {}x{}",
                    display_id,
                    sck_width, sck_height,
                    cg_pixels_width, cg_pixels_height,
                    cg_bounds_width, cg_bounds_height,
                    capture_width, capture_height
                );

                Monitor {
                    display_id,
                    name: format!("Display {}", display_id),
                    x: frame.origin.x as i32,
                    y: frame.origin.y as i32,
                    width: capture_width,
                    height: capture_height,
                    logical_width: cg_bounds_width,
                    logical_height: cg_bounds_height,
                    scale_factor,
                    is_primary: display_id == primary_id,
                }
            })
            .collect();

        Ok(monitors)
    }

    /// Get the primary monitor
    pub fn primary() -> XCapResult<Monitor> {
        let monitors = Self::all()?;
        monitors
            .into_iter()
            .find(|m| m.is_primary)
            .ok_or_else(|| XCapError::new("No primary monitor found"))
    }

    /// Get the monitor ID
    pub fn id(&self) -> u32 {
        self.display_id
    }

    /// Get the monitor name
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Get the monitor X position
    pub fn x(&self) -> i32 {
        self.x
    }

    /// Get the monitor Y position
    pub fn y(&self) -> i32 {
        self.y
    }

    /// Get the monitor width in pixels
    pub fn width(&self) -> XCapResult<u32> {
        Ok(self.width)
    }

    /// Get the monitor height in pixels
    pub fn height(&self) -> XCapResult<u32> {
        Ok(self.height)
    }

    /// Get the raw width (non-Result version) - returns physical pixels
    pub fn raw_width(&self) -> u32 {
        self.width
    }

    /// Get the raw height (non-Result version) - returns physical pixels
    pub fn raw_height(&self) -> u32 {
        self.height
    }

    /// Get the logical width (what macOS reports for UI layout)
    pub fn logical_width(&self) -> u32 {
        self.logical_width
    }

    /// Get the logical height (what macOS reports for UI layout)
    pub fn logical_height(&self) -> u32 {
        self.logical_height
    }

    /// Get the scale factor (for Retina displays)
    pub fn scale_factor(&self) -> f64 {
        self.scale_factor
    }

    /// Check if this is the primary monitor
    pub fn is_primary(&self) -> bool {
        self.is_primary
    }

    /// Capture an image of the monitor
    ///
    /// Returns an RGBA image of the entire monitor.
    /// Uses a persistent SCStream internally (reuses across calls).
    pub fn capture_image(&self) -> XCapResult<RgbaImage> {
        capture::capture_monitor_sync(self.display_id, self.width, self.height, &[])
    }

    /// Capture an image of the monitor, excluding the given SCK window IDs.
    ///
    /// The OS will not render excluded windows into the capture buffer
    /// (zero overhead, pixel-perfect). Use this to hide sensitive apps
    /// (password managers, banking apps, etc.) from stored frames.
    pub fn capture_image_excluding(&self, excluded_window_ids: &[u32]) -> XCapResult<RgbaImage> {
        capture::capture_monitor_sync(self.display_id, self.width, self.height, excluded_window_ids)
    }

    /// Capture an image of the monitor, downscaled at the source.
    ///
    /// `max_width` is the upper bound on captured width; height is derived
    /// from the source aspect ratio. If `max_width >= native_width` this is
    /// equivalent to `capture_image()` (no downscale).
    ///
    /// Cheaper than capturing native and resizing in user space: the GPU
    /// resizes the framebuffer before `replayd` hands it back, so WindowServer
    /// composites + reads back a smaller surface. Use for OCR-quality
    /// consumers that don't need pixel-perfect captures.
    ///
    /// Internally reuses the persistent SCStream cache. Different `max_width`
    /// values for the same monitor will recreate the stream (same caching
    /// rules as resolution changes).
    pub fn capture_image_scaled(&self, max_width: u32) -> XCapResult<RgbaImage> {
        let (target_w, target_h) = scaled_dims(self.width, self.height, max_width);
        capture::capture_monitor_sync(self.display_id, target_w, target_h, &[])
    }

    /// Same as `capture_image_scaled` but with window exclusion.
    pub fn capture_image_scaled_excluding(
        &self,
        max_width: u32,
        excluded_window_ids: &[u32],
    ) -> XCapResult<RgbaImage> {
        let (target_w, target_h) = scaled_dims(self.width, self.height, max_width);
        capture::capture_monitor_sync(self.display_id, target_w, target_h, excluded_window_ids)
    }

    /// Stop the persistent capture stream for this monitor.
    ///
    /// The stream will be recreated automatically on the next `capture_image()` call.
    /// Use this when pausing capture (e.g., for DRM content) to fully release
    /// ScreenCaptureKit handles.
    pub fn stop_stream(&self) {
        crate::stream_manager::invalidate_monitor_stream(self.display_id);
    }
}

/// Compute target (width, height) capped at `max_width` while preserving
/// the source aspect ratio. Always returns at least 1×1 to avoid degenerate
/// SCK configs.
fn scaled_dims(src_w: u32, src_h: u32, max_width: u32) -> (u32, u32) {
    if src_w == 0 || src_h == 0 || max_width == 0 || max_width >= src_w {
        return (src_w.max(1), src_h.max(1));
    }
    let target_w = max_width;
    // Preserve aspect ratio with rounding.
    let target_h = ((max_width as u64 * src_h as u64) + (src_w as u64 / 2)) / src_w as u64;
    (target_w, (target_h as u32).max(1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_monitor_getters() {
        let monitor = Monitor {
            display_id: 1,
            name: "Test Display".to_string(),
            x: 0,
            y: 0,
            width: 3840,
            height: 2160,
            logical_width: 1920,
            logical_height: 1080,
            scale_factor: 2.0,
            is_primary: true,
        };

        assert_eq!(monitor.id(), 1);
        assert_eq!(monitor.name(), "Test Display");
        assert_eq!(monitor.x(), 0);
        assert_eq!(monitor.y(), 0);
        assert_eq!(monitor.width().unwrap(), 3840);
        assert_eq!(monitor.height().unwrap(), 2160);
        assert_eq!(monitor.raw_width(), 3840);
        assert_eq!(monitor.raw_height(), 2160);
        assert_eq!(monitor.logical_width(), 1920);
        assert_eq!(monitor.logical_height(), 1080);
        assert_eq!(monitor.scale_factor(), 2.0);
        assert!(monitor.is_primary());
    }

    #[test]
    fn test_monitor_all() {
        let result = Monitor::all();
        let _ = result;
    }
}
