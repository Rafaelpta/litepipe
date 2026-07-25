/**
 * Redact PII from text before sharing logs.
 *
 * Phone regex must require formatting (country code, parentheses, or separators)
 * to avoid false-positives on numeric values like accessibility bounding-box
 * coordinates, frame IDs, monitor IDs, and hash values.
 */
export function redactPii(text: string): string {
  return text
    // emails
    .replace(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, "[EMAIL]")
    // phone numbers — require at least one formatting marker:
    //   +country code, parenthesized area code, or separators between groups
    // This mirrors the stricter Rust regex in pii_removal.rs (#2340)
    .replace(
      /\+\d{1,3}[-.\s]?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}|\(?[2-9]\d{2}\)[-.\s]?\d{3}[-.\s]?\d{4}|[2-9]\d{2}[-.\s]\d{3}[-.\s]\d{4}/g,
      "[PHONE]"
    )
    // SSN
    .replace(/\b\d{3}-\d{2}-\d{4}\b/g, "[SSN]")
    // credit card numbers
    .replace(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/g, "[CARD]")
    // API keys / tokens (long hex or base64 strings)
    .replace(
      /\b(sk|pk|key|token|secret|password|api[_-]?key)[_-]?\s*[:=]\s*\S{8,}/gi,
      "$1=[REDACTED]"
    )
    // bearer tokens
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]{20,}/g, "Bearer [REDACTED]")
    // IP addresses (keep localhost)
    .replace(
      /\b(?!127\.0\.0\.1\b)(?!0\.0\.0\.0\b)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g,
      "[IP]"
    )
    // home directory paths (redact username)
    .replace(/\/Users\/[^/\s]+/g, "/Users/[USER]")
    .replace(/C:\\Users\\[^\\\s]+/g, "C:\\Users\\[USER]")
    .replace(/\/home\/[^/\s]+/g, "/home/[USER]");
}
