# screenpipe-rfdetr-mlx

RF-DETR-Nano image-PII detector in pure Rust + [`mlx-rs`][mlx-rs],
Apple-Silicon-only. Runtime backing for the `mlx-mac` feature on
`screenpipe-redact`.

Bench on the 8-image PII corpus (M-series, F32, single-image batch):

| runtime                   | p50 ms | fps | speedup vs ONNX |
|---------------------------|-------:|----:|----------------:|
| **this crate**            |    7.9 | 126 | —               |
| ONNX Runtime, CPU EP      |   51.3 |  20 | 6.5×            |
| ONNX Runtime, CoreML EP   |   53.9 |  19 | 6.8×            |

Same model (`rfdetr_v9`), same weights, same image preprocessing.
Parity: 41/42 detections match ONNX 1-to-1 at IoU ≥ 0.7, max score
diff 0.075.

## Layout

  - `src/backbone/`    — DINOv2-small ViT, 12 windowed layers, dim 384
  - `src/encoder/`     — empty (LWDETR uses just the backbone here)
  - `src/decoder/`     — 2-layer LWDETR, single-scale deformable attn
  - `src/deformable_attn/` — pure-MLX deformable cross-attention
  - `src/postprocess.rs`   — sigmoid + per-query argmax + thresholding
  - `src/weights.rs`   — safetensors loader
  - `src/util.rs`      — `mlx_contiguous` wrapper (mlx-rs doesn't
    expose this op; we go through `mlx-sys` for the raw C call)

## Weights

The runtime loads safetensors. The adapter
(`screenpipe-redact::adapters::rfdetr_mlx`) looks for the file at
`~/.screenpipe/models/rfdetr_v9.safetensors` by default.

Until a safetensors sibling is published next to `rfdetr_v9.onnx` on
[huggingface.co/screenpipe/pii-image-redactor][hf], convert from the
existing ONNX yourself with the script kept in the archived
[`screenpipe/rfdetr-mlx`][archive] repo (`convert/onnx_to_mlx.py`).
Single-shot, deterministic, reproducible.

## Performance notes — what worked

  * **Tail-eval the encoder once.** Per-layer `eval()` blocks GPU
    pipelining; one eval at the end of the 12-block stack lets MLX
    schedule freely, and CSE dedupes the 4 multi-scale snapshots.
    Saves ~3ms on the backbone.
  * **Fold LayerScale into out_proj/fc2 weights.** LayerScale is a
    per-output-channel multiply: `linear(x, w, b) * lambda ==
    linear(x, w*lambda, b*lambda)`. Pre-multiply at load → 2× ops
    elided per encoder block per forward.
  * **Pre-transpose constant weights at load.** The decoder self-attn
    `out_proj_w` was being transposed + materialized every forward.
  * **Materialize conv weights once.** PatchEmbed's NHWC weight was a
    strided transpose view; conv2d copied it internally on every call.
  * **`Array::clone()` is a refcount bump, not a deep copy.** Use
    `clone()` everywhere `deep_clone()` was used for read-only
    handles (residual shortcuts, refpoint tensors).
  * **Fused QKV switched twice.** Stacking Q/K/V into one
    `(384, 1152)` matmul + split *regressed* ~20% under per-layer
    eval (MLX dispatched the three small matmuls in parallel and
    fusing serialised them). After tail-eval and LayerScale fold
    landed, fused QKV now wins ~3% — the per-block path is short
    enough that one kernel dispatch beats three.
  * **F16/BF16 weights are slower on M-series.** Apple GPU has no
    native BF16; the F16 kernels for these shapes hit a fallback.
    Stays env-var opt-in (`RFDETR_MLX_FP16=f16` / `=bf16`).

## mlx-rs gotchas hit during the port

  1. `transpose_axes` returns a strided view; `multiply(&one)` does
     NOT force materialization (mlx-rs's optimiser folds `*1` away).
     Use `crate::util::contiguous` (raw `mlx_contiguous` C op via
     `mlx-sys`) at every transpose-then-reshape boundary.
  2. ONNX exports `nn.Linear` as `MatMul` (weight in `(in, out)`)
     for 3D inputs and `Gemm(transB=1)` (weight in `(out, in)`) for
     2D inputs. Decoder `MultiheadAttention.out_proj` happens to hit
     the 2D path; needs `.t()` on its weight, the in-projections
     don't.
  3. RF-DETR's decoder cross-attention takes the RAW projector
     output as memory, NOT the post-`enc_output` Linear+LN result.
     `enc_output` is only used for the two-stage proposal heads.

[mlx-rs]: https://github.com/oxiglade/mlx-rs
[hf]: https://huggingface.co/screenpipe/pii-image-redactor
[archive]: https://github.com/screenpipe/rfdetr-mlx
