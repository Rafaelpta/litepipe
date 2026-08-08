import SwiftUI
import AppKit

/// A room with nothing in it yet, said out loud.
///
/// Two sections of the sidebar lead somewhere that has not been written. The
/// alternative to a page like this is a grid filtered by some proxy — captures
/// with a lot of text standing in for memory — which looks like a feature and is
/// not one. This says what would live here, why it does not, and where to start
/// if you want to build it.
struct UnbuiltPage: View {
    let eyebrow: String
    let title: String
    let blurb: String
    let points: [(String, String)]
    let startingPoint: String
    let illustration: AnyView

    private static let repo = "https://github.com/Rafaelpta/litepipe"

    var body: some View {
        ScrollView {
            // Side by side while there is room for both to be readable; stacked
            // once there is not. A text column squeezed to 200pt truncates its
            // own buttons, which is worse than a taller page.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 40) {
                    art(width: 320, height: 400)
                    copy.frame(width: 440, alignment: .leading)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 28) {
                    art(width: 300, height: 300)
                    copy.frame(maxWidth: 440, alignment: .leading)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func art(width: CGFloat, height: CGFloat) -> some View {
        illustration
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                    .fixedSize()
                Text("NOT BUILT YET")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(blurb)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(points, id: \.0) { point($0.0, $0.1) }
            }
            .padding(.top, 2)

            Divider().padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 7) {
                Text("Want to build it?")
                    .font(.system(size: 13, weight: .semibold))
                Text("""
                     litepipe is open source, and this is a good place to start: the \
                     shape is decided, the work is not. Open an issue describing what \
                     you intend before writing much of it, so two people do not build \
                     the same half.
                     """)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(startingPoint)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.top, 1)

                HStack(spacing: 10) {
                    Button("Open the repository") {
                        if let url = URL(string: Self.repo) { NSWorkspace.shared.open(url) }
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)

                    Button("Read the open issues") {
                        if let url = URL(string: Self.repo + "/issues") { NSWorkspace.shared.open(url) }
                    }
                    .controlSize(.large)
                }
                // Buttons that shorten their own labels to "Open the r…" are
                // worse than a wider column.
                .fixedSize()
                .padding(.top, 6)
            }
        }
    }

    private func point(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - The two rooms

extension UnbuiltPage {
    static var agentMemory: UnbuiltPage {
        UnbuiltPage(
            eyebrow: "AGENT MEMORY",
            title: "What an agent should already know about you",
            blurb: """
                   The archive holds what was on your screen. This would hold what \
                   follows from it: the way you like things done, the decisions you \
                   are tired of repeating, the facts an agent should have before it \
                   starts rather than after it guesses wrong.
                   """,
            points: [
                ("Standing facts", "Drawn from your own sessions, not typed into a settings pane."),
                ("Corrections that stick", "Say it once. The next agent starts from there."),
                ("Files your tools already read", "CLAUDE.md and AGENTS.md are the format; this would keep them current.")
            ],
            startingPoint: "start at Sources/litepipe/UI/Models/ContextLibrary.swift",
            illustration: AnyView(MemoryIllustration())
        )
    }

    static var workflows: UnbuiltPage {
        UnbuiltPage(
            eyebrow: "WORKFLOWS",
            title: "The things you do over and over, found rather than declared",
            blurb: """
                   You move between the same few windows in the same order most of \
                   the day. That shape is already in the archive: which app followed \
                   which, how often, at what hour. This is where those routines would \
                   be named and collected — not workflows you set up, workflows you \
                   were seen doing.
                   """,
            points: [
                ("Found, not configured", "Nothing to define up front. The archive is the evidence, and it is already there."),
                ("One card per routine", "The screens it passes through, how many times, how long it takes you."),
                ("Where automation would start", "You cannot hand off a routine you have never named.")
            ],
            startingPoint: "start at Sources/litepipe/UI/Support/ContextDB.swift",
            illustration: AnyView(WorkflowIllustration())
        )
    }

    static var sharedContexts: UnbuiltPage {
        UnbuiltPage(
            eyebrow: "SHARED CONTEXTS",
            title: "Handing one slice of the archive to someone else",
            blurb: """
                   Everything litepipe keeps stays on this Mac. This is where the \
                   deliberate exception would live: a named slice — a project, a \
                   week, a single app — handed to a person or a tool, and nothing \
                   around it.
                   """,
            points: [
                ("A slice, never the whole thing", "Scoped by time, by app, by project. The archive itself never travels."),
                ("Read it before it goes", "A share is assembled and shown to you first. No surprises after the fact."),
                ("Take it back", "Withdrawing a share is as ordinary as making one, and the log says who opened it.")
            ],
            startingPoint: "start at crates/screenpipe-engine/src/routes/",
            illustration: AnyView(ShareIllustration())
        )
    }

    static var firewall: UnbuiltPage {
        UnbuiltPage(
            eyebrow: "FIREWALL",
            title: "The line nothing crosses without your say",
            blurb: """
                   Capturing is the easy half. The boundary is the hard one: what is \
                   never recorded, what is stripped before it is written down, and \
                   what any tool asking for your context is actually allowed to see.
                   """,
            points: [
                ("Never recorded", "Apps and sites that the engine skips entirely, not hides afterwards."),
                ("Stripped before storage", "Passwords and keys removed on the way in, not filtered on the way out."),
                ("A log worth reading", "Every request for your context, what it got, and what it was refused.")
            ],
            startingPoint: "start at crates/screenpipe-engine/src/routes/",
            illustration: AnyView(FirewallIllustration())
        )
    }
}

// MARK: - Drawn, not shipped

/// Flat two-tone shapes, no gradients and no imported art. Cool tones so the
/// unbuilt rooms do not read as the same page twice.
private struct MemoryIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = Color(red: 0.10, green: 0.11, blue: 0.13)
            let paper = Color(red: 0.55, green: 0.68, blue: 0.86)
            let deep = Color(red: 0.33, green: 0.47, blue: 0.71)

            ZStack {
                paper

                // Many captures narrowing into a few kept facts: the point of a
                // memory is that it is smaller than what it came from.
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ink, lineWidth: 2.5)
                        .frame(width: w * 0.22, height: w * 0.16)
                        .offset(x: -w * 0.26 + Double(i % 2) * w * 0.20,
                                y: -h * 0.30 + Double(i) * h * 0.075)
                }

                // The one thing that survived, filled in and larger.
                RoundedRectangle(cornerRadius: 10)
                    .fill(deep)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ink, lineWidth: 3))
                    .overlay {
                        VStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule().fill(ink).frame(height: 3)
                            }
                        }
                        .padding(.horizontal, 22)
                    }
                    .frame(width: w * 0.52, height: h * 0.22)
                    .offset(y: h * 0.26)
            }
        }
    }
}

/// The same three windows, in the same order, again: a loop drawn as a loop.
private struct WorkflowIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = Color(red: 0.10, green: 0.11, blue: 0.13)
            let paper = Color(red: 0.80, green: 0.66, blue: 0.82)
            let deep = Color(red: 0.55, green: 0.40, blue: 0.62)
            let r = min(w, h) * 0.30

            ZStack {
                paper

                // The circuit the three windows sit on.
                Circle()
                    .stroke(ink, style: StrokeStyle(lineWidth: 3, dash: [9, 7]))
                    .frame(width: r * 2, height: r * 2)

                // Three stops, evenly spaced, because a routine is a small set
                // repeated rather than a long list done once.
                ForEach(0..<3, id: \.self) { i in
                    let angle = Double(i) / 3 * 2 * .pi - .pi / 2
                    RoundedRectangle(cornerRadius: 6)
                        .fill(i == 0 ? deep : paper)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ink, lineWidth: 3))
                        .frame(width: w * 0.26, height: w * 0.19)
                        .offset(x: cos(angle) * r, y: sin(angle) * r)
                }
            }
        }
    }
}

/// One thing crossing a boundary while the rest stays put: the whole idea of a
/// share, and the opposite of the wall next door, which lets nothing through.
private struct ShareIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = Color(red: 0.10, green: 0.11, blue: 0.13)
            let paper = Color(red: 0.85, green: 0.72, blue: 0.55)
            let deep = Color(red: 0.72, green: 0.53, blue: 0.33)

            ZStack {
                paper

                // The archive, held together on the near side.
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(deep)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ink, lineWidth: 2.5))
                        .frame(width: w * 0.30, height: w * 0.21)
                        .rotationEffect(.degrees(-6 + Double(i) * 4))
                        .offset(x: -w * 0.18 + Double(i) * w * 0.03,
                                y: h * 0.20 - Double(i) * h * 0.045)
                }

                // The one that was chosen, outlined and on its own, past the edge.
                RoundedRectangle(cornerRadius: 8)
                    .fill(paper)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ink, lineWidth: 3))
                    .frame(width: w * 0.32, height: w * 0.23)
                    .rotationEffect(.degrees(10))
                    .offset(x: w * 0.22, y: -h * 0.24)

                // The hand it went to, reduced to the gesture: an open bracket.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.80, y: h * 0.14))
                    p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.14))
                    p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.40))
                    p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.40))
                }
                .stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct FirewallIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = Color(red: 0.10, green: 0.11, blue: 0.13)
            let paper = Color(red: 0.62, green: 0.75, blue: 0.66)
            let deep = Color(red: 0.31, green: 0.52, blue: 0.42)

            ZStack {
                paper

                // The wall: one unbroken line across the whole panel, because a
                // boundary with a gap in it is not a boundary.
                Rectangle()
                    .fill(ink)
                    .frame(width: w, height: 4)

                // Held on the near side.
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(deep)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ink, lineWidth: 2.5))
                        .frame(width: w * 0.26, height: w * 0.18)
                        .rotationEffect(.degrees(Double(i) * 6 - 6))
                        .offset(x: -w * 0.16 + Double(i) * w * 0.14,
                                y: h * 0.20 + Double(i % 2) * h * 0.10)
                }

                // Let through, on the far side, alone.
                RoundedRectangle(cornerRadius: 6)
                    .fill(paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(ink, lineWidth: 2.5))
                    .frame(width: w * 0.26, height: w * 0.18)
                    .rotationEffect(.degrees(-8))
                    .offset(x: w * 0.14, y: -h * 0.26)
            }
        }
    }
}
