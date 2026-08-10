import SwiftUI
import AppKit

/// Where someone points the agent they already use at this archive.
///
/// The alternative was for litepipe to bring a model of its own, which means
/// either asking for an API key or shipping one and paying for everybody. Most
/// people already have an agent they trust and pay for; this makes the
/// archive readable by it. litepipe never holds a key and never sees a question.
struct ConnectAgentsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var refresh = 0

    private var installed: [AgentConnector.Target] { AgentConnector.installed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !AgentConnector.isReady {
                        missingRequirement
                    } else if installed.isEmpty {
                        nothingInstalled
                    } else {
                        ForEach(installed) { row($0) }
                        manual
                        note
                    }
                }
                .padding(20)
                .id(refresh)
            }
        }
        .frame(width: 600, height: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Connect your agent")
                    .font(.system(size: 19, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("""
                 The archive stays on this Mac. Whatever you connect can look things \
                 up in it, on your account, and litepipe never sees the question or \
                 the answer.
                 """)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private func row(_ target: AgentConnector.Target) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: target.symbol)
                .font(.system(size: 16))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .font(.system(size: 13.5, weight: .medium))
                Text(target.answersHere
                     ? "Can answer here, in this window"
                     : "Answers in its own window")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                if target.isConnected {
                    Text("Restart \(target.name) for it to notice.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
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
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    /// Listing assistants nobody has would be this app advertising other
    /// companies' products. Naming the category is enough.
    private var nothingInstalled: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No agent found on this Mac")
                .font(.system(size: 13, weight: .medium))
            Text("""
                 litepipe can connect to Claude Desktop, Claude Code and Cursor. \
                 Install any of them and this list fills in on its own. Until then \
                 the chat answers from the archive without a model, which is slower \
                 to read but never leaves the machine.
                 """)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private var missingRequirement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Node is missing")
                .font(.system(size: 13, weight: .medium))
            Text("""
                 The bridge that lets an agent read the archive runs on Node. \
                 Install it and reopen this window. Nothing else is needed, and \
                 nothing about the archive changes.
                 """)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("How to install Node") {
                if let url = URL(string: "https://nodejs.org") { NSWorkspace.shared.open(url) }
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    /// For anything not on the list, and for anyone who would rather see what is
    /// being written than press a button that writes it.
    @State private var copied = false

    private var manual: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Or wire it up yourself")
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.top, 8)
            Text("Registers a read only server that opens the archive file directly: no port, no key, and it answers with litepipe closed. Six tools: search, activity summary, meetings, transcripts, frame context, and SQL for anything those do not cover.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // A dev build has no bundle, so the line below points at a build
            // directory. Saying so beats letting someone paste a path that will
            // not exist on the machine they paste it into.
            if !AgentConnector.isBundled {
                Text("Development build: an installed litepipe registers the copy inside litepipe.app.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 8) {
                Text(AgentConnector.claudeCodeCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AgentConnector.claudeCodeCommand, forType: .string)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
            .padding(9)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What connecting does")
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.top, 8)
            line("Adds litepipe to that agent's list of places it can look things up. Anything already in that list is left alone.")
            line("The agent can read the archive and nothing else. It cannot change or delete anything.")
            line("Your question and whatever it finds go to whoever makes that agent, billed to your account, not ours.")
        }
    }

    private func line(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
            Text(t)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
