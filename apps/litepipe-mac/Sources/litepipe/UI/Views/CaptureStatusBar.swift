import SwiftUI

/// Pinned to the bottom of the sidebar: whether capture is running, and what is
/// in the archive. Littlebird puts a subscription tier here; a local product
/// should put the archive itself, because "1,15 GB, this Mac, never uploaded" is
/// the claim that sells it.
struct CaptureStatusBar: View {
    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib
    @State private var hovering = false
    @State private var showExclusions = false
    @State private var confirmDelete: DeleteScope?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                statusRow
                archiveRow
            }
            .padding(.horizontal, 10)
            .padding(.top, 9)
            .padding(.bottom, 10)
        }
        // The sidebar pins this strip with safeAreaInset, so the list scrolls
        // underneath it. Without a background of its own the rows show straight
        // through the status line.
        .background(.bar)
        .sheet(isPresented: $showExclusions) { ExclusionsSheet() }
        .confirmationDialog(
            confirmDelete.map { "Delete \($0.label.lowercased())?" } ?? "",
            isPresented: Binding(get: { confirmDelete != nil },
                                 set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { confirmDelete = nil }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Captures and their screenshots are removed from this Mac. This cannot be undone.")
        }
    }

    // MARK: Status

    /// One shape for both states. The pill states what is happening; the action
    /// button only exists while the pointer is over the strip, so the resting
    /// state is a status line and not a control panel.
    private var statusRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                // The indicator lives outside the Menu label: .borderlessButton
                // renders the label's text and drops anything else, so a Circle
                // or an Image nested inside simply never appears.
                if nav.capturePaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 7)
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                }
                // No fixedSize and no trailing Spacer: the menu has to span the
                // whole pill, otherwise only the glyphs of the label are
                // clickable and the empty half of the pill does nothing.
                Menu {
                    menuItems
                } label: {
                    Text(nav.capturePaused ? "Paused" : "Context enabled")
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 9)
            .padding(.trailing, 9)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

            if hovering {
                Button {
                    if nav.capturePaused { nav.resumeCapture() }
                    else { nav.pauseCapture(for: 15 * 60) }
                } label: {
                    Image(systemName: nav.capturePaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .help(nav.capturePaused ? "Resume Context Awareness" : "Pause")
                .transition(.opacity)
            }
        }
        .onHover { inside in
            withAnimation(Anim.hover) { hovering = inside }
        }
    }

    // MARK: Menu

    /// A system menu rather than a popover: no beak, it sits flush against the
    /// pill, and `Label` gives each row its icon for free. The only thing lost
    /// against a custom panel is the footer button, which becomes a plain item.
    @ViewBuilder private var menuItems: some View {
        Group {
        if nav.capturePaused {
            Button { nav.resumeCapture() } label: {
                Label("Resume Context Awareness", systemImage: "play")
            }
        } else {
            Menu {
                Button("5 minutes")  { nav.pauseCapture(for: 5 * 60) }
                Button("15 minutes") { nav.pauseCapture(for: 15 * 60) }
                Button("30 minutes") { nav.pauseCapture(for: 30 * 60) }
                Button("An hour")    { nav.pauseCapture(for: 60 * 60) }
                Divider()
                Button("Until next launch") { nav.pauseCapture(for: nil) }
            } label: {
                Label("Pause Context Awareness", systemImage: "pause")
            }
        }
        Menu {
            ForEach(DeleteScope.allCases) { scope in
                Button(scope.label, role: scope == .everything ? .destructive : nil) {
                    confirmDelete = scope
                }
            }
        } label: {
            Label("Delete Data", systemImage: "trash")
        }
        Divider()
        Button { showExclusions = true } label: {
            Label("Exclude Apps and Websites…", systemImage: "nosign")
        }
        }
        // macOS drops menu-item icons unless the style is stated outright.
        .labelStyle(.titleAndIcon)
    }

    // MARK: Archive

    /// Where a subscription tier would go. The numbers are the product.
    private var archiveRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                // "local only" rides on the title line, where a subscription
                // product would print the plan tier. That is the claim.
                Text("This Mac · local only")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text(archiveLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
    }

    private var archiveLine: String {
        var parts = ["\(lib.items.count.formatted()) moments"]
        if let size = lib.archiveSize { parts.append(size) }
        return parts.joined(separator: " · ")
    }
}

enum DeleteScope: String, CaseIterable, Identifiable {
    case lastHour, lastDay, lastWeek, everything
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lastHour: "Last hour"
        case .lastDay: "Last 24 hours"
        case .lastWeek: "Last 7 days"
        case .everything: "Everything"
        }
    }
}

/// The exclusion list the loader already honours through PC_EXCLUDE, shown as a
/// surface rather than an environment variable.
struct ExclusionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContextLibrary.self) private var lib
    @State private var draft = ""

    private var active: [String] { ContextDB.exclusions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Excluded from context")
                    .font(.system(size: 15, weight: .semibold))
                Text("Anything matching these is dropped before it is stored — it never reaches the archive, the search index, or the chat.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)

            Divider()

            if active.isEmpty {
                VStack(spacing: 6) {
                    Text("Nothing is excluded")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Every app and site on this Mac is being captured.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            } else {
                List {
                    ForEach(active, id: \.self) { rule in
                        HStack(spacing: 8) {
                            Image(systemName: "nosign")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(rule).font(.system(size: 12.5))
                            Spacer()
                            Text(matchCount(rule))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(height: 150)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("app name or domain", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("Add") {}
                    .disabled(draft.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            HStack {
                Text("Set with PC_EXCLUDE for now")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 430)
    }

    /// How much this rule is actually keeping out, so it is not a blind setting.
    private func matchCount(_ rule: String) -> String {
        let n = lib.items.filter { p in
            (p.app + " " + (p.url ?? "") + " " + p.window).lowercased().contains(rule)
        }.count
        return n == 0 ? "no matches" : "\(n) hidden"
    }
}
