import SwiftUI

struct SidebarView: View {
    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib
    @Environment(SelectionModel.self) private var sel

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.sidebarItem) {
            // Above the sections, with no header of its own — the way New Chat
            // sits above everything in a chat app.
            Section {
                row(.assistant, "sparkles.rectangle.stack")
            }

            Section("Capture") {
                row(.timeline, "clock")
                row(.highlights, "sparkles")
                row(.places, "map")
                row(.today, "calendar")
                HStack {
                    Label("Recently Deleted", systemImage: "trash")
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .tag(SidebarItem.recentlyDeleted)
            }

            Section("Collections") {
                row(.dayRecaps, "note.text")
                row(.people, "person.crop.circle")
                row(.meetings, "person.2.wave.2")
                row(.sessions, "timeline.selection")
                row(.activity, "bolt")

                DisclosureGroup(isExpanded: $nav.extractedExpanded) {
                    row(.decisions, "checkmark.seal", nested: true)
                    row(.actionItems, "checklist", nested: true)
                    row(.questions, "questionmark.bubble", nested: true)
                    row(.codeSnippets, "chevron.left.forwardslash.chevron.right", nested: true)
                    row(.links, "link", nested: true)
                    row(.errors, "exclamationmark.triangle", nested: true)
                    row(.redacted, "eye.slash", nested: true)
                } label: {
                    Label("Extracted", systemImage: "wand.and.rays")
                        .tag(SidebarItem.extracted)
                }

                DisclosureGroup(isExpanded: $nav.sourcesExpanded) {
                    row(.screen, "display", nested: true)
                    row(.microphone, "mic", nested: true)
                    row(.systemAudio, "speaker.wave.2", nested: true)
                    row(.keyboardClicks, "keyboard", nested: true)
                    row(.browser, "safari", nested: true)
                    row(.terminal, "terminal", nested: true)
                    row(.editor, "curlybraces", nested: true)
                    row(.messaging, "bubble.left.and.bubble.right", nested: true)
                    row(.email, "envelope", nested: true)
                    row(.documents, "doc.text", nested: true)
                    row(.design, "paintbrush", nested: true)
                } label: {
                    Label("Sources", systemImage: "folder")
                        .tag(SidebarItem.sources)
                }

                DisclosureGroup(isExpanded: $nav.notebooksExpanded) {
                    ForEach(lib.notebookNames, id: \.self) { name in
                        row(.notebook(name), "rectangle.stack", nested: true)
                    }
                } label: {
                    Label("Notebooks", systemImage: "folder")
                        .tag(SidebarItem.notebooksRoot)
                }

                DisclosureGroup(isExpanded: $nav.pipesExpanded) {
                    ForEach(lib.pipeNames, id: \.self) { name in
                        row(.pipe(name), "wand.and.rays", nested: true)
                    }
                } label: {
                    Label("Pipes", systemImage: "folder")
                        .tag(SidebarItem.pipesRoot)
                }
            }

            Section("Memory") {
                DisclosureGroup(isExpanded: $nav.agentMemoryExpanded) {
                    row(.facts, "quote.bubble", nested: true)
                    row(.playbooks, "book.closed", nested: true)
                    row(.sops, "list.bullet.rectangle", nested: true)
                    ForEach(lib.memoryTargets, id: \.self) { name in
                        row(.memoryTarget(name), "doc.text", nested: true)
                    }
                } label: {
                    Label("Agent Memory", systemImage: "brain")
                        .tag(SidebarItem.agentMemory)
                }
            }

            Section("Sharing") {
                DisclosureGroup(isExpanded: $nav.sharedContextsExpanded) {
                    row(.accessLog, "clock.arrow.circlepath", nested: true)
                    ForEach(lib.shareNames, id: \.self) { name in
                        row(.share(name), "antenna.radiowaves.left.and.right", nested: true)
                    }
                } label: {
                    Label("Shared Contexts", systemImage: "rectangle.stack.badge.person.crop")
                        .tag(SidebarItem.sharedContexts)
                }

                DisclosureGroup(isExpanded: $nav.firewallExpanded) {
                    row(.firewallRules, "slider.horizontal.3", nested: true)
                    row(.connectedApps, "puzzlepiece.extension", nested: true)
                    row(.blocked, "hand.raised", nested: true)
                } label: {
                    Label("Firewall", systemImage: "lock.shield")
                        .tag(SidebarItem.firewall)
                }

                row(.requests, "tray.and.arrow.down")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { CaptureStatusBar() }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        .onChange(of: nav.sidebarItem) {
            sel.clear()
            nav.openedPhotoID = nil
            nav.heroActive = true
        }
    }

    /// Top-level rows get the accent-tinted icon; rows nested inside a disclosure
    /// group get a secondary (gray) icon, matching Photos.
    private func row(_ item: SidebarItem, _ icon: String, nested: Bool = false) -> some View {
        Label {
            Text(item.displayName)
        } icon: {
            if nested {
                Image(systemName: icon).foregroundStyle(.secondary)
            } else {
                Image(systemName: icon)
            }
        }
        .tag(item)
    }
}
