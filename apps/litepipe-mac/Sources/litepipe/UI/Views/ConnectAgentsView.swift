import SwiftUI
import AppKit

/// Where someone points the agent they already use at this archive.
///
/// The alternative was for litepipe to bring a model of its own, which means
/// either asking for an API key or shipping one and paying for everybody. Most
/// people already have an agent they trust and pay for; this makes the
/// archive readable by it. litepipe never holds a key and never sees a question.
///
/// The first row of the sidebar, rather than a sheet buried in a chat that no
/// longer exists: an archive nothing reads is not worth keeping, so this is the
/// one page the app opens with something to do on it.
///
/// Written as two steps toward a first answer rather than a description of a
/// feature, because the page has real state to report: the first step marks
/// itself done once a client is wired up. Everything that explains rather than
/// advances sits in `docs/MCP.md`.
struct ConnectAgentsView: View {
    @State private var refresh = 0
    @State private var showManual = true
    @State private var recipe: AgentConnector.Recipe = .claudeCode
    @State private var copied: AgentConnector.Recipe?
    @State private var copiedQuestion: String?

    private var installed: [AgentConnector.Target] { AgentConnector.installed }
    private var anyConnected: Bool { installed.contains(where: \.isConnected) }

    private static let docs =
        "https://github.com/Rafaelpta/litepipe/blob/main/docs/MCP.md"

    /// One ScrollView holding everything, the shape `UnbuiltPage` already uses in
    /// this same slot. An earlier attempt pinned the header outside the scroll and
    /// claimed `maxHeight: .infinity`; the parent then handed this a frame taller
    /// than the window, which pushed the header off the top and left half a screen
    /// blank under the last row.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !AgentConnector.canConnect {
                    cannotConnect
                } else {
                    step(done: anyConnected,
                         title: "Connect a client",
                         sub: "Registers a read only MCP server in that client's config") {
                        VStack(alignment: .leading, spacing: 8) {
                            // The button only covers clients whose config is JSON
                            // under `mcpServers`. Finding none of them installed is
                            // not the end of the page: `manual` is what everyone
                            // else needs, so it stays either way.
                            if installed.isEmpty {
                                nothingInstalled
                            } else {
                                ForEach(installed) { row($0) }
                            }
                            manual
                        }
                    }

                    step(done: false,
                         title: "Ask it something",
                         sub: "Run these in the agent, not here") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Self.questions, id: \.self) { question($0) }
                        }
                    }
                }

                footer
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(refresh)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Connect an agent")
                .font(.system(size: 22, weight: .semibold))
            Text("Follow the steps to read the archive from your agent.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Steps

    /// A marker, a title, one line under it, and the thing you act on. The filled
    /// marker is not decoration: it reads the same state the buttons write, so the
    /// page says where you are without anyone maintaining a second copy of it.
    private func step<Content: View>(
        done: Bool, title: String, sub: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Circle()
                .strokeBorder(done ? Color.green : Color.secondary.opacity(0.45), lineWidth: 2)
                .background(Circle().fill(done ? Color.green : Color.clear))
                .frame(width: 11, height: 11)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
        }
    }

    // MARK: - Step one

    private func row(_ target: AgentConnector.Target) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: target.symbol)
                .font(.system(size: 15))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .font(.system(size: 13, weight: .medium))
                // The config file this writes into, rather than a sentence that
                // now reads the same under all three.
                Text(Self.tilde(target.configPath))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Only where a restart is the next thing to do. A client spawned
                // per question picks the wiring up on the next one, so telling
                // its owner to restart it is an instruction with no task behind it.
                if target.isConnected && target.needsRestart {
                    Text("Restart \(target.name) to load it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            if target.isConnected {
                HStack(spacing: 8) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Button("Remove") {
                        AgentConnector.disconnect(target)
                        refresh += 1
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            } else {
                Button("Connect") {
                    AgentConnector.connect(target)
                    refresh += 1
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    /// Open by default, and collapsible. The button above only reaches clients
    /// whose config is JSON under `mcpServers`; everyone else is one line away,
    /// and a page that only spoke Claude read as a product that only worked with
    /// Claude. A user with Codex installed asked how to connect it and there was
    /// nothing on the page that answered him.
    private var manual: some View {
        DisclosureGroup(isExpanded: $showManual) {
            VStack(alignment: .leading, spacing: 8) {
                // A dev build has no bundle, so the line below points at a build
                // directory. Saying so beats letting someone paste a path that will
                // not exist on the machine they paste it into.
                if !AgentConnector.isBundled {
                    Text("Development build: an installed litepipe registers the copy inside litepipe.app.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("", selection: $recipe) {
                    ForEach(AgentConnector.Recipe.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                HStack(alignment: .top, spacing: 8) {
                    Text(AgentConnector.recipe(recipe))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AgentConnector.recipe(recipe),
                                                       forType: .string)
                        copied = recipe
                    } label: {
                        Image(systemName: copied == recipe ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
                .padding(9)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                Text(recipe.note)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Text("Manual setup")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Any MCP client works")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Step two

    /// What to ask once it is wired up. These outlived the chat pane they were
    /// written for: the point was never a text field in this window, it was that
    /// the archive can answer things nothing else on the machine can.
    private static let questions = [
        "What did I do yesterday?",
        "What are my top five open loops right now?",
        "Find one repeated, costly workflow that could become a useful low risk automation",
        "Generate a small batch of LinkedIn post drafts based on my recent activity",
    ]

    private func question(_ q: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(q)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(q, forType: .string)
                copiedQuestion = q
            } label: {
                Image(systemName: copiedQuestion == q ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(9)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Footer

    /// The three things worth promising, in one line. What connecting does to a
    /// config file is implementation, and lives in the docs.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("""
                     Read only. litepipe never sees the question or the answer. \
                     Usage is billed to your agent's provider.
                     """)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Read the docs") {
                    if let url = URL(string: Self.docs) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5))
                .fixedSize()
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Empty and blocked states

    /// Listing assistants nobody has would be this app advertising other
    /// companies' products. Naming the category is enough.
    private var nothingInstalled: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No one click client found")
                .font(.system(size: 13, weight: .medium))
            Text("""
                 Claude Code, Claude Desktop and Cursor connect with a button. \
                 Install one and it appears here. Any other MCP client takes the \
                 line below.
                 """)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    /// Shown instead of the client list when connecting now would write a path that
    /// stops resolving later. Refusing is the kinder failure: a config pointing at an
    /// ejected disk image looks connected and answers nothing.
    private var cannotConnect: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AgentConnector.isReady ? "Move litepipe to Applications first"
                                        : "The bridge is missing")
                .font(.system(size: 13, weight: .medium))
            Text(AgentConnector.blockedReason ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if AgentConnector.isReady {
                Button("Show litepipe in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .controlSize(.small)
                .padding(.top, 4)
            } else {
                Button("Download litepipe again") {
                    if let url = URL(string: "https://litepipe.ai") { NSWorkspace.shared.open(url) }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private static func tilde(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
