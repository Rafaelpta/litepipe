//! Low-level helpers that bypass mlx-rs's safe wrappers when we need
//! ops it doesn't expose (`mlx_contiguous`).

use mlx_rs::Array;

use crate::{Error, Result};

/// Force `arr` into a row-contiguous buffer.
///
/// mlx-rs doesn't expose this op directly, so we call the underlying
/// `mlx_contiguous` C function via `mlx_sys`. Equivalent to PyTorch's
/// `.contiguous()`. Used after every `transpose_axes` we hand to a
/// kernel that doesn't follow strides correctly (which, in mlx-rs as of
/// 0.25, is essentially every kernel — see
/// `src/deformable_attn/mod.rs` for the full story). Cheaper than
/// `add(zeros_of_target_shape)` because it skips constructing the
/// zero tensor.
pub fn contiguous(arr: &Array) -> Result<Array> {
    use mlx_sys::{mlx_array, mlx_array_new, mlx_contiguous, mlx_stream};
    unsafe {
        let mut res: mlx_array = mlx_array_new();
        // Default stream = CPU/GPU based on env. Get the default via
        // a safe path — mlx_rs::Stream::default() handles this.
        let stream = mlx_rs::Stream::default();
        let stream_ptr: mlx_stream = stream.as_ptr();
        let status = mlx_contiguous(&mut res as *mut _, arr.as_ptr(), false, stream_ptr);
        if status != 0 {
            return Err(Error::Inference("mlx_contiguous failed".into()));
        }
        Ok(Array::from_ptr(res))
    }
}
