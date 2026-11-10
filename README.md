# ScanMaster

ScanMaster is a local-first document scanner and PDF organizer built with Flutter. Capture documents with the camera or import images from the gallery, enhance each page, save multi-page PDFs, and organize them into color-coded folders without a cloud backend.

## Features

- **Multi-page scanning** — Capture unlimited pages with manual capture or a 3-second auto-capture mode.
- **Gallery import** — Add multiple existing images to a scan in one step.
- **Page editing** — Apply Original, B&W, Magic, Text, or Sepia filters; rotate pages; crop margins; adjust brightness and contrast; reorder pages; and remove unwanted pages.
- **Multi-page PDFs** — Save processed pages as a PDF and open or share the result through the platform share sheet.
- **Local storage** — Documents, folders, and recent searches are persisted locally in the app documents directory.
- **Folder organization** — Create, rename, recolor, and delete folders; move documents between folders; or scan directly into a folder.
- **Search and navigation** — Search document names with highlighted matches and recent-search history. Browse Home, Folders, and Recents views.
- **Document management** — Rename, sort, share, multi-select, and delete documents.
- **Accessibility and fallback behavior** — Custom controls have accessible labels, and scanning falls back to placeholder captures when a camera is unavailable (useful for emulator or desktop development).

> PDFs currently contain the processed page images. OCR and searchable text layers are not implemented yet.

## Requirements

- Flutter SDK 3.12.2 or newer on the stable channel
- Dart SDK compatible with the constraint in `pubspec.yaml`
- Android API 21 or newer for Android builds
- Xcode and iOS 12 or newer for iOS builds

On Windows development machines, enable Developer Mode so Flutter can create symlinks:

```text
start ms-settings:developers
```

### Permissions

The app requests camera permission at runtime. iOS also declares camera and photo-library usage descriptions in `ios/Runner/Info.plist`. Review platform permission settings before testing camera or gallery features on a physical device.

## Getting started

Install dependencies and run the app:

```bash
flutter pub get
flutter run
```

Run static analysis and tests:

```bash
flutter analyze
flutter test
```

Build a release APK locally:

```bash
flutter build apk --release
```

## Data and storage

ScanMaster stores data under the platform application documents directory:

```text
<app documents directory>/manifest.json  # document, folder, and search metadata
<app documents directory>/scans/          # processed page images
<app documents directory>/pdfs/           # generated PDFs
```

There is no account, sync service, or cloud upload. Deleting a document also removes its stored page images and PDF.

## Project structure

```text
lib/
├── main.dart                         # App entry point and store initialization
├── app_theme.dart                     # Shared colors and theme
├── data/
│   ├── models.dart                    # ScanDocument and ScanFolder models
│   └── document_store.dart            # Local JSON persistence and document operations
├── utils/
│   └── image_processor.dart           # Isolate-based image processing and previews
└── screens/
    ├── splash_screen.dart
    ├── home_screen.dart               # Home, Folders, and Recents navigation
    ├── scanner_screen.dart             # Camera and gallery capture
    ├── edit_page_screen.dart           # Page editing and PDF generation
    ├── folder_screen.dart
    ├── search_screen.dart
    └── document_viewer_screen.dart
```

## Architecture notes

- `DocumentStore` is a singleton that loads and persists `manifest.json` on writes.
- Image transformations run through Flutter's `compute()` isolate pathway so the UI stays responsive.
- Filter previews use GPU `ColorFilter.matrix` operations; final page images are processed with the `image` package before PDF generation.
- Temporary raw captures are cleaned up when a scan is canceled or saved.

## Dependencies

| Package | Purpose |
| --- | --- |
| `camera` | Camera preview and image capture |
| `permission_handler` | Runtime camera permission |
| `image_picker` | Multi-image gallery import |
| `path_provider` | App documents directory |
| `image` | Image processing and JPEG encoding |
| `pdf` | PDF generation |
| `share_plus` | Native share sheet |
| `uuid` | Unique document and folder IDs |
| `intl` | Date formatting |

## Android releases

The GitHub Actions workflow in `.github/workflows/android-release.yml` runs tests, builds a release APK, and publishes it to GitHub Releases when `main` or a `v*` tag is pushed. It can also be started manually from the Actions tab.

For versioning, update `version` in `pubspec.yaml` and add optional release notes at `.github/release-notes/<version>.md`. See [docs/android_release.md](docs/android_release.md) for signing setup and the complete release process.

## License

MIT
