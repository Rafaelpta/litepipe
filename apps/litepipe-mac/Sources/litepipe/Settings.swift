import AppKit
import Combine
import Foundation
import ServiceManagement
import SQLite3
import SwiftUI

// Local data operations for the Data settings section: total size + delete by
// time range / all. Deletes the DB rows and the frame/audio files on disk.
enum DataStore {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".litepipe", isDirectory: true)
    }

    static func totalBytes() -> Int64 {
        var total: Int64 = 0
        if let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in en {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    static func deleteAll() {
        let fm = FileManager.default
        for n in ["data", "db.sqlite", "db.sqlite-wal", "db.sqlite-shm"] {
            try? fm.removeItem(at: dir.appendingPathComponent(n))
        }
    }

    // Delete everything captured at/after `cutoff` (e.g. "last hour").
    static func deleteSince(_ cutoff: Date) {
        let iso = isoUTC(cutoff)
        var db: OpaquePointer?
        guard sqlite3_open(dir.appendingPathComponent("db.sqlite").path, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        removeFiles(db, "SELECT snapshot_path FROM frames WHERE snapshot_path IS NOT NULL AND timestamp >= ?", iso)
        removeFiles(db, "SELECT file_path FROM audio_chunks WHERE timestamp >= ?", iso)

        for sql in [
            "DELETE FROM ocr_text WHERE frame_id IN (SELECT id FROM frames WHERE timestamp >= ?)",
            "DELETE FROM frames WHERE timestamp >= ?",
            "DELETE FROM audio_transcriptions WHERE timestamp >= ?",
            "DELETE FROM audio_chunks WHERE timestamp >= ?",
            "DELETE FROM ui_events WHERE timestamp >= ?",
        ] {
            exec(db, sql, iso) // best-effort; ignore errors for tables/columns that differ
        }
    }

    private static func removeFiles(_ db: OpaquePointer?, _ query: String, _ iso: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (iso as NSString).utf8String, -1, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                try? FileManager.default.removeItem(atPath: String(cString: c))
            }
        }
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String, _ iso: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (iso as NSString).utf8String, -1, nil)
        _ = sqlite3_step(stmt)
    }

    private static func isoUTC(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'+00:00'"
        return f.string(from: d)
    }
}

final class SettingsController {
    /// The one instance, so the menu bar item and ⌘, raise the same window
    /// rather than each building their own.
    @MainActor static let shared = SettingsController(engine: EngineController.shared)

    private var window: NSWindow?
    private let engine: EngineController
    init(engine: EngineController) { self.engine = engine }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            w.title = "litepipe — Settings"
            w.center()
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(engine: engine))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum Section: String, CaseIterable, Identifiable {
    case general = "General", privacy = "Privacy", data = "Data", shortcuts = "Shortcuts", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        case .data: return "internaldrive"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var engine: EngineController
    @State private var section: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            // sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("SETTINGS").font(.system(size: 10, weight: .semibold)).foregroundColor(DS.Colors.faint)
                    .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
                ForEach(Section.allCases) { s in
                    HStack(spacing: 8) {
                        Image(systemName: s.icon).font(.system(size: 12)).frame(width: 16)
                        Text(s.rawValue).font(.system(size: 13))
                    }
                    .foregroundColor(section == s ? DS.Colors.fg : DS.Colors.dim)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(section == s ? Color.white.opacity(0.08) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { section = s }
                    .padding(.horizontal, 8)
                }
                Spacer()
                Text("litepipe \(appVersion())").font(.system(size: 10)).foregroundColor(DS.Colors.faint)
                    .padding(12)
            }
            .frame(width: 190)
            .background(Color.white.opacity(0.02))

            Rectangle().fill(DS.Colors.hair).frame(width: 1)

            // content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .general: GeneralPane(engine: engine)
                    case .privacy: PrivacyPane(engine: engine)
                    case .data: DataPane(engine: engine)
                    case .shortcuts: ShortcutsPane()
                    case .about: AboutPane()
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(Color.black)
    }
}

private func appVersion() -> String {
    "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var engine: EngineController
    @AppStorage("capture.audio") private var captureAudio = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General").font(.system(size: 18, weight: .semibold)).foregroundColor(DS.Colors.fg)

            Toggle("Launch litepipe at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
                .foregroundColor(DS.Colors.dim)

            Toggle("Capture audio (mic + system) for transcription", isOn: $captureAudio)
                .onChange(of: captureAudio) { _ in engine.restart() }
                .foregroundColor(DS.Colors.dim)

            HStack {
                Text("Data folder").foregroundColor(DS.Colors.dim)
                Spacer()
                Button("Open") { engine.openDataFolder() }
            }
        }
        .font(.system(size: 13))
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @ObservedObject var engine: EngineController
    @AppStorage("privacy.redactSecrets") private var redactSecrets = true
    @AppStorage("privacy.ignoredUrls") private var ignoredUrls = ""
    @AppStorage("privacy.ignoredApps") private var ignoredApps = ""
    // Lists apply on engine restart; track edits so the Apply button only
    // shows when there is something new to apply.
    @State private var draftUrls = ""
    @State private var draftApps = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy").font(.system(size: 18, weight: .semibold)).foregroundColor(DS.Colors.fg)

            Toggle("Redact secrets (keys, cards, passwords) from the memory", isOn: $redactSecrets)
                .onChange(of: redactSecrets) { _ in engine.restart() }
                .foregroundColor(DS.Colors.dim)
            Text("Detected secrets become labels in text and black boxes in screenshots. The original is overwritten.")
                .font(.system(size: 11)).foregroundColor(DS.Colors.dim.opacity(0.7))

            Divider().background(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 6) {
                Text("Never capture these websites").foregroundColor(DS.Colors.dim)
                TextField("bank.com, health.com", text: $draftUrls)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                Text("Never capture these apps").foregroundColor(DS.Colors.dim)
                TextField("WhatsApp, Signal", text: $draftApps)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                if draftUrls != ignoredUrls || draftApps != ignoredApps {
                    Button("Apply (restarts capture)") {
                        ignoredUrls = draftUrls
                        ignoredApps = draftApps
                        engine.restart()
                    }
                }
            }

            Divider().background(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 6) {
                Label("Private browser windows are never captured", systemImage: "eye.slash")
                Label("Password managers are never captured", systemImage: "key")
                Label("The shortcut pauses everything instantly", systemImage: "pause.circle")
            }
            .font(.system(size: 12)).foregroundColor(DS.Colors.dim)
        }
        .font(.system(size: 13))
        .onAppear {
            draftUrls = ignoredUrls
            draftApps = ignoredApps
        }
    }
}

// MARK: - Data

private struct DataPane: View {
    @ObservedObject var engine: EngineController
    @State private var sizeText = "…"
    @State private var confirm: (title: String, action: () -> Void)?
    @State private var customDate = Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data").font(.system(size: 18, weight: .semibold)).foregroundColor(DS.Colors.fg)

            // Usage
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Storage used").font(.system(size: 13, weight: .medium)).foregroundColor(DS.Colors.fg)
                    Text("Everything litepipe has captured, on this Mac.").font(.system(size: 11)).foregroundColor(DS.Colors.faint)
                }
                Spacer()
                Text(sizeText).font(.system(size: 14, weight: .semibold)).foregroundColor(DS.Colors.live)
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))

            Text("Manage context collected").font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.faint)

            deleteRow("Delete last hour of context", "Remove everything captured in the last hour.") {
                deleteSince(hours: 1)
            }
            deleteRow("Delete last day of context", "Remove everything captured in the last 24 hours.") {
                deleteSince(hours: 24)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete context for a custom time period").font(.system(size: 13)).foregroundColor(DS.Colors.dim)
                    DatePicker("since", selection: $customDate, in: ...Date()).labelsHidden()
                        .datePickerStyle(.compact).frame(width: 200)
                }
                Spacer()
                Button("Delete") {
                    confirm = ("Delete everything captured since \(short(customDate))?", { DataStore.deleteSince(customDate); refresh() })
                }
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.03)))

            deleteRow("Delete all context", "Permanently remove everything. This cannot be undone.", destructive: true) {
                DataStore.deleteAll(); refresh()
            }
        }
        .font(.system(size: 13))
        .onAppear { refresh() }
        .alert(item: Binding(get: { confirm.map { AlertBox(title: $0.title, action: $0.action) } },
                             set: { _ in confirm = nil })) { box in
            Alert(title: Text(box.title),
                  primaryButton: .destructive(Text("Delete")) { withEnginePaused(box.action) },
                  secondaryButton: .cancel())
        }
    }

    private func deleteRow(_ title: String, _ sub: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundColor(destructive ? Color(red: 0.9, green: 0.45, blue: 0.4) : DS.Colors.dim)
                Text(sub).font(.system(size: 11)).foregroundColor(DS.Colors.faint)
            }
            Spacer()
            Button("Delete") { confirm = (title + "?", action) }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.03)))
    }

    private func deleteSince(hours: Int) {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
        DataStore.deleteSince(cutoff); refresh()
    }

    // Pause the engine, run the destructive op, resume — avoids DB write races.
    private func withEnginePaused(_ op: @escaping () -> Void) {
        engine.stop()
        DispatchQueue.global().async {
            op()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { engine.start() }
        }
    }

    private func refresh() {
        sizeText = "…"
        DispatchQueue.global().async {
            let bytes = DataStore.totalBytes()
            DispatchQueue.main.async { sizeText = byteString(bytes) }
        }
    }

    private func short(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"; return f.string(from: d)
    }
}

private struct AlertBox: Identifiable { let id = UUID(); let title: String; let action: () -> Void }

private func byteString(_ b: Int64) -> String {
    let f = ByteCountFormatter(); f.countStyle = .file; return f.string(fromByteCount: b)
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcuts").font(.system(size: 18, weight: .semibold)).foregroundColor(DS.Colors.fg)
            HStack {
                Text("Pause / resume context awareness").font(.system(size: 13)).foregroundColor(DS.Colors.dim)
                Spacer()
                keycap("⌥"); keycap("⌃")
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.03)))
        }
    }
    private func keycap(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .medium)).foregroundColor(DS.Colors.dim)
            .frame(minWidth: 20).padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About").font(.system(size: 18, weight: .semibold)).foregroundColor(DS.Colors.fg)
            Text("litepipe \(appVersion())").font(.system(size: 13)).foregroundColor(DS.Colors.dim)
            Text("A local memory of your work. Everything stays on your Mac.").font(.system(size: 12)).foregroundColor(DS.Colors.faint)
            Button("Acknowledgements") {
                if let u = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                    NSWorkspace.shared.open(u)
                }
            }
            Divider().overlay(DS.Colors.hair)
            Button("Quit litepipe") { NSApp.terminate(nil) }
                .foregroundColor(Color(red: 0.9, green: 0.45, blue: 0.4))
        }
        .font(.system(size: 13))
    }
}
