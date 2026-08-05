# PhotosClone — Photos.app UI replica (SwiftUI prototype)

UI-only replica of macOS Photos (Sequoia) with mock, code-generated photos.
Built to validate the look/feel before adapting the layout for litepipe.
Nothing here touches the litepipe app.

## Run

```bash
cd prototypes/photos-clone
swift run                # normal (follows system appearance)
PC_DARK=1 swift run      # force dark mode
```

Requires macOS 15.

## What to try

- **Sidebar**: Library / Memories / Favorites / Recently Saved, Albums, Utilities
  (Duplicates shows real identical pairs; Recently Deleted has restore/erase).
- **Toolbar**: Years / Months / Days / All Photos segmented control, zoom slider,
  favorites filter menu, Info (inspector), search.
- **Grid**: pinch-to-zoom (live tracking, spring snap on release) or drag the slider;
  pinned day headers with locations; hover a cell → heart appears bottom-left;
  click / ⌘-click / ⇧-click selection; arrow keys, ⌘A, Esc, Delete;
  right-click → Get Info / Favorite / Duplicate / Hide / Delete.
- **Detail**: double-click (or Return/Space) zooms into the photo with a hero
  transition; ← → navigate (crossfade), filmstrip at the bottom, `.` toggles
  favorite, Esc or back-chevron returns to the exact cell.
- **Drill**: Years → click a year → Months → click a month → Days anchored there.
- **Inspector**: metadata, EXIF-style line, fake map with pin, keywords; persists
  between grid and detail.
- Light/dark follow the system automatically.

All motion constants live in `Sources/PhotosClone/Support/Anim.swift`, tuned to
Photos-like springs (open 0.35/0.85, zoom relayout 0.30/0.90, crossfade 0.18s).
Fake "photos" are deterministic per-seed renders (`ThumbnailRenderer.swift`),
pre-rendered to bitmaps and cached so pinch/scroll stay smooth with 600+ items.
