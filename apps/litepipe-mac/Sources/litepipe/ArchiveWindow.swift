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

    var body: some View {
        MainWindow()
            .environment(models.library)
            .environment(models.nav)
            .environment(models.selection)
            .environment(models.chat)
    }
}

/// Holds the four models the UI runs on and keeps the capture pill honest: the
/// engine decides whether capture is running, and the pill follows it.
@MainActor
final class ArchiveModels {
    let library: ContextLibrary
    let nav = NavigationState()
    let selection = SelectionModel()
    let chat = ChatModel()

    private let engine: EngineController
    private var statusSink: AnyCancellable?
    /// A timed pause has no equivalent in the engine, which only knows running
    /// and stopped. The timer is what turns "pause for fifteen minutes" into a
    /// stop now and a start later.
    private var resumeWork: DispatchWorkItem?

    init(engine: EngineController) {
        self.engine = engine
        library = ContextLibrary()

        nav.onPause = { [weak self] seconds in
            guard let self else { return }
            self.resumeWork?.cancel()
            self.engine.stop(markPaused: true, source: "archive window")
            guard let seconds else { return }
            let work = DispatchWorkItem { [weak self] in self?.engine.start() }
            self.resumeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        nav.onResume = { [weak self] in
            self?.resumeWork?.cancel()
            self?.resumeWork = nil
            self?.engine.start()
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
