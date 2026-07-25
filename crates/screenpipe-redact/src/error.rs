use thiserror::Error;

#[derive(Error, Debug)]
pub enum RedactError {
    /// Network / HTTP error talking to a remote redactor.
    #[error("redactor http request failed: {0}")]
    Http(#[from] reqwest::Error),

    /// Remote redactor returned a non-success status.
    #[error("redactor returned status {status}: {body}")]
    HttpStatus {
        status: reqwest::StatusCode,
        body: String,
    },

    /// I/O or runtime failure inside a local redactor (model load,
    /// tokenization, etc.).
    #[error("redactor runtime error: {0}")]
    Runtime(String),

    /// The redactor was disabled or unavailable; the caller should
    /// either fall back to another adapter or surface a clear error.
    #[error("redactor unavailable: {0}")]
    Unavailable(String),

    /// Database error while reading or writing redaction rows.
    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    /// Anything we didn't categorize. Always a bug — never the
    /// caller's input.
    #[error("unexpected error: {0}")]
    Unexpected(String),
}
