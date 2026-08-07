import SwiftUI
import AppKit
import Combine

/// The archive window: the Photos style browser over everything the engine has
/// kept. It lives beside the notch rather than replacing it, so nothing that
/// worked yesterday stops working today.
///
/// The models are built on first sight, not at launch. Opening the archive reads
/// eleven thousand captures out of SQLite and folds them into moments, which
/// costs a couple of seconds; paying that on every launch would tax people who
/// only ever use the notch.
struct ArchiveWindow: View {
    let models: ArchiveModels
    @ObservedObject private var onboarding: OnboardingModel

    init(models: ArchiveModels) {
        self.models = models
        self.onboarding = models.onboarding
    }

    /// The ask is a short list and gets a window the size of the list. The
    /// archive is a wall of screens and wants the room.
    static let askSize = CGSize(width: 660, height: 580)
    static let archiveSize = CGSize(width: 1440, height: 900)

    /// Sizing the scene's own window is not something SwiftUI offers a view, so
    /// this reaches for it and centres it on the screen it is already on.
    static func resize(to size: CGSize) {
        DispatchQueue.main.async {
            guard let window = AppDelegate.archiveWindow() else { return }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            var frame = window.frame
            frame.size = size
            if let visible {
                frame.origin = CGPoint(x: visible.midX - size.width / 2,
                                       y: visible.midY - size.height / 2)
            }
            window.setFrame(frame, display: true, animate: true)
        }
    }

    var body: some View {
        Group {
            if onboarding.phase == .done {
                MainWindow()
                    .environment(models.library)
                    .environment(models.nav)
                    .environment(models.selection)
                    .environment(models.chat)
            } else {
                // Before the grants there is nothing captured to show, so the
                // window opens on the ask instead of an empty grid.
                FirstRunView(model: onboarding)
            }
        }
        .onAppear {
            // Only on the way in. A window that already holds the archive keeps
            // whatever size it was left at.
            if onboarding.phase != .done { Self.resize(to: Self.askSize) }
        }
        .onChange(of: onboarding.phase) { _, phase in
            // The delegate starts the engine on this, the same signal the notch
            // panel used to send when it finished.
            guard phase == .done else { return }
            NotificationCenter.default.post(name: .litepipeOnboardingDone, object: nil)
            Self.resize(to: Self.archiveSize)
            // Only on a true first run, where the archive is empty and reading it
            // costs nothing. On a machine that already has one this reread was
            // twelve thousand captures folded on the main thread, and the window
            // sat frozen through all of it before the grid appeared.
            if models.library.items.isEmpty { models.library.reload() }
        }
    }
}

/// Holds the four models the UI runs on and keeps the capture pill honest: the
/// engine decides whether capture is running, and the pill follows it.
@MainActor
final class ArchiveModels {
    /// One instance, deliberately. `@State`'s initial expression is evaluated
    /// every time the App struct is built, so writing `ArchiveModels(engine:)`
    /// there constructed a throwaway on each pass: each one read twelve thousand
    /// captures out of SQLite and attached its own subscription to the engine.
    static let shared = ArchiveModels(engine: .shared)

    let library: ContextLibrary
    let nav = NavigationState()
    let selection = SelectionModel()
    let chat = ChatModel()
    /// Owns the permission flow. It reads the live grants at startup and decides
    /// whether this window opens on the archive or on the ask.
    let onboarding = OnboardingModel()

    private let engine: EngineController
    private var statusSink: AnyCancellable?
    /// A timed pause has no equivalent in the engine, which only knows running
    /// and stopped. The timer is what turns "pause for fifteen minutes" into a
    /// stop now and a start later.
    private var resumeWork: DispatchWorkItem?

    /// When capture last changed through this window. Pausing kills the engine
    /// process, so a stray toggle is not a cosmetic bug: it stops recording. The
    /// log shows these arriving in pairs seconds apart, which no person clicking
    /// a menu produces, so anything that fast is refused and named in the log
    /// until the source is found.
    private var lastToggle = Date.distantPast

    private func accept(_ what: String) -> Bool {
        let gap = Date().timeIntervalSince(lastToggle)
        guard gap > 1.0 else {
            litepipeLog("capture \(what) refused: \(String(format: "%.2f", gap))s after the last one")
            return false
        }
        lastToggle = Date()
        litepipeLog("capture \(what) from the window")
        return true
    }

    init(engine: EngineController) {
        self.engine = engine
        library = ContextLibrary()
        onboarding.bootstrap()

        nav.onPause = { [weak self] seconds in
            guard let self, self.accept("pause") else { return }
            self.resumeWork?.cancel()
            self.engine.stop(markPaused: true, source: "archive window")
            self.engine.cue(paused: true)
            guard let seconds else { return }
            let work = DispatchWorkItem { [weak self] in self?.engine.start() }
            self.resumeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        nav.onResume = { [weak self] in
            guard let self, self.accept("resume") else { return }
            self.resumeWork?.cancel()
            self.resumeWork = nil
            self.engine.start()
            self.engine.cue(paused: false)
        }

        // The chord, the notch and a crashed engine all change capture without
        // going through this window. Mirror the engine so the pill never lies.
        nav.reflectEngine(paused: engine.status != .recording && engine.status != .starting)
        statusSink = engine.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                let running = status == .recording || status == .starting
                self?.nav.reflectEngine(paused: !running)
                if running { self?.resumeWork?.cancel(); self?.resumeWork = nil }
            }
    }
}
