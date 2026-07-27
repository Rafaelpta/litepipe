import AppKit
import Combine
import Foundation
import SQLite3
import SwiftUI

// A native timeline that recreates the screenpipe rewind experience: scrub through
// captured frames, navigate by day, see the active app / window / URL and the OCR
// text for each frame. Reads the engine's SQLite DB (~/.litepipe/db.sqlite) directly
// plus the JPG snapshots on disk — no API token needed.

struct TimelineFrame: Identifiable {
    let id: Int64
    let ms: Int64
    let monitor: Int
    let imagePath: String
    let app: String
    let window: String
    let url: String?
    let ocr: String?

    var date: Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
    var imageURL: URL { URL(fileURLWithPath: imagePath) }
}

// Minimal read-only SQLite loader.
enum TimelineDB {
    static func load(dbPath: String) -> [TimelineFrame] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT f.id, f.snapshot_path, f.app_name, f.window_name, f.browser_url,
               COALESCE(o.text, f.full_text, f.accessibility_text)
        FROM frames f
        LEFT JOIN ocr_text o ON o.frame_id = f.id
        WHERE f.snapshot_path IS NOT NULL
        GROUP BY f.id
        ORDER BY f.id ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        func text(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            return String(cString: c)
        }

        var out: [TimelineFrame] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            guard let path = text(1) else { continue }
            let name = (((path as NSString).lastPathComponent) as NSString).deletingPathExtension
            let parts = name.components(separatedBy: "_m")
            guard parts.count == 2, let ms = Int64(parts[0]), let mon = Int(parts[1]) else { continue }
            out.append(TimelineFrame(id: id, ms: ms, monitor: mon, imagePath: path,
                                     app: text(2) ?? "", window: text(3) ?? "",
                                     url: text(4), ocr: text(5)))
        }
        return out
    }
}

final class TimelineModel: ObservableObject {
    @Published var all: [TimelineFrame] = []
    @Published var day: Date = Calendar.current.startOfDay(for: Date())
    @Published var monitor: Int = 1
    @Published var index: Int = 0
    @Published var showOCR: Bool = true

    private let dbPath: String
    init(dbPath: String) { self.dbPath = dbPath }

    var monitors: [Int] { Array(Set(all.map(\.monitor))).sorted() }
    var shown: [TimelineFrame] {
        let cal = Calendar.current
        return all.filter { $0.monitor == monitor && cal.isDate($0.date, inSameDayAs: day) }
    }
    var current: TimelineFrame? { shown.indices.contains(index) ? shown[index] : nil }

    func load() {
        all = TimelineDB.load(dbPath: dbPath)
        if !monitors.contains(monitor) { monitor = monitors.first ?? 1 }
        if let latest = all.map({ Calendar.current.startOfDay(for: $0.date) }).max() { day = latest }
        clampIndex(toEnd: true)
    }

    func stepDay(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: delta, to: day) {
            day = d
            clampIndex(toEnd: true)
        }
    }

    func clampIndex(toEnd: Bool = false) {
        let n = shown.count
        index = n == 0 ? 0 : (toEnd ? n - 1 : min(index, n - 1))
    }

    func dayLabel() -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: day)
    }
    func timeLabel(_ f: TimelineFrame) -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        return df.string(from: f.date)
    }
}

final class TimelineController {
    private var window: NSWindow?
    private let model: TimelineModel
    init(dataDir: URL) {
        model = TimelineModel(dbPath: dataDir.appendingPathComponent("db.sqlite").path)
    }
    func show() {
        model.load()
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            w.title = "litepipe — Timeline"
            w.center()
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: TimelineView(model: model))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct TimelineView: View {
    @ObservedObject var model: TimelineModel
    @State private var showCalendar = false

    var body: some View {
        VStack(spacing: 0) {
            header
            line
            contextBar
            line
            frameArea
            scrubber
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color.black)
        .onAppear { model.load() }
    }

    private var line: some View { Rectangle().fill(DS.Colors.hair).frame(height: 1) }

    // MARK: - Header: day navigation + monitor + OCR + refresh

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: { model.stepDay(-1) }) {
                Image(systemName: "chevron.left").foregroundColor(DS.Colors.dim)
            }.buttonStyle(.plain)

            Button(action: { showCalendar.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11))
                    Text(model.dayLabel()).font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(DS.Colors.fg)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCalendar) {
                DatePicker("", selection: $model.day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(10)
                    .onChange(of: model.day) { _ in model.clampIndex(toEnd: true) }
            }

            Button(action: { model.stepDay(1) }) {
                Image(systemName: "chevron.right").foregroundColor(DS.Colors.dim)
            }.buttonStyle(.plain)

            if model.monitors.count > 1 {
                Picker("", selection: $model.monitor) {
                    ForEach(model.monitors, id: \.self) { m in Text("Display \(m)").tag(m) }
                }
                .labelsHidden().frame(width: 120)
                .onChange(of: model.monitor) { _ in model.clampIndex(toEnd: true) }
            }

            Spacer()

            Text("\(model.shown.count) frames").font(.system(size: 11)).foregroundColor(DS.Colors.faint)
            Toggle(isOn: $model.showOCR) { Text("Text").font(.system(size: 11)) }
                .toggleStyle(.switch).tint(DS.Colors.live)
                .foregroundColor(DS.Colors.dim)
            Button(action: { model.load() }) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundColor(DS.Colors.dim)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: - Context bar: app / window / URL of the current frame

    private var contextBar: some View {
        HStack(spacing: 8) {
            if let f = model.current {
                Image(systemName: "macwindow").font(.system(size: 11)).foregroundColor(DS.Colors.faint)
                Text(f.app.isEmpty ? "—" : f.app).font(.system(size: 12, weight: .medium)).foregroundColor(DS.Colors.fg)
                if !f.window.isEmpty {
                    Text("·").foregroundColor(DS.Colors.faint)
                    Text(f.window).font(.system(size: 12)).foregroundColor(DS.Colors.dim).lineLimit(1)
                }
                Spacer()
                if let url = f.url, !url.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.system(size: 10))
                        Text(url).font(.system(size: 11)).lineLimit(1)
                    }
                    .foregroundColor(DS.Colors.faint)
                    .frame(maxWidth: 340, alignment: .trailing)
                }
            } else {
                Text("No frame").font(.system(size: 12)).foregroundColor(DS.Colors.faint)
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    // MARK: - Frame image (+ optional OCR text panel)

    @ViewBuilder
    private var frameArea: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                if let f = model.current, let img = NSImage(contentsOf: f.imageURL) {
                    Image(nsImage: img).resizable().scaledToFit().padding(12)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 26)).foregroundColor(DS.Colors.faint)
                        Text(model.shown.isEmpty ? "No frames on this day." : "…")
                            .font(.system(size: 12)).foregroundColor(DS.Colors.faint)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.showOCR {
                Rectangle().fill(DS.Colors.hair).frame(width: 1)
                ScrollView {
                    Text(model.current?.ocr?.isEmpty == false ? model.current!.ocr! : "No recognized text for this frame.")
                        .font(.system(size: 11.5))
                        .foregroundColor(DS.Colors.dim)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(width: 320)
                .background(Color.white.opacity(0.02))
            }
        }
    }

    // MARK: - Scrubber (time + slider + thumbnail strip)

    private var scrubber: some View {
        VStack(spacing: 10) {
            if let f = model.current {
                Text(model.timeLabel(f)).font(.system(size: 13, weight: .medium)).foregroundColor(DS.Colors.dim)
            }
            HStack(spacing: 12) {
                Button(action: { model.index = max(0, model.index - 1) }) {
                    Image(systemName: "chevron.left").foregroundColor(DS.Colors.dim)
                }.buttonStyle(.plain)
                Slider(
                    value: Binding(get: { Double(model.index) },
                                   set: { model.index = Int($0.rounded()) }),
                    in: 0...Double(max(1, model.shown.count - 1))
                ).disabled(model.shown.count < 2)
                Button(action: { model.index = min(model.shown.count - 1, model.index + 1) }) {
                    Image(systemName: "chevron.right").foregroundColor(DS.Colors.dim)
                }.buttonStyle(.plain)
            }

            thumbnailStrip
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 16)
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.shown.enumerated()), id: \.element.id) { i, f in
                        thumb(f, selected: i == model.index)
                            .id(i)
                            .onTapGesture { model.index = i }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 46)
            .onChange(of: model.index) { i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
        }
    }

    private func thumb(_ f: TimelineFrame, selected: Bool) -> some View {
        Group {
            if let img = NSImage(contentsOf: f.imageURL) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.05)
            }
        }
        .frame(width: 66, height: 40)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .stroke(selected ? DS.Colors.live : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1))
    }
}
