import SwiftUI

struct InspectorView: View {
    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib
    @Environment(SelectionModel.self) private var sel

    private var target: Photo? {
        if let id = nav.openedPhotoID { return lib.photo(id) }
        if sel.selection.count == 1, let id = sel.selection.first { return lib.photo(id) }
        return nil
    }

    var body: some View {
        Group {
            if nav.sidebarItem == .assistant {
                // The chat has nothing to select, so the column says what it is
                // instead of what is missing.
                ChatInspectorNote()
            } else if let photo = target {
                info(photo)
            } else if sel.selection.count > 1 {
                ContentUnavailableView("\(sel.selection.count) Captures Selected",
                                       systemImage: "square.stack")
            } else {
                ContentUnavailableView("No Capture Selected", systemImage: "info.circle")
            }
        }
        // Wide enough that a captured line does not wrap every few words: this
        // column carries whole comment threads and transcripts, not a field list.
        .inspectorColumnWidth(min: 300, ideal: 460, max: 640)
    }

    private func info(_ photo: Photo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(photo)
                Divider()
                where_(photo)
                Divider()
                how(photo)

                if let snippet = lib.matchSnippet(photo) {
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Matched here", systemImage: "text.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(snippet)
                            .font(.system(size: 11.5))
                            .lineSpacing(2)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)
                    }
                }

                let lines = lib.transcript(for: photo)
                if !lines.isEmpty {
                    Divider()
                    transcript(lines, meeting: lib.meeting(for: photo))
                }
                if true {
                    Divider()
                    onScreenText(photo)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: photo.source.symbol)
                    .foregroundStyle(.secondary)
                Text(photo.app.isEmpty ? photo.source.label : photo.app)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if photo.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if !photo.window.isEmpty {
                Text(photo.window)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(photo.date.formatted(.dateTime.weekday(.wide).month(.wide).day()
                    .hour().minute().second()))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func where_(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = photo.url {
                Text(url)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                chip(photo.source.label)
                if let host = photo.host { chip(host) }
                if let m = photo.monitor { chip(m) }
            }
        }
    }

    private func how(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if !photo.captureTrigger.isEmpty { chip(photo.captureTrigger.replacingOccurrences(of: "_", with: " ")) }
                if !photo.textSource.isEmpty { chip(photo.textSource) }
                chip(photo.hasImage ? "image + text" : "text only")
            }
            Text(momentLine(photo))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    /// How much this moment folded, so the reader can trust the number.
    private func momentLine(_ photo: Photo) -> String {
        var parts = ["frame \(photo.frameId)"]
        if photo.repeatCount > 1 { parts.append("\(photo.repeatCount) captures folded") }
        if photo.rawLineCount > 0 {
            parts.append("\(photo.contentLineCount) of \(photo.rawLineCount) lines kept")
        }
        return parts.joined(separator: " · ")
    }

    private func onScreenText(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(photo.isThin ? "Activity" : "What happened")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(photo.isThin ? photo.activityLine : photo.excerpt)
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .textSelection(.enabled)
                .foregroundStyle(photo.isThin ? .secondary : .primary)
        }
    }

    /// This is the microphone running alongside the screen, not a transcript of it.
    /// Saying so matters: the capture can show WhatsApp while the audio is a call.
    private func transcript(_ lines: [ContextDB.TranscriptLine],
                            meeting: ContextDB.Meeting?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Heard at the same time")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let title = meeting?.title, !title.isEmpty {
                        Text("in \(title)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text("\(lines.count) segments")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            ForEach(lines.prefix(80)) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(line.speaker)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(line.isMe ? Color.accentColor : .secondary)
                        Text(line.at.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text(line.text)
                        .font(.system(size: 11.5))
                        .lineSpacing(1.5)
                        .textSelection(.enabled)
                }
            }
            if lines.count > 80 {
                Text("+ \(lines.count - 80) more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }
}
