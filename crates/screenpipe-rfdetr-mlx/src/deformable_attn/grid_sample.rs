//! Single-scale 2D bilinear `grid_sample`-equivalent in pure MLX.
//!
//! Matches `torch.nn.functional.grid_sample(mode='bilinear',
//! padding_mode='zeros', align_corners=False)` exactly. Used by the
//! decoder's deformable cross-attention to look up encoder features at
//! arbitrary fractional positions.

use mlx_rs::{ops, Array};

use crate::{Error, Result};

/// `input`: `(B, C, H, W)`. `grid`: `(B, H_out, W_out, 2)` in `[-1, 1]`,
/// `(x, y)` per location. Returns `(B, C, H_out, W_out)`.
pub fn grid_sample_2d(input: &Array, grid: &Array) -> Result<Array> {
    let in_shape = input.shape();
    let (b, c, h, w) = (in_shape[0], in_shape[1], in_shape[2], in_shape[3]);
    let g_shape = grid.shape();
    let (gb, h_out, w_out, _) = (g_shape[0], g_shape[1], g_shape[2], g_shape[3]);
    debug_assert_eq!(b, gb, "input and grid must share batch dim");

    // Helpers — mlx-rs methods return its own Result; convert to ours.
    let e = err_inf;

    // Split grid into x and y components (both shape (B, H_out, W_out)).
    let xy = ops::split_sections(grid, &[1], -1).map_err(e("split"))?;
    let gx = xy[0].reshape(&[b, h_out, w_out]).map_err(e("gx reshape"))?;
    let gy = xy[1].reshape(&[b, h_out, w_out]).map_err(e("gy reshape"))?;

    // Map [-1, 1] → pixel space with align_corners=False.
    let one = Array::from_f32(1.0);
    let half = Array::from_f32(0.5);
    let w_f = Array::from_f32(w as f32);
    let h_f = Array::from_f32(h as f32);
    let ix = mul(&sub(&mul(&add(&gx, &one)?, &w_f)?, &one)?, &half)?;
    let iy = mul(&sub(&mul(&add(&gy, &one)?, &h_f)?, &one)?, &half)?;

    let ix0 = ops::floor(&ix).map_err(e("ix0 floor"))?;
    let iy0 = ops::floor(&iy).map_err(e("iy0 floor"))?;
    let ix1 = add(&ix0, &one)?;
    let iy1 = add(&iy0, &one)?;

    // Bilinear weights.
    let dx0 = sub(&ix, &ix0)?;
    let dy0 = sub(&iy, &iy0)?;
    let dx1 = sub(&ix1, &ix)?;
    let dy1 = sub(&iy1, &iy)?;
    let w00 = mul(&dx1, &dy1)?;
    let w01 = mul(&dx0, &dy1)?;
    let w10 = mul(&dx1, &dy0)?;
    let w11 = mul(&dx0, &dy0)?;

    // Boundary masks (1.0 if in-bounds, 0.0 otherwise).
    let zero = Array::from_f32(0.0);
    let w_max = Array::from_f32((w - 1) as f32);
    let h_max = Array::from_f32((h - 1) as f32);
    let in_x0 = and_(&ge_(&ix0, &zero)?, &le_(&ix0, &w_max)?)?;
    let in_x1 = and_(&ge_(&ix1, &zero)?, &le_(&ix1, &w_max)?)?;
    let in_y0 = and_(&ge_(&iy0, &zero)?, &le_(&iy0, &h_max)?)?;
    let in_y1 = and_(&ge_(&iy1, &zero)?, &le_(&iy1, &h_max)?)?;
    let m00 = mul(&in_x0, &in_y0)?;
    let m01 = mul(&in_x1, &in_y0)?;
    let m10 = mul(&in_x0, &in_y1)?;
    let m11 = mul(&in_x1, &in_y1)?;

    // Clip integer indices for safe gather.
    let ix0c = clip01(&ix0, (w - 1) as f32)?;
    let ix1c = clip01(&ix1, (w - 1) as f32)?;
    let iy0c = clip01(&iy0, (h - 1) as f32)?;
    let iy1c = clip01(&iy1, (h - 1) as f32)?;

    // Linear flat indices: idx = iy * W + ix.
    let w_arr = Array::from_f32(w as f32);
    let idx_a = add(&mul(&iy0c, &w_arr)?, &ix0c)?;
    let idx_b = add(&mul(&iy0c, &w_arr)?, &ix1c)?;
    let idx_c = add(&mul(&iy1c, &w_arr)?, &ix0c)?;
    let idx_d = add(&mul(&iy1c, &w_arr)?, &ix1c)?;

    // Flatten input spatial: (B, C, H, W) → (B, C, H*W).
    let input_flat = input.reshape(&[b, c, h * w]).map_err(e("input flatten"))?;

    let v00 = gather_corner(&input_flat, &idx_a, b, c, h_out, w_out)?;
    let v01 = gather_corner(&input_flat, &idx_b, b, c, h_out, w_out)?;
    let v10 = gather_corner(&input_flat, &idx_c, b, c, h_out, w_out)?;
    let v11 = gather_corner(&input_flat, &idx_d, b, c, h_out, w_out)?;

    // Combine: weighted sum, masked.
    let mw00 = mul(&w00, &m00)?;
    let mw01 = mul(&w01, &m01)?;
    let mw10 = mul(&w10, &m10)?;
    let mw11 = mul(&w11, &m11)?;
    // Reshape weights for broadcast over channel dim.
    let mw00 = mw00.reshape(&[b, 1, h_out, w_out]).map_err(e("mw00 rs"))?;
    let mw01 = mw01.reshape(&[b, 1, h_out, w_out]).map_err(e("mw01 rs"))?;
    let mw10 = mw10.reshape(&[b, 1, h_out, w_out]).map_err(e("mw10 rs"))?;
    let mw11 = mw11.reshape(&[b, 1, h_out, w_out]).map_err(e("mw11 rs"))?;
    let s = add(&mul(&v00, &mw00)?, &mul(&v01, &mw01)?)?;
    let s = add(&s, &mul(&v10, &mw10)?)?;
    let s = add(&s, &mul(&v11, &mw11)?)?;
    Ok(s)
}

fn gather_corner(
    input_flat: &Array,
    idx_f: &Array,
    b: i32,
    c: i32,
    h_out: i32,
    w_out: i32,
) -> Result<Array> {
    let e = err_inf;
    let idx_i = idx_f
        .as_dtype(mlx_rs::Dtype::Int32)
        .map_err(e("idx cast"))?;
    let idx_b = idx_i
        .reshape(&[b, 1, h_out * w_out])
        .map_err(e("idx reshape"))?;
    let idx_bc = ops::broadcast_to(&idx_b, &[b, c, h_out * w_out]).map_err(e("idx broadcast"))?;
    let gathered = input_flat
        .take_along_axis(&idx_bc, 2)
        .map_err(e("take_along_axis"))?;
    gathered
        .reshape(&[b, c, h_out, w_out])
        .map_err(e("gather reshape"))
}

// ---------- small wrappers that map mlx-rs error → our Error ----------

fn add(a: &Array, b: &Array) -> Result<Array> {
    a.add(b).map_err(err_inf("add"))
}
fn sub(a: &Array, b: &Array) -> Result<Array> {
    a.subtract(b).map_err(err_inf("sub"))
}
fn mul(a: &Array, b: &Array) -> Result<Array> {
    a.multiply(b).map_err(err_inf("mul"))
}
fn ge_(a: &Array, b: &Array) -> Result<Array> {
    a.ge(b)
        .map_err(err_inf("ge"))?
        .as_dtype(mlx_rs::Dtype::Float32)
        .map_err(err_inf("ge cast"))
}
fn le_(a: &Array, b: &Array) -> Result<Array> {
    a.le(b)
        .map_err(err_inf("le"))?
        .as_dtype(mlx_rs::Dtype::Float32)
        .map_err(err_inf("le cast"))
}
fn and_(a: &Array, b: &Array) -> Result<Array> {
    mul(a, b)
}
fn clip01(x: &Array, hi: f32) -> Result<Array> {
    // clip(x, lo, hi). mlx-rs's clip expects (x, ClipBound) where
    // ClipBound = a single bound or (lo, hi). Easier to do max(min(x, hi), 0).
    let hi_arr = Array::from_f32(hi);
    let zero = Array::from_f32(0.0);
    let upper = ops::minimum(x, &hi_arr).map_err(err_inf("clip min"))?;
    ops::maximum(&upper, &zero).map_err(err_inf("clip max"))
}

fn err_inf(tag: &'static str) -> impl Fn(mlx_rs::error::Exception) -> Error {
    move |e| Error::Inference(format!("grid_sample {tag}: {e}"))
}
