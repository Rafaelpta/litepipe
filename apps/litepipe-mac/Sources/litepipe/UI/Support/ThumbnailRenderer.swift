import SwiftUI
import AppKit
import AVFoundation

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
                    Text(Photo.shortTitle(photo.window, app: photo.app, host: photo.host))
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

/// Opens the screens themselves. Serial on purpose: pulling a frame out of an
/// H.265 chunk costs about 50 ms, and a grid that scrolls fast would otherwise
/// queue hundreds of decodes at once and take every core with it. One at a time
/// fills a visible screenful in about a second and leaves the machine alone.
///
/// Memory only. A disk cache would make relaunch instant for about 16 MB, but
/// those files would be decoded screens sitting outside the archive, and the
/// vault locks the archive — not a cache beside it.
actor ScreenStore {
    static let shared = ScreenStore()

    private let cache = NSCache<NSString, CGImageBox>()
    /// Chunks that could not be opened or seeked. Without this every scroll past
    /// a broken chunk pays the failure again.
    private var failed = Set<Int64>()

    init() {
        // Budgeted in bytes, not in images. At 768 px a screen is ~1.3 MB, so the
        // old count limit of 1200 would have reserved 1.6 GB of memory for
        // thumbnails alone.
        cache.totalCostLimit = 300 * 1024 * 1024
    }

    final class CGImageBox: NSObject, @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    func screen(_ shot: Shot, maxEdge: CGFloat) -> CGImageBox? {
        let key = "\(shot.frameId)-\(Int(maxEdge))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard !failed.contains(shot.frameId) else { return nil }

        let cg: CGImage?
        if let jpg = shot.jpgPath, FileManager.default.fileExists(atPath: jpg) {
            cg = Self.fromJPEG(jpg, maxEdge: maxEdge)
        } else if let video = shot.videoPath {
            cg = Self.fromVideo(video, offset: shot.offset, fps: shot.fps, maxEdge: maxEdge)
        } else {
            cg = nil
        }

        guard let cg else {
            failed.insert(shot.frameId)
            return nil
        }
        let box = CGImageBox(cg)
        cache.setObject(box, forKey: key, cost: cg.height * cg.bytesPerRow)
        return box
    }

    /// Decode straight to the size we need — full-resolution screen captures are
    /// several megapixels each and would blow memory at a few hundred cells.
    private static func fromJPEG(_ path: String, maxEdge: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
        else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge * 2
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// The frame index maps to a time through the chunk's own rate, which the
    /// engine varies with the capture interval — 0.1 fps here, 0.13 there. A
    /// constant would land on a screen from another minute entirely. Tolerance is
    /// zero for the same reason: near enough is a different screen.
    private static func fromVideo(_ path: String, offset: Int, fps: Double,
                                  maxEdge: CGFloat) -> CGImage? {
        guard fps > 0, FileManager.default.fileExists(atPath: path) else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxEdge * 2, height: maxEdge * 2)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let at = CMTime(seconds: Double(offset) / fps, preferredTimescale: 600)
        return try? gen.copyCGImage(at: at, actualTime: nil)
    }
}

/// A moment's screen, wherever one is needed outside the grid: the year and
/// month posters, the map pins, the citations under a chat answer. Draws the
/// card immediately and swaps in the screen when the store has opened it, so
/// nothing ever waits on a blank rectangle.
struct ScreenImage: View {
    let photo: Photo
    var bucket: Thumbs.Bucket = .grid
    @State private var screen: NSImage?

    var body: some View {
        Group {
            if let screen {
                Image(nsImage: screen).resizable()
            } else if photo.hasImage {
                Rectangle().fill(.quaternary)
            } else {
                Image(nsImage: Thumbs.shared.card(for: photo, bucket: bucket)).resizable()
            }
        }
        .task(id: photo.id) {
            screen = await Thumbs.shared.screen(for: photo, bucket: bucket)
        }
    }
}

@MainActor
final class Thumbs {
    static let shared = Thumbs()
    private let cards = NSCache<NSString, NSImage>()

    init() { cards.countLimit = 400 }

    enum Bucket: CGFloat {
        case grid = 384
        case card = 800
        case zoom = 1600
    }

    /// The drawn card: what a moment looks like before — or instead of — its
    /// screen. Synchronous, so a cell always has something to paint on the frame
    /// it appears; the real screen replaces it a moment later.
    func card(for photo: Photo, bucket: Bucket) -> NSImage {
        let key = "\(photo.frameId)-card-\(Int(bucket.rawValue))" as NSString
        if let img = cards.object(forKey: key) { return img }
        let img = renderCard(photo, edge: bucket.rawValue)
        cards.setObject(img, forKey: key)
        return img
    }

    /// The screen itself, opened from a loose JPEG or from inside a chunk.
    /// Returns nil when this capture kept no picture at all — 289 of 11,548 in a
    /// real archive — and the card stands in for good.
    func screen(for shot: Shot, bucket: Bucket) async -> NSImage? {
        guard let box = await ScreenStore.shared.screen(shot, maxEdge: bucket.rawValue)
        else { return nil }
        let cg = box.image
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func screen(for photo: Photo, bucket: Bucket) async -> NSImage? {
        guard let cover = photo.coverShot else { return nil }
        return await screen(for: cover, bucket: bucket)
    }

    private func renderCard(_ photo: Photo, edge: CGFloat) -> NSImage {
        let size = CGSize(width: edge, height: edge)
        let renderer = ImageRenderer(content: CaptureCard(photo: photo, size: size))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        return renderer.nsImage ?? NSImage(size: size)
    }

    /// Warm the newest screens so the first scroll is already filled. Kept short:
    /// the store is serial, and a long queue here would sit in front of whatever
    /// the user actually scrolls to.
    func prewarm(_ photos: [Photo]) {
        Task.detached(priority: .utility) {
            for p in photos.suffix(60).reversed() {
                if Task.isCancelled { return }
                guard let shot = p.coverShot else { continue }
                _ = await ScreenStore.shared.screen(shot, maxEdge: Bucket.grid.rawValue)
            }
        }
    }
}
