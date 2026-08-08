import SwiftUI
import AppKit

/// Who built this, fetched from GitHub when you open the page.
///
/// The list is short. That is the honest state of it and also the argument: an
/// archive of how people actually work is not a thing one person should own the
/// shape of.
struct ContributionsPage: View {
    private static let repo = "https://github.com/Rafaelpta/litepipe"
    private static let api = "https://api.github.com/repos/Rafaelpta/litepipe/contributors?per_page=60"

    @State private var people: [Contributor] = []
    @State private var failed = false
    @State private var loading = true

    struct Contributor: Identifiable, Decodable {
        let login: String
        let avatar_url: String
        let contributions: Int
        let html_url: String
        var id: String { login }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                roll
                footer
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTRIBUTIONS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)

            Text("litepipe is open source")
                .font(.system(size: 26, weight: .semibold))

            Text("""
                 It records your day on your own machine and answers to you, which \
                 only stays true if anyone can read what it does. The code is on \
                 GitHub, and so is every decision behind it.
                 """)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var roll: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Thank you")
                    .font(.system(size: 15, weight: .semibold))
                if !people.isEmpty {
                    Text(people.count == 1 ? "1 person" : "\(people.count) people")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }

            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Asking GitHub who has contributed")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if failed {
                Text("Could not reach GitHub. The list lives at \(Self.repo)/graphs/contributors.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if people.isEmpty {
                // The empty roll is the invitation, and more honest than a page
                // of one face.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nobody yet")
                        .font(.system(size: 13, weight: .medium))
                    Text("The first person to fix or build something here goes at the top of this page, with their face on it.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 16)],
                          alignment: .leading, spacing: 18) {
                    ForEach(people) { person in
                        card(person)
                    }
                }
            }
        }
    }

    private func card(_ person: Contributor) -> some View {
        Button {
            if let url = URL(string: person.html_url) { NSWorkspace.shared.open(url) }
        } label: {
            VStack(spacing: 7) {
                AsyncImage(url: URL(string: person.avatar_url)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 62, height: 62)
                .clipShape(Circle())
                .overlay(Circle().stroke(.quaternary, lineWidth: 1))

                Text(person.login)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(person.contributions == 1 ? "1 commit" : "\(person.contributions) commits")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("How to land here")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                line("Read the open issues. The ones marked in the app say where to start.")
                line("Open an issue before writing much, so two people do not build the same half.")
                line("Small and finished beats large and pending.")
            }

            HStack(spacing: 10) {
                Button("Open the repository") { open(Self.repo) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                Button("Read the open issues") { open(Self.repo + "/issues") }
                    .controlSize(.large)
            }
            .fixedSize()
            .padding(.top, 6)

            // Worth stating on the one screen that reaches the network.
            Text("This page asks GitHub for the list of contributors when you open it. It is the only request litepipe makes, it carries nothing about you, and closing the page ends it.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    private func load() async {
        guard people.isEmpty, let url = URL(string: Self.api) else { return }
        defer { loading = false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            people = try JSONDecoder().decode([Contributor].self, from: data)
        } catch {
            failed = true
        }
    }
}
