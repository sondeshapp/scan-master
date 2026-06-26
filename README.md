# ScanMaster

A full-featured document scanning app built with Flutter. Capture physical documents with your camera, apply image filters, generate PDFs, and organise everything into folders — all stored locally on device.

## Features

- **Document scanning** — Live camera preview with auto-mode, flash toggle, and multi-page capture
- **Image filters** — Original, B&W, Magic, Text, and Sepia filters with instant GPU preview and compute-isolated processing on save
- **PDF generation** — Every scan is saved as a searchable PDF using the `pdf` package
- **Local storage** — All documents and folders persist via a JSON manifest; no cloud dependency
- **Folder organisation** — Create colour-coded folders and move documents between them
- **Search** — Full-text search across document names with highlighted matches and recent search history
- **Share** — Share any PDF via the system share sheet
- **Rename / Delete** — Manage documents from the home screen or within folders

## Screens

| Splash | Home | Scanner | Edit | Search |
|--------|------|---------|------|--------|
| Animated progress bar | Folder grid + recent files | Live camera + thumbnail strip | Filter preview + PDF save | Live search + highlighted results |

## Tech Stack

| Package | Purpose |
|---------|---------|
| `camera ^0.11` | Live camera preview and image capture |
| `permission_handler ^11` | Runtime camera permission |
| `path_provider ^2.1` | App documents directory |
| `image ^4.2` | Server-side image processing in isolate |
| `pdf ^3.11` | PDF generation from image bytes |
| `share_plus ^10` | Native share sheet |
| `uuid ^4.5` | Unique document IDs |
| `intl ^0.20` | Date formatting |

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.12
- Android API 21+ (minSdk enforced in `build.gradle.kts`)
- iOS 12+ with `NSCameraUsageDescription` set in `Info.plist`
- **Windows dev machines**: enable Developer Mode (`start ms-settings:developers`) for Flutter symlink support

### Run

```bash
flutter pub get
flutter run
```

### Build APK

```bash
flutter build apk --release
```

## Project Structure

```
lib/
├── main.dart               # App entry + DocumentStore init
├── app_theme.dart          # Color constants
├── data/
│   ├── models.dart         # ScanDocument, ScanFolder
│   └── document_store.dart # Singleton JSON persistence
├── utils/
│   └── image_processor.dart # compute() filter + ColorFilter matrices
└── screens/
    ├── splash_screen.dart
    ├── home_screen.dart
    ├── scanner_screen.dart
    ├── edit_page_screen.dart
    ├── folder_screen.dart
    └── search_screen.dart
```

## Architecture Notes

- `DocumentStore` is a singleton that loads/saves `<app_docs>/manifest.json` on every write
- Image processing runs in a Dart isolate via `compute()` to keep the UI thread free
- Filter previews use `ColorFilter.matrix` (GPU, instant); actual save uses the `image` package (CPU, accurate)
- Scanner falls back gracefully when a real camera is unavailable (emulator / desktop)

## License

MIT
