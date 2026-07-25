//! Per-visual-line geometry capture for Windows UIA text nodes.
//!
//! ## Status: stub
//!
//! The Windows UIA walker (`tree/windows.rs`) consumes `IUIAutomationElement`
//! handles eagerly into a cached `AccessibilityNode` snapshot, then runs
//! `extract_text_from_tree` over the snapshot. Line capture needs the live
//! element handle to fetch `UIA_TextPatternId` and walk `TextRange` units;
//! threading those handles through the recursive walker is a separate
//! refactor.
//!
//! `AccessibilityTreeNode::lines` is `None` on Windows for now and the
//! search side falls back to the paragraph bbox path automatically — same
//! behaviour as before this commit, no regression.
//!
//! ## When the refactor lands, the implementation is:
//!
//! 1. From the live `IUIAutomationElement`, fetch the `TextPattern`:
//!    ```ignore
//!    let pat: IUIAutomationTextPattern =
//!        elem.GetCurrentPatternAs(UIA_TextPatternId)?;
//!    ```
//! 2. Get the document range covering the element's text:
//!    ```ignore
//!    let doc = pat.DocumentRange()?;
//!    ```
//! 3. Iterate visual lines by cloning + moving endpoints:
//!    ```ignore
//!    let mut cursor = doc.Clone()?;
//!    cursor.MoveEndpointByRange(TextPatternRangeEndpoint_End, &cursor,
//!                               TextPatternRangeEndpoint_Start)?;
//!    while cursor.MoveEndpointByUnit(TextPatternRangeEndpoint_End,
//!                                    TextUnit_Line, 1)? != 0 {
//!        let text = cursor.GetText(-1)?;
//!        let rects = cursor.GetBoundingRectangles()?;  // SAFEARRAY of doubles
//!        // each rect = 4 doubles (left, top, width, height)
//!        // build LineSpan and reset cursor.Start = cursor.End
//!    }
//!    ```
//! 4. Mirror `linux_lines::capture_line_spans`'s budget and normalize
//!    handling — same `LineBudget` from `tree::mod`.

use super::{LineBudget, LineSpan, NodeBounds};

/// Geometry inputs for normalizing UIA screen-pixel rects to 0-1
/// monitor-relative bounds. Mirrors `windows::normalize_bounds` so when the
/// real implementation lands it can use this directly.
#[derive(Clone, Copy)]
#[allow(dead_code)] // exercised once the UIA refactor lands
pub(crate) struct NormalizeRefs {
    pub monitor_x: f64,
    pub monitor_y: f64,
    pub monitor_w: f64,
    pub monitor_h: f64,
}

#[allow(dead_code)] // exercised once the UIA refactor lands
impl NormalizeRefs {
    pub fn normalize(&self, x: f64, y: f64, w: f64, h: f64) -> Option<NodeBounds> {
        if self.monitor_w <= 0.0 || self.monitor_h <= 0.0 {
            return None;
        }
        let left = ((x - self.monitor_x) / self.monitor_w) as f32;
        let top = ((y - self.monitor_y) / self.monitor_h) as f32;
        let width = (w / self.monitor_w) as f32;
        let height = (h / self.monitor_h) as f32;
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

/// Returns `None` until the UIA TextPattern path is plumbed through the
/// walker. The search side renders the paragraph bbox as a fallback —
/// identical to the pre-line-capture behaviour, no regression.
#[allow(dead_code, unused_variables)] // pending the UIA refactor
pub(crate) fn capture_line_spans(
    refs: &NormalizeRefs,
    budget: &mut LineBudget,
    max_calls_per_node: usize,
) -> Option<Vec<LineSpan>> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_returns_none_when_monitor_zero() {
        let r = NormalizeRefs {
            monitor_x: 0.0,
            monitor_y: 0.0,
            monitor_w: 0.0,
            monitor_h: 0.0,
        };
        assert!(r.normalize(0.0, 0.0, 100.0, 100.0).is_none());
    }

    #[test]
    fn normalize_clamps_inside_unit_square() {
        let r = NormalizeRefs {
            monitor_x: 0.0,
            monitor_y: 0.0,
            monitor_w: 1920.0,
            monitor_h: 1080.0,
        };
        let nb = r.normalize(0.0, 0.0, 960.0, 540.0).expect("normalizes");
        assert!((nb.width - 0.5).abs() < 1e-6);
        assert!((nb.height - 0.5).abs() < 1e-6);
    }
}
