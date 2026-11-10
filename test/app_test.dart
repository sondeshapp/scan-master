import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scan_master/data/document_store.dart';
import 'package:scan_master/data/models.dart';
import 'package:scan_master/screens/edit_page_screen.dart';
import 'package:scan_master/screens/folder_screen.dart';
import 'package:scan_master/screens/home_screen.dart';
import 'package:scan_master/screens/search_screen.dart';
import 'package:scan_master/utils/image_processor.dart';

void main() {
  setUp(() {
    DocumentStore.instance.seedForTesting(
      docs: [],
      folders: [],
      recentSearches: [],
    );
  });

  group('Models & DocumentStore', () {
    test('ScanDocument JSON round-trip and formatted metadata', () {
      final now = DateTime.now();
      final doc = ScanDocument(
        id: 'doc-1',
        name: 'Invoice #42',
        pdfPath: '/tmp/invoice.pdf',
        pageImagePaths: const ['/tmp/page1.jpg', '/tmp/page2.jpg'],
        folderId: 'folder-1',
        createdAt: now,
        sizeBytes: 51200,
      );

      final json = doc.toJson();
      final restored = ScanDocument.fromJson(json);

      expect(restored.id, doc.id);
      expect(restored.name, doc.name);
      expect(restored.pdfPath, doc.pdfPath);
      expect(restored.pageImagePaths, doc.pageImagePaths);
      expect(restored.folderId, doc.folderId);
      expect(restored.sizeBytes, 51200);
      expect(restored.formattedSize, '50 KB');
      expect(restored.formattedDate, 'Today');

      final uncategorized =
          restored.copyWith(clearFolder: true, name: 'Renamed');
      expect(uncategorized.folderId, isNull);
      expect(uncategorized.name, 'Renamed');
    });

    test('ScanFolder JSON round-trip and copyWith', () {
      final folder = ScanFolder(
        id: 'f-1',
        name: 'Receipts',
        colorValue: 0xFF2563EB,
        createdAt: DateTime(2026, 11, 10),
      );
      final restored = ScanFolder.fromJson(folder.toJson());
      expect(restored.id, 'f-1');
      expect(restored.name, 'Receipts');
      expect(restored.color, const Color(0xFF2563EB));

      final updated = restored.copyWith(name: 'Taxes', colorValue: 0xFF22C55E);
      expect(updated.name, 'Taxes');
      expect(updated.colorValue, 0xFF22C55E);
    });

    test('DocumentStore updateFolder, deleteFolder, and recentSearches',
        () async {
      final store = DocumentStore.instance;
      final folder = ScanFolder(
        id: 'f-10',
        name: 'Work',
        colorValue: 0xFF2563EB,
        createdAt: DateTime.now(),
      );
      final doc = ScanDocument(
        id: 'd-10',
        name: 'Contract.pdf',
        pdfPath: '/nonexistent/contract.pdf',
        pageImagePaths: const [],
        folderId: 'f-10',
        createdAt: DateTime.now(),
        sizeBytes: 2048,
      );
      store.seedForTesting(docs: [doc], folders: [folder], recentSearches: []);

      await store.updateFolder('f-10', name: 'Legal');
      expect(store.folders.single.name, 'Legal');

      await store.deleteFolder('f-10');
      expect(store.folders, isEmpty);
      expect(store.documents.single.folderId, isNull);

      await store.addRecentSearch('Contract');
      await store.addRecentSearch('Invoice');
      await store.addRecentSearch('contract'); // deduplicates case-insensitively
      expect(store.recentSearches, ['contract', 'Invoice']);

      await store.clearRecentSearches();
      expect(store.recentSearches, isEmpty);
    });
  });

  group('Image Processor', () {
    late Uint8List sampleJpg;

    setUpAll(() {
      final image = img.Image(width: 20, height: 10);
      img.fill(image, color: img.ColorRgb8(120, 160, 200));
      sampleJpg = Uint8List.fromList(img.encodeJpg(image));
    });

    test('All 5 filters, rotation, crop, and adjustments produce valid JPEG',
        () async {
      expect(filterMatrices.length, 5);
      for (var i = 0; i < 5; i++) {
        final out = await processImageFilter({
          'bytes': sampleJpg,
          'filterIndex': i,
          'quarterTurns': 1,
          'cropMargin': 0.1,
          'brightness': 1.1,
          'contrast': 1.2,
        });
        expect(out, isNotEmpty);
        final decoded = img.decodeImage(out);
        expect(decoded, isNotNull);
        // Rotated 90° (10x20) then cropped by 10% on each side -> 8x16
        expect(decoded!.width, 8);
        expect(decoded.height, 16);
      }

      expect(
        buildPreviewMatrix(filterIndex: 0, brightness: 1.0, contrast: 1.0),
        isNull,
      );
      expect(
        buildPreviewMatrix(filterIndex: 2, brightness: 1.1, contrast: 1.2),
        hasLength(20),
      );
    });
  });

  group('Widget Tests', () {
    testWidgets(
        'HomeScreen switches between Home, Folders, and Recents tabs',
        (tester) async {
      final folder = ScanFolder(
        id: 'f-1',
        name: 'Invoices',
        colorValue: 0xFF2563EB,
        createdAt: DateTime.now(),
      );
      final categorizedDoc = ScanDocument(
        id: 'd-1',
        name: 'Categorized Invoice',
        pdfPath: '/nonexistent/cat.pdf',
        pageImagePaths: const [],
        folderId: 'f-1',
        createdAt: DateTime.now(),
        sizeBytes: 4096,
      );
      DocumentStore.instance.seedForTesting(
        docs: [categorizedDoc],
        folders: [folder],
      );

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

      final screenBottom =
          tester.getBottomLeft(find.byType(Scaffold)).dy;
      final homeTabDy = tester.getBottomLeft(find.text('Home')).dy;
      expect(homeTabDy, greaterThan(screenBottom - 80));

      // Home tab: shows My Folders + Uncategorized Files (empty since doc is in folder)
      expect(find.text('My Folders'), findsOneWidget);
      expect(find.text('Uncategorized Files'), findsOneWidget);

      // Tap View All -> switches to Folders tab
      await tester.tap(find.text('View All'));
      await tester.pump();
      expect(find.text('Uncategorized Files'), findsNothing);
      expect(find.text('My Folders'), findsOneWidget);
      // Dock remains pinned at the bottom even when content is shorter than screen
      expect(tester.getBottomLeft(find.text('Home')).dy, equals(homeTabDy));

      // Tap Recents in bottom bar -> shows Recent Documents including categorized doc
      await tester.tap(find.text('Recents'));
      await tester.pump();
      expect(find.text('Recent Documents'), findsOneWidget);
      expect(find.text('Categorized Invoice'), findsOneWidget);
    });

    testWidgets(
        'EditPageScreen supports rotate, crop, adjust sheet, and delete page without overflow',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EditPageScreen(
            imagePaths: ['/nonexistent/page1.jpg', '/nonexistent/page2.jpg'],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Rotate page
      await tester.tap(find.text('Rotate'));
      await tester.pump();

      // Crop cycle
      await tester.tap(find.text('Crop'));
      await tester.pump();
      expect(find.text('Cropped'), findsOneWidget);

      // Adjust bottom sheet
      await tester.tap(find.text('Adjust'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust Page'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20)); // dismiss sheet
      await tester.pumpAndSettle();

      // Delete Page (available when _pages.length > 1)
      expect(find.text('Delete Page'), findsOneWidget);
      await tester.tap(find.text('Delete Page'));
      await tester.pump();
      // Now only 1 page remains, so Delete Page is replaced by Text Mode
      expect(find.text('Delete Page'), findsNothing);
      expect(find.text('Text Mode'), findsOneWidget);
    });

    testWidgets(
        'SearchScreen opens result on tap and refreshes list when result is deleted',
        (tester) async {
      final doc = ScanDocument(
        id: 'd-99',
        name: 'Tax Return 2026',
        pdfPath: '/nonexistent/tax.pdf',
        pageImagePaths: const [],
        createdAt: DateTime.now(),
        sizeBytes: 10240,
      );
      DocumentStore.instance.seedForTesting(
        docs: [doc],
        recentSearches: ['Receipt'],
      );

      await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
      // Shows persisted recent search
      expect(find.text('Receipt'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Tax');
      await tester.pump();
      expect(find.text('RESULTS (1)'), findsOneWidget);

      // Delete result via popup menu and verify list updates immediately
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('No results for "Tax"'), findsOneWidget);
    });

    testWidgets('FolderScreen renders folder documents and Scan FAB',
        (tester) async {
      final folder = ScanFolder(
        id: 'f-2',
        name: 'School',
        colorValue: 0xFF22C55E,
        createdAt: DateTime.now(),
      );
      final doc = ScanDocument(
        id: 'd-2',
        name: 'Lecture Notes',
        pdfPath: '/nonexistent/notes.pdf',
        pageImagePaths: const [],
        folderId: 'f-2',
        createdAt: DateTime.now(),
        sizeBytes: 8192,
      );
      DocumentStore.instance.seedForTesting(docs: [doc], folders: [folder]);

      await tester.pumpWidget(MaterialApp(home: FolderScreen(folder: folder)));
      expect(find.text('School'), findsOneWidget);
      expect(find.text('Lecture Notes'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Move to folder from HomeScreen options sheet moves document',
        (tester) async {
      final folder = ScanFolder(
        id: 'f-move',
        name: 'Invoices',
        colorValue: 0xFF2563EB,
        createdAt: DateTime.now(),
      );
      final doc = ScanDocument(
        id: 'd-move',
        name: 'Unfiled Doc',
        pdfPath: '/nonexistent/unfiled.pdf',
        pageImagePaths: const [],
        folderId: null,
        createdAt: DateTime.now(),
        sizeBytes: 4096,
      );
      DocumentStore.instance.seedForTesting(docs: [doc], folders: [folder]);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      expect(find.text('Unfiled Doc'), findsOneWidget);
      expect(find.text('0 files'), findsOneWidget);

      // Scroll into view and open options sheet
      await tester.ensureVisible(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // Tap 'Move to folder'
      await tester.tap(find.text('Move to folder'));
      await tester.pumpAndSettle();

      // Tap 'Invoices' in the Move to Folder dialog
      await tester.tap(find.widgetWithText(ListTile, 'Invoices'));
      await tester.pumpAndSettle();

      expect(DocumentStore.instance.documents.single.folderId, 'f-move');
      expect(find.text('1 file'), findsOneWidget);
    });
  });
}
