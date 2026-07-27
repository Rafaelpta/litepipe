import SwiftUI

struct OnboardingView: View {
    @StateObject private var model = OnboardingModel()

    var body: some View {
        VStack(spacing: 0) {
            panel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { model.bootstrap() }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            chrome
            content
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
        }
        .frame(width: DS.Dim.panelWidth)
        .background(DS.Colors.panel)
        .clipShape(HangShape())
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .animation(.easeOut(duration: DS.Motion.normal), value: model.phase)
        .animation(.easeOut(duration: DS.Motion.normal), value: model.currentPermission)
    }

    private let stepTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 8)),
        removal: .opacity.combined(with: .offset(y: -8))
    )

    // Progress dashes (permissions phase) + close.
    private var chrome: some View {
        ZStack {
            if model.phase == .permissions {
                HStack(spacing: 6) {
                    ForEach(Array(model.steps.enumerated()), id: \.offset) { idx, p in
                        Capsule()
                            .fill(model.isDone(p) || idx == model.currentIndex ? DS.Colors.fg : DS.Colors.fg.opacity(0.2))
                            .frame(width: idx == model.currentIndex && !model.isDone(p) ? 20 : 6, height: 4)
                            .animation(.easeInOut(duration: DS.Motion.normal), value: model.currentIndex)
                    }
                }
            }
            HStack {
                Spacer()
                Button(action: { model.close() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Colors.faint)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .welcome:
            welcome.transition(stepTransition)
        case .permissions:
            if let cur = model.currentPermission {
                stepView(cur)
                    .id(cur)
                    .transition(stepTransition)
            }
        case .done:
            allSet.transition(stepTransition)
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            wave.frame(width: 30, height: 30).padding(.bottom, 16)
            Text("litepipe lives in your notch.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(DS.Colors.fg)
                .padding(.bottom, 6)
            Text("A local memory of your screen. Everything stays on your Mac. No account, no cloud.")
                .font(.system(size: 12.5))
                .foregroundColor(DS.Colors.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)
                .padding(.bottom, 22)
            pill("Let's start") { model.beginPermissions() }
        }
    }

    // MARK: - Permission step

    private func stepView(_ p: Permission) -> some View {
        let granted = model.granted[p] ?? false
        return VStack(spacing: 0) {
            Text(granted ? "Granted." : p.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(granted ? DS.Colors.live : DS.Colors.fg)
                .padding(.bottom, 6)
            Text(p.why)
                .font(.system(size: 12.5))
                .foregroundColor(DS.Colors.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 320)
                .padding(.bottom, granted ? 0 : 20)

            if !granted {
                pill(p.action) { model.request(p) }
                if p.dragHint {
                    Text("drag litepipe into the list when Settings opens")
                        .font(.system(size: 10.5))
                        .foregroundColor(DS.Colors.faint)
                        .padding(.top, 12)
                }
                if p.needsRestart {
                    // macOS only applies Screen Recording after a relaunch.
                    Button(action: { model.restart() }) {
                        Text("enabled it? restart to apply")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Colors.fg)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
                if p.skippable {
                    Button(action: { model.skip(p) }) {
                        Text("skip for now")
                            .font(.system(size: 11))
                            .foregroundColor(DS.Colors.faint)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
        }
    }

    // MARK: - All set

    private var allSet: some View {
        VStack(spacing: 0) {
            wave.frame(width: 30, height: 30).foregroundColor(DS.Colors.live).padding(.bottom, 16)
            Text("You're all set.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.Colors.live)
                .padding(.bottom, 6)
            Text("I'm recording now and I live in your notch. Click me any time to rewind.")
                .font(.system(size: 12.5))
                .foregroundColor(DS.Colors.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 320)
                .padding(.bottom, 22)
            pill("Start") { model.finishOnboarding() }
        }
    }

    // MARK: - Bits

    private func pill(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(PillButtonStyle())
    }

    // simple wave mark (original, not a third-party asset)
    private var wave: some View {
        WaveShape()
            .stroke(DS.Colors.fg, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }
}

struct WaveShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let midY = r.midY
        p.move(to: CGPoint(x: r.minX, y: midY))
        p.addCurve(to: CGPoint(x: r.midX, y: midY),
                   control1: CGPoint(x: r.width * 0.22, y: r.minY),
                   control2: CGPoint(x: r.width * 0.28, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: midY),
                   control1: CGPoint(x: r.width * 0.72, y: r.minY),
                   control2: CGPoint(x: r.width * 0.78, y: r.maxY))
        return p
    }
}
