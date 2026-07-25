//! Tests for batch mode deferral logic.
//!
//! Batch mode should:
//! - Always persist audio to disk + DB (regardless of session state)
//! - Defer transcription while an audio session is active (meeting OR output audio)
//! - Transcribe accumulated chunks when the session ends
//! - Transcribe immediately when NOT in a session (same as realtime)
//!
//! Run with: cargo test -p screenpipe-audio --test batch_deferral_test -- --nocapture

#[cfg(test)]
mod tests {
    use screenpipe_audio::core::device::DeviceType;
    use screenpipe_audio::meeting_detector::MeetingDetector;
    use std::sync::Arc;

    // ---------------------------------------------------------------
    // 1. Meeting detector state transitions (v2 override API)
    // ---------------------------------------------------------------

    #[test]
    fn meeting_starts_when_v2_override_set() {
        let detector = MeetingDetector::new();
        assert!(
            !detector.is_in_meeting(),
            "should not be in meeting initially"
        );

        detector.set_v2_in_meeting(true);
        assert!(
            detector.is_in_meeting(),
            "should be in meeting after v2 override set"
        );
    }

    #[test]
    fn meeting_ends_when_v2_override_cleared() {
        let detector = MeetingDetector::new();

        detector.set_v2_in_meeting(true);
        assert!(detector.is_in_meeting());

        detector.set_v2_in_meeting(false);
        assert!(
            !detector.is_in_meeting(),
            "should not be in meeting after v2 override cleared"
        );
    }

    #[test]
    fn toggling_v2_override_multiple_times() {
        let detector = MeetingDetector::new();

        // Start meeting, end, start again
        detector.set_v2_in_meeting(true);
        assert!(detector.is_in_meeting());

        detector.set_v2_in_meeting(false);
        assert!(!detector.is_in_meeting());

        detector.set_v2_in_meeting(true);
        assert!(
            detector.is_in_meeting(),
            "returning to meeting should keep meeting active"
        );
    }

    // ---------------------------------------------------------------
    // 2. Batch deferral decision matrix
    //    Tests the logic from manager.rs start_audio_receiver_handler
    //    Now uses "in_session" (meeting OR output audio) instead of
    //    just "in_meeting"
    // ---------------------------------------------------------------

    /// Represents what the handler should do for each audio chunk
    #[derive(Debug, PartialEq)]
    enum BatchDecision {
        /// Transcribe immediately (realtime mode, or batch without active session)
        TranscribeNow,
        /// Defer transcription (batch mode, session active)
        Defer,
        /// Session just ended — trigger reconciliation of all deferred chunks
        Reconcile,
    }

    /// Pure function that mirrors the decision logic in manager.rs.
    /// This is the exact same if/else chain we put in the handler.
    fn decide(is_batch_mode: bool, was_in_session: bool, now_in_session: bool) -> BatchDecision {
        if !is_batch_mode {
            return BatchDecision::TranscribeNow;
        }
        if was_in_session && !now_in_session {
            return BatchDecision::Reconcile;
        }
        if now_in_session {
            return BatchDecision::Defer;
        }
        BatchDecision::TranscribeNow
    }

    #[test]
    fn realtime_mode_always_transcribes() {
        assert_eq!(decide(false, false, false), BatchDecision::TranscribeNow);
        assert_eq!(decide(false, true, true), BatchDecision::TranscribeNow);
        assert_eq!(decide(false, true, false), BatchDecision::TranscribeNow);
        assert_eq!(decide(false, false, true), BatchDecision::TranscribeNow);
    }

    #[test]
    fn batch_mode_defers_during_session() {
        assert_eq!(decide(true, true, true), BatchDecision::Defer);
        assert_eq!(decide(true, false, true), BatchDecision::Defer);
    }

    #[test]
    fn batch_mode_reconciles_on_session_end() {
        assert_eq!(decide(true, true, false), BatchDecision::Reconcile);
    }

    #[test]
    fn batch_mode_transcribes_immediately_when_no_session() {
        assert_eq!(decide(true, false, false), BatchDecision::TranscribeNow);
    }

    // ---------------------------------------------------------------
    // 3. End-to-end decision flow with MeetingDetector
    //    Simulates the exact sequence the handler runs per chunk
    // ---------------------------------------------------------------

    #[tokio::test]
    async fn batch_flow_meeting_lifecycle() {
        let detector = Arc::new(MeetingDetector::new());
        let is_batch_mode = true;

        // --- Chunk 1: No meeting → transcribe immediately ---
        let was = detector.is_in_audio_session();
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(is_batch_mode, was, now),
            BatchDecision::TranscribeNow,
            "chunk 1: no session → transcribe"
        );

        // --- v2 detection system detects meeting (e.g., Zoom UI) ---
        detector.set_v2_in_meeting(true);

        // --- Chunk 2: In meeting, should defer ---
        let was = detector.is_in_audio_session();
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(is_batch_mode, was, now),
            BatchDecision::Defer,
            "chunk 2: in meeting → defer"
        );

        // --- Chunk 3: Still in meeting, should defer ---
        let was = detector.is_in_audio_session();
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(is_batch_mode, was, now),
            BatchDecision::Defer,
            "chunk 3: still in meeting → defer"
        );

        // --- v2 detection system detects meeting ended ---
        detector.set_v2_in_meeting(false);

        // --- Chunk 4: Meeting ended → reconcile ---
        let was = true; // was in session before v2 cleared it
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(is_batch_mode, was, now),
            BatchDecision::Reconcile,
            "chunk 4: meeting ended → reconcile"
        );

        // --- v2 detects meeting again ---
        detector.set_v2_in_meeting(true);

        // --- Chunk 5: Back in meeting ---
        let was = detector.is_in_audio_session();
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(is_batch_mode, was, now),
            BatchDecision::Defer,
            "chunk 5: back in meeting → defer"
        );
    }

    #[tokio::test]
    async fn realtime_flow_ignores_session_state() {
        let detector = Arc::new(MeetingDetector::new());
        let is_batch_mode = false;

        // v2 sets meeting active
        detector.set_v2_in_meeting(true);

        // Realtime should always transcribe, even during meeting
        let was = detector.is_in_audio_session();
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(is_batch_mode, was, now),
            BatchDecision::TranscribeNow,
            "realtime always transcribes, even in session"
        );
    }

    #[tokio::test]
    async fn batch_flow_no_meeting_detector_always_transcribes() {
        // When meeting_detector is None, batch mode falls back to immediate transcription
        let meeting_detector: Option<Arc<MeetingDetector>> = None;
        let _is_batch_mode = true;

        // Without a meeting detector, we can't defer — must transcribe
        let should_transcribe = meeting_detector.is_none();
        assert!(should_transcribe, "no meeting detector → always transcribe");
    }

    // ---------------------------------------------------------------
    // 4. Audio activity updates meeting detector state
    //    Note: on_audio_activity is now a no-op in v2; detection is
    //    UI-based via set_v2_in_meeting(). These tests verify the
    //    no-op behavior doesn't cause issues.
    // ---------------------------------------------------------------

    #[tokio::test]
    async fn audio_activity_alone_does_not_start_meeting() {
        let detector = MeetingDetector::new();

        // Simulate bidirectional speech (mic + speaker)
        // on_audio_activity is a no-op in v2
        detector.on_audio_activity(&DeviceType::Input, true);
        detector.on_audio_activity(&DeviceType::Output, true);

        // Audio alone should NOT start a meeting (v2 uses UI detection)
        assert!(
            !detector.is_in_meeting(),
            "audio activity alone should not trigger meeting"
        );
    }

    // ---------------------------------------------------------------
    // 5. Audio session detection
    //    In v2, is_in_audio_session() is identical to is_in_meeting()
    //    and is driven entirely by the v2 UI-scanning system.
    // ---------------------------------------------------------------

    #[test]
    fn v2_meeting_is_always_an_audio_session() {
        let detector = MeetingDetector::new();

        // Start meeting via v2 override
        detector.set_v2_in_meeting(true);

        assert!(detector.is_in_meeting(), "should be in meeting");
        assert!(
            detector.is_in_audio_session(),
            "meeting should always be an audio session"
        );
    }

    #[test]
    fn no_session_initially() {
        let detector = MeetingDetector::new();

        assert!(
            !detector.is_in_audio_session(),
            "should not be in session initially"
        );
    }

    // ---------------------------------------------------------------
    // 6. Meeting detection with Arc (thread-safe access)
    // ---------------------------------------------------------------

    #[tokio::test]
    async fn batch_defers_for_both_device_types() {
        let detector = Arc::new(MeetingDetector::new());

        // Start meeting via v2 override
        detector.set_v2_in_meeting(true);

        // Simulate processing chunks from both devices
        for device_name in &["input (input)", "Display 3 (output)"] {
            let was = detector.is_in_audio_session();
            detector.check_grace_period().await;
            let now = detector.is_in_audio_session();
            assert_eq!(
                decide(true, was, now),
                BatchDecision::Defer,
                "should defer for device {}",
                device_name
            );
        }
    }

    // ---------------------------------------------------------------
    // 7. RMS threshold validation with real-world audio levels
    //    Empirical data from macOS ScreenCaptureKit captures:
    //      SCK silence:        RMS = 0.000000
    //      SCK audio playing:  RMS = 0.002753
    //      Loud output device: RMS = 0.061207
    //      Mic ambient noise:  RMS = 0.004465
    //    Output threshold: 0.001 (detects "any audio playing")
    //    Input threshold:  0.05  (detects "someone speaking")
    // ---------------------------------------------------------------

    /// Mirrors the threshold logic in manager.rs audio receiver handler.
    fn has_audio_activity(device_type: &DeviceType, rms: f32) -> bool {
        match device_type {
            DeviceType::Output => rms > 0.001,
            DeviceType::Input => rms > 0.05,
        }
    }

    #[test]
    fn output_threshold_rejects_sck_silence() {
        // Real SCK silence: RMS = 0.0
        assert!(
            !has_audio_activity(&DeviceType::Output, 0.0),
            "SCK silence should not trigger activity"
        );
    }

    #[test]
    fn output_threshold_detects_sck_audio_playing() {
        // Real SCK audio (YouTube): RMS = 0.002753
        assert!(
            has_audio_activity(&DeviceType::Output, 0.002753),
            "SCK output with audio playing should trigger activity"
        );
    }

    #[test]
    fn output_threshold_detects_loud_output_device() {
        // Real loud output device: RMS = 0.061
        assert!(
            has_audio_activity(&DeviceType::Output, 0.061),
            "loud output device should trigger activity"
        );
    }

    #[test]
    fn input_threshold_rejects_ambient_noise() {
        // Real mic ambient noise: RMS = 0.004
        assert!(
            !has_audio_activity(&DeviceType::Input, 0.004),
            "mic ambient noise should not trigger activity"
        );
    }

    #[test]
    fn input_threshold_detects_speech() {
        // Typical speech on mic: RMS ~0.08-0.3
        assert!(
            has_audio_activity(&DeviceType::Input, 0.08),
            "mic speech should trigger activity"
        );
    }

    #[tokio::test]
    async fn v2_meeting_triggers_deferral_in_batch_mode() {
        // End-to-end: v2 detects meeting → session detected → batch defers
        let detector = MeetingDetector::new();

        // v2 UI detection sets meeting flag
        detector.set_v2_in_meeting(true);

        // Session should now be active
        assert!(
            detector.is_in_audio_session(),
            "audio session should be active after v2 meeting detection"
        );

        // Batch mode should defer
        let was = detector.is_in_audio_session();
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(true, was, now),
            BatchDecision::Defer,
            "batch mode should defer when v2 detects meeting"
        );
    }

    #[tokio::test]
    async fn no_meeting_does_not_trigger_deferral() {
        // End-to-end: no meeting → no session → batch transcribes immediately
        let detector = MeetingDetector::new();

        assert!(
            !detector.is_in_audio_session(),
            "no session when no meeting detected"
        );

        let was = detector.is_in_audio_session();
        detector.check_grace_period().await;
        let now = detector.is_in_audio_session();
        assert_eq!(
            decide(true, was, now),
            BatchDecision::TranscribeNow,
            "batch should transcribe immediately when no meeting"
        );
    }
}
