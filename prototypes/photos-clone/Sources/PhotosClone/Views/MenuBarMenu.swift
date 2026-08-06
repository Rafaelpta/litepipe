import SwiftUI
import AppKit

/// What the app looks like from the menu bar while its window is closed or
/// buried. Capture runs whether or not anything is on screen, so the status and
/// the pause control have to be reachable from here.
struct MenuBarMenu: View {
    @Environment(NavigationState.self) private var nav
    @Environment(ContextLibrary.self) private var lib

    var body: some View {
        content.labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var content: some View {
        // The most recent meeting, so the menu opens with something real rather
        // than a list of commands.
        if let meeting = lib.meetings.last {
            Section(Self.dayWord(meeting.start)) {
                Text("\(meeting.start.formatted(date: .omitted, time: .shortened))  ·  \(meeting.title ?? "Untitled meeting")")
            }
        }

        Button("Open litepipe") { Self.activate() }
        Button("Ask about your day") {
            nav.sidebarItem = .assistant
            Self.activate()
        }

        Divider()

        if nav.capturePaused {
            Button { nav.resumeCapture() } label: {
                Label("Resume Context Collection", systemImage: "play")
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
                Label("Pause Context Collection", systemImage: "pause")
            }
        }

        Divider()

        // Disabled rows, the way an app states its own version.
        Text("litepipe prototype 0.1")
        Text("\(lib.items.count.formatted()) moments · this Mac only")

        Divider()

        Button("Quit litepipe Completely") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.isVisible && $0.contentView != nil }?
            .makeKeyAndOrderFront(nil)
    }

    static func dayWord(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide))
    }
}
