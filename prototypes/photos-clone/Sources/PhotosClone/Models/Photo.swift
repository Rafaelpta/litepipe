import Foundation

enum PhotoKind: String, CaseIterable {
    case landscape, sunset, portrait, food, pet, city, beach, forest, screenshot

    var searchName: String {
        switch self {
        case .landscape: "landscape mountains"
        case .sunset: "sunset sky"
        case .portrait: "portrait people"
        case .food: "food restaurant"
        case .pet: "pet dog cat"
        case .city: "city buildings"
        case .beach: "beach sea ocean"
        case .forest: "forest trees nature"
        case .screenshot: "screenshot"
        }
    }
}

struct Photo: Identifiable, Hashable {
    let id: UUID
    let seed: UInt64
    let date: Date
    let kind: PhotoKind
    let location: String?
    var isFavorite: Bool
    var isDeleted: Bool
    var isHidden: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let fileName: String
    let camera: String?
    let aperture: String?
    let iso: Int?
    let focalLength: String?
    let shutter: String?
    let megabytes: Double

    var aspect: CGFloat { CGFloat(pixelWidth) / CGFloat(pixelHeight) }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case years, months, days, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .years: "Years"
        case .months: "Months"
        case .days: "Days"
        case .all: "All Photos"
        }
    }
}

enum SidebarItem: Hashable {
    // Photos
    case library, favorites, map, recentlySaved, recentlyDeleted
    // Collections
    case days, peoplePets, memories, trips, featured
    case utilities, duplicates, receipts, handwriting, illustrations, recentlyViewed, documents
    case mediaTypes, videos, selfies, livePhotos, portrait, panoramas, timelapse, slomo,
         bursts, screenshots, screenRecordings, animated
    case albumsRoot, album(String), projects
    // Sharing
    case sharedAlbums, activity, sharedAlbum(String), sharedWithYou

    var displayName: String {
        switch self {
        case .library: "Library"
        case .favorites: "Favorites"
        case .map: "Map"
        case .recentlySaved: "Recently Saved"
        case .recentlyDeleted: "Recently Deleted"
        case .days: "Days"
        case .peoplePets: "People & Pets"
        case .memories: "Memories"
        case .trips: "Trips"
        case .featured: "Featured Photos"
        case .utilities: "Utilities"
        case .duplicates: "Duplicates"
        case .receipts: "Receipts"
        case .handwriting: "Handwriting"
        case .illustrations: "Illustrations"
        case .recentlyViewed: "Recently Viewed"
        case .documents: "Documents"
        case .mediaTypes: "Media Types"
        case .videos: "Videos"
        case .selfies: "Selfies"
        case .livePhotos: "Live Photos"
        case .portrait: "Portrait"
        case .panoramas: "Panoramas"
        case .timelapse: "Time-lapse"
        case .slomo: "Slo-mo"
        case .bursts: "Bursts"
        case .screenshots: "Screenshots"
        case .screenRecordings: "Screen Recordings"
        case .animated: "Animated"
        case .albumsRoot: "Albums"
        case .album(let name): name
        case .projects: "Projects"
        case .sharedAlbums: "Shared Albums"
        case .activity: "Activity"
        case .sharedAlbum(let name): name
        case .sharedWithYou: "Shared with You"
        }
    }
}

struct DaySection: Identifiable {
    let id: Date
    let title: String
    let subtitle: String?
    let photos: [Photo]
}
