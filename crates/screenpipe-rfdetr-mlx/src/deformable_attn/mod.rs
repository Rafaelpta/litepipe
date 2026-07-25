//! Single-scale deformable attention — RF-DETR-Nano uses one feature
//! scale (P4) so multi-scale gathering reduces to one bilinear sample
//! per (head, point).
//!
//! Reference: `rfdetr/models/ops/modules/ms_deform_attn.py` and the
//! pure-PyTorch fallback in `ms_deform_attn_core_pytorch`.

pub mod grid_sample;

use mlx_rs::{ops, Array};

use crate::{Error, Result};

const N_HEADS: i32 = 16;
const N_POINTS: i32 = 2;
const HEAD_DIM: i32 = 16; // 256 / 16
const H: i32 = 24;
const W: i32 = 24;

/// Diagnostic outputs for [`deformable_attn_single_scale_debug`].
pub struct DefAttnDebug {
    pub v_nchw: Array,   // (B*M, D, H, W)
    pub grids: Array,    // (B*M, Lq, P, 2)
    pub sampled: Array,  // (B*M, D, Lq, P)
    pub aw_mul: Array,   // (B*M, 1, Lq, P)
    pub weighted: Array, // (B*M, D, Lq, P)
    pub summed: Array,   // (B*M, D, Lq)
    pub output: Array,   // (B, Lq, M*D)
}

/// Same as [`deformable_attn_single_scale`] but exposes every intermediate
/// for parity debugging.
pub fn deformable_attn_single_scale_debug(
    value: &Array,
    sampling_locations: &Array,
    attention_weights: &Array,
) -> Result<DefAttnDebug> {
    let v_shape = value.shape();
    let (b, hw, c) = (v_shape[0], v_shape[1], v_shape[2]);
    let l_shape = sampling_locations.shape();
    let lq = l_shape[1];
    let one = Array::from_f32(1.0);
    debug_assert_eq!(hw, H * W);
    debug_assert_eq!(c, N_HEADS * HEAD_DIM);

    let v_t = value
        .transpose_axes(&[0, 2, 1])
        .map_err(err("v transpose"))?;
    let v_zero = ops::zeros::<f32>(&[b, c, hw]).map_err(err("v zero"))?;
    let v = v_t.add(&v_zero).map_err(err("v materialize"))?;
    let v = v
        .reshape(&[b, N_HEADS, HEAD_DIM, hw])
        .map_err(err("v split heads"))?;
    let v = v
        .reshape(&[b * N_HEADS, HEAD_DIM, H, W])
        .map_err(err("v reshape NCHW"))?;
    v.eval().map_err(err("eval v"))?;

    let two = Array::from_f32(2.0);
    let scaled = sampling_locations.multiply(&two).map_err(err("loc *2"))?;
    let grids = scaled.subtract(&one).map_err(err("loc -1"))?;
    let grids_t = grids
        .transpose_axes(&[0, 2, 1, 3, 4])
        .map_err(err("grids perm"))?;
    let grids_zero =
        ops::zeros::<f32>(&[b, N_HEADS, lq, N_POINTS, 2]).map_err(err("grids zero"))?;
    let grids = grids_t.add(&grids_zero).map_err(err("grids materialize"))?;
    let grids = grids
        .reshape(&[b * N_HEADS, lq, N_POINTS, 2])
        .map_err(err("grids reshape"))?;
    grids.eval().map_err(err("eval grids"))?;

    let sampled = grid_sample::grid_sample_2d(&v, &grids)?;
    sampled.eval().map_err(err("eval sampled"))?;

    let aw_t = attention_weights
        .transpose_axes(&[0, 2, 1, 3])
        .map_err(err("aw perm"))?;
    let aw_zero = ops::zeros::<f32>(&[b, N_HEADS, lq, N_POINTS]).map_err(err("aw zero"))?;
    let aw_materialized = aw_t.add(&aw_zero).map_err(err("aw materialize"))?;
    let aw_mul = aw_materialized
        .reshape(&[b * N_HEADS, 1, lq, N_POINTS])
        .map_err(err("aw reshape"))?;
    aw_mul.eval().map_err(err("eval aw"))?;

    let weighted = sampled.multiply(&aw_mul).map_err(err("weighted"))?;
    weighted.eval().map_err(err("eval weighted"))?;

    let summed = ops::sum_axis(&weighted, -1, false).map_err(err("sum points"))?;
    summed.eval().map_err(err("eval summed"))?;

    let four_d = summed
        .reshape(&[b, N_HEADS, HEAD_DIM, lq])
        .map_err(err("4d reshape"))?;
    let perm = four_d
        .transpose_axes(&[0, 3, 1, 2])
        .map_err(err("final perm"))?;
    let final_zero = ops::zeros::<f32>(&[b, lq, N_HEADS, HEAD_DIM]).map_err(err("final zero"))?;
    let materialized = perm.add(&final_zero).map_err(err("final materialize"))?;
    let output = materialized
        .reshape(&[b, lq, N_HEADS * HEAD_DIM])
        .map_err(err("final flatten"))?;
    output.eval().map_err(err("eval output"))?;

    Ok(DefAttnDebug {
        v_nchw: v,
        grids,
        sampled,
        aw_mul,
        weighted,
        summed,
        output,
    })
}

/// Single-scale deformable cross-attention forward.
///
/// Inputs:
/// - `value`: `(B, HW, C)` after `value_proj` (NOT split into heads yet).
/// - `sampling_locations`: `(B, Lq, n_heads, n_points, 2)` in `[0, 1]`.
/// - `attention_weights`: `(B, Lq, n_heads, n_points)` softmax-normalized
///   across `n_points` (since `n_levels=1`).
///
/// Output: `(B, Lq, C)` — pre-`output_proj`, post-deformable-gather.
pub fn deformable_attn_single_scale(
    value: &Array,
    sampling_locations: &Array,
    attention_weights: &Array,
) -> Result<Array> {
    let v_shape = value.shape();
    let (b, hw, c) = (v_shape[0], v_shape[1], v_shape[2]);
    let l_shape = sampling_locations.shape();
    let lq = l_shape[1];
    debug_assert_eq!(hw, H * W);
    debug_assert_eq!(c, N_HEADS * HEAD_DIM);

    // Reshape value to per-head: (B, HW, M, D) → (B*M, D, H, W) for grid_sample.
    //
    // We use `crate::util::contiguous` (the unwrapped `mlx_contiguous` C
    // op) after every transpose-then-reshape boundary because
    // `transpose_axes` returns a strided view and mlx-rs's optimizer
    // folds `multiply(&one)` away. `contiguous` is cheaper than the
    // earlier `add(zeros_of_target_shape)` workaround.
    let v_t = value
        .transpose_axes(&[0, 2, 1])
        .map_err(err("v transpose"))?;
    let v = crate::util::contiguous(&v_t)?;
    let v = v
        .reshape(&[b, N_HEADS, HEAD_DIM, hw])
        .map_err(err("v split heads"))?;
    let v = v
        .reshape(&[b * N_HEADS, HEAD_DIM, H, W])
        .map_err(err("v reshape NCHW"))?;

    // sampling_locations from [0,1] to [-1,1] for grid_sample.
    let two = Array::from_f32(2.0);
    let one = Array::from_f32(1.0);
    let scaled = sampling_locations.multiply(&two).map_err(err("loc *2"))?;
    let grids = scaled.subtract(&one).map_err(err("loc -1"))?;
    let grids_t = grids
        .transpose_axes(&[0, 2, 1, 3, 4])
        .map_err(err("grids perm"))?;
    let grids = crate::util::contiguous(&grids_t)?;
    let grids = grids
        .reshape(&[b * N_HEADS, lq, N_POINTS, 2])
        .map_err(err("grids reshape"))?;

    let sampled = grid_sample::grid_sample_2d(&v, &grids)?;

    // Multiply by attention weights and sum over points.
    let aw_t = attention_weights
        .transpose_axes(&[0, 2, 1, 3])
        .map_err(err("aw perm"))?;
    let aw = crate::util::contiguous(&aw_t)?;
    let aw = aw
        .reshape(&[b * N_HEADS, 1, lq, N_POINTS])
        .map_err(err("aw reshape"))?;
    let weighted = sampled.multiply(&aw).map_err(err("weighted"))?;
    let summed = ops::sum_axis(&weighted, -1, false).map_err(err("sum points"))?;
    let four_d = summed
        .reshape(&[b, N_HEADS, HEAD_DIM, lq])
        .map_err(err("4d reshape"))?;
    let perm = four_d
        .transpose_axes(&[0, 3, 1, 2])
        .map_err(err("final perm"))?;
    let materialized = crate::util::contiguous(&perm)?;
    materialized
        .reshape(&[b, lq, N_HEADS * HEAD_DIM])
        .map_err(err("final flatten"))
}

fn err(tag: &'static str) -> impl Fn(mlx_rs::error::Exception) -> Error {
    move |e| Error::Inference(format!("ms_deform_attn {tag}: {e}"))
}
