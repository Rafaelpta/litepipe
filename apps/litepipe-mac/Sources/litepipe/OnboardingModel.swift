import Foundation
import Combine

// Real flow with resume: screen/accessibility grants on macOS often need the app
// to relaunch to take effect, so onboarding must survive quit+reopen. On launch
// we read the live permission state and jump straight to the first thing still
// missing — never restarting from welcome once the user has begun. Onboarding is
// "done" only when everything we need is actually granted (or skipped).
final class OnboardingModel: ObservableObject {
    enum Phase: Equatable { case welcome, permissions, done }

    @Published var phase: Phase = .welcome
    @Published var granted: [Permission: Bool] = [:]
    @Published var skipped: Set<Permission> = []
    @Published var celebrating: Permission?

    private var timer: Timer?
    private var initial: [Permission: Bool] = [:]

    private let defaults = UserDefaults.standard
    private let kStarted = "onboarding.started.v1"
    private let kComplete = "onboarding.complete.v1"
    private let kSkipped = "onboarding.skipped.v1"

    let steps: [Permission] = Permission.allCases

    // MARK: - Launch

    func bootstrap() {
        // load persisted skips + live grant state
        if let raw = defaults.array(forKey: kSkipped) as? [String] {
            skipped = Set(raw.compactMap(Permission.init(rawValue:)))
        }
        for p in steps {
            let g = Permissions.isGranted(p)
            granted[p] = g
            initial[p] = g
        }

        if defaults.bool(forKey: kComplete) {
            phase = .done
            return
        }

        let anyGranted = steps.contains { (granted[$0] ?? false) }
        if defaults.bool(forKey: kStarted) || anyGranted || !skipped.isEmpty {
            // returning mid-flow (e.g. after a relaunch): resume in permissions,
            // landing on the first still-missing one.
            defaults.set(true, forKey: kStarted)
            phase = .permissions
            startPolling()
            maybeFinish()
        } else {
            phase = .welcome
        }
    }

    // MARK: - Derived

    var currentPermission: Permission? {
        guard phase == .permissions else { return nil }
        if let c = celebrating { return c }
        return steps.first { !isDone($0) }
    }

    var currentIndex: Int { currentPermission.flatMap { steps.firstIndex(of: $0) } ?? steps.count }

    func isDone(_ p: Permission) -> Bool { (granted[p] ?? false) || skipped.contains(p) }

    // MARK: - Actions

    func beginPermissions() {
        defaults.set(true, forKey: kStarted)
        phase = .permissions
        startPolling()
    }

    func request(_ p: Permission) {
        Permissions.request(p)
        if p.dragHint {
            NotificationCenter.default.post(name: .litepipeShowDragHelper, object: nil)
        }
    }

    func skip(_ p: Permission) {
        hideHelper()
        skipped.insert(p)
        defaults.set(Array(skipped.map(\.rawValue)), forKey: kSkipped)
        maybeFinish()
    }

    // Screen Recording only applies after a relaunch; persist progress and restart.
    func restart() {
        defaults.set(true, forKey: kStarted)
        hideHelper()
        Permissions.relaunchApp()
    }

    func close() { NotificationCenter.default.post(name: .litepipeClose, object: nil) }

    // Hand off from onboarding to the persistent notch companion.
    func finishOnboarding() { NotificationCenter.default.post(name: .litepipeOnboardingDone, object: nil) }

    // MARK: - Polling

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard phase == .permissions else { return }
        for p in steps {
            let g = Permissions.isGranted(p)
            let was = granted[p] ?? false
            granted[p] = g
            if g && !was && !(initial[p] ?? false) {
                hideHelper()
                celebrating = p
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                    guard let self else { return }
                    if self.celebrating == p { self.celebrating = nil }
                    self.maybeFinish()
                }
            }
        }
    }

    private func maybeFinish() {
        if phase == .permissions && steps.allSatisfy({ isDone($0) }) {
            hideHelper()
            timer?.invalidate()
            defaults.set(true, forKey: kComplete)
            phase = .done
        }
    }

    private func hideHelper() {
        NotificationCenter.default.post(name: .litepipeHideDragHelper, object: nil)
    }
}
