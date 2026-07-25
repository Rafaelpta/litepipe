//! Safetensors → MLX-array loader.
//!
//! `convert/onnx_to_mlx.py` writes one safetensors file holding every
//! ONNX initializer verbatim. This module memory-maps it, deserializes,
//! and converts each tensor to an `mlx_rs::Array` via the `TryFrom`
//! impl already provided by mlx-rs (`mlx_rs::array::safetensors`).
//!
//! The Rust side is the source of truth for naming — Python writes
//! `onnx::MatMul_3985` etc., the per-module forward() pulls weights by
//! whatever ONNX name the graph used.

use std::collections::HashMap;
use std::path::Path;

use mlx_rs::Array;
use safetensors::SafeTensors;

use crate::{Error, Result};

const EXPECTED_MODEL: &str = "rfdetr_nano_v9";

/// Holds every initializer from the converted ONNX, keyed by its
/// original ONNX name.
pub struct Weights {
    inner: HashMap<String, Array>,
    /// Human-readable model identifier from the safetensors metadata —
    /// e.g. `"rfdetr_nano_v9"`. Used by the loader to refuse weights
    /// from an architecture this code doesn't know how to wire up.
    pub model: String,
}

impl Weights {
    /// Memory-maps the file and parses the header. The actual tensor
    /// payloads stay in the mmap'd region — `mlx_rs::Array` copies them
    /// into MLX-managed memory at construction time.
    pub fn load(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        let bytes = std::fs::read(path)
            .map_err(|e| Error::Weights(format!("read {}: {e}", path.display())))?;
        Self::from_bytes(&bytes)
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        let st = SafeTensors::deserialize(bytes)
            .map_err(|e| Error::Weights(format!("safetensors header: {e}")))?;

        // Pull metadata so we can sanity-check architecture before loading.
        // safetensors 0.4 exposes metadata only via `read_metadata`.
        let (_, meta) = SafeTensors::read_metadata(bytes)
            .map_err(|e| Error::Weights(format!("safetensors metadata: {e}")))?;
        let metadata_map = meta.metadata().clone().unwrap_or_default();
        let model = metadata_map
            .get("model")
            .cloned()
            .unwrap_or_else(|| "unknown".to_string());
        if model != EXPECTED_MODEL {
            return Err(Error::Weights(format!(
                "model mismatch: expected {EXPECTED_MODEL}, got {model}",
            )));
        }

        // Cast to a lower-precision dtype if the env var is set:
        //   RFDETR_MLX_FP16=f16 → IEEE half (best on M1/M2)
        //   RFDETR_MLX_FP16=bf16 → bfloat16 (slower on this hw)
        //   RFDETR_MLX_FP16=1 → f16 (default)
        //   unset → keep f32
        let cast_dtype: Option<mlx_rs::Dtype> = match std::env::var("RFDETR_MLX_FP16").as_deref() {
            Ok("f16" | "1") => Some(mlx_rs::Dtype::Float16),
            Ok("bf16") => Some(mlx_rs::Dtype::Bfloat16),
            _ => None,
        };
        let mut inner = HashMap::with_capacity(st.len());
        for (name, view) in st.iter() {
            let arr = Array::try_from(view)
                .map_err(|e| Error::Weights(format!("convert {name}: {e}")))?;
            let arr = match cast_dtype {
                Some(d) if arr.dtype() == mlx_rs::Dtype::Float32 => arr
                    .as_dtype(d)
                    .map_err(|e| Error::Weights(format!("cast {name}: {e}")))?,
                _ => arr,
            };
            inner.insert(name.to_string(), arr);
        }

        Ok(Self { inner, model })
    }

    /// Look up a tensor by its ONNX name. Returns `Error::Weights` if
    /// the name is missing — most modules treat this as fatal because a
    /// missing weight means the forward graph won't match.
    pub fn get(&self, name: &str) -> Result<&Array> {
        self.inner
            .get(name)
            .ok_or_else(|| Error::Weights(format!("missing tensor {name:?}")))
    }

    /// Returns names of all loaded tensors.
    pub fn names(&self) -> impl Iterator<Item = &str> {
        self.inner.keys().map(|s| s.as_str())
    }

    pub fn len(&self) -> usize {
        self.inner.len()
    }

    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }
}
