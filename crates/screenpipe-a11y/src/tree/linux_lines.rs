//! Per-visual-line geometry capture for Linux AT-SPI2 text nodes.
//!
//! Mirrors `macos_lines` for the AT-SPI2 D-Bus interface: walks line
//! boundaries via `Text::GetStringAtOffset(BOUNDARY_LINE_START)` and asks
//! `Text::GetRangeExtents` for each line's screen-absolute rect. The result
//! feeds `AccessibilityTreeNode::lines`, which the search side uses to
//! highlight a tight rect around the matching word inside its line rather
//! than painting the entire paragraph rect.
//!
//! ## Cost model
//!
//! Per multi-line node:
//!   - 1 D-Bus round-trip per line for `GetStringAtOffset`
//!   - 1 D-Bus round-trip per line for `GetRangeExtents`
//!   - = 2 calls per line. Capped by `LineBudget`.
//!
//! D-Bus is local socket IPC, typically 0.1–0.5ms per call — comparable to
//! macOS AX IPC cost.
//!
//! ## Compatibility
//!
//! Most GTK/Qt/Chromium apps implement the Text interface. Apps that don't
//! return a D-Bus error; `capture_line_spans` returns `None` and the caller
//! falls back to the paragraph-only bbox (graceful degrade).

use super::{LineBudget, LineSpan, NodeBounds};
use zbus::blocking::Connection;
use zbus::names::{BusName, InterfaceName};
use zbus::zvariant::ObjectPath;

/// AT-SPI2 D-Bus interface name for text-bearing accessibles.
const ATSPI_TEXT: &str = "org.a11y.atspi.Text";

/// AT-SPI2 `TEXT_BOUNDARY_LINE_START` — boundary type passed to
/// `GetStringAtOffset` so each call returns one full visual line.
/// Source: at-spi2-core/atspi-constants.h.
const BOUNDARY_LINE_START: u32 = 5;

/// AT-SPI2 `ATSPI_COORD_TYPE_SCREEN` — coordinate frame for `GetRangeExtents`.
const COORD_TYPE_SCREEN: u32 = 0;

/// Defensive cap on the iteration loop so a misbehaving Text implementation
/// (one that returns a non-advancing range) can't hang the walker.
const MAX_LOOP_ITERATIONS: usize = 1024;

/// Geometry inputs for normalizing AT-SPI screen-pixel rects to 0-1
/// monitor-relative bounds. Mirrors `linux::normalize_bounds`'s window/monitor
/// fallback cascade without taking a hard dep on `WalkState`.
#[derive(Clone, Copy)]
pub(crate) struct NormalizeRefs {
    pub monitor_x: f64,
    pub monitor_y: f64,
    pub monitor_w: f64,
    pub monitor_h: f64,
    pub window_x: f64,
    pub window_y: f64,
    pub window_w: f64,
    pub window_h: f64,
}

impl NormalizeRefs {
    pub fn normalize(&self, x: f64, y: f64, w: f64, h: f64) -> Option<NodeBounds> {
        let (rx, ry, rw, rh) = if self.monitor_w > 0.0 && self.monitor_h > 0.0 {
            (
                self.monitor_x,
                self.monitor_y,
                self.monitor_w,
                self.monitor_h,
            )
        } else if self.window_w > 0.0 && self.window_h > 0.0 {
            (self.window_x, self.window_y, self.window_w, self.window_h)
        } else {
            return None;
        };
        let left = ((x - rx) / rw) as f32;
        let top = ((y - ry) / rh) as f32;
        let width = (w / rw) as f32;
        let height = (h / rh) as f32;
        if !left.is_finite() || !top.is_finite() || !width.is_finite() || !height.is_finite() {
            return None;
        }
        if left < -0.1 || top < -0.1 || width <= 0.0 || height <= 0.0 || left > 1.1 || top > 1.1 {
            return None;
        }
        Some(NodeBounds {
            left: left.clamp(0.0, 1.0),
            top: top.clamp(0.0, 1.0),
            width: width.min(1.0 - left.max(0.0)),
            height: height.min(1.0 - top.max(0.0)),
        })
    }
}

/// Reference into an AT-SPI2 accessible — bus name + object path. Mirrors
/// the local `AccessibleRef` in `linux.rs` but exposed here so this module
/// can stay decoupled from the walker's internal state.
#[derive(Debug, Clone)]
pub(crate) struct AtspiRef<'a> {
    pub bus_name: &'a str,
    pub path: &'a str,
}

/// Capture per-line spans for a multi-line AT-SPI text node.
///
/// Returns `None` when the budget is exhausted, the Text interface isn't
/// implemented, or the loop fails to advance (defensive — protects against
/// a buggy `GetStringAtOffset` implementation that returns a stale range).
pub(crate) fn capture_line_spans(
    conn: &Connection,
    aref: AtspiRef,
    text: &str,
    refs: &NormalizeRefs,
    budget: &mut LineBudget,
    max_calls_per_node: usize,
) -> Option<Vec<LineSpan>> {
    let total_chars = text.chars().count();
    if total_chars == 0 {
        return None;
    }

    // The Text interface offsets are in characters (Unicode scalar values),
    // matching `text.chars()`. AT-SPI returns (string, start, end) from
    // `GetStringAtOffset(BOUNDARY_LINE_START)` where `end` is exclusive.
    let mut spans: Vec<LineSpan> = Vec::with_capacity(8);
    let mut offset: i32 = 0;
    let total: i32 = total_chars as i32;
    let mut iter: usize = 0;

    while offset < total && spans.len() < max_calls_per_node && iter < MAX_LOOP_ITERATIONS {
        iter += 1;
        if !budget.try_consume(2) {
            break;
        }

        let (line_str, start, end) =
            match get_string_at_offset(conn, &aref, offset, BOUNDARY_LINE_START) {
                Some(t) => t,
                None => break,
            };
        if end <= start {
            // Defensive: degenerate range. Advance past `offset` so we don't
            // loop forever; some impls return (start=end=offset) at the
            // very end of the document.
            offset += 1;
            continue;
        }

        // Skip whitespace-only lines: they're rendered as zero-height spans
        // by browsers and clutter the line list without aiding search.
        if line_str.trim().is_empty() {
            offset = end;
            continue;
        }

        let Some((x, y, w, h)) = get_range_extents(conn, &aref, start, end) else {
            offset = end;
            continue;
        };
        let Some(bounds) = refs.normalize(x as f64, y as f64, w as f64, h as f64) else {
            offset = end;
            continue;
        };

        spans.push(LineSpan {
            char_start: start as u32,
            char_count: (end - start) as u32,
            bounds,
        });
        offset = end;
    }

    if spans.len() <= 1 {
        // One line means the node was actually single-line (caller's heuristic
        // disagreed with AT-SPI's wrap calculation) — drop the lines list so
        // search just uses the paragraph bbox via the existing single-line
        // narrow path.
        return None;
    }
    Some(spans)
}

// ---------------------------------------------------------------------------
// D-Bus helpers — thin wrappers around `Text.GetStringAtOffset` and
// `Text.GetRangeExtents`. Errors on either method (interface not implemented,
// connection drop, etc.) collapse into `None`, matching the rest of the
// AT-SPI walker's defensive style.
// ---------------------------------------------------------------------------

fn dbus_call<B>(
    conn: &Connection,
    dest: &str,
    path: &str,
    iface: &str,
    method: &str,
    body: &B,
) -> zbus::Result<zbus::Message>
where
    B: serde::ser::Serialize + zbus::zvariant::DynamicType,
{
    let dest: BusName = dest.try_into().map_err(zbus::Error::from)?;
    let obj_path: ObjectPath = path.try_into().map_err(zbus::Error::from)?;
    let iface_name: InterfaceName = iface.try_into().map_err(zbus::Error::from)?;
    conn.call_method(Some(dest), obj_path, Some(iface_name), method, body)
}

/// `Text::GetStringAtOffset(offset, type) → (s, startOffset, endOffset)`.
/// Returns `None` on any D-Bus error or unsupported interface.
fn get_string_at_offset(
    conn: &Connection,
    aref: &AtspiRef,
    offset: i32,
    boundary_type: u32,
) -> Option<(String, i32, i32)> {
    let reply = dbus_call(
        conn,
        aref.bus_name,
        aref.path,
        ATSPI_TEXT,
        "GetStringAtOffset",
        &(offset, boundary_type),
    )
    .ok()?;
    let body: (String, i32, i32) = reply.body().deserialize().ok()?;
    Some(body)
}

/// `Text::GetRangeExtents(startOffset, endOffset, coordType) → (x, y, w, h)`.
fn get_range_extents(
    conn: &Connection,
    aref: &AtspiRef,
    start: i32,
    end: i32,
) -> Option<(i32, i32, i32, i32)> {
    let reply = dbus_call(
        conn,
        aref.bus_name,
        aref.path,
        ATSPI_TEXT,
        "GetRangeExtents",
        &(start, end, COORD_TYPE_SCREEN),
    )
    .ok()?;
    let body: (i32, i32, i32, i32) = reply.body().deserialize().ok()?;
    Some(body)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_uses_monitor_when_available() {
        let r = NormalizeRefs {
            monitor_x: 0.0,
            monitor_y: 0.0,
            monitor_w: 1920.0,
            monitor_h: 1080.0,
            window_x: 100.0,
            window_y: 100.0,
            window_w: 800.0,
            window_h: 600.0,
        };
        let nb = r.normalize(960.0, 0.0, 480.0, 270.0).expect("normalizes");
        // 960/1920 = 0.5
        assert!((nb.left - 0.5).abs() < 1e-6);
        // 270/1080 = 0.25
        assert!((nb.height - 0.25).abs() < 1e-6);
    }

    #[test]
    fn normalize_falls_back_to_window() {
        let r = NormalizeRefs {
            monitor_x: 0.0,
            monitor_y: 0.0,
            monitor_w: 0.0,
            monitor_h: 0.0,
            window_x: 0.0,
            window_y: 0.0,
            window_w: 800.0,
            window_h: 600.0,
        };
        let nb = r.normalize(0.0, 0.0, 400.0, 300.0).expect("normalizes");
        assert!((nb.width - 0.5).abs() < 1e-6);
    }

    #[test]
    fn normalize_returns_none_when_no_reference() {
        let r = NormalizeRefs {
            monitor_x: 0.0,
            monitor_y: 0.0,
            monitor_w: 0.0,
            monitor_h: 0.0,
            window_x: 0.0,
            window_y: 0.0,
            window_w: 0.0,
            window_h: 0.0,
        };
        assert!(r.normalize(0.0, 0.0, 100.0, 100.0).is_none());
    }
}
