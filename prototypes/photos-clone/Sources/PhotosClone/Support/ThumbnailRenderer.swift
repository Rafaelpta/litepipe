import SwiftUI
import AppKit

/// What a capture looks like in the grid. Most frames in a real archive have no
/// screenshot — only text — so the card is the common case, not the fallback.
struct CaptureCard: View {
    let photo: Photo
    let size: CGSize

    private var tint: Color {
        Color(hue: photo.source.hue, saturation: 0.55, brightness: 0.62)
    }

    /// A moment shows its span; a single capture shows its clock time.
    private var timeLabel: String {
        let start = photo.date.formatted(date: .omitted, time: .shortened)
        let secs = Int(photo.dwell)
        guard secs >= 60 else { return start }
        return "\(start) · \(secs / 60) min"
    }

    var body: some View {
        let unit = size.width / 384

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6 * unit) {
                Image(systemName: photo.source.symbol)
                    .font(.system(size: 13 * unit, weight: .semibold))
                Text(photo.app.isEmpty ? photo.source.label : photo.app)
                    .font(.system(size: 13 * unit, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(timeLabel)
                    .font(.system(size: 11 * unit, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14 * unit)
            .frame(height: 38 * unit)
            .background(tint)

            VStack(alignment: .leading, spacing: 7 * unit) {
                if !photo.window.isEmpty {
                    Text(photo.window)
                        .font(.system(size: 14 * unit, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }
                if photo.isThin {
                    // Nothing but interface furniture was on screen. Say what
                    // happened in one line instead of dumping forty sidebar labels.
                    Text(photo.activityLine)
                        .font(.system(size: 12 * unit))
                        .italic()
                        .lineLimit(2)
                        .foregroundStyle(.tertiary)
                } else if !photo.excerpt.isEmpty {
                    Text(photo.excerpt)
                        .font(.system(size: 11.5 * unit))
                        .lineSpacing(1.5 * unit)
                        .lineLimit(9)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let host = photo.host {
                    Text(host)
                        .font(.system(size: 11 * unit, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(tint)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14 * unit)
            .background(Color(white: 0.99))
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)   // cards are paper, in both app themes
    }
}

@MainActor
final class Thumbs {
    static let shared = Thumbs()
    private let cache = NSCache<NSString, NSImage>()
    private var missingSnapshots = Set<Int64>()

    init() { cache.countLimit = 1200 }

    enum Bucket: CGFloat {
        case grid = 384
        case card = 800
        case zoom = 1600
    }

    func image(for photo: Photo, bucket: Bucket) -> NSImage {
        let key = "\(photo.frameId)-\(Int(bucket.rawValue))" as NSString
        if let img = cache.object(forKey: key) { return img }

        let img: NSImage
        if let path = photo.snapshotPath,
           !missingSnapshots.contains(photo.frameId),
           let loaded = loadSnapshot(path, maxEdge: bucket.rawValue) {
            img = loaded
        } else {
            if photo.snapshotPath != nil { missingSnapshots.insert(photo.frameId) }
            img = renderCard(photo, edge: bucket.rawValue)
        }
        cache.setObject(img, forKey: key)
        return img
    }

    /// Decode straight to the size we need — full-resolution screen captures are
    /// several megapixels each and would blow memory at a few hundred cells.
    private func loadSnapshot(_ path: String, maxEdge: CGFloat) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path),
              let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge * 2
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func renderCard(_ photo: Photo, edge: CGFloat) -> NSImage {
        let size = CGSize(width: edge, height: edge)
        let renderer = ImageRenderer(content: CaptureCard(photo: photo, size: size))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        return renderer.nsImage ?? NSImage(size: size)
    }

    func prewarm(_ photos: [Photo]) {
        Task { @MainActor in
            for (i, p) in photos.suffix(400).reversed().enumerated() {
                _ = image(for: p, bucket: .grid)
                if i % 8 == 0 { await Task.yield() }
            }
        }
    }
}
