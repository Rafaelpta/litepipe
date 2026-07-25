//! End-to-end integration test for the opf-rs text adapter.
//!
//! Gated on:
//!   - the `opf-text` cargo feature
//!   - the `OPF_MODEL_DIR` env var (the path to a real OPF v3
//!     checkpoint dir containing `config.json` + `model.safetensors`)
//!
//! When either is missing the test is a no-op so CI / contributors
//! without the 2.8 GB checkpoint don't hit a failure. With both set,
//! it loads the model on whatever device is available and runs three
//! representative inputs covering the canonical PII categories.

#![cfg(feature = "opf-text")]

use std::path::PathBuf;

use screenpipe_redact::adapters::opf::{OpfAdapter, OpfConfig};
use screenpipe_redact::{Redactor, SpanLabel};

fn require_model_dir() -> Option<PathBuf> {
    match std::env::var("OPF_MODEL_DIR") {
        Ok(p) => Some(PathBuf::from(p)),
        Err(_) => {
            eprintln!("skipping: set OPF_MODEL_DIR=/path/to/model");
            None
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn redacts_person_email_phone() {
    let Some(model_dir) = require_model_dir() else {
        return;
    };
    let cfg = OpfConfig {
        model_dir,
        max_seq_len: 256,
    };
    let adapter = OpfAdapter::load(cfg).expect("load adapter");

    let cases: &[(&str, &[SpanLabel])] = &[
        (
            "Welcome | Marcus Chen — Confluence",
            &[SpanLabel::Person],
        ),
        (
            "Outlook — Inbox — marcus.chen@helios-ai.io",
            &[SpanLabel::Email],
        ),
        (
            "Hi team, please reach out to Marcus Chen at marcus.chen@helios-ai.io or call +1 (415) 555-0142.",
            &[SpanLabel::Person, SpanLabel::Email, SpanLabel::Phone],
        ),
    ];

    for (text, expected) in cases {
        let out = adapter.redact(text).await.expect("redact ok");
        let got: Vec<SpanLabel> = out.spans.iter().map(|s| s.label).collect();
        eprintln!("input:    {}", text);
        eprintln!("redacted: {}", out.redacted);
        for s in &out.spans {
            eprintln!("  {:?}: {:?}", s.label, s.text);
        }
        for want in *expected {
            assert!(
                got.contains(want),
                "expected to detect {want:?} in {text:?}, got {got:?}"
            );
        }
        // Every span's `text` must equal the corresponding input slice.
        for s in &out.spans {
            let slice = &out.input[s.start..s.end];
            assert_eq!(s.text, slice, "span text must match the input byte range");
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn batch_preserves_order() {
    let Some(model_dir) = require_model_dir() else {
        return;
    };
    let cfg = OpfConfig {
        model_dir,
        max_seq_len: 256,
    };
    let adapter = OpfAdapter::load(cfg).expect("load adapter");

    let texts = vec![
        "alice@example.com".to_string(),
        "Cursor — Welcome".to_string(),
        "Outlook — Inbox — marcus.chen@helios-ai.io".to_string(),
    ];
    let out = adapter.redact_batch(&texts).await.expect("batch redact ok");
    assert_eq!(out.len(), texts.len());
    for (i, r) in out.iter().enumerate() {
        assert_eq!(r.input, texts[i], "batch order must be preserved");
    }
}
