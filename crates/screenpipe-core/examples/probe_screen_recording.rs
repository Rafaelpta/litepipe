//! Smoke-test the screen recording permission probe.
//!
//! Prints what each path reports so we can verify locally that the
//! definitive `CGWindowListCreateImage` probe agrees with reality
//! even when `CGPreflightScreenCaptureAccess` does not.

use screenpipe_core::permissions;

fn main() {
    let status = permissions::check_screen_recording();
    println!("check_screen_recording() = {:?}", status);
    println!("check_microphone() = {:?}", permissions::check_microphone());
    println!(
        "check_accessibility() = {:?}",
        permissions::check_accessibility()
    );
}
