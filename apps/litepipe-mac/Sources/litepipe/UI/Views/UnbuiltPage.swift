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
            HStack(alignment: .top, spacing: 40) {
                illustration
                    .frame(width: 340, height: 430)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                copy
                    .frame(maxWidth: 430, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(44)
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
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
