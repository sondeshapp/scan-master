# ScanMaster — Bugs & Improvements Tracker

This document tracks all bugs, stubbed/incomplete UI controls, state synchronization issues, storage leaks, and performance/accessibility improvements identified during full-app testing on Android (`emulator-5554`) and static code review.

---

## Progress Checklist

### Completed
- [x] **#0 — Android Build & Plugin Compatibility (`camera`, `share_plus`, `permission_handler`)**
- [x] **#1 — `RenderFlex` Bottom Overflow (`6.0px`) in `EditPageScreen` Filter Strip**
- [x] **#2 — Search Screen: Results Not Tappable, Stale State on Delete, and Ephemeral Recent Searches**
- [x] **#3 — Edit Screen: Stubbed Toolbar (`Rotate`, `Crop`, `Adjust`, Delete Page) & Per-Page Filter State**
- [x] **#4 — Home Screen: Non-Functional Bottom Navigation Tabs (`Folders`, `Recents`) & `"View All"` Button**
- [x] **#5 — Folder Management: Missing Folder Rename/Delete, Document Rename in Folder, and Scan-to-Folder**
- [x] **#6 — Scanner Screen: 3-Thumbnail Hard Cap, Non-Functional `+` Tile, Page Removal, and `AUTO` Mode Toggle**
- [x] **#7 — Storage Hygiene: Orphaned Raw Scan Image Files (`scans/`)**
- [x] **#8 — Performance & Accessibility: Thumbnail `cacheWidth` Decoding & Screen-Reader `Semantics`**

---

## Detailed Issue Breakdown

---

### #0 — Android Build & Plugin Compatibility (FIXED)
* **Files**:
  * [pubspec.yaml](file:///home/akash/projects/scan-master/pubspec.yaml)
  * [android/app/build.gradle.kts](file:///home/akash/projects/scan-master/android/app/build.gradle.kts)
  * [android/gradle.properties](file:///home/akash/projects/scan-master/android/gradle.properties)
* **Symptoms**:
  * `:camera_android_camerax:compileDebugJavaWithJavac` failed with `class file for androidx.concurrent.futures.CallbackToFutureAdapter not found`.
  * Deprecated Kotlin Gradle Plugin warnings from older `camera_android_camerax` (`0.6.30`) and `share_plus` (`10.1.4`).
  * Deprecated `Share.shareXFiles` analyzer warnings.
* **Resolution**:
  * Upgraded `camera` to `^0.12.2`, `permission_handler` to `^13.0.2`, and `share_plus` to `^13.3.1`.
  * Updated `compileSdk = 37` in `android/app/build.gradle.kts` and migrated `Share.shareXFiles(...)` calls to `SharePlus.instance.share(ShareParams(...))`.

---

### #1 — `RenderFlex` Bottom Overflow (`6.0px`) in `EditPageScreen` Filter Strip (FIXED)
* **File**: [lib/screens/edit_page_screen.dart](file:///home/akash/projects/scan-master/lib/screens/edit_page_screen.dart#L247-L302)
* **Severity**: High (Visual layout error banner in debug builds, clipped text in release builds)
* **Root Cause**:
  * `_buildFilterStrip()` constrained its `SizedBox` to `height: 100` with `padding: EdgeInsets.symmetric(vertical: 8)` (`16px` total vertical padding), leaving `84px` for each filter item's `Column`.
  * Inside the `Column`, the `70px` thumbnail container + `4px` `SizedBox` + `~16px` `Text` (`fontSize: 11`) required `90px`, overflowing by `6.0px` at the bottom.
* **Resolution**:
  * Increased `_buildFilterStrip()` container `height` from `100` to `108` and added a widget regression test in [test/app_test.dart](file:///home/akash/projects/scan-master/test/app_test.dart).

---

### #2 — Search Screen: Results Not Tappable, Stale State on Delete, and Ephemeral Recent Searches
* **File**: [lib/screens/search_screen.dart](file:///home/akash/projects/scan-master/lib/screens/search_screen.dart)
* **Severity**: High (Broken core user flow)
* **Bugs Identified**:
  1. **Tapping a search result does nothing** ([search_screen.dart#L239-L341](file:///home/akash/projects/scan-master/lib/screens/search_screen.dart#L239-L341)):
     * `_ResultItem` renders a `Row` with the document thumbnail, highlighted title, and a `PopupMenuButton` (`Share`, `Delete`), but has no `GestureDetector`/`InkWell` `onTap` handler to open [`DocumentViewerScreen`](file:///home/akash/projects/scan-master/lib/screens/document_viewer_screen.dart).
  2. **Deleted documents stay on screen in search results** ([search_screen.dart#L323-L325](file:///home/akash/projects/scan-master/lib/screens/search_screen.dart#L323-L325)):
     * When a user selects `Delete` from `_ResultItem`'s popup menu, it calls `await DocumentStore.instance.deleteDocument(doc.id)` directly inside the stateless `_ResultItem` without notifying `_SearchScreenState`. `_results` still holds the deleted `ScanDocument` until the user edits the search query.
  3. **Recent searches are never saved unless keyboard "Submit" is pressed, and are lost on exit** ([search_screen.dart#L19-L39](file:///home/akash/projects/scan-master/lib/screens/search_screen.dart#L19-L39)):
     * `_recentSearches` is an in-memory `List<String>` on `_SearchScreenState`. Because live search updates on every keystroke (`onChanged`), users rarely press the keyboard submit button before tapping a result or leaving the screen, and even when they do, `_recentSearches` is wiped as soon as `SearchScreen` is popped.
  4. **Highlight only matches the first occurrence** ([search_screen.dart#L343-L369](file:///home/akash/projects/scan-master/lib/screens/search_screen.dart#L343-L369)):
     * `_HighlightText` uses `lower.indexOf(query.toLowerCase())` and only highlights the first match in the document name.
* **Proposed Fix**:
  * Add an `onTap` callback to `_ResultItem` that records the query in recent searches and navigates to `DocumentViewerScreen(doc: doc)`.
  * Pass an `onDelete` callback from `_SearchScreenState` to `_ResultItem` so `_runSearch(_ctrl.text)` refreshes `_results` immediately after deletion.
  * Persist `recentSearches` in `DocumentStore` (`manifest.json`) so recent queries survive screen navigation and app restarts.

---

### #3 — Edit Screen: Stubbed Toolbar (`Rotate`, `Crop`, `Adjust`, Delete Page) & Per-Page Filter State
* **Files**:
  * [lib/screens/edit_page_screen.dart](file:///home/akash/projects/scan-master/lib/screens/edit_page_screen.dart)
  * [lib/utils/image_processor.dart](file:///home/akash/projects/scan-master/lib/utils/image_processor.dart)
* **Severity**: High (Visible buttons do nothing when tapped)
* **Bugs / Gaps Identified**:
  1. **Bottom toolbar buttons are no-ops** ([edit_page_screen.dart#L316-L320](file:///home/akash/projects/scan-master/lib/screens/edit_page_screen.dart#L316-L320)):
     ```dart
     _ToolBtn(icon: Icons.crop, label: 'Crop', onTap: () {}),
     _ToolBtn(icon: Icons.rotate_right, label: 'Rotate', onTap: () {}),
     _ToolBtn(icon: Icons.text_fields, label: 'Text', onTap: () {}),
     _ToolBtn(icon: Icons.tune, label: 'Adjust', onTap: () {}),
     ```
     Tapping any of the 4 buttons in the bottom bar has zero effect.
  2. **Single global filter instead of per-page filter/rotation state** ([edit_page_screen.dart#L20-L21](file:///home/akash/projects/scan-master/lib/screens/edit_page_screen.dart#L20-L21)):
     * `_selectedFilter` is a single `int` applied to every page when saving, and the multi-page thumbnail strip ([edit_page_screen.dart#L210-L245](file:///home/akash/projects/scan-master/lib/screens/edit_page_screen.dart#L210-L245)) does not preview filters or rotations.
  3. **No way to delete a page in `EditPageScreen`**:
     * In a multi-page scan, pages can be reordered via drag-and-drop, but an unwanted page cannot be removed.
* **Proposed Fix**:
  * Track per-page edit state (filter index, 90° rotation steps, brightness/contrast adjustments).
  * Wire up **Rotate** (90° clockwise rotation in preview and in `processImageFilter` via `img.copyRotate`), **Adjust** (interactive brightness & contrast bottom sheet/slider), **Crop** (aspect-ratio/margin crop dialog or page trim), and **Delete Page** (when `_imagePaths.length > 1`).

---

### #4 — Home Screen: Non-Functional Bottom Navigation Tabs (`Folders`, `Recents`) & `"View All"` Button
* **File**: [lib/screens/home_screen.dart](file:///home/akash/projects/scan-master/lib/screens/home_screen.dart)
* **Severity**: Medium-High (Dead navigation controls)
* **Bugs Identified**:
  1. **Bottom navigation tabs `2` (Folders) and `3` (Recents) don't change the screen content** ([home_screen.dart#L546-L556](file:///home/akash/projects/scan-master/lib/screens/home_screen.dart#L546-L556)):
     * Tapping the folder icon sets `_navIndex = 2` and tapping `Recents` sets `_navIndex = 3`, changing the highlighted icon color, but `HomeScreen.build` ([home_screen.dart#L189-L220](file:///home/akash/projects/scan-master/lib/screens/home_screen.dart#L189-L220)) ignores `_navIndex` and always renders the same Home scroll view.
  2. **`"View All"` button in *My Folders* is a no-op** ([home_screen.dart#L328-L337](file:///home/akash/projects/scan-master/lib/screens/home_screen.dart#L328-L337)):
     * `TextButton(onPressed: () {}, child: const Text('View All', ...))` does nothing when tapped.
  3. **Bottom nav icons lack labels for 3 out of 4 tabs** ([home_screen.dart#L528-L556](file:///home/akash/projects/scan-master/lib/screens/home_screen.dart#L528-L556)):
     * Only the 4th tab passes `label: 'Recents'`, making the bottom bar visually unbalanced (`Home`, `Search`, `Folders` have no text label while `Recents` does).
* **Proposed Fix**:
  * Switch the body content based on `_navIndex`:
    * `0` (**Home**): Folders overview + Uncategorized files
    * `1` (**Search**): Opens `SearchScreen`
    * `2` (**Folders**): Dedicated Folders management grid (also triggered by `"View All"`)
    * `3` (**Recents**): All scanned documents across all folders (including folder badges), sorted by newest first
  * Make bottom navigation labels consistent across all 4 tabs.

---

### #5 — Folder Management: Missing Folder Rename/Delete, Document Rename in Folder, and Scan-to-Folder
* **Files**:
  * [lib/data/document_store.dart](file:///home/akash/projects/scan-master/lib/data/document_store.dart)
  * [lib/screens/folder_screen.dart](file:///home/akash/projects/scan-master/lib/screens/folder_screen.dart)
  * [lib/screens/home_screen.dart](file:///home/akash/projects/scan-master/lib/screens/home_screen.dart)
* **Severity**: Medium
* **Bugs / Gaps Identified**:
  1. **Folders cannot be renamed, recolored, or deleted** ([document_store.dart#L134-L144](file:///home/akash/projects/scan-master/lib/data/document_store.dart#L134-L144)):
     * `DocumentStore` only has `createFolder(name, colorValue)`. Default folders (`Invoices`, `Tax 2023`, `School`, `Work`) or user-created folders can never be renamed or deleted.
  2. **`FolderScreen` is missing document Rename and Move-to-another-folder options** ([folder_screen.dart#L40-L123](file:///home/akash/projects/scan-master/lib/screens/folder_screen.dart#L40-L123)):
     * Unlike `HomeScreen`'s `_FileOptionsSheet`, `FolderScreen._showOptions` only offers `Open`, `Share`, `Remove from folder`, and `Delete` (no `Rename` or `Move to folder`).
  3. **Cannot scan directly into a folder**:
     * `FolderScreen` has no `+` FloatingActionButton to scan a new document directly into `widget.folder.id`, and `EditPageScreen` always saves documents with `folderId: null`.
* **Proposed Fix**:
  * Add `renameFolder(String id, String newName, {int? colorValue})` and `deleteFolder(String id)` (moving contained documents to uncategorized) to `DocumentStore`.
  * Add folder options (rename/recolor/delete) via long-press on `_FolderCard` or an AppBar menu in `FolderScreen`.
  * Add `Rename` and a `+` scan button to `FolderScreen` (passing `folderId` through `ScannerScreen` → `EditPageScreen`).

---

### #6 — Scanner Screen: 3-Thumbnail Hard Cap, Non-Functional `+` Tile, Page Removal, and `AUTO` Mode Toggle
* **File**: [lib/screens/scanner_screen.dart](file:///home/akash/projects/scan-master/lib/screens/scanner_screen.dart)
* **Severity**: Medium
* **Bugs / Gaps Identified**:
  1. **Thumbnail strip only displays the first 3 pages** ([scanner_screen.dart#L328-L341](file:///home/akash/projects/scan-master/lib/screens/scanner_screen.dart#L328-L341)):
     ```dart
     if (count >= 1) ...[ _Thumb(path: _capturedPaths[0], number: 1, selected: true), ... ],
     if (count >= 2) ...[ _Thumb(path: _capturedPaths[1], number: 2), ... ],
     if (count >= 3) ...[ _Thumb(path: _capturedPaths[2], number: 3), ... ],
     _AddBtn(),
     ```
     When a user scans 4 or more pages, pages 4+ are never shown in the thumbnail strip, and page 1 is hardcoded as `selected: true`.
  2. **`_AddBtn` (`+` tile in thumbnail strip) is not clickable** ([scanner_screen.dart#L513-L526](file:///home/akash/projects/scan-master/lib/screens/scanner_screen.dart#L513-L526)):
     * `_AddBtn` renders a `+` icon box next to the page thumbnails, but tapping it does nothing (users expect it to import from gallery or trigger a capture).
  3. **Cannot remove a bad capture from `ScannerScreen`**:
     * If a user accidentally takes a blurry photo, there is no `×` badge on `_Thumb` to discard that page before proceeding.
  4. **`AUTO` pill in top bar is static** ([scanner_screen.dart#L224-L239](file:///home/akash/projects/scan-master/lib/screens/scanner_screen.dart#L224-L239)):
     * The README mentions *"Live camera preview with auto-mode"*, but the `AUTO` badge has no tap handler or timer/auto-capture logic.
* **Proposed Fix**:
  * Replace the hardcoded 3-item `Row` with a scrollable `ListView.separated` showing all captured pages, auto-scrolling to the latest page, with a remove (`×`) button on each thumbnail.
  * Wire `_AddBtn` to `_pickFromGallery`.
  * Make the `AUTO` / `MANUAL` pill toggleable (with a countdown auto-shutter when `AUTO` is active).

---

### #7 — Storage Hygiene: Orphaned Raw Scan Image Files (`scans/`)
* **Files**:
  * [lib/screens/scanner_screen.dart](file:///home/akash/projects/scan-master/lib/screens/scanner_screen.dart#L85-L92)
  * [lib/screens/edit_page_screen.dart](file:///home/akash/projects/scan-master/lib/screens/edit_page_screen.dart#L68-L78)
* **Severity**: Medium (Unbounded disk space leak over time)
* **Root Cause**:
  * `ScannerScreen._capture()` and `_pickFromGallery()` copy every raw image into `<app_docs>/scans/<timestamp>.jpg`.
  * In `EditPageScreen._save()`, each image in `_imagePaths` is processed and written to a **new** file `<app_docs>/scans/<timestamp>_f.jpg`, and only `processedPaths` are stored in `ScanDocument.pageImagePaths`.
  * The original `<timestamp>.jpg` files are never deleted after saving, nor are they deleted if the user backs out of `ScannerScreen` without saving. When the user later deletes the document via `DocumentStore.deleteDocument()`, only `processedPaths` (`*_f.jpg`) are deleted, leaving the raw `<timestamp>.jpg` files orphaned on disk permanently.
* **Proposed Fix**:
  * Delete intermediate raw scan files once their processed `*_f.jpg` counterparts are written in `EditPageScreen._save()`.
  * Clean up unsaved `_capturedPaths` when `ScannerScreen` is popped without saving.

---

### #8 — Performance & Accessibility: Thumbnail `cacheWidth` Decoding & Screen-Reader `Semantics`
* **Files**:
  * [lib/screens/home_screen.dart](file:///home/akash/projects/scan-master/lib/screens/home_screen.dart)
  * [lib/screens/folder_screen.dart](file:///home/akash/projects/scan-master/lib/screens/folder_screen.dart)
  * [lib/screens/search_screen.dart](file:///home/akash/projects/scan-master/lib/screens/search_screen.dart)
  * [lib/screens/edit_page_screen.dart](file:///home/akash/projects/scan-master/lib/screens/edit_page_screen.dart)
  * [lib/screens/scanner_screen.dart](file:///home/akash/projects/scan-master/lib/screens/scanner_screen.dart)
* **Severity**: Low-Medium (Memory usage & accessibility compliance)
* **Root Cause**:
  1. **Full-resolution image decoding for small thumbnails**:
     * `Image.file(File(...), fit: BoxFit.cover)` is used inside `48×60` and `58×70` containers without `cacheWidth`, causing Flutter's image cache to decode full multi-megapixel camera photos for tiny list thumbnails.
  2. **Missing accessibility labels on custom icon buttons**:
     * Custom `GestureDetector` buttons (Home `+` FAB, bottom nav icons, Scanner close/gallery/flash/shutter buttons, Edit back button) have no `Semantics(label: ..., button: true)` or `Tooltip`, resulting in unlabeled clickable nodes in the Android accessibility hierarchy.
* **Proposed Fix**:
  * Add `cacheWidth: 180` to all thumbnail `Image.file` widgets (keeping full resolution for `DocumentViewerScreen` and the main preview in `EditPageScreen`).
  * Wrap custom icon-only controls with `Semantics` / `Tooltip` labels.
