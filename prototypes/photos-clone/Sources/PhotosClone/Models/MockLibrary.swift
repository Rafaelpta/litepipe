import Foundation
import Observation

@Observable
final class MockLibrary {
    private(set) var photos: [Photo] = []   // ascending by date

    let notebookNames = ["Auth Rewrite", "Q3 Planning", "Vendor Calls", "Onboarding"]
    let pipeNames = ["Day Recap", "Standup", "Meeting Summary"]
    let memoryTargets = ["CLAUDE.md", "AGENTS.md"]
    /// Named slices of context that cross the machine boundary. Each one is a
    /// different reason to share: internal team, a scoped vendor handoff, and an
    /// aggregated panel — the one you'd actually get paid for.
    let shareNames = ["Team Standup", "Acme Support", "Research Panel"]

    init() { generate() }

    // MARK: - Filtering

    func photos(for item: SidebarItem?, search: String, favoritesOnly: Bool) -> [Photo] {
        var base: [Photo]
        if item == .recentlyDeleted {
            base = photos.filter { $0.isDeleted }
        } else {
            let visible = photos.filter { !$0.isDeleted && !$0.isHidden }
            let scenic: Set<PhotoKind> = [.landscape, .beach, .sunset, .city, .forest]
            switch item {
            // Capture
            case .timeline, .none: base = visible
            case .highlights:     base = visible.filter { $0.isFavorite }
            case .places:         base = visible.filter { $0.location != nil }
            case .today:
                // The generator only emits captures on ~26% of days, so filtering on the
                // real calendar day would leave this empty most launches. Use the day of
                // the most recent capture instead.
                let lastDay = visible.last.map { Calendar.current.startOfDay(for: $0.date) }
                base = visible.filter { p in
                    guard let lastDay else { return false }
                    return Calendar.current.isDate(p.date, inSameDayAs: lastDay)
                }
            // Collections
            case .dayRecaps:      base = visible.filter { $0.seed % 6 == 0 }
            case .people:         base = visible.filter { [.portrait, .pet].contains($0.kind) }
            case .meetings:       base = visible.filter { $0.kind == .portrait && $0.seed % 3 == 0 }
            case .sessions:       base = visible.filter { $0.seed % 4 == 0 }
            case .activity:       base = visible.filter { $0.seed % 5 == 0 && scenic.contains($0.kind) }
            case .extracted:      base = visible.filter { $0.kind == .screenshot }
            case .decisions:      base = visible.filter { $0.kind == .screenshot && $0.seed % 7 == 0 }
            case .actionItems:    base = visible.filter { $0.kind == .screenshot && $0.seed % 5 == 0 }
            case .questions:      base = visible.filter { $0.kind == .screenshot && $0.seed % 11 == 0 }
            case .codeSnippets:   base = visible.filter { $0.kind == .screenshot && $0.seed % 3 == 0 }
            case .links:          base = visible.filter { $0.seed % 9 == 0 }
            case .errors:         base = visible.filter { $0.kind == .screenshot && $0.seed % 13 == 0 }
            case .redacted:       base = visible.filter { $0.seed % 17 == 0 }
            case .sources, .screen:
                base = visible.filter { ![.portrait, .pet].contains($0.kind) }
            case .microphone:     base = visible.filter { $0.kind == .portrait }
            case .systemAudio:    base = visible.filter { $0.kind == .portrait && $0.seed % 2 == 0 }
            case .keyboardClicks: base = visible.filter { $0.seed % 2 == 0 }
            case .browser:        base = visible.filter { [.city, .landscape].contains($0.kind) }
            case .terminal:       base = visible.filter { $0.kind == .screenshot && $0.seed % 4 == 0 }
            case .editor:         base = visible.filter { $0.kind == .screenshot && $0.seed % 2 == 0 }
            case .chat:           base = visible.filter { $0.kind == .food }
            case .email:          base = visible.filter { $0.kind == .food && $0.seed % 3 == 0 }
            case .documents:      base = visible.filter { $0.kind == .forest }
            case .design:         base = visible.filter { $0.kind == .sunset }
            case .notebooksRoot:
                base = visible.filter { p in notebookNames.contains { notebookContains($0, p) } }
            case .notebook(let name): base = visible.filter { notebookContains(name, $0) }
            case .pipesRoot:
                base = visible.filter { p in pipeNames.contains { pipeContains($0, p) } }
            case .pipe(let name): base = visible.filter { pipeContains(name, $0) }
            // Memory
            case .agentMemory:    base = visible.filter { $0.isFavorite }
            case .facts:          base = visible.filter { $0.isFavorite && $0.seed % 2 == 0 }
            case .playbooks:      base = visible.filter { $0.seed % 31 == 0 }
            case .sops:           base = visible.filter { $0.seed % 29 == 0 }
            case .memoryTarget(let name):
                // The real sync only writes memories above an importance threshold, so
                // each target file gets a different slice of the favorites.
                base = visible.filter { $0.isFavorite && (name == "CLAUDE.md" ? $0.seed % 3 != 0 : $0.seed % 3 == 0) }
            // Sharing — everything here is a subset of what already left or could leave
            case .sharedContexts:
                base = visible.filter { p in shareNames.contains { shareContains($0, p) } }
            case .accessLog:      base = Array(visible.filter { $0.seed % 4 == 1 }.suffix(40))
            case .share(let name): base = visible.filter { shareContains(name, $0) }
            case .firewall, .firewallRules:
                base = visible.filter { $0.seed % 5 == 1 }
            case .connectedApps:  base = visible.filter { $0.seed % 10 == 3 }
            case .blocked:        base = visible.filter { $0.seed % 17 == 0 }
            case .requests:       base = Array(visible.filter { $0.seed % 14 == 5 }.suffix(12))
            case .recentlyDeleted: base = []
            }
        }
        if favoritesOnly { base = base.filter { $0.isFavorite } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            base = base.filter { p in
                let month = p.date.formatted(.dateTime.month(.wide)).lowercased()
                let year = p.date.formatted(.dateTime.year()).lowercased()
                return p.kind.searchName.contains(q)
                    || (p.location?.lowercased().contains(q) ?? false)
                    || p.fileName.lowercased().contains(q)
                    || month.contains(q) || year.contains(q)
            }
        }
        return base
    }

    private func notebookContains(_ name: String, _ p: Photo) -> Bool {
        switch name {
        case "Auth Rewrite":  p.kind == .screenshot && p.seed % 2 == 0
        case "Q3 Planning":   [.forest, .landscape].contains(p.kind) && p.seed % 3 != 0
        case "Vendor Calls":  [.portrait, .pet].contains(p.kind) && p.seed % 2 == 0
        case "Onboarding":    [.city, .sunset].contains(p.kind) && p.seed % 3 == 0
        default:              false
        }
    }

    private func shareContains(_ name: String, _ p: Photo) -> Bool {
        switch name {
        case "Team Standup":  p.seed % 6 == 0
        case "Acme Support":  p.kind == .screenshot && p.seed % 3 == 1
        case "Research Panel": p.seed % 7 == 2
        default:              false
        }
    }

    private func pipeContains(_ name: String, _ p: Photo) -> Bool {
        switch name {
        case "Day Recap":       p.seed % 6 == 0
        case "Standup":         p.seed % 8 == 0
        case "Meeting Summary": p.kind == .portrait && p.seed % 3 == 0
        default:                false
        }
    }

    func photo(_ id: UUID) -> Photo? { photos.first { $0.id == id } }

    // MARK: - Grouping

    func daySections(_ list: [Photo]) -> [DaySection] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Photo]] = [:]
        for p in list {
            let day = cal.startOfDay(for: p.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(p)
        }
        return order.map { day in
            let ps = buckets[day]!
            let locs = ps.compactMap(\.location)
            let topLoc = Dictionary(grouping: locs, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            return DaySection(id: day, title: Self.dayTitle(day), subtitle: topLoc, photos: ps)
        }
    }

    static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if cal.component(.year, from: day) == cal.component(.year, from: Date()) {
            return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    func monthGroups(_ list: [Photo]) -> [(month: Date, photos: [Photo])] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Photo]] = [:]
        for p in list {
            let comps = cal.dateComponents([.year, .month], from: p.date)
            let m = cal.date(from: comps)!
            if buckets[m] == nil { order.append(m) }
            buckets[m, default: []].append(p)
        }
        return order.map { ($0, buckets[$0]!) }
    }

    func yearGroups(_ list: [Photo]) -> [(year: Date, photos: [Photo])] {
        let cal = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Photo]] = [:]
        for p in list {
            let y = cal.date(from: cal.dateComponents([.year], from: p.date))!
            if buckets[y] == nil { order.append(y) }
            buckets[y, default: []].append(p)
        }
        return order.map { ($0, buckets[$0]!) }
    }

    // MARK: - Mutations

    func toggleFavorite(_ ids: Set<UUID>) {
        let allFav = photos.filter { ids.contains($0.id) }.allSatisfy(\.isFavorite)
        for i in photos.indices where ids.contains(photos[i].id) { photos[i].isFavorite = !allFav }
    }

    func moveToTrash(_ ids: Set<UUID>) {
        for i in photos.indices where ids.contains(photos[i].id) { photos[i].isDeleted = true }
    }

    func restore(_ ids: Set<UUID>) {
        for i in photos.indices where ids.contains(photos[i].id) { photos[i].isDeleted = false }
    }

    func eraseForever(_ ids: Set<UUID>) {
        photos.removeAll { ids.contains($0.id) }
    }

    func hide(_ ids: Set<UUID>) {
        for i in photos.indices where ids.contains(photos[i].id) { photos[i].isHidden.toggle() }
    }

    func duplicate(_ ids: Set<UUID>) {
        var copies: [Photo] = []
        for p in photos where ids.contains(p.id) {
            copies.append(Photo(id: UUID(), seed: p.seed, date: p.date.addingTimeInterval(45),
                                kind: p.kind, location: p.location, isFavorite: false, isDeleted: false,
                                isHidden: false, pixelWidth: p.pixelWidth, pixelHeight: p.pixelHeight,
                                fileName: p.fileName, camera: p.camera, aperture: p.aperture,
                                iso: p.iso, focalLength: p.focalLength, shutter: p.shutter,
                                megabytes: p.megabytes))
        }
        photos.append(contentsOf: copies)
        photos.sort { $0.date < $1.date }
    }

    // MARK: - Generation

    private func generate() {
        var g = SplitMix64(seed: 0x11FE_C0DE)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Photo] = []
        var imgNum = 2874

        struct Trip { let lastDayAgo: Int; let length: Int; let location: String }
        let tripLocs = ["Lisbon", "Tokyo", "Paris", "Rio de Janeiro", "New York"]
        var trips: [Trip] = []
        for (i, loc) in tripLocs.enumerated() {
            let last = 45 + i * 100 + Int(Double.random(in: 0...35, using: &g))
            trips.append(Trip(lastDayAgo: last, length: 4 + Int(Double.random(in: 0...5, using: &g)), location: loc))
        }
        let homeAlts = ["São Paulo", "São Paulo", "São Paulo", "Campinas", "Santos", "São Roque"]

        for daysAgo in stride(from: 545, through: 0, by: -1) {
            let trip = trips.first { daysAgo <= $0.lastDayAgo && daysAgo > $0.lastDayAgo - $0.length }
            let r = Double.random(in: 0...1, using: &g)
            guard trip != nil || r < 0.26 else { continue }

            let count: Int
            if trip != nil {
                count = 4 + Int(Double.random(in: 0...8, using: &g))
            } else {
                let x = Double.random(in: 0...1, using: &g)
                count = 1 + Int(x * x * 7)
            }
            let location: String?
            if let trip { location = trip.location }
            else if Double.random(in: 0...1, using: &g) < 0.7 {
                location = homeAlts[Int(Double.random(in: 0...0.999, using: &g) * Double(homeAlts.count))]
            } else { location = nil }

            let dayStart = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            var minuteOfDay = 8 * 60 + Int(Double.random(in: 0...240, using: &g))

            for _ in 0..<count {
                minuteOfDay += 2 + Int(Double.random(in: 0...90, using: &g))
                if minuteOfDay > 22 * 60 { break }
                let date = dayStart.addingTimeInterval(TimeInterval(minuteOfDay * 60 + Int(Double.random(in: 0...59, using: &g))))
                let kind = pickKind(onTrip: trip != nil, &g)
                let seed = g.next()
                result.append(makePhoto(seed: seed, date: date, kind: kind, location: location, imgNum: &imgNum, &g))
            }
        }

        // Favorites (~9%)
        for i in result.indices where Double.random(in: 0...1, using: &g) < 0.09 {
            result[i].isFavorite = true
        }
        // Hidden: 3
        for _ in 0..<3 {
            let i = Int(Double.random(in: 0...0.999, using: &g) * Double(result.count))
            result[i].isHidden = true
        }
        // Recently deleted: 6 from the recent tail
        let tail = max(0, result.count - 80)
        for _ in 0..<6 {
            let i = tail + Int(Double.random(in: 0...0.999, using: &g) * Double(result.count - tail))
            result[i].isDeleted = true
        }
        // Duplicates: 4 exact pairs (same seed → identical artwork)
        for _ in 0..<4 {
            let i = Int(Double.random(in: 0...0.999, using: &g) * Double(result.count))
            let p = result[i]
            guard !p.isDeleted, !p.isHidden else { continue }
            result.append(Photo(id: UUID(), seed: p.seed, date: p.date.addingTimeInterval(40),
                                kind: p.kind, location: p.location, isFavorite: false, isDeleted: false,
                                isHidden: false, pixelWidth: p.pixelWidth, pixelHeight: p.pixelHeight,
                                fileName: "IMG_\(imgNum).HEIC", camera: p.camera, aperture: p.aperture,
                                iso: p.iso, focalLength: p.focalLength, shutter: p.shutter,
                                megabytes: p.megabytes))
            imgNum += 1
        }

        photos = result.sorted { $0.date < $1.date }
    }

    private func pickKind(onTrip: Bool, _ g: inout SplitMix64) -> PhotoKind {
        let weights: [(PhotoKind, Double)] = onTrip
            ? [(.beach, 0.18), (.city, 0.22), (.landscape, 0.18), (.food, 0.16), (.sunset, 0.12), (.portrait, 0.10), (.forest, 0.04)]
            : [(.portrait, 0.16), (.food, 0.14), (.pet, 0.14), (.screenshot, 0.16), (.city, 0.10), (.landscape, 0.10), (.sunset, 0.08), (.forest, 0.07), (.beach, 0.05)]
        var x = Double.random(in: 0...1, using: &g)
        for (k, w) in weights {
            x -= w
            if x <= 0 { return k }
        }
        return weights.last!.0
    }

    private func makePhoto(seed: UInt64, date: Date, kind: PhotoKind, location: String?,
                           imgNum: inout Int, _ g: inout SplitMix64) -> Photo {
        let dims: (Int, Int)
        switch kind {
        case .portrait: dims = (3024, 4032)
        case .pet: dims = Double.random(in: 0...1, using: &g) < 0.5 ? (3024, 4032) : (4032, 3024)
        case .screenshot:
            dims = Double.random(in: 0...1, using: &g) < 0.3 ? (1179, 2556) : (2940, 1912)
        default:
            dims = Double.random(in: 0...1, using: &g) < 0.15 ? (4032, 2268) : (4032, 3024)
        }
        let fileName: String
        let camera: String?
        if kind == .screenshot {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            fileName = String(format: "Screenshot %04d-%02d-%02d at %02d.%02d.%02d.png",
                              comps.year!, comps.month!, comps.day!, comps.hour!, comps.minute!, comps.second!)
            camera = nil
        } else {
            fileName = "IMG_\(imgNum).HEIC"
            imgNum += 1 + Int(Double.random(in: 0...3, using: &g))
            let cams = ["iPhone 15 Pro", "iPhone 15 Pro", "iPhone 15 Pro", "iPhone 13", "Canon EOS R6"]
            camera = cams[Int(Double.random(in: 0...0.999, using: &g) * Double(cams.count))]
        }
        let apertures = ["ƒ/1.6", "ƒ/1.8", "ƒ/2.2", "ƒ/2.8"]
        let focals = ["24 mm", "26 mm", "13 mm", "77 mm"]
        let shutters = ["1/60 s", "1/120 s", "1/250 s", "1/500 s", "1/1000 s"]
        let isScreen = kind == .screenshot
        return Photo(
            id: UUID(), seed: seed, date: date, kind: kind, location: isScreen ? nil : location,
            isFavorite: false, isDeleted: false, isHidden: false,
            pixelWidth: dims.0, pixelHeight: dims.1, fileName: fileName, camera: camera,
            aperture: isScreen ? nil : apertures[Int(Double.random(in: 0...0.999, using: &g) * 4)],
            iso: isScreen ? nil : [32, 64, 100, 125, 200, 400, 800][Int(Double.random(in: 0...0.999, using: &g) * 7)],
            focalLength: isScreen ? nil : focals[Int(Double.random(in: 0...0.999, using: &g) * 4)],
            shutter: isScreen ? nil : shutters[Int(Double.random(in: 0...0.999, using: &g) * 5)],
            megabytes: (Double.random(in: 0...1, using: &g) * 4.2 + 0.9).rounded(toPlaces: 1)
        )
    }
}

private extension Double {
    func rounded(toPlaces n: Int) -> Double {
        let m = pow(10, Double(n))
        return (self * m).rounded() / m
    }
}
