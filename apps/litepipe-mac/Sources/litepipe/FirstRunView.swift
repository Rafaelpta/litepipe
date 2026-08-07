import SwiftUI

/// What the window shows before there is an archive to show.
///
/// The notch asked for one permission at a time because a panel hanging off the
/// menu bar has room for one thing. A window does not, so all four are on screen
/// at once with their state visible: what is granted, what is missing, what was
/// skipped. Being able to see the whole ask is the point of moving it here.
///
/// The logic underneath is unchanged. `OnboardingModel` still polls once a
/// second, still resumes mid flow after the relaunch that Screen Recording
/// needs, and still decides when this is over.
struct FirstRunView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                VStack(spacing: 0) {
                    ForEach(Array(model.steps.enumerated()), id: \.element) { i, p in
                        if i > 0 { Divider() }
                        row(p)
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                footer
            }
            .padding(34)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            LitepipeMark()
                .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 26, height: 12)
            Text("litepipe needs a few permissions")
                .font(.system(size: 20, weight: .semibold))
            // Two sentences, two lines. Left to wrap, the second one broke after
            // "stays on" and the promise landed on a widow.
            Text("It captures what you were doing so you can find it again.\nEverything it keeps stays on this Mac.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func row(_ p: Permission) -> some View {
        let granted = model.granted[p] ?? false
        let skipped = model.skipped.contains(p)
        HStack(alignment: .top, spacing: 12) {
            state(granted: granted, skipped: skipped)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(p.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(granted || skipped ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                                                        : AnyShapeStyle(HierarchicalShapeStyle.primary))
                Text(p.why)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // Screen Recording is read once at launch, so a fresh grant is
                // invisible until the app comes back. Saying so beats leaving
                // the row stuck on "missing" while the switch is already on.
                if p.needsRestart, !granted, !skipped {
                    Button("Enabled it? Restart to apply") { model.restart() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if !granted && !skipped {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(p.action) { model.request(p) }
                        .controlSize(.small)
                    if p.skippable {
                        Button("Skip") { model.skip(p) }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func state(granted: Bool, skipped: Bool) -> some View {
        if granted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if skipped {
            Image(systemName: "minus.circle")
                .foregroundStyle(.tertiary)
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.secondary)
            Text("Nothing is uploaded. The archive is a folder on this Mac and you can delete it at any time.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
