# FileScape

An experimental macOS app that visualizes your files as a 3D "data city" using SceneKit. Folders become districts; files are colored blocks sized by their disk usage.

Status: MVP prototype. You can select a folder, scan it, and explore a 3D scene with orbit/pan/zoom camera controls. Click blocks to view details, open files, reveal them in Finder, or move them to Trash. Double‑click folders to enter; use Back or crumbs to exit.

## Run

- Open `FileScap/FileScap.xcodeproj` in Xcode 16 or newer.
- Build and run the `FileScap` macOS target.
- In the app, click "Choose Folder" to select a directory to visualize, then "Rescan" if needed.

Notes:
- The Xcode target and module are currently named `FileScap` (without the trailing 'e'). This does not affect functionality; rename in Xcode if you prefer perfect naming alignment.
- The app operates fully offline. No data is sent anywhere.

## Features

- SceneKit 3D view with camera controls and basic lighting
- Blocks sized by relative file size and colored by type (video/image/audio/app/document/code/archive/other)
- Folder picker (NSOpenPanel) and rescanning
- Hidden files toggle (off by default)
- Selection details with actions: Open, Reveal in Finder, Move to Trash
- Enter/exit folder navigation (double‑click to enter, Back/crumbs to exit) with simple camera transition
- Search by name (highlights matches)
- LOD slider (Top N) to cap number of blocks rendered, with an aggregate “Others” block for the remainder
- Color legend overlay
- Rooms view layout (folders around the perimeter, files in the room)
- Filters by type (toggle categories) and an info side panel with metadata

## Limitations and Next Steps

- Currently lays out the children of the focused folder. Zoom/enter interactions can be expanded to multi‑level views or aggregate blocks.
- Height can optionally encode file age; the default is a constant height with slight scaling.
- For very large folders, consider increasing paging/LOD and lazy loading.

## Privacy & Safety

- No telemetry or network use. Scans are in-memory only.
- Uses macOS sandbox "User Selected Files" entitlement with read-only access to chosen folders.
