import SwiftUI

/// Talking to the whole archive. Deliberately plain — the interesting part is not
/// the chat, it is that every answer carries the moments it was built from, and
/// clicking one lands on the screen where it happened.
struct ChatPane: View {
    @Environment(ContextLibrary.self) private var lib
    @Environment(ChatModel.self) private var chat
    @Environment(NavigationState.self) private var nav
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if chat.turns.isEmpty {
                            empty
                        } else {
                            ForEach(chat.turns) { turn in
                                bubble(turn).id(turn.id)
                            }
                        }
                        if chat.pending { thinking.id("thinking") }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 26)
                }
                .onChange(of: chat.turns.count) { _, _ in
                    withAnimation(Anim.crossfade) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: chat.pending) { _, _ in
                    withAnimation(Anim.crossfade) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            composer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { inputFocused = true }
    }

    // MARK: Empty state

    private var empty: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask your archive")
                    .font(.system(size: 26, weight: .semibold))
                Text("\(lib.items.count.formatted()) moments captured on this Mac. Nothing leaves it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(chat.suggestions(lib), id: \.self) { s in
                    Button { chat.ask(s, lib: lib) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Text(s).font(.system(size: 13))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    // MARK: Turns

    @ViewBuilder private func bubble(_ turn: ChatTurn) -> some View {
        if turn.role == .you {
            HStack {
                Spacer(minLength: 60)
                Text(turn.text)
                    .font(.system(size: 13.5))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(markdown(turn.text))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                if !turn.citations.isEmpty { citations(turn) }
                if turn.searchedCount > 0 {
                    Text("read \(turn.searchedCount.formatted()) moments")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The receipt. Each answer shows the moments behind it; clicking one leaves
    /// the chat and lands on that exact capture in the timeline.
    private func citations(_ turn: ChatTurn) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(turn.citations) { p in
                    Button { jump(to: p) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Image(nsImage: Thumbs.shared.image(for: p, bucket: .grid))
                                .resizable()
                                .scaledToFill()
                                .frame(width: 132, height: 84)
                                .clipped()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Photo.shortTitle(p.window, app: p.app, host: p.host))
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                Text(p.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 132, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                        }
                        .background(.quaternary.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Open this moment in the timeline")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var thinking: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading the archive…")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                @Bindable var chat = chat
                TextField("Ask about anything you have seen or said…", text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { chat.ask(chat.draft, lib: lib) }

                Button {
                    chat.ask(chat.draft, lib: lib)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(chat.draft.isEmpty ? AnyShapeStyle(.tertiary)
                                                            : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(chat.draft.isEmpty || chat.pending)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.bottom, 14)
            .padding(.top, 10)
        }
        .background(.bar)
    }

    // MARK: Actions

    private func jump(to photo: Photo) {
        nav.sidebarItem = .timeline
        nav.searchText = ""
        DispatchQueue.main.async { nav.scrollTarget = photo.id }
    }

    /// The answers use light markdown — bold for names, italics for caveats.
    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
