import SwiftUI

struct InspectorView: View {
    @Environment(NavigationState.self) private var nav
    @Environment(MockLibrary.self) private var lib
    @Environment(SelectionModel.self) private var sel

    private var target: Photo? {
        if let id = nav.openedPhotoID { return lib.photo(id) }
        if sel.selection.count == 1, let id = sel.selection.first { return lib.photo(id) }
        return nil
    }

    var body: some View {
        Group {
            if let photo = target {
                info(photo)
            } else if sel.selection.count > 1 {
                ContentUnavailableView("\(sel.selection.count) Photos Selected",
                                       systemImage: "photo.stack")
            } else {
                ContentUnavailableView("No Photo Selected", systemImage: "info.circle")
            }
        }
        .inspectorColumnWidth(min: 245, ideal: 280, max: 340)
    }

    private func info(_ photo: Photo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(photo.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Spacer()
                    if photo.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.system(size: 12))
                    Text(photo.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(photo.camera ?? "Screenshot")
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 6) {
                        chip("\(photo.pixelWidth) × \(photo.pixelHeight)")
                        chip(photo.fileName.hasSuffix(".png") ? "PNG" : "HEIC")
                        chip("\(photo.megabytes.formatted()) MB")
                    }
                    if let ap = photo.aperture, let iso = photo.iso,
                       let focal = photo.focalLength, let shutter = photo.shutter {
                        Text("\(focal) · \(ap) · \(shutter) · ISO \(iso)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if let location = photo.location {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        mapPlaceholder
                        Text(location)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Keywords")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(photo.kind.searchName.split(separator: " ").prefix(3), id: \.self) { word in
                            chip(String(word))
                        }
                    }
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }

    private var mapPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: 0.36, saturation: 0.18, brightness: 0.88),
                                    Color(hue: 0.55, saturation: 0.25, brightness: 0.82)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 42))
                p.addCurve(to: CGPoint(x: 260, y: 60),
                           control1: CGPoint(x: 90, y: 10),
                           control2: CGPoint(x: 170, y: 95))
            }
            .stroke(Color.white.opacity(0.7), lineWidth: 3)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.red, .white)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
