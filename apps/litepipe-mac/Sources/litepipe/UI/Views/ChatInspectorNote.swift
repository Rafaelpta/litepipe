import SwiftUI
import AppKit

/// What the inspector says while the chat is open.
///
/// The column exists to describe a selected capture, and the chat has none, so it
/// sat there reading "No Capture Selected" beside a pane that cannot answer
/// anything yet. Two blanks side by side look like a broken window rather than
/// one under construction. This says which it is, and where the work is tracked.
struct ChatInspectorNote: View {
    private static let issue = "https://github.com/Rafaelpta/litepipe/issues/9"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ChatBuildIllustration()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 7) {
                    Text("STILL BEING BUILT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.tertiary)

                    Text("The chat is the newest part of litepipe")
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("""
                         The archive and the timeline are finished work. This pane is \
                         not: attaching a model takes a step that only lands on some \
                         machines, and until it does the questions here go nowhere.
                         """)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    line("The bridge a model connects through is not in the download yet.")
                    line("With nothing attached the field is locked on purpose, not stuck.")
                    line("Answers arrive whole, with no way to follow along or stop.")
                }

                Button("Read what is left to do") {
                    if let url = URL(string: Self.issue) { NSWorkspace.shared.open(url) }
                }
                .controlSize(.small)

                Text("Everything else in this window works on the archive already on this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
    }

    private func line(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
            Text(t)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Drawn, like the other unbuilt rooms: flat shapes, two tones, no imported art.
/// A conversation with one side of it still missing.
private struct ChatBuildIllustration: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ink = Color(red: 0.10, green: 0.11, blue: 0.13)
            let paper = Color(red: 0.83, green: 0.78, blue: 0.62)
            let deep = Color(red: 0.66, green: 0.58, blue: 0.38)

            ZStack(alignment: .topLeading) {
                paper

                // Asked, and sitting there.
                RoundedRectangle(cornerRadius: 9)
                    .fill(deep)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(ink, lineWidth: 2.5))
                    .frame(width: w * 0.46, height: h * 0.22)
                    .offset(x: w * 0.44, y: h * 0.16)

                // The reply, drawn as an outline: the shape is decided, the
                // inside is not.
                RoundedRectangle(cornerRadius: 9)
                    .fill(.clear)
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.5, dash: [7, 6])))
                    .frame(width: w * 0.54, height: h * 0.26)
                    .offset(x: w * 0.08, y: h * 0.50)
            }
        }
    }
}
